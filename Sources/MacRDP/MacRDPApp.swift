import AppKit
import SwiftUI
import UniformTypeIdentifiers

@main
struct MacRDPApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = ConnectionStore()
    @StateObject private var sessions = SessionManager()

    init() {
        if CommandLine.arguments.contains("--self-test") { exit(SelfTest.run()) }
    }

    var body: some Scene {
        Window("MacRDP", id: "main") {
            ContentView()
                .environmentObject(store)
                .environmentObject(sessions)
                .frame(minWidth: 760, minHeight: 600)
                .onAppear { delegate.sessions = sessions }
                .background(OpenWindowCapture { delegate.openMainWindow = $0 })
        }
        .defaultSize(width: 1000, height: 680)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add PC…") { NotificationCenter.default.post(name: .newConnection, object: nil) }
                    .keyboardShortcut("n")
                Button("Import .rdp File…") { NotificationCenter.default.post(name: .importRDP, object: nil) }
                    .keyboardShortcut("o")
            }
        }

        Settings {
            PreferencesView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var sessions: SessionManager?
    /// Reopens the main window; captured from SwiftUI because a closed `Window` scene does not
    /// come back by itself when the Dock icon is clicked.
    var openMainWindow: (() -> Void)?

    /// The app keeps running when its window is closed (sessions may still be open), like Windows App.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Clicking the Dock icon (or opening the app again) with no window open brings the main window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showMainWindow() }
        return true
    }

    func showMainWindow() {
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" && !$0.isVisible }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            MainActor.assumeIsolated { openMainWindow?() }
        }
        NSApp.activate()
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { sessions?.disconnectAll() }
    }

    /// Double-clicking a .rdp file in Finder.
    func application(_ application: NSApplication, open urls: [URL]) {
        NotificationCenter.default.post(name: .openRDPFiles, object: urls)
    }
}

extension Notification.Name {
    static let newConnection = Notification.Name("MacRDP.newConnection")
    static let importRDP = Notification.Name("MacRDP.importRDP")
    static let openRDPFiles = Notification.Name("MacRDP.openRDPFiles")
}

extension UTType {
    static let rdp = UTType(filenameExtension: "rdp") ?? .data
}


/// Hands SwiftUI's `openWindow` action to the app delegate.
private struct OpenWindowCapture: View {
    @Environment(\.openWindow) private var openWindow
    let store: (@escaping () -> Void) -> Void

    var body: some View {
        Color.clear.onAppear { store { openWindow(id: "main") } }
    }
}
