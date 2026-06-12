import ServiceManagement
import SwiftUI

private let supportedLanguages: [(code: String, name: String)] = [
    ("system", "System Default"),
    ("en", "English"),
    ("de", "Deutsch"),
    ("nl", "Nederlands"),
    ("sk", "Slovenčina"),
    ("cs", "Čeština"),
    ("es", "Español"),
    ("fr", "Français"),
]

struct BehaviourTab: View {
    @EnvironmentObject var settings: SettingsStore
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var selectedLanguage: String = {
        UserDefaults.standard.string(forKey: "ClipContextLanguage") ?? "system"
    }()
    @State private var showRestartNote = false


    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("General")
                        .font(.headline)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)

                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Image(systemName: "power")
                            .frame(width: 20)
                            .foregroundStyle(.secondary)
                        Text("Launch at Login")
                        Spacer()
                        Toggle("", isOn: $launchAtLogin)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .onChange(of: launchAtLogin) { _, enabled in
                                setLaunchAtLogin(enabled)
                            }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    Divider().padding(.leading, 52)

                    HStack(spacing: 12) {
                        Image(systemName: "globe")
                            .frame(width: 20)
                            .foregroundStyle(.secondary)
                        Text("Language")
                        Spacer()
                        Picker("", selection: $selectedLanguage) {
                            ForEach(supportedLanguages, id: \.code) { lang in
                                Text(lang.code == "system" ? String(localized: "System Default") : lang.name)
                                    .tag(lang.code)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                        .onChange(of: selectedLanguage) { _, newValue in
                            UserDefaults.standard.set(newValue, forKey: "ClipContextLanguage")
                            if newValue == "system" {
                                UserDefaults.standard.removeObject(forKey: "AppleLanguages")
                            } else {
                                UserDefaults.standard.set([newValue], forKey: "AppleLanguages")
                            }
                            showRestartNote = true
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    if showRestartNote {
                        Divider().padding(.leading, 52)
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.counterclockwise.circle")
                                .foregroundStyle(.orange)
                                .frame(width: 20)
                            Text("Restart ClipContext to apply the language change.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(.controlBackgroundColor))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08), lineWidth: 1))
                )
                .padding(.horizontal, 16)

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
                    let applyableActions = allActions.filter { $0.id != "translate" }
                    ForEach(Array(applyableActions.enumerated()), id: \.element.id) { index, action in
                        AutoApplyRow(
                            action: action,
                            isEnabled: settings.autoApplyActionIDs.contains(action.id),
                            onToggle: { toggle(action.id) }
                        )
                        if index < applyableActions.count - 1 {
                            Divider().padding(.leading, 52)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(.controlBackgroundColor))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08), lineWidth: 1))
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
                        .fill(Color(.controlBackgroundColor))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08), lineWidth: 1))
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // requiresApproval means the user previously removed the item — send them to System Settings
            if SMAppService.mainApp.status == .requiresApproval {
                NSWorkspace.shared.open(
                    URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!
                )
            }
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
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
