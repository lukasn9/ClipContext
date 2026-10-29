import AppKit
import Combine
import Darwin.malloc

@MainActor
class ClipboardManager: ObservableObject {
    @Published var clipboardItems: [ClipboardItem] = [] {
        didSet { revision &+= 1 }
    }
    /// Bumps on every change to the list so views can re-run searches.
    @Published private(set) var revision = 0
    /// Item the UI should present the system translation sheet for (set by the Translate hotkey).
    @Published var translationRequest: UUID?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var timer: Timer?
    private let store: ClipboardStore
    private let reader: ClipboardStore?
    /// Serial queue that owns `store`: reads run via `sync`, writes via `async`, so order is preserved.
    private let ioQueue = DispatchQueue(label: "com.LukasNagy.ClipContext.io", qos: .utility)
    private let searchQueue = DispatchQueue(label: "com.LukasNagy.ClipContext.search", qos: .userInitiated)

    // MARK: - Persistence
    private struct LegacyItem: Decodable {
        let id: UUID
        let content: String
        let sourceApp: String
        let dateCopied: Date
    }

    private static func storageDirectory() -> URL {
        let fm = FileManager.default
        let appSupport = try? fm.url(for: .applicationSupportDirectory,
                                     in: .userDomainMask,
                                     appropriateFor: nil,
                                     create: true)
        let bundleID = Bundle.main.bundleIdentifier ?? "ClipContext"
        let dir = appSupport?.appendingPathComponent(bundleID, isDirectory: true)
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Opens the database; a corrupt file is moved aside, and as a last resort history is kept in memory only.
    private static func openStore(in dir: URL) -> ClipboardStore {
        let fm = FileManager.default
        let dbURL = dir.appendingPathComponent("clipboard.sqlite")
        if let store = try? ClipboardStore(path: dbURL.path) { return store }

        let stamp = Int(Date().timeIntervalSince1970)
        try? fm.moveItem(at: dbURL, to: dir.appendingPathComponent("clipboard.corrupt-\(stamp).sqlite"))
        for suffix in ["-wal", "-shm"] {
            try? fm.removeItem(atPath: dbURL.path + suffix)
        }
        if let store = try? ClipboardStore(path: dbURL.path) { return store }
        return try! ClipboardStore(path: ":memory:")
    }

    /// One-time import of the pre-SQLite JSON history. The JSON file is removed only after the row count is verified.
    private static func migrateLegacyJSON(at url: URL, into store: ClipboardStore) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path), store.count() == 0,
              let data = try? Data(contentsOf: url),
              let legacy = try? JSONDecoder().decode([LegacyItem].self, from: data) else { return }
        do {
            try store.transaction {
                // JSON was newest-first; insert oldest-first so sequence order matches
                for old in legacy.reversed() {
                    let item = ClipboardItem(id: old.id, content: old.content, sourceApp: old.sourceApp, dateCopied: old.dateCopied)
                    try store.insert(item, content: old.content)
                }
            }
            if store.count() == legacy.count {
                try? fm.removeItem(at: url)
            }
        } catch {
            print("Legacy history migration failed: \(error)")
        }
    }

    init() {
        let dir = Self.storageDirectory()
        store = Self.openStore(in: dir)
        Self.migrateLegacyJSON(at: dir.appendingPathComponent("clipboardItems.json"), into: store)
        reader = store.path == ":memory:" ? nil : try? ClipboardStore(path: store.path, readOnly: true)
        clipboardItems = (try? store.loadItems()) ?? []
        startMonitoring()
    }

    func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                self.checkForChanges()
            }
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    func checkForChanges() {
        let pasteboard = NSPasteboard.general
        if pasteboard.changeCount != lastChangeCount {
            lastChangeCount = pasteboard.changeCount
            if let content = pasteboard.string(forType: .string) {
                let frontApp = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"

                // Auto-apply enabled transforms
                var processedContent = content
                for id in SettingsStore.shared.autoApplyActionIDs {
                    if let action = allActions.action(id: id) {
                        processedContent = action.transform(processedContent)
                    }
                }
                if processedContent != content {
                    pasteboard.clearContents()
                    pasteboard.setString(processedContent, forType: .string)
                    lastChangeCount = pasteboard.changeCount  // avoid re-detecting our own write
                }

                let item = ClipboardItem(content: processedContent, sourceApp: frontApp, dateCopied: Date())
                let store = self.store
                let isDuplicate = ioQueue.sync {
                    store.containsContent(processedContent, charCount: item.charCount)
                }
                guard !isDuplicate else { return }

                let limit = SettingsStore.shared.historyLimit
                let finalContent = processedContent
                clipboardItems.insert(item, at: 0)
                if clipboardItems.count > limit {
                    clipboardItems.removeLast(clipboardItems.count - limit)
                }
                persist { store in
                    try store.insert(item, content: finalContent)
                    try store.trim(keeping: limit)
                }
                if item.charCount > 20_000 { Self.returnFreedMemory() }
            }
        }
    }

    /// Full text of an item, read from disk on demand.
    func content(for itemID: UUID) -> String? {
        let store = self.store
        return ioQueue.sync { store.content(id: itemID) }
    }

    /// Replaces an item's text and mirrors it to the system pasteboard.
    func updateContent(itemID: UUID, newText: String) {
        guard let idx = clipboardItems.firstIndex(where: { $0.id == itemID }) else { return }
        let old = clipboardItems[idx]
        let updated = ClipboardItem(id: old.id, content: newText, sourceApp: old.sourceApp, dateCopied: old.dateCopied)
        clipboardItems[idx] = updated
        persist { store in try store.update(updated, content: newText) }
        writeToPasteboard(newText)
    }

    func apply(_ action: ClipAction, to itemID: UUID) {
        guard let text = content(for: itemID) else { return }
        updateContent(itemID: itemID, newText: action.transform(text))
    }

    /// Runs off the main thread on a read-only connection; cancelling the task drops queued work.
    func search(_ query: String) async -> [ClipboardItem] {
        let store = self.store, reader = self.reader
        let ioQueue = self.ioQueue, searchQueue = self.searchQueue
        let flag = CancelFlag()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                searchQueue.async {
                    if flag.isCancelled { continuation.resume(returning: []); return }
                    // Barrier: let queued writes commit first so results are current
                    ioQueue.sync {}
                    if let reader {
                        continuation.resume(returning: (try? reader.search(query)) ?? [])
                    } else {
                        continuation.resume(returning: ioQueue.sync { (try? store.search(query)) ?? [] })
                    }
                }
            }
        } onCancel: {
            flag.cancel()
        }
    }

    /// Queues a database write. On failure the list is reloaded from disk so UI and storage can't drift apart.
    private func persist(_ work: @escaping @Sendable (ClipboardStore) throws -> Void) {
        let store = self.store
        ioQueue.async {
            do {
                try work(store)
            } catch {
                print("Failed to save clipboard change: \(error)")
                Task { @MainActor in self.reloadFromDisk() }
            }
        }
    }

    private func reloadFromDisk() {
        let store = self.store
        if let items = ioQueue.sync(execute: { try? store.loadItems() }) {
            clipboardItems = items
        }
    }

    private func writeToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        lastChangeCount = pasteboard.changeCount  // avoid re-detecting our own write
    }

    func remove(itemID: UUID) {
        clipboardItems.removeAll { $0.id == itemID }
        persist { store in try store.delete(id: itemID) }
    }

    func clearAll() {
        clipboardItems.removeAll()
        persist { store in try store.deleteAll() }
    }

    /// Large copies leave freed-but-resident heap pages behind; hand them back to the OS.
    /// Queued behind pending writes so the big buffers are already released.
    nonisolated static func returnFreedMemory() {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
            malloc_zone_pressure_relief(nil, 0)
        }
    }

    /// Waits for queued writes, then folds the WAL into the main file.
    func prepareForTermination() {
        let store = self.store
        ioQueue.sync { store.checkpoint() }
    }
}

private nonisolated final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
}
