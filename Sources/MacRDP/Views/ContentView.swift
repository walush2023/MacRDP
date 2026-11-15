import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum SidebarItem: Hashable {
    case all, recent, group(String)
}

struct ContentView: View {
    @EnvironmentObject private var store: ConnectionStore
    @EnvironmentObject private var sessions: SessionManager

    @Local private var sidebar: SidebarItem? = .all
    @Local private var search = ""
    @Local private var selection = Set<UUID>()
    @Local private var editing: Connection?
    @Local private var isNew = false
    @Local private var passwordPrompt: Connection?
    @Local private var confirmDelete = false
    @AppStorage("viewAsGrid") private var grid = true

    var body: some View {
        NavigationSplitView {
            List(selection: $sidebar) {
                Label("所有電腦", systemImage: "desktopcomputer").tag(SidebarItem.all)
                Label("最近使用", systemImage: "clock").tag(SidebarItem.recent)
                if !store.groups.isEmpty {
                    Section("群組") {
                        ForEach(store.groups, id: \.self) { g in
                            Label(g, systemImage: "folder").tag(SidebarItem.group(g))
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } detail: {
            detail
                .searchable(text: $search, placement: .toolbar, prompt: "搜尋電腦")
                .toolbar { toolbar }
        }
        .sheet(item: $editing) { c in
            ConnectionEditor(connection: c, isNew: isNew) { saved, password, gatewayPassword in
                store.upsert(saved)
                if saved.savePassword {
                    if let password { Keychain.setPassword(password, account: saved.keychainAccount) }
                } else {
                    Keychain.delete(account: saved.keychainAccount)
                }
                if let gatewayPassword { Keychain.setPassword(gatewayPassword, account: Keychain.gatewayAccount(saved)) }
            }
        }
        .sheet(item: $passwordPrompt) { c in
            PasswordPrompt(connection: c) { password, remember in
                var c = c
                if remember {
                    c.savePassword = true
                    Keychain.setPassword(password, account: c.keychainAccount)
                    store.upsert(c)
                }
                start(c, password: password)
            }
        }
        .alert(item: $sessions.failure) { f in
            Alert(title: Text(f.title), message: Text(f.message),
                  primaryButton: .default(Text(f.openPrivacySettings ? "打開系統設定" : (f.wrongPassword ? "重新輸入密碼" : "顯示記錄"))) {
                      if f.openPrivacySettings {
                          NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork")!)
                      } else if f.wrongPassword, let c = store.connection(id: f.connectionID) {
                          Keychain.delete(account: c.keychainAccount)
                          passwordPrompt = c
                      } else {
                          NSWorkspace.shared.open(f.logURL)
                      }
                  },
                  secondaryButton: .cancel(Text("關閉")))
        }
        .confirmationDialog("刪除 \(selection.count) 台電腦？", isPresented: $confirmDelete) {
            Button("刪除", role: .destructive) { store.delete(selection); selection.removeAll() }
        } message: {
            Text("連線設定和鑰匙圈中的密碼都會刪除。")
        }
        .onReceive(NotificationCenter.default.publisher(for: .newConnection)) { _ in newConnection() }
        .onReceive(NotificationCenter.default.publisher(for: .importRDP)) { _ in importRDP() }
        .onReceive(NotificationCenter.default.publisher(for: .openRDPFiles)) { n in
            for url in (n.object as? [URL]) ?? [] { importFile(url) }
        }
        .onAppear(perform: connectFromCommandLine)
    }

    /// `MacRDP --connect "<name, host or id>"` connects right after launch (for scripts, Shortcuts, Alfred…).
    private func connectFromCommandLine() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--connect"), i + 1 < args.count else { return }
        let key = args[i + 1]
        if let c = store.connections.first(where: {
            $0.id.uuidString == key || $0.displayName.caseInsensitiveCompare(key) == .orderedSame
                || $0.host.caseInsensitiveCompare(key) == .orderedSame
        }) {
            connect(c)
        }
    }

    // MARK: Detail

    private var filtered: [Connection] {
        var list = store.connections
        switch sidebar ?? .all {
        case .all: list.sort { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        case .recent:
            list = list.filter { $0.lastConnected != nil }
                .sorted { ($0.lastConnected ?? .distantPast) > ($1.lastConnected ?? .distantPast) }
        case .group(let g):
            list = list.filter { $0.group == g }
                .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        }
        if !search.isEmpty {
            list = list.filter {
                $0.displayName.localizedCaseInsensitiveContains(search) ||
                    $0.host.localizedCaseInsensitiveContains(search) ||
                    $0.username.localizedCaseInsensitiveContains(search)
            }
        }
        return list
    }

    @ViewBuilder private var detail: some View {
        if store.connections.isEmpty {
            ContentUnavailableView {
                Label("尚未加入任何電腦", systemImage: "display.2")
            } description: {
                Text("加入一台 Windows 電腦，或匯入 .rdp 檔案。")
            } actions: {
                Button("新增電腦") { newConnection() }.buttonStyle(.borderedProminent)
                Button("匯入 .rdp 檔案…") { importRDP() }
            }
        } else if filtered.isEmpty {
            ContentUnavailableView.search(text: search)
        } else if grid {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210, maximum: 260), spacing: 16)], spacing: 16) {
                    ForEach(filtered) { c in
                        ConnectionCard(connection: c, state: sessions.states[c.id], selected: selection.contains(c.id))
                            .onTapGesture(count: 2) { connect(c) }
                            .simultaneousGesture(TapGesture().onEnded { selection = [c.id] })
                            .contextMenu { menu(for: c) }
                    }
                }
                .padding(20)
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .onTapGesture { selection.removeAll() }
        } else {
            Table(filtered, selection: $selection) {
                TableColumn("名稱") { c in
                    HStack {
                        StatusDot(state: sessions.states[c.id])
                        Text(c.displayName)
                    }
                }
                TableColumn("主機") { c in Text(c.port == 3389 ? c.host : "\(c.host):\(c.port)") }
                TableColumn("使用者") { c in Text(c.username) }
                TableColumn("群組") { c in Text(c.group) }
                TableColumn("上次連線") { c in
                    Text(c.lastConnected.map { $0.formatted(.relative(presentation: .named)) } ?? "—")
                }
            }
            .contextMenu(forSelectionType: UUID.self) { ids in
                if let id = ids.first, let c = store.connection(id: id) { menu(for: c) }
            } primaryAction: { ids in
                ids.compactMap(store.connection(id:)).forEach(connect)
            }
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Picker("檢視", selection: $grid) {
                Image(systemName: "square.grid.2x2").tag(true)
                Image(systemName: "list.bullet").tag(false)
            }
            .pickerStyle(.segmented)
            .help("切換格狀或清單檢視")

            Menu {
                Button("新增電腦…") { newConnection() }
                Button("匯入 .rdp 檔案…") { importRDP() }
            } label: {
                Label("新增", systemImage: "plus")
            } primaryAction: {
                newConnection()
            }
            .help("新增電腦")
        }
    }

