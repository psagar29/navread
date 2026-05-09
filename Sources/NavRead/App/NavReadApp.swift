import AppKit
import SwiftUI

@main
struct NavReadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = NavReadStore()
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.system.rawValue

    var body: some Scene {
        WindowGroup("NavRead") {
            ContentView()
                .environmentObject(store)
                .preferredColorScheme(AppearanceMode(rawValue: appearanceMode)?.colorScheme)
                .frame(minWidth: 900, minHeight: 640)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Add Book") {
                    NotificationCenter.default.post(name: .navReadAddBook, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command])

                Button("Quick Capture") {
                    NotificationCenter.default.post(name: .navReadQuickCapture, object: nil)
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])

                Button("Quotes") {
                    NotificationCenter.default.post(name: .navReadOpenQuoteVault, object: nil)
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(store)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        if let icon = NavReadLogo.appIconImage {
            NSApp.applicationIconImage = icon
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension Notification.Name {
    static let navReadAddBook = Notification.Name("navReadAddBook")
    static let navReadQuickCapture = Notification.Name("navReadQuickCapture")
    static let navReadOpenQuoteVault = Notification.Name("navReadOpenQuoteVault")
    static let navReadCodexAuthCompleted = Notification.Name("navReadCodexAuthCompleted")
    static let navReadCodexAuthFailed = Notification.Name("navReadCodexAuthFailed")
}
