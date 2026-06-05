import AppKit
import SwiftUI
import Combine

struct KeyboardShortcutsTab: View {
    @EnvironmentObject var settings: SettingsStore
    @State private var isAccessibilityTrusted = AXIsProcessTrusted()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !isAccessibilityTrusted {
                    AccessibilityPermissionBanner()
                }

                VStack(alignment: .leading, spacing: 20) {
                    shortcutSection(
                        title: "Global",
                        subtitle: "Works system-wide. Requires Accessibility permission."
                    ) {
                        ShortcutRow(
                            systemImage: "menubar.dock.rectangle",
                            label: "Open App",
                            shortcut: settings.openAppShortcut,
                            onCommit: { settings.openAppShortcut = $0 }
                        )
                    }

                    shortcutSection(
                        title: "Actions",
                        subtitle: "Applied to the most recently copied item. Works system-wide."
                    ) {
                        ForEach(Array(allActions.enumerated()), id: \.element.id) { index, action in
                            ShortcutRow(
                                systemImage: action.systemImage,
                                label: action.label,
                                shortcut: settings.actionShortcuts[action.id],
                                onCommit: { sc in
                                    if let sc {
                                        settings.actionShortcuts[action.id] = sc
                                    } else {
                                        settings.actionShortcuts.removeValue(forKey: action.id)
                                    }
                                }
                            )
                            if index < allActions.count - 1 {
                                Divider().padding(.leading, 52)
                            }
                        }
                    }
                }
                .disabled(!isAccessibilityTrusted)
                .opacity(isAccessibilityTrusted ? 1.0 : 0.4)
            }
            .padding(16)
        }
        .onReceive(Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()) { _ in
            isAccessibilityTrusted = AXIsProcessTrusted()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            isAccessibilityTrusted = AXIsProcessTrusted()
        }
    }

    @ViewBuilder
    private func shortcutSection<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.controlBackgroundColor))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08), lineWidth: 1))
            )
        }
    }
}

struct AccessibilityPermissionBanner: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.title2)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("Accessibility Permission Required")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("Global shortcuts need Accessibility access to work system-wide.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button("Grant Access") {
                // Register ClipContext in the Accessibility list
                AXIsProcessTrustedWithOptions(
                    [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                )
                // Open System Settings directly — needed because the system alert
                // may appear behind the Options window on macOS 14
                NSWorkspace.shared.open(
                    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                )
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.orange.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.35), lineWidth: 1))
        )
    }
}

struct ShortcutRow: View {
    let systemImage: String
    let label: String
    let shortcut: KeyShortcut?
    let onCommit: (KeyShortcut?) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .frame(width: 20)
                .foregroundStyle(.secondary)

            Text(label)
                .foregroundStyle(.primary)

            Spacer()

            ShortcutRecorderField(shortcut: shortcut, onCommit: onCommit)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
