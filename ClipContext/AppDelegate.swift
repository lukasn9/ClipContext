import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var clipboardManager = ClipboardManager()
    private var optionsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
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
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
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
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp || (event.type == .leftMouseUp && event.modifierFlags.contains(.control)) {
            let menu = NSMenu()
            let optionsItem = NSMenuItem(title: "Options", action: #selector(openOptions), keyEquivalent: "")
            optionsItem.target = self
            menu.addItem(optionsItem)
            menu.addItem(NSMenuItem.separator())
            let clearItem = NSMenuItem(title: "Clear Clipboard", action: #selector(clearClipboard), keyEquivalent: "")
            clearItem.target = self
            menu.addItem(clearItem)
            menu.addItem(NSMenuItem.separator())
            let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
            quitItem.target = self
            menu.addItem(quitItem)

            let location = NSEvent.mouseLocation
            menu.popUp(positioning: nil, at: NSPoint(x: location.x, y: location.y), in: nil)
        } else {
            togglePopover(nil)
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
