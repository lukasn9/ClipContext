import Foundation

struct ClipboardItem: Identifiable, Equatable, Codable {
    let id = UUID()
    var content: String
    let sourceApp: String
    let dateCopied: Date
}

