import Foundation

/// Lightweight row model. The full text lives in the database and is loaded on demand.
nonisolated struct ClipboardItem: Identifiable, Equatable, Sendable {
    static let previewLength = 300

    let id: UUID
    let sourceApp: String
    let dateCopied: Date
    let preview: String
    let wordCount: Int
    let charCount: Int

    init(id: UUID = UUID(), content: String, sourceApp: String, dateCopied: Date) {
        let stats = Self.stats(for: content)
        self.init(id: id, sourceApp: sourceApp, dateCopied: dateCopied,
                  preview: stats.preview, wordCount: stats.wordCount, charCount: stats.charCount)
    }

    init(id: UUID, sourceApp: String, dateCopied: Date, preview: String, wordCount: Int, charCount: Int) {
        self.id = id
        self.sourceApp = sourceApp
        self.dateCopied = dateCopied
        self.preview = preview
        self.wordCount = wordCount
        self.charCount = charCount
    }

    static func stats(for content: String) -> (preview: String, wordCount: Int, charCount: Int) {
        (String(content.prefix(previewLength)), wordCount(in: content), content.count)
    }

    /// Single pass over the scalars; avoids `split`, which allocates a Substring per word.
    static func wordCount(in text: String) -> Int {
        var count = 0
        var inWord = false
        for scalar in text.unicodeScalars {
            if scalar.properties.isWhitespace {
                inWord = false
            } else if !inWord {
                inWord = true
                count += 1
            }
        }
        return count
    }
}
