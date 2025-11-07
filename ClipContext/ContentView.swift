import SwiftUI

struct ContentView: View {
    @EnvironmentObject var clipboardManager: ClipboardManager
    @State private var searchText = ""
    @State private var showCopiedMessage = false
    @State private var copiedText = ""

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
                    ClipboardRowView(item: item) {
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
        .animation(.easeInOut, value: showCopiedMessage)
        .frame(minWidth: 600, minHeight: 400)
        .background(.thinMaterial)
    }
}

struct ClipboardRowView: View {
    let item: ClipboardItem
    let onClick: () -> Void
    @State private var isHovering = false
    @State private var currentText: String

    init(item: ClipboardItem, onClick: @escaping () -> Void) {
        self.item = item
        self.onClick = onClick
        _currentText = State(initialValue: item.content)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                Text(currentText)
                    .lineLimit(3)

                Spacer()

                HStack(spacing: 6) {
                    Button(action: { currentText = currentText.trimmingCharacters(in: .whitespacesAndNewlines) }) {
                        Image(systemName: "arrow.left.and.right")
                    }
                    .buttonStyle(.borderless)

                    Button(action: { currentText = currentText.lowercased() }) {
                        Image(systemName: "textformat.size.smaller")
                    }
                    .buttonStyle(.borderless)

                    Button(action: { currentText = currentText.capitalized }) {
                        Image(systemName: "textformat")
                    }
                    .buttonStyle(.borderless)

                    Button(action: {
                        if let url = extractFirstURL(from: currentText) {
                            currentText = url
                        }
                    }) {
                        Image(systemName: "link")
                    }
                    .buttonStyle(.borderless)
                }
                .foregroundColor(.secondary)
            }

            HStack {
                Text(item.sourceApp)
                    .foregroundStyle(.secondary)
                Spacer()
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
    }

    private func extractFirstURL(from text: String) -> String? {
        let types: NSTextCheckingResult.CheckingType = .link
        guard let detector = try? NSDataDetector(types: types.rawValue) else { return nil }
        let matches = detector.matches(in: text, range: NSRange(text.startIndex..., in: text))
        if let match = matches.first, let range = Range(match.range, in: text) {
            return String(text[range])
        }
        return nil
    }
}
