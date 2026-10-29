import SwiftUI
import Combine
import Translation

struct ContentView: View {
    @EnvironmentObject var clipboardManager: ClipboardManager
    @State private var searchText = ""
    @State private var activeQuery = ""
    @State private var searchResults: [ClipboardItem] = []
    @State private var showCopiedMessage = false
    @StateObject private var tooltipController = TooltipController()

    var filteredItems: [ClipboardItem] {
        activeQuery.isEmpty ? clipboardManager.clipboardItems : searchResults
    }

    private struct SearchTrigger: Equatable {
        let query: String
        let revision: Int
    }

    func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        showCopiedMessage = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            showCopiedMessage = false
        }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                ToolbarView(searchText: $searchText) {
                    clipboardManager.clearAll()
                }

                List(filteredItems) { item in
                    ClipboardRowView(item: item, tooltipController: tooltipController) {
                        copyToClipboard(clipboardManager.content(for: item.id) ?? item.preview)
                    }
                    .listRowSeparator(.hidden)
                }
                .scrollContentBackground(.hidden)
                .background(.thinMaterial)
            }

            if showCopiedMessage {
                Text("Copied to clipboard")
                    .padding(10)
                    .background(.regularMaterial.opacity(0.9))
                    .cornerRadius(12)
                    .shadow(radius: 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .overlayPreferenceValue(TooltipPreferenceKey.self) { value in
            GeometryReader { proxy in
                if let value = value {
                    TooltipBubble(text: value.text)
                        .position(x: proxy[value.anchor].midX, y: proxy[value.anchor].minY - 10)
                        .allowsHitTesting(false)
                }
            }
        }
        .animation(.easeInOut, value: showCopiedMessage)
        .task(id: searchText) {
            // Debounce: only filter once typing pauses
            if !searchText.isEmpty { try? await Task.sleep(for: .milliseconds(150)) }
            guard !Task.isCancelled else { return }
            activeQuery = searchText
        }
        .task(id: SearchTrigger(query: activeQuery, revision: clipboardManager.revision)) {
            guard !activeQuery.isEmpty else { searchResults = []; return }
            let results = await clipboardManager.search(activeQuery)
            if !Task.isCancelled { searchResults = results }
        }
        .background(.thinMaterial)
        .contextMenu {
            Button {
                NotificationCenter.default.post(name: .openOptionsRequest, object: nil)
            } label: {
                Label("Options", systemImage: "gearshape")
            }
            Divider()
            Button {
                clipboardManager.clearAll()
            } label: {
                Label("Clear All", systemImage: "trash")
            }
            Divider()
            Button(role: .destructive) {
                NSApp.terminate(nil)
            } label: {
                Label("Quit ClipContext", systemImage: "power")
            }
        }
    }
}

struct ClipboardRowView: View {
    let item: ClipboardItem
    let onClick: () -> Void
    let tooltipController: TooltipController
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var clipboardManager: ClipboardManager
    @State private var isHovering = false
    @State private var showMoreOptions = false
    @State private var showTranslation = false
    @State private var translationText = ""

    init(item: ClipboardItem, tooltipController: TooltipController, onClick: @escaping () -> Void) {
        self.item = item
        self.onClick = onClick
        self.tooltipController = tooltipController
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                Text(item.preview)
                    .lineLimit(3)

                Spacer()

                HStack(spacing: 6) {
                    ForEach(settings.pinnedActionIDs.prefix(4), id: \.self) { id in
                        if let action = allActions.action(id: id) {
                            TooltipButton(systemImage: action.systemImage, tooltip: action.label, action: {
                                handleAction(action)
                            }, controller: tooltipController)
                        }
                    }

                    Button(action: { showMoreOptions.toggle() }) {
                        Image(systemName: "ellipsis")
                            .rotationEffect(.degrees(90))
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .popover(isPresented: $showMoreOptions, arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(settings.moreActionIDs, id: \.self) { id in
                                if let action = allActions.action(id: id) {
                                    MoreOptionButton(label: action.label, systemImage: action.systemImage) {
                                        handleAction(action)
                                        if action.id != "translate" {
                                            showMoreOptions = false
                                        }
                                    }
                                }
                            }
                            Divider().padding(.horizontal, 4).padding(.vertical, 2)
                            MoreOptionButton(label: loc("Remove"), systemImage: "trash", tint: .red) {
                                showMoreOptions = false
                                clipboardManager.remove(itemID: item.id)
                            }
                        }
                        .padding(4)
                        .frame(minWidth: 200)
                    }
                }
                .foregroundColor(.secondary)
            }

