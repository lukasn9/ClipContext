import AppKit
import SwiftUI

extension Notification.Name {
    static let openOptionsRequest = Notification.Name("com.LukasNagy.ClipContext.openOptions")
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var clipboardManager = ClipboardManager()
    private var optionsWindow: NSWindow?
    private var rightClickGlobalMonitor: Any?
    private var rightClickLocalMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(self, selector: #selector(openOptions), name: .openOptionsRequest, object: nil)
        popover = NSPopover()
        popover.contentSize = NSSize(width: 400, height: 250)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: ContentView()
                .environmentObject(clipboardManager)
                .environmentObject(SettingsStore.shared)
        )

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Clipboard")
            button.target = self
            button.action = #selector(statusBarButtonClicked(_:))
            button.sendAction(on: [.leftMouseUp])
        }

        // sendAction(on: .rightMouseUp) is broken on macOS 26+; use event monitors instead.
        // Global fires when another app is frontmost; local fires when our popover is focused.
        rightClickGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .rightMouseDown) { [weak self] _ in
            guard let self, self.isEventOnStatusButton() else { return }
            DispatchQueue.main.async { self.showStatusBarContextMenu() }
        }
        rightClickLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            guard let self, self.isEventOnStatusButton() else { return event }
            DispatchQueue.main.async { self.showStatusBarContextMenu() }
            return nil
        }

        // Remove SwiftUI's auto-generated "Settings…" menu item (and its ⌘, shortcut)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let appMenu = NSApp.mainMenu?.item(at: 0)?.submenu {
                let toRemove = appMenu.items.filter {
                    $0.action.map { NSStringFromSelector($0) } == "showSettingsWindow:"
                }
                toRemove.forEach { appMenu.removeItem($0) }
            }
        }

        HotkeyManager.shared.start(with: SettingsStore.shared)
        HotkeyManager.shared.onTriggered = { [weak self] id in
            DispatchQueue.main.async {
                if id == "openApp" {
                    self?.togglePopover(nil)
                } else if let action = allActions.action(id: id),
                          let top = self?.clipboardManager.clipboardItems.first {
                    let result = action.transform(top.content)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(result, forType: .string)
                }
            }
        }
    }

    @objc func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        // Control+click as an additional right-click trigger for older macOS
        if NSApp.currentEvent?.modifierFlags.contains(.control) == true {
            showStatusBarContextMenu()
        } else {
            togglePopover(nil)
        }
    }

    private func isEventOnStatusButton() -> Bool {
        guard let button = statusItem.button,
              let buttonWindow = button.window else { return false }
        let buttonFrameInScreen = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        return buttonFrameInScreen.contains(NSEvent.mouseLocation)
    }

    private func showStatusBarContextMenu() {
        let menu = NSMenu()

        let optionsItem = NSMenuItem(title: NSLocalizedString("Options", comment: ""), action: #selector(openOptions), keyEquivalent: "")
        optionsItem.target = self
        menu.addItem(optionsItem)
        menu.addItem(.separator())

        let clearItem = NSMenuItem(title: NSLocalizedString("Clear Clipboard", comment: ""), action: #selector(clearClipboard), keyEquivalent: "")
        clearItem.target = self
        menu.addItem(clearItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: NSLocalizedString("Quit ClipContext", comment: ""), action: #selector(quitApp), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)

        if let button = statusItem.button {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
        }
    }

    @objc func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            popover.contentViewController?.view.window?.level = .floating
        }
    }

    // No-op: prevents ⌘, from opening any window if SwiftUI's Settings item is still in the responder chain
    @objc func showSettingsWindow(_ sender: Any?) { }

    @objc func openOptions() {
        if optionsWindow == nil {
            let hosting = NSHostingController(
                rootView: OptionsView().environmentObject(SettingsStore.shared)
            )
            let win = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 500),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            win.title = "ClipContext Options"
            win.titlebarAppearsTransparent = true
            win.isMovableByWindowBackground = true
            win.isReleasedWhenClosed = false
            win.standardWindowButton(.miniaturizeButton)?.isHidden = true
            win.standardWindowButton(.zoomButton)?.isHidden = true
            win.center()
            win.contentViewController = hosting
            optionsWindow = win
        }
        NSApp.activate(ignoringOtherApps: true)
        optionsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func clearClipboard() {
        clipboardManager.clearAll()
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
    }
}
