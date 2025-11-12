import SwiftUI
import Combine
import Translation

struct ContentView: View {
    @EnvironmentObject var clipboardManager: ClipboardManager
    @State private var searchText = ""
    @State private var showCopiedMessage = false
    @State private var copiedText = ""
    @StateObject private var tooltipController = TooltipController()

    var filteredItems: [ClipboardItem] {
        if searchText.isEmpty {
            return clipboardManager.clipboardItems
        } else {
            return clipboardManager.clipboardItems.filter {
                $0.content.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copiedText = text
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
                        copyToClipboard(item.content)
                    }
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
        .background(.thinMaterial)
    }
}

struct ClipboardRowView: View {
    let item: ClipboardItem
    let onClick: () -> Void
    let tooltipController: TooltipController
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var clipboardManager: ClipboardManager
    @State private var isHovering = false
    @State private var currentText: String
    @State private var showMoreOptions = false
    @State private var showTranslation = false

    init(item: ClipboardItem, tooltipController: TooltipController, onClick: @escaping () -> Void) {
        self.item = item
        self.onClick = onClick
        self.tooltipController = tooltipController
        _currentText = State(initialValue: item.content)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                Text(currentText)
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
                            MoreOptionButton(label: "Remove", systemImage: "trash", tint: .red) {
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
                Text("\(wordCount) words · \(currentText.count) chars")
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
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
                .opacity(isHovering ? 0.95 : 0.9)
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
        .translationPresentation(isPresented: $showTranslation, text: currentText) { translatedText in
            currentText = translatedText
        }
        .onChange(of: currentText) { _, newText in
            clipboardManager.updateContent(itemID: item.id, newText: newText)
        }
    }

    private var wordCount: Int {
        currentText.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
    }

    private func handleAction(_ action: ClipAction) {
        if action.id == "translate" {
            showTranslation = true
        } else {
            currentText = action.transform(currentText)
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
