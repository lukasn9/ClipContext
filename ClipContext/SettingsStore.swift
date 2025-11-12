import AppKit
import Carbon.HIToolbox
import Combine
import Foundation

struct KeyShortcut: Codable, Equatable {
    let keyCode: UInt16
    let modifierFlags: UInt  // NSEventModifierFlags.rawValue, masked to ⌘⌥⇧⌃

    var displayString: String {
        var s = ""
        let flags = NSEvent.ModifierFlags(rawValue: modifierFlags)
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option)  { s += "⌥" }
        if flags.contains(.shift)   { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        s += keyCodeToDisplayString(keyCode)
        return s
    }
}

private func keyCodeToDisplayString(_ keyCode: UInt16) -> String {
    let table: [UInt16: String] = [
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋",
        76: "↩", 115: "↖", 116: "⇞", 117: "⌦", 119: "↘",
        121: "⇟", 122: "F1", 120: "F2", 99: "F3", 118: "F4",
        96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9",
        109: "F10", 103: "F11", 111: "F12", 123: "←", 124: "→",
        125: "↓", 126: "↑",
    ]
    if let s = table[keyCode] { return s }

    guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
          let rawData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
        return "(\(keyCode))"
    }
    let layoutData = Unmanaged<CFData>.fromOpaque(rawData).takeUnretainedValue() as Data
    var deadKeyState: UInt32 = 0
    var chars = [UniChar](repeating: 0, count: 4)
    var actualLength: Int = 0
    let err = layoutData.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) -> OSStatus in
        UCKeyTranslate(
            ptr.baseAddress!.assumingMemoryBound(to: UCKeyboardLayout.self),
            keyCode,
            UInt16(kUCKeyActionDisplay),
            0,
            UInt32(LMGetKbdType()),
            UInt32(kUCKeyTranslateNoDeadKeysMask),
            &deadKeyState,
            4,
            &actualLength,
            &chars
        )
    }
    guard err == noErr, actualLength > 0 else { return "(\(keyCode))" }
    return String(chars[0..<Int(actualLength)].compactMap { Unicode.Scalar($0).map(Character.init) }).uppercased()
}

// MARK: -

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private let defaults = UserDefaults.standard
    private let prefix = "com.LukasNagy.ClipContext."
    private var cancellables = Set<AnyCancellable>()

    @Published var pinnedActionIDs: [String]
    @Published var moreActionIDs: [String]
    @Published var autoApplyActionIDs: [String]
    @Published var actionShortcuts: [String: KeyShortcut]
    @Published var openAppShortcut: KeyShortcut?
    @Published var historyLimit: Int

    private init() {
        let defaultPinned = Array(allActions.prefix(4).map(\.id))
        let defaultMore   = Array(allActions.dropFirst(4).map(\.id))

        pinnedActionIDs    = defaults.stringArray(forKey: prefix + "pinnedActionIDs")    ?? defaultPinned
        moreActionIDs      = defaults.stringArray(forKey: prefix + "moreActionIDs")      ?? defaultMore
        autoApplyActionIDs = defaults.stringArray(forKey: prefix + "autoApplyActionIDs") ?? []
        actionShortcuts    = Self.decodeDict(from: defaults, key: prefix + "actionShortcuts")   ?? [:]
        openAppShortcut    = Self.decodeValue(from: defaults, key: prefix + "openAppShortcut")
        let saved = defaults.integer(forKey: prefix + "historyLimit")
        historyLimit = saved > 0 ? saved : 200

        // Migrate: append any action IDs added since the user's last launch
        let placed = Set(pinnedActionIDs + moreActionIDs)
        let missing = allActions.map(\.id).filter { !placed.contains($0) }
        moreActionIDs.append(contentsOf: missing)

        $pinnedActionIDs   .dropFirst().sink { [weak self] _ in self?.save() }.store(in: &cancellables)
        $moreActionIDs     .dropFirst().sink { [weak self] _ in self?.save() }.store(in: &cancellables)
        $autoApplyActionIDs.dropFirst().sink { [weak self] _ in self?.save() }.store(in: &cancellables)
        $actionShortcuts   .dropFirst().sink { [weak self] _ in self?.save() }.store(in: &cancellables)
        $openAppShortcut   .dropFirst().sink { [weak self] _ in self?.save() }.store(in: &cancellables)
        $historyLimit      .dropFirst().sink { [weak self] _ in self?.save() }.store(in: &cancellables)
    }

    func save() {
        defaults.set(pinnedActionIDs,    forKey: prefix + "pinnedActionIDs")
        defaults.set(moreActionIDs,      forKey: prefix + "moreActionIDs")
        defaults.set(autoApplyActionIDs, forKey: prefix + "autoApplyActionIDs")
        defaults.set(historyLimit,       forKey: prefix + "historyLimit")
        if let data = try? JSONEncoder().encode(actionShortcuts) {
            defaults.set(data, forKey: prefix + "actionShortcuts")
        }
        if let sc = openAppShortcut, let data = try? JSONEncoder().encode(sc) {
            defaults.set(data, forKey: prefix + "openAppShortcut")
        } else if openAppShortcut == nil {
            defaults.removeObject(forKey: prefix + "openAppShortcut")
        }
    }

    private static func decodeDict<V: Decodable>(from defaults: UserDefaults, key: String) -> [String: V]? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode([String: V].self, from: data)
    }

    private static func decodeValue<V: Decodable>(from defaults: UserDefaults, key: String) -> V? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(V.self, from: data)
    }
}