    @ViewBuilder private func menu(for c: Connection) -> some View {
        if sessions.isRunning(c.id) {
            Button("中斷連線") { sessions.disconnect(c.id) }
        } else {
            Button("連線") { connect(c) }
        }
        Divider()
        Button("編輯…") { isNew = false; editing = c }
        Button("複製") { selection = [store.duplicate(c).id] }
        Button("匯出成 .rdp…") { export(c) }
        Button("拷貝 FreeRDP 指令") { copyCommand(c) }
        Button("顯示連線記錄") { NSWorkspace.shared.open(sessions.logURL(for: c.id)) }
        Divider()
        Button("刪除…", role: .destructive) {
            if !selection.contains(c.id) { selection = [c.id] }
            confirmDelete = true
        }
    }

    // MARK: Actions

    private func newConnection() {
        var c = Connection()
        if case .group(let g) = sidebar ?? .all { c.group = g }
        isNew = true
        editing = c
    }

    private func connect(_ c: Connection) {
        if sessions.isRunning(c.id) { return }
        if c.savePassword, let p = Keychain.password(account: c.keychainAccount) {
            start(c, password: p)
        } else if c.username.isEmpty {
            start(c, password: nil)
        } else {
            passwordPrompt = c
        }
    }

    private func start(_ c: Connection, password: String?) {
        let gw = c.gateway.enabled && !c.gateway.useConnectionCredentials
            ? Keychain.password(account: Keychain.gatewayAccount(c)) : nil
        sessions.connect(c, credentials: .init(password: password, gatewayPassword: gw), store: store)
    }

