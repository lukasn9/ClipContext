import SwiftUI
import AppKit

@main
struct ClipContextApp: App {
    @StateObject private var clipboardManager = ClipboardManager()
    
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
