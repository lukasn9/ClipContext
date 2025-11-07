import AppKit
import Combine

@MainActor
class ClipboardManager: ObservableObject {
    @Published var clipboardItems: [ClipboardItem] = []
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var timer: Timer?

    init() {
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

                    let item = ClipboardItem(
                        content: content,
                        sourceApp: frontApp,
                        dateCopied: Date()
                    )
                    if !clipboardItems.contains(where: { $0.content == content }) {
                        clipboardItems.insert(item, at: 0)
                    }
                }
            }
        }

    func clearAll() {
        clipboardItems.removeAll()
    }
}
