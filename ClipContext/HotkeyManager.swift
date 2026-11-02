import AppKit
import Carbon.HIToolbox
import Combine

/// Global shortcuts via Carbon's RegisterEventHotKey: works system-wide, inside the sandbox,
/// and needs no Accessibility or Input Monitoring permission.
final class HotkeyManager {
    static let shared = HotkeyManager()

    var onTriggered: ((String) -> Void)?

    private static let signature: OSType = 0x434C5043  // 'CLPC'

    private weak var store: SettingsStore?
    private var cancellables = Set<AnyCancellable>()
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var actionIDs: [UInt32: String] = [:]
    private var handlerInstalled = false
    private var suspendCount = 0

    private init() {}

    func start(with store: SettingsStore) {
        self.store = store
        installHandler()
        register()

        store.$actionShortcuts
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.register() }
            .store(in: &cancellables)

        store.$openAppShortcut
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.register() }
            .store(in: &cancellables)
    }

    /// Unregisters every shortcut (used while recording a new one, so an existing combo can be captured instead of fired).
    func suspend() {
        suspendCount += 1
        unregisterAll()
    }

    func resume() {
        suspendCount = max(0, suspendCount - 1)
        if suspendCount == 0 { register() }
    }

    // MARK: - Registration

    private func register() {
        unregisterAll()
        guard suspendCount == 0, let store else { return }

        var entries: [(id: String, shortcut: KeyShortcut)] = store.actionShortcuts.map { ($0.key, $0.value) }
        if let open = store.openAppShortcut { entries.append(("openApp", open)) }

        var nextID: UInt32 = 1
        for entry in entries {
            let hotKeyID = EventHotKeyID(signature: Self.signature, id: nextID)
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                UInt32(entry.shortcut.keyCode),
                Self.carbonModifiers(from: entry.shortcut.modifierFlags),
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &ref
            )
            // Fails if another app already owns the combination; that shortcut simply stays inactive.
            if status == noErr, let ref {
                hotKeyRefs.append(ref)
                actionIDs[nextID] = entry.id
            }
            nextID += 1
        }
    }

    private func unregisterAll() {
        hotKeyRefs.forEach { UnregisterEventHotKey($0) }
        hotKeyRefs.removeAll()
        actionIDs.removeAll()
    }

    private static func carbonModifiers(from rawFlags: UInt) -> UInt32 {
        let flags = NSEvent.ModifierFlags(rawValue: rawFlags)
        var result = 0
        if flags.contains(.command) { result |= cmdKey }
        if flags.contains(.shift)   { result |= shiftKey }
        if flags.contains(.option)  { result |= optionKey }
        if flags.contains(.control) { result |= controlKey }
        return UInt32(result)
    }

    // MARK: - Event handling

    private func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr else { return status }
            // Carbon delivers hot key events on the main thread
            MainActor.assumeIsolated { HotkeyManager.shared.handle(hotKeyID: hotKeyID.id) }
            return noErr
        }, 1, &spec, nil, nil)
    }

    private func handle(hotKeyID: UInt32) {
        guard let actionID = actionIDs[hotKeyID] else { return }
        onTriggered?(actionID)
    }
}
