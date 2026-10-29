import Foundation
import SQLite3

private nonisolated let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Thin SQLite wrapper. Not internally serialized: the owner must confine each instance
/// to one serial queue (ClipboardManager does: one writer instance, one read-only instance).
nonisolated final class ClipboardStore: @unchecked Sendable {
    struct StoreError: Error { let message: String }

    let path: String
    private var db: OpaquePointer?

    private static let metaColumns = "id, source_app, date, preview, word_count, char_count"

    /// A read-only instance (for search) sees committed data through its own WAL snapshot.
    init(path: String, readOnly: Bool = false) throws {
        self.path = path
        let flags = readOnly ? SQLITE_OPEN_READONLY : (SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
        guard sqlite3_open_v2(path, &db, flags | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "Unable to open database"
            sqlite3_close(db)
            throw StoreError(message: message)
        }
        do {
            if readOnly {
                try exec("PRAGMA cache_size=-1024")
                try registerSearchFunction()
                return
            }
            try exec("PRAGMA journal_mode=WAL")
            try exec("PRAGMA synchronous=NORMAL")
            try exec("PRAGMA cache_size=-1024")  // 1 MB page cache (default 2 MB)
            try exec("PRAGMA secure_delete=ON")  // deleted clipboard text is overwritten, not left in free pages
            // `content` is the last column so metadata reads never touch its overflow pages.
            try exec("""
                CREATE TABLE IF NOT EXISTS items (
                    seq INTEGER PRIMARY KEY AUTOINCREMENT,
                    id TEXT NOT NULL UNIQUE,
                    source_app TEXT NOT NULL,
                    date REAL NOT NULL,
                    preview TEXT NOT NULL,
                    word_count INTEGER NOT NULL,
                    char_count INTEGER NOT NULL,
                    content TEXT NOT NULL
                )
                """)
            try exec("CREATE INDEX IF NOT EXISTS items_char_count ON items(char_count)")
            try registerSearchFunction()
        } catch {
            sqlite3_close(db)
            throw error
        }
    }

    deinit { sqlite3_close(db) }

    // MARK: - Queries

    func count() -> Int {
        (try? scalarInt("SELECT COUNT(*) FROM items")) ?? 0
    }

    func loadItems() throws -> [ClipboardItem] {
        try fetchItems("SELECT \(Self.metaColumns) FROM items ORDER BY seq DESC")
    }

    func search(_ query: String) throws -> [ClipboardItem] {
        if query.allSatisfy(\.isASCII) {
            // Fast path: SQLite's LIKE is case-insensitive for ASCII
            let escaped = query
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "%", with: "\\%")
                .replacingOccurrences(of: "_", with: "\\_")
            return try fetchItems(
                "SELECT \(Self.metaColumns) FROM items WHERE content LIKE ? ESCAPE '\\' ORDER BY seq DESC",
                binding: ["%\(escaped)%"]
            )
        }
        // Unicode-aware case-insensitive match, same semantics as the in-memory search used before
        return try fetchItems(
            "SELECT \(Self.metaColumns) FROM items WHERE contains_ci(content, ?) ORDER BY seq DESC",
            binding: [query]
        )
    }

    func content(id: UUID) -> String? {
        guard let stmt = try? prepare("SELECT content FROM items WHERE id = ?") else { return nil }
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, id.uuidString)
        guard sqlite3_step(stmt) == SQLITE_ROW, let text = sqlite3_column_text(stmt, 0) else { return nil }
        return String(cString: text)
    }

    func containsContent(_ content: String, charCount: Int) -> Bool {
        guard let stmt = try? prepare("SELECT 1 FROM items WHERE char_count = ? AND content = ? LIMIT 1") else { return false }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, Int64(charCount))
        bind(stmt, 2, content)
        return sqlite3_step(stmt) == SQLITE_ROW
    }

    // MARK: - Mutations

    func insert(_ item: ClipboardItem, content: String) throws {
        let stmt = try prepare("""
            INSERT INTO items (id, source_app, date, preview, word_count, char_count, content)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """)
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, item.id.uuidString)
        bind(stmt, 2, item.sourceApp)
        sqlite3_bind_double(stmt, 3, item.dateCopied.timeIntervalSince1970)
        bind(stmt, 4, item.preview)
        sqlite3_bind_int64(stmt, 5, Int64(item.wordCount))
        sqlite3_bind_int64(stmt, 6, Int64(item.charCount))
        bind(stmt, 7, content)
        try stepDone(stmt)
    }

    func update(_ item: ClipboardItem, content: String) throws {
        let stmt = try prepare("UPDATE items SET preview = ?, word_count = ?, char_count = ?, content = ? WHERE id = ?")
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, item.preview)
        sqlite3_bind_int64(stmt, 2, Int64(item.wordCount))
        sqlite3_bind_int64(stmt, 3, Int64(item.charCount))
        bind(stmt, 4, content)
        bind(stmt, 5, item.id.uuidString)
        try stepDone(stmt)
    }

    func delete(id: UUID) throws {
        let stmt = try prepare("DELETE FROM items WHERE id = ?")
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, id.uuidString)
        try stepDone(stmt)
    }

    func deleteAll() throws {
        try exec("DELETE FROM items")
        checkpoint()
    }

    /// Keeps only the newest `limit` items.
    func trim(keeping limit: Int) throws {
        let stmt = try prepare("""
            DELETE FROM items WHERE seq <= COALESCE(
                (SELECT seq FROM items ORDER BY seq DESC LIMIT 1 OFFSET ?), 0)
            """)
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, Int64(limit))
        try stepDone(stmt)
    }

    func transaction(_ body: () throws -> Void) throws {
        try exec("BEGIN IMMEDIATE")
        do {
            try body()
            try exec("COMMIT")
        } catch {
            try? exec("ROLLBACK")
            throw error
        }
    }

    /// Folds the WAL back into the main file (and shrinks it).
    func checkpoint() {
        sqlite3_wal_checkpoint_v2(db, nil, SQLITE_CHECKPOINT_TRUNCATE, nil, nil)
    }

    // MARK: - Helpers

    private func registerSearchFunction() throws {
        let rc = sqlite3_create_function_v2(db, "contains_ci", 2, SQLITE_UTF8 | SQLITE_DETERMINISTIC, nil, { ctx, _, argv in
            guard let argv, let hay = sqlite3_value_text(argv[0]), let needle = sqlite3_value_text(argv[1]) else {
                sqlite3_result_int(ctx, 0)
                return
            }
            let found = String(cString: hay).localizedCaseInsensitiveContains(String(cString: needle))
            sqlite3_result_int(ctx, found ? 1 : 0)
        }, nil, nil, nil)
        guard rc == SQLITE_OK else { throw lastError() }
    }

    private func fetchItems(_ sql: String, binding: [String] = []) throws -> [ClipboardItem] {
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        for (i, value) in binding.enumerated() { bind(stmt, Int32(i + 1), value) }
        var items: [ClipboardItem] = []
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else { throw lastError() }
            guard let uuid = UUID(uuidString: text(stmt, 0)) else { continue }
            items.append(ClipboardItem(
                id: uuid,
                sourceApp: text(stmt, 1),
                dateCopied: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2)),
                preview: text(stmt, 3),
                wordCount: Int(sqlite3_column_int64(stmt, 4)),
                charCount: Int(sqlite3_column_int64(stmt, 5))
            ))
        }
        return items
    }

    private func scalarInt(_ sql: String) throws -> Int {
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { throw lastError() }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    private func text(_ stmt: OpaquePointer, _ column: Int32) -> String {
        sqlite3_column_text(stmt, column).map { String(cString: $0) } ?? ""
    }

    private func bind(_ stmt: OpaquePointer, _ index: Int32, _ value: String) {
        sqlite3_bind_text(stmt, index, value, -1, SQLITE_TRANSIENT)
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { throw lastError() }
        return stmt
    }

    private func stepDone(_ stmt: OpaquePointer) throws {
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw lastError() }
    }

    private func exec(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw lastError() }
    }

    private func lastError() -> StoreError {
        StoreError(message: db.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite error")
    }
}
