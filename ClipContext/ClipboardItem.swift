import Foundation

struct ClipboardItem: Identifiable, Equatable, Codable {
    let id: UUID
    var content: String
    let sourceApp: String
    let dateCopied: Date

    init(content: String, sourceApp: String, dateCopied: Date) {
        self.id = UUID()
        self.content = content
        self.sourceApp = sourceApp
        self.dateCopied = dateCopied
    }
}