    private func importRDP() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.rdp]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        panel.urls.forEach(importFile)
    }

    private func importFile(_ url: URL) {
        guard let data = try? Data(contentsOf: url) else { return }
        // .rdp files are usually UTF-16 LE with BOM; fall back to UTF-8.
        let text = String(data: data, encoding: .utf16) ?? String(decoding: data, as: UTF8.self)
        var c = RDPFile.parse(text)
        c.friendlyName = url.deletingPathExtension().lastPathComponent
        store.upsert(c)
        selection = [c.id]
    }

    private func export(_ c: Connection) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.rdp]
        panel.nameFieldStringValue = c.displayName + ".rdp"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? RDPFile.export(c).write(to: url, atomically: true, encoding: .utf8)
    }

    private func copyCommand(_ c: Connection) {
        let bin = SessionManager.freerdpBinary()?.path ?? "sdl-freerdp"
        let args = FreeRDPCommand.redacted(FreeRDPCommand.arguments(for: c, credentials: .init(password: nil)))
        let quoted = args.map { $0.contains(" ") ? "\"\($0)\"" : $0 }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(([bin] + quoted).joined(separator: " "), forType: .string)
    }
}

struct StatusDot: View {
    let state: SessionManager.State?
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .opacity(state == nil ? 0 : 1)
    }
    private var color: Color {
        switch state {
        case .connected: return .green
        case .connecting: return .orange
        case .failed: return .red
        case nil: return .clear
        }
    }
}

struct ConnectionCard: View {
    let connection: Connection
    let state: SessionManager.State?
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(colors: [Color.accentColor.opacity(0.85), Color.accentColor.opacity(0.45)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(Image(systemName: connection.remoteApp.isEmpty ? "pc" : "app.badge")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(.white.opacity(0.9)))
                    .frame(height: 110)
                if let state {
                    Text(state == .connected ? "已連線" : "連線中…")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.thinMaterial, in: Capsule())
                        .padding(6)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(connection.displayName).font(.headline).lineLimit(1)
                Text(connection.username.isEmpty ? connection.host : "\(connection.username) · \(connection.host)")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(.horizontal, 4).padding(.top, 8)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(selected ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: selected ? 2 : 1))
        .contentShape(Rectangle())
    }
}

struct PasswordPrompt: View {
    let connection: Connection
    let onConnect: (String, Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @Local private var password = ""
    @Local private var remember = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("登入 \(connection.displayName)").font(.headline)
            Text(connection.domain.isEmpty ? connection.username : "\(connection.domain)\\\(connection.username)")
                .foregroundStyle(.secondary)
            SecureField("密碼", text: $password).onSubmit(go)
            Toggle("記住密碼（存在鑰匙圈）", isOn: $remember)
            HStack {
                Spacer()
                Button("取消", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("連線", action: go).keyboardShortcut(.defaultAction).disabled(password.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 340)
    }

    private func go() {
        guard !password.isEmpty else { return }
        dismiss()
        onConnect(password, remember)
    }
}
