import SwiftUI

struct BehaviourTab: View {
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Auto-apply on Copy")
                        .font(.headline)
                    Text("Selected actions are automatically applied whenever new text is copied. They run in the order listed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)

                VStack(spacing: 0) {
                    ForEach(Array(allActions.enumerated()), id: \.element.id) { index, action in
                        AutoApplyRow(
                            action: action,
                            isEnabled: settings.autoApplyActionIDs.contains(action.id),
                            onToggle: { toggle(action.id) }
                        )
                        if index < allActions.count - 1 {
                            Divider().padding(.leading, 52)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.regularMaterial)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.2), lineWidth: 1))
                )
                .padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 4) {
                    Text("History")
                        .font(.headline)
                    Text("Maximum number of clipboard entries to keep. Older items are removed automatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16)

                HStack {
                    Image(systemName: "clock.arrow.2.circlepath")
                        .frame(width: 20)
                        .foregroundStyle(.secondary)
                    Text("History limit")
                    Spacer()
                    Text("\(settings.historyLimit) items")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Stepper("", value: $settings.historyLimit, in: 10...2000, step: 10)
                        .labelsHidden()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.regularMaterial)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.2), lineWidth: 1))
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
    }

    private func toggle(_ id: String) {
        if let idx = settings.autoApplyActionIDs.firstIndex(of: id) {
            settings.autoApplyActionIDs.remove(at: idx)
        } else {
            settings.autoApplyActionIDs.append(id)
        }
    }
}

struct AutoApplyRow: View {
    let action: ClipAction
    let isEnabled: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: action.systemImage)
                .frame(width: 20)
                .foregroundStyle(.secondary)

            Text(action.label)
                .foregroundStyle(.primary)

            Spacer()

            Toggle("", isOn: Binding(get: { isEnabled }, set: { _ in onToggle() }))
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
