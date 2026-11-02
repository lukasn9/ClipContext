import AppKit
import SwiftUI
import Combine

struct KeyboardShortcutsTab: View {
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 20) {
                    shortcutSection(
                        title: loc("Global"),
                        subtitle: nil
                    ) {
                        ShortcutRow(
                            systemImage: "menubar.dock.rectangle",
                            label: loc("Open App"),
                            shortcut: settings.openAppShortcut,
                            onCommit: { settings.openAppShortcut = $0 }
                        )
                    }

                    shortcutSection(
                        title: loc("Actions"),
                        subtitle: loc("Applied to the most recently copied item. Works system-wide.")
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
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private func shortcutSection<Content: View>(
        title: String,
        subtitle: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
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
