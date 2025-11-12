import AppKit
import Combine

@MainActor
class ClipboardManager: ObservableObject {
    @Published var clipboardItems: [ClipboardItem] = []
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var timer: Timer?

    // MARK: - Persistence
    private let fileURL: URL = {
        let fm = FileManager.default
        let appSupport = try? fm.url(for: .applicationSupportDirectory,
                                     in: .userDomainMask,
                                     appropriateFor: nil,
                                     create: true)
        let bundleID = Bundle.main.bundleIdentifier ?? "ClipContext"
        let dir = appSupport?.appendingPathComponent(bundleID, isDirectory: true)
        if let dir, !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return (dir ?? URL(fileURLWithPath: NSTemporaryDirectory()))
            .appendingPathComponent("clipboardItems.json")
    }()

    init() {
        loadFromDisk()
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
                if !clipboardItems.contains(where: { $0.content == processedContent }) {
                    clipboardItems.insert(item, at: 0)
                    let limit = SettingsStore.shared.historyLimit
                    if clipboardItems.count > limit {
                        clipboardItems.removeLast(clipboardItems.count - limit)
                    }
                    saveToDisk()
                }
            }
        }
    }

    func updateContent(itemID: UUID, newText: String) {
        guard let idx = clipboardItems.firstIndex(where: { $0.id == itemID }) else { return }
        clipboardItems[idx].content = newText
        saveToDisk()
    }

    func remove(itemID: UUID) {
        clipboardItems.removeAll { $0.id == itemID }
        saveToDisk()
    }

    func clearAll() {
        clipboardItems.removeAll()
        saveToDisk()
    }

    // MARK: - Disk I/O
    private func loadFromDisk() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode([ClipboardItem].self, from: data)
            clipboardItems = decoded
        } catch {
            // If decoding fails, we won’t crash; we’ll just start fresh.
            print("Failed to load clipboard items: \(error)")
        }
    }

    private func saveToDisk() {
        do {
            let data = try JSONEncoder().encode(clipboardItems)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            print("Failed to save clipboard items: \(error)")
        }
    }
}

