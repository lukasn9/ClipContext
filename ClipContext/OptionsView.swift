import AppKit
import SwiftUI

// Hides the minimize and zoom traffic-light buttons, leaving only close.
private struct HideExtraWindowButtons: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.standardWindowButton(.miniaturizeButton)?.isHidden = true
            view.window?.standardWindowButton(.zoomButton)?.isHidden = true
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

enum OptionsTab: String, CaseIterable {
    case customization  = "Customization"
    case behaviour      = "Behaviour"
    case shortcuts      = "Shortcuts"
    case about          = "About"

    var systemImage: String {
        switch self {
        case .customization: return "slider.horizontal.3"
        case .behaviour:     return "gearshape"
        case .shortcuts:     return "keyboard"
        case .about:         return "info.circle"
        }
    }
}

struct OptionsView: View {
    @EnvironmentObject var settings: SettingsStore
    @State private var selectedTab: OptionsTab = .customization

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 4) {
                ForEach(OptionsTab.allCases, id: \.self) { tab in
                    OptionsTabButton(tab: tab, isSelected: selectedTab == tab) {
                        selectedTab = tab
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .padding(.top, 28) // clear the hidden title bar
            .background(.thinMaterial)

            Divider()

            Group {
                switch selectedTab {
                case .customization: CustomizationTab()
                case .behaviour:     BehaviourTab()
                case .shortcuts:     KeyboardShortcutsTab()
                case .about:         AboutTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 520, height: 500)
        .background(.thinMaterial)
        .background(HideExtraWindowButtons())
    }
}

struct OptionsTabButton: View {
    let tab: OptionsTab
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: tab.systemImage)
                    .imageScale(.small)
                Text(LocalizedStringKey(tab.rawValue))
                    .font(.subheadline)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected
                          ? Color.accentColor.opacity(0.15)
                          : (isHovering ? Color.primary.opacity(0.06) : Color.clear))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
        .onHover { isHovering = $0 }
    }
}
