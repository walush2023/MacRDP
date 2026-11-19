import AppKit
import SwiftUI

/// Add / edit PC sheet. Tabs follow Windows App: General, Display, Devices & Audio, Folders,
/// then the extras (Performance, Gateway, Advanced).
struct ConnectionEditor: View {
    @Local var connection: Connection
    let isNew: Bool
    /// (connection, new password or nil = unchanged, new gateway password or nil = unchanged)
    let onSave: (Connection, String?, String?) -> Void

    @EnvironmentObject private var store: ConnectionStore
    @Environment(\.dismiss) private var dismiss
    @Local private var password = ""
    @Local private var gatewayPassword = ""
    @Local private var hasSavedPassword = false
    @Local private var tab = 0

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $tab) {
                general.tabItem { Text("General") }.tag(0)
                display.tabItem { Text("Display") }.tag(1)
                devices.tabItem { Text("Devices & Audio") }.tag(2)
                folders.tabItem { Text("Folders") }.tag(3)
                performance.tabItem { Text("Performance") }.tag(4)
                gateway.tabItem { Text("Gateway") }.tag(5)
                advanced.tabItem { Text("Advanced") }.tag(6)
            }
            .padding([.horizontal, .top])

            Divider()
            HStack {
                if !connection.host.isEmpty {
                    Text(connection.port == 3389 ? connection.host : "\(connection.host):\(connection.port)")
                        .foregroundStyle(.secondary).font(.callout)
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(isNew ? String(localized: "Add") : String(localized: "Save")) { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(connection.host.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(width: 700, height: 500)
        .onAppear {
            hasSavedPassword = Keychain.hasPassword(account: connection.keychainAccount)
        }
    }

    // MARK: Tabs

    private var general: some View {
        Form {
            Section {
                TextField("PC name or IP", text: $connection.host, prompt: Text("e.g. 192.168.1.10 or pc.example.com"))
                TextField("Port", value: $connection.port, format: .number.grouping(.never))
                TextField("Friendly name", text: $connection.friendlyName, prompt: Text("Optional"))
                Picker("Group", selection: $connection.group) {
                    Text("None").tag("")
                    ForEach(Array(Set(store.groups + [connection.group]).filter { !$0.isEmpty }).sorted(), id: \.self) {
                        Text($0).tag($0)
                    }
                }
                TextField("New group", text: $connection.group, prompt: Text("Type a name to create a group"))
            }
            Section("Credentials") {
                TextField("User name", text: $connection.username, prompt: Text("user, DOMAIN\\user or user@domain"))
                TextField("Domain", text: $connection.domain, prompt: Text("Optional"))
                SecureField("Password", text: $password,
                            prompt: Text(hasSavedPassword ? String(localized: "Saved (leave empty to keep)") : String(localized: "Optional")))
                Toggle("Save password in Keychain", isOn: $connection.savePassword)
                if hasSavedPassword {
                    Button("Clear Saved Password") {
                        Keychain.delete(account: connection.keychainAccount)
                        hasSavedPassword = false
                    }
                }
            }
            Section {
                Toggle("Reconnect if the connection drops", isOn: $connection.reconnect)
                Toggle("Connect to an admin session", isOn: $connection.adminSession)
            }
        }
        .formStyle(.grouped)
    }

    private var display: some View {
        Form {
            Section {
                Picker("Resolution", selection: $connection.resolution) {
                    ForEach(Resolution.allCases) { Text($0.label).tag($0) }
                }
                if connection.resolution == .custom {
                    HStack {
                        TextField("Width", value: $connection.customWidth, format: .number.grouping(.never))
                        Text("×")
                        TextField("Height", value: $connection.customHeight, format: .number.grouping(.never))
                    }
                }
                Toggle("Update the session resolution on resize", isOn: $connection.dynamicResolution)
                Picker("Scale", selection: $connection.desktopScale) {
                    ForEach([100, 125, 150, 175, 200, 250, 300], id: \.self) { Text("\($0)%").tag($0) }
                }
            }
            Section {
                Toggle("Start session in full screen", isOn: $connection.fullscreen)
                Toggle("Use all monitors", isOn: $connection.useAllMonitors)
                Toggle("Fit session to window", isOn: $connection.fitToWindow)
            } footer: {
                Text("Full screen uses native macOS full screen: each session gets its own Space; swipe with four fingers or press Control-←/→ to switch. Control-Option-Return toggles full screen.")
            }
            Section {
                Picker("Color quality", selection: $connection.colorDepth) {
                    ForEach(ColorDepth.allCases) { Text($0.label).tag($0) }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var devices: some View {
        Form {
            Section("Clipboard") {
                Picker("Text and images", selection: $connection.clipboard) {
                    ForEach(ClipboardDirection.allCases) { Text($0.label).tag($0) }
                }
                Picker("Files", selection: $connection.fileClipboard) {
                    ForEach(ClipboardDirection.allCases) { Text($0.label).tag($0) }
                }
            }
            Section("Redirect") {
                Toggle("Printers", isOn: $connection.printers)
                Toggle("Smart cards", isOn: $connection.smartCards)
                Toggle("Microphone", isOn: $connection.microphone)
            }
            Section("Audio") {
                Picker("Play sound", selection: $connection.sound) {
                    ForEach(SoundMode.allCases) { Text($0.label).tag($0) }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var folders: some View {
        Form {
            Section {
                Toggle("Share my home folder", isOn: $connection.redirectHome)
            }
            Section {
                ForEach($connection.folders) { $f in
                    HStack {
                        TextField("Name", text: $f.name).frame(width: 120)
                        Text(f.path).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                        Spacer()
                        Button(role: .destructive) {
                            connection.folders.removeAll { $0.id == f.id }
                        } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                    }
                }
                Button("Add Folder…") { addFolder() }
            } header: {
                Text("Redirected folders")
            } footer: {
                Text("They appear on the remote PC under This PC as \"<name> on <this Mac>\".")
            }
        }
        .formStyle(.grouped)
    }

    private var performance: some View {
        Form {
            Section {
                Picker("Transport", selection: $connection.transport) {
                    ForEach(Transport.allCases) { Text($0.label).tag($0) }
                }
                Picker("Graphics codec", selection: $connection.codec) {
                    ForEach(GraphicsCodec.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Uncapped frame rate (don't wait for frame acknowledgements)", isOn: $connection.unlimitedFrames)
                Picker("Network type", selection: $connection.network) {
                    ForEach(NetworkType.allCases) { Text($0.label).tag($0) }
                }
            } footer: {
                Text("To go above 30 fps and use H.264, the Windows PC needs a few changes too. See \"Windows setup\" in the README.")
            }
            Section("Visual effects") {
                Toggle("Wallpaper", isOn: $connection.wallpaper)
                Toggle("Themes", isOn: $connection.themes)
                Toggle("Font smoothing (ClearType)", isOn: $connection.fontSmoothing)
                Toggle("Desktop composition (transparency)", isOn: $connection.desktopComposition)
                Toggle("Show window contents while dragging", isOn: $connection.windowDrag)
                Toggle("Menu animations", isOn: $connection.menuAnimations)
            }
        }
        .formStyle(.grouped)
    }

    private var gateway: some View {
        Form {
            Section {
                Toggle("Use a Remote Desktop Gateway", isOn: $connection.gateway.enabled)
                if connection.gateway.enabled {
                    TextField("Gateway server", text: $connection.gateway.host, prompt: Text("gateway.example.com"))
                    TextField("Port", value: $connection.gateway.port, format: .number.grouping(.never))
                    Toggle("Bypass the gateway for local addresses", isOn: $connection.gateway.bypassForLocal)
                    Toggle("Use the PC's credentials", isOn: $connection.gateway.useConnectionCredentials)
                    if !connection.gateway.useConnectionCredentials {
                        TextField("Gateway user name", text: $connection.gateway.username)
                        TextField("Gateway domain", text: $connection.gateway.domain)
                        SecureField("Gateway password", text: $gatewayPassword, prompt: Text("Leave empty to keep"))
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var advanced: some View {
        Form {
            Section("Security") {
                Picker("Server certificate", selection: $connection.certificate) {
                    ForEach(CertificatePolicy.allCases) { Text($0.label).tag($0) }
                }
                Picker("Security protocol", selection: $connection.security) {
                    ForEach(SecurityMode.allCases) { Text($0.label).tag($0) }
                }
            }
            Section("Launch") {
                TextField("RemoteApp program", text: $connection.remoteApp, prompt: Text("e.g. ||notepad or C:\\Windows\\notepad.exe"))
                TextField("Alternate shell", text: $connection.alternateShell, prompt: Text("Optional"))
                TextField("Load balance info", text: $connection.loadBalanceInfo, prompt: Text("Optional"))
            }
            Section {
                TextField("Keyboard layout", text: $connection.keyboardLayout, prompt: Text("Empty = follow the Mac, e.g. 0x00000409"))
                TextField("Extra FreeRDP arguments", text: $connection.extraArguments, prompt: Text("e.g. /timeout:30000 +async-channels"), axis: .vertical)
                    .lineLimit(2...4)
            } footer: {
                Text("Extra arguments are appended to the sdl-freerdp command line.")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Actions

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            connection.folders.append(SharedFolder(name: url.lastPathComponent, path: url.path))
        }
    }

    private func save() {
        connection.host = connection.host.trimmingCharacters(in: .whitespaces)
        // Accept "host:port" typed into the host field.
        let (h, p) = RDPFile.splitHostPort(connection.host)
        connection.host = h
        if let p { connection.port = p }
        // Accept DOMAIN\user typed into the user field.
        if let slash = connection.username.firstIndex(of: "\\"), connection.domain.isEmpty {
            connection.domain = String(connection.username[..<slash])
            connection.username = String(connection.username[connection.username.index(after: slash)...])
        }
        onSave(connection, password.isEmpty ? nil : password, gatewayPassword.isEmpty ? nil : gatewayPassword)
        dismiss()
    }
}

struct PreferencesView: View {
    @AppStorage("freerdpPath") private var freerdpPath = ""
    @AppStorage("useRelay") private var useRelay = true

    var body: some View {
        Form {
            Section {
                TextField("sdl-freerdp path", text: $freerdpPath, prompt: Text("Empty = find automatically"))
                LabeledContent("In use", value: SessionManager.freerdpBinary()?.path ?? String(localized: "Not found"))
            } footer: {
                Text("Search order: the FreeRDP inside the app → /opt/homebrew/bin → /usr/local/bin. The Homebrew build has no UDP support.")
            }
            Section {
                Toggle("Relay connections through MacRDP", isOn: $useRelay)
            } footer: {
                Text("macOS asks only MacRDP, not FreeRDP, for Local Network access. With this on, FreeRDP connects to 127.0.0.1 and MacRDP relays TCP and UDP to the PC, so no extra permission is needed. Not used with an RD Gateway.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .padding()
    }
}