            HStack {
                Text(item.sourceApp)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(item.wordCount) words · \(item.charCount) chars")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Text(item.dateCopied, style: .time)
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.controlBackgroundColor))
                .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.primary.opacity(isHovering ? 0.12 : 0.07), lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onClick()
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovering = hovering
            }
        }
        .translationPresentation(isPresented: $showTranslation, text: translationText) { translatedText in
            clipboardManager.updateContent(itemID: item.id, newText: translatedText)
            translationText = ""
        }
        .onReceive(clipboardManager.$translationRequest) { id in
            guard id == item.id else { return }
            beginTranslation()
            DispatchQueue.main.async { clipboardManager.translationRequest = nil }
        }
    }

    private func beginTranslation() {
        translationText = clipboardManager.content(for: item.id) ?? item.preview
        showTranslation = true
    }

    private func handleAction(_ action: ClipAction) {
        if action.id == "translate" {
            beginTranslation()
        } else {
            clipboardManager.apply(action, to: item.id)
        }
    }
}

struct MoreOptionButton: View {
    let label: String
    let systemImage: String
    let tint: Color
    let action: () -> Void
    @State private var isHovering = false

    init(label: String, systemImage: String, tint: Color = .primary, action: @escaping () -> Void) {
        self.label = label
        self.systemImage = systemImage
        self.tint = tint
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .frame(width: 16)
                Text(label)
                Spacer()
            }
            .foregroundStyle(tint)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(isHovering ? tint.opacity(0.12) : Color.clear)
            .cornerRadius(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

struct TooltipData: Equatable {
    let text: String
    let anchor: Anchor<CGRect>

    static func == (lhs: TooltipData, rhs: TooltipData) -> Bool {
        lhs.text == rhs.text
    }
}

struct TooltipPreferenceKey: PreferenceKey {
    static var defaultValue: TooltipData? = nil

    static func reduce(value: inout TooltipData?, nextValue: () -> TooltipData?) {
        value = nextValue() ?? value
    }
}

struct TooltipBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(.regularMaterial.opacity(0.9))
            .cornerRadius(8)
            .shadow(radius: 6)
            .fixedSize()
    }
}

final class TooltipController: ObservableObject {
    @Published private(set) var isWarm = false
    private var warmResetTask: DispatchWorkItem?

    var currentDelay: TimeInterval {
        isWarm ? 0.15 : 1.0
    }

    func markShown() {
        isWarm = true
        cancelWarmReset()
    }

    func markHidden() {
        cancelWarmReset()
        let task = DispatchWorkItem { [weak self] in
            self?.isWarm = false
        }
        warmResetTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: task)
    }

    private func cancelWarmReset() {
        warmResetTask?.cancel()
        warmResetTask = nil
    }
}

struct TooltipButton: View {
    let systemImage: String
    let tooltip: String
    let action: () -> Void
    @ObservedObject var controller: TooltipController
    @State private var isTooltipVisible = false
    @State private var showTask: DispatchWorkItem?

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
        }
        .buttonStyle(.borderless)
        .anchorPreference(key: TooltipPreferenceKey.self, value: .bounds) { anchor in
            isTooltipVisible ? TooltipData(text: tooltip, anchor: anchor) : nil
        }
        .onHover { hovering in
            if hovering {
                scheduleTooltip()
            } else {
                cancelTooltip()
                isTooltipVisible = false
                controller.markHidden()
            }
        }
    }

    private func scheduleTooltip() {
        cancelTooltip()
        let task = DispatchWorkItem {
            isTooltipVisible = true
            controller.markShown()
        }
        showTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + controller.currentDelay, execute: task)
    }

    private func cancelTooltip() {
        showTask?.cancel()
        showTask = nil
    }
}
