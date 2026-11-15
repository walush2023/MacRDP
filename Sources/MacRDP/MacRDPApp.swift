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
        }
        .defaultSize(width: 1000, height: 680)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新增電腦…") { NotificationCenter.default.post(name: .newConnection, object: nil) }
                    .keyboardShortcut("n")
                Button("匯入 .rdp 檔案…") { NotificationCenter.default.post(name: .importRDP, object: nil) }
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

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

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
