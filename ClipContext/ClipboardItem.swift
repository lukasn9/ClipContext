import Foundation

struct ClipboardItem: Identifiable, Equatable {
    let id = UUID()
    let content: String
    let sourceApp: String
    let dateCopied: Date
}
