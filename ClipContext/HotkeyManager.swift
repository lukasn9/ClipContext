import AppKit
import Carbon.HIToolbox
import Combine

final class HotkeyManager {
    static let shared = HotkeyManager()

    var onTriggered: ((String) -> Void)?

    private var monitor: Any?
    private var localMonitor: Any?
    private var shortcutMap: [ShortcutKey: String] = [:]
    private var cancellables = Set<AnyCancellable>()
    private var pollTimer: Timer?

    private init() {}

    func start(with store: SettingsStore) {
        rebuildMap(from: store)

        store.$actionShortcuts
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak store] _ in
                guard let store else { return }
                self?.rebuildMap(from: store)
            }.store(in: &cancellables)

        store.$openAppShortcut
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak store] _ in
                guard let store else { return }
                self?.rebuildMap(from: store)
            }.store(in: &cancellables)

        installMonitor()
    }

    private func rebuildMap(from store: SettingsStore) {
        var map: [ShortcutKey: String] = [:]
        for (id, sc) in store.actionShortcuts {
            map[ShortcutKey(sc)] = id
        }
        if let sc = store.openAppShortcut {
            map[ShortcutKey(sc)] = "openApp"
        }
        shortcutMap = map
    }

    private func installMonitor() {
        guard monitor == nil else { return }
        guard AXIsProcessTrusted() else {
            startPolling()
            return
        }
        stopPolling()
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let relevant = event.modifierFlags.intersection([.command, .shift, .option, .control])
            let key = ShortcutKey(keyCode: event.keyCode, modifierFlags: relevant.rawValue)
            if shortcutMap[key] != nil {
                self.handle(event)
                return nil  // consume the event so it doesn't propagate
            }
            return event
        }
    }

    private func startPolling() {
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard AXIsProcessTrusted() else { return }
            self?.installMonitor()
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func handle(_ event: NSEvent) {
        let relevant = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard !relevant.isEmpty else { return }

        let key = ShortcutKey(keyCode: event.keyCode, modifierFlags: relevant.rawValue)
        guard let actionID = shortcutMap[key] else { return }
        onTriggered?(actionID)
    }
}

private struct ShortcutKey: Hashable {
    let keyCode: UInt16
    let modifierFlags: UInt  // NSEventModifierFlags.rawValue masked to ⌘⌥⇧⌃

    init(_ sc: KeyShortcut) {
        self.keyCode = sc.keyCode
        let masked = NSEvent.ModifierFlags(rawValue: sc.modifierFlags)
            .intersection([.command, .shift, .option, .control])
        self.modifierFlags = masked.rawValue
    }

    init(keyCode: UInt16, modifierFlags: UInt) {
        self.keyCode = keyCode
        self.modifierFlags = NSEvent.ModifierFlags(rawValue: modifierFlags)
            .intersection([.command, .shift, .option, .control])
            .rawValue
    }
}
