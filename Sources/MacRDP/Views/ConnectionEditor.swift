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
                general.tabItem { Text("一般") }.tag(0)
                display.tabItem { Text("顯示") }.tag(1)
                devices.tabItem { Text("裝置與音訊") }.tag(2)
                folders.tabItem { Text("資料夾") }.tag(3)
                performance.tabItem { Text("效能") }.tag(4)
                gateway.tabItem { Text("閘道") }.tag(5)
                advanced.tabItem { Text("進階") }.tag(6)
            }
            .padding([.horizontal, .top])

            Divider()
            HStack {
                if !connection.host.isEmpty {
                    Text(connection.port == 3389 ? connection.host : "\(connection.host):\(connection.port)")
                        .foregroundStyle(.secondary).font(.callout)
                }
                Spacer()
                Button("取消", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(isNew ? "新增" : "儲存") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(connection.host.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(width: 620, height: 500)
        .onAppear {
            hasSavedPassword = Keychain.hasPassword(account: connection.keychainAccount)
        }
    }

    // MARK: Tabs

    private var general: some View {
        Form {
            Section {
                TextField("電腦名稱或 IP", text: $connection.host, prompt: Text("例如 192.168.1.10 或 pc.example.com"))
                TextField("埠號", value: $connection.port, format: .number.grouping(.never))
                TextField("易記名稱", text: $connection.friendlyName, prompt: Text("選填"))
                Picker("群組", selection: $connection.group) {
                    Text("無").tag("")
                    ForEach(Array(Set(store.groups + [connection.group]).filter { !$0.isEmpty }).sorted(), id: \.self) {
                        Text($0).tag($0)
                    }
                }
                TextField("新群組", text: $connection.group, prompt: Text("輸入名稱即可建立新群組"))
            }
            Section("認證") {
                TextField("使用者名稱", text: $connection.username, prompt: Text("user、DOMAIN\\user 或 user@domain"))
                TextField("網域", text: $connection.domain, prompt: Text("選填"))
                SecureField("密碼", text: $password,
                            prompt: Text(hasSavedPassword ? "已儲存（留空 = 不變）" : "選填"))
                Toggle("把密碼存在鑰匙圈", isOn: $connection.savePassword)
                if hasSavedPassword {
                    Button("清除已儲存的密碼") {
                        Keychain.delete(account: connection.keychainAccount)
                        hasSavedPassword = false
                    }
                }
            }
            Section {
                Toggle("連線中斷時自動重新連線", isOn: $connection.reconnect)
                Toggle("連線到系統管理工作階段", isOn: $connection.adminSession)
            }
        }
        .formStyle(.grouped)
    }

    private var display: some View {
        Form {
            Section {
                Picker("解析度", selection: $connection.resolution) {
                    ForEach(Resolution.allCases) { Text($0.label).tag($0) }
                }
                if connection.resolution == .custom {
                    HStack {
                        TextField("寬", value: $connection.customWidth, format: .number.grouping(.never))
                        Text("×")
                        TextField("高", value: $connection.customHeight, format: .number.grouping(.never))
                    }
                }
                Toggle("視窗大小改變時更新遠端解析度", isOn: $connection.dynamicResolution)
                Picker("顯示比例", selection: $connection.desktopScale) {
                    ForEach([100, 125, 150, 175, 200, 250, 300], id: \.self) { Text("\($0)%").tag($0) }
                }
            }
            Section {
                Toggle("以全螢幕開始工作階段", isOn: $connection.fullscreen)
                Toggle("使用所有顯示器", isOn: $connection.useAllMonitors)
                Toggle("讓工作階段符合視窗大小（縮放）", isOn: $connection.fitToWindow)
            } footer: {
                Text("全螢幕使用 macOS 原生全螢幕：工作階段有自己的 Space，可用四指滑動或 Control-←/→ 切換。按 Control-Option-Return 切換全螢幕。")
            }
            Section {
                Picker("色彩品質", selection: $connection.colorDepth) {
                    ForEach(ColorDepth.allCases) { Text($0.label).tag($0) }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var devices: some View {
        Form {
            Section("剪貼簿") {
                Picker("文字與圖片", selection: $connection.clipboard) {
                    ForEach(ClipboardDirection.allCases) { Text($0.label).tag($0) }
                }
                Picker("檔案", selection: $connection.fileClipboard) {
                    ForEach(ClipboardDirection.allCases) { Text($0.label).tag($0) }
                }
            }
            Section("重新導向") {
                Toggle("印表機", isOn: $connection.printers)
                Toggle("智慧卡", isOn: $connection.smartCards)
                Toggle("麥克風", isOn: $connection.microphone)
            }
            Section("音訊") {
                Picker("播放聲音", selection: $connection.sound) {
                    ForEach(SoundMode.allCases) { Text($0.label).tag($0) }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var folders: some View {
        Form {
            Section {
                Toggle("分享我的家目錄", isOn: $connection.redirectHome)
            }
            Section {
                ForEach($connection.folders) { $f in
                    HStack {
                        TextField("名稱", text: $f.name).frame(width: 120)
                        Text(f.path).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                        Spacer()
                        Button(role: .destructive) {
                            connection.folders.removeAll { $0.id == f.id }
                        } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                    }
                }
                Button("加入資料夾…") { addFolder() }
            } header: {
                Text("重新導向的資料夾")
            } footer: {
                Text("在遠端的「本機」中會以「名稱 on 這台 Mac」出現。")
            }
        }
        .formStyle(.grouped)
    }

    private var performance: some View {
        Form {
            Section {
                Picker("傳輸方式", selection: $connection.transport) {
                    ForEach(Transport.allCases) { Text($0.label).tag($0) }
                }
                Picker("影像編碼", selection: $connection.codec) {
                    ForEach(GraphicsCodec.allCases) { Text($0.label).tag($0) }
                }
                Toggle("不限制幀率（不等待每幀確認）", isOn: $connection.unlimitedFrames)
                Picker("網路類型", selection: $connection.network) {
                    ForEach(NetworkType.allCases) { Text($0.label).tag($0) }
                }
            } footer: {
                Text("要超過 30 fps 並使用 H.264，遠端 Windows 也需要調整設定，請看 README 的「Windows 端設定」。")
            }
            Section("視覺效果") {
                Toggle("桌布", isOn: $connection.wallpaper)
                Toggle("佈景主題", isOn: $connection.themes)
                Toggle("字型平滑 (ClearType)", isOn: $connection.fontSmoothing)
                Toggle("桌面組合（透明效果）", isOn: $connection.desktopComposition)
                Toggle("拖曳時顯示視窗內容", isOn: $connection.windowDrag)
                Toggle("選單動畫", isOn: $connection.menuAnimations)
            }
        }
        .formStyle(.grouped)
    }

    private var gateway: some View {
        Form {
            Section {
                Toggle("使用遠端桌面閘道 (RD Gateway)", isOn: $connection.gateway.enabled)
                if connection.gateway.enabled {
                    TextField("閘道伺服器", text: $connection.gateway.host, prompt: Text("gateway.example.com"))
                    TextField("埠號", value: $connection.gateway.port, format: .number.grouping(.never))
                    Toggle("連線到區域網路的電腦時不使用閘道", isOn: $connection.gateway.bypassForLocal)
                    Toggle("使用電腦的帳號密碼", isOn: $connection.gateway.useConnectionCredentials)
                    if !connection.gateway.useConnectionCredentials {
                        TextField("閘道使用者名稱", text: $connection.gateway.username)
                        TextField("閘道網域", text: $connection.gateway.domain)
                        SecureField("閘道密碼", text: $gatewayPassword, prompt: Text("留空 = 不變"))
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var advanced: some View {
        Form {
            Section("安全性") {
                Picker("伺服器憑證", selection: $connection.certificate) {
                    ForEach(CertificatePolicy.allCases) { Text($0.label).tag($0) }
                }
                Picker("安全性通訊協定", selection: $connection.security) {
                    ForEach(SecurityMode.allCases) { Text($0.label).tag($0) }
                }
            }
            Section("啟動") {
                TextField("RemoteApp 程式", text: $connection.remoteApp, prompt: Text("例如 ||notepad 或 C:\\Windows\\notepad.exe"))
                TextField("替代殼層", text: $connection.alternateShell, prompt: Text("選填"))
                TextField("負載平衡資訊", text: $connection.loadBalanceInfo, prompt: Text("選填"))
            }
            Section {
                TextField("鍵盤配置", text: $connection.keyboardLayout, prompt: Text("留空 = 跟隨 Mac，例如 0x00000409"))
                TextField("其他 FreeRDP 參數", text: $connection.extraArguments, prompt: Text("例如 /timeout:30000 +async-channels"), axis: .vertical)
                    .lineLimit(2...4)
            } footer: {
                Text("其他參數會直接加在 sdl-freerdp 指令後面。")
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
                TextField("sdl-freerdp 路徑", text: $freerdpPath, prompt: Text("留空 = 自動尋找"))
                LabeledContent("目前使用", value: SessionManager.freerdpBinary()?.path ?? "找不到")
            } footer: {
                Text("自動尋找順序：App 內附的 FreeRDP → /opt/homebrew/bin → /usr/local/bin。Homebrew 版沒有 UDP 支援。")
            }
            Section {
                Toggle("透過 MacRDP 轉送連線", isOn: $useRelay)
            } footer: {
                Text("macOS 的「區域網路」權限只會詢問 MacRDP，不會詢問 FreeRDP。開啟時 FreeRDP 連到 127.0.0.1，由 MacRDP 轉送 TCP 與 UDP，所以不需要另外授權。使用閘道時不轉送。")
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .padding()
    }
}
