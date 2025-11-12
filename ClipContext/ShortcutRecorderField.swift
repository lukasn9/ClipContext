import AppKit
import SwiftUI

final class KeyCaptureNSView: NSView {
    var onKeyEvent: ((NSEvent) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        onKeyEvent?(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard let onKeyEvent else { return false }
        onKeyEvent(event)
        return true
    }
}

struct KeyCaptureView: NSViewRepresentable {
    let onKeyEvent: (NSEvent) -> Void

    func makeNSView(context: Context) -> KeyCaptureNSView {
        let view = KeyCaptureNSView()
        view.onKeyEvent = onKeyEvent
        return view
    }

    func updateNSView(_ nsView: KeyCaptureNSView, context: Context) {
        nsView.onKeyEvent = onKeyEvent
        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
        }
    }
}

struct ShortcutRecorderField: View {
    let shortcut: KeyShortcut?
    let onCommit: (KeyShortcut?) -> Void

    @State private var isRecording = false

    var body: some View {
        ZStack {
            // Visible pill
            HStack(spacing: 6) {
                if isRecording {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 7, height: 7)
                    Text("Recording…")
                        .foregroundStyle(.secondary)
                } else if let sc = shortcut {
                    Text(sc.displayString)
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                } else {
                    Text("None")
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.subheadline)
            .padding(.horizontal, 10)
            .frame(minWidth: 100, minHeight: 28)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(isRecording ? Color.accentColor : Color.white.opacity(0.2), lineWidth: 1)
            )
            .contentShape(Rectangle())
            .onTapGesture { isRecording = true }

            if isRecording {
                KeyCaptureView { event in handleKey(event) }
                    .frame(width: 1, height: 1)
                    .allowsHitTesting(false)
            }
        }
        .onChange(of: isRecording) { _, recording in
            if !recording { }
        }
    }

    private func handleKey(_ event: NSEvent) {
        let keyCode = event.keyCode

        if keyCode == 53 {
            isRecording = false
            return
        }
        if keyCode == 51 || keyCode == 117 {
            onCommit(nil)
            isRecording = false
            return
        }

        let relevant = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard !relevant.isEmpty else { return }

        let sc = KeyShortcut(keyCode: keyCode, modifierFlags: relevant.rawValue)
        onCommit(sc)
        isRecording = false
    }
}
