import Foundation

/// One saved PC. Mirrors the settings of Microsoft's Windows App "Add PC" dialog,
/// plus performance options (UDP, codec, frame pacing) that the Windows App hides.
struct Connection: Codable, Identifiable, Hashable {
    var id = UUID()

    // MARK: General
    var host = ""
    var port = 3389
    var friendlyName = ""
    var group = ""
    var username = ""
    var domain = ""
    /// Store the password in the macOS Keychain. When false the password is asked for every time.
    var savePassword = true
    var gateway = Gateway()
    var reconnect = true
    var adminSession = false

    // MARK: Display
    var resolution = Resolution.matchDisplay
    var customWidth = 1920
    var customHeight = 1080
    var fullscreen = true
    var useAllMonitors = false
    var fitToWindow = false
    var colorDepth = ColorDepth.bits32
    var dynamicResolution = true
    var desktopScale = 100

    // MARK: Devices & audio
    var clipboard = ClipboardDirection.both
    var fileClipboard = ClipboardDirection.both
    var printers = false
    var smartCards = false
    var microphone = false
    var sound = SoundMode.local
    var folders: [SharedFolder] = []
    var redirectHome = false

    // MARK: Performance & experience
    var network = NetworkType.auto
    var codec = GraphicsCodec.avc444
    var transport = Transport.udpPreferred
    var unlimitedFrames = true
    var wallpaper = true
    var themes = true
    var fontSmoothing = true
    var desktopComposition = true
    var windowDrag = true
    var menuAnimations = true

    // MARK: Security
    var certificate = CertificatePolicy.trustOnFirstUse
    var security = SecurityMode.auto

    // MARK: Advanced
    var keyboardLayout = ""
    var remoteApp = ""
    var alternateShell = ""
    var loadBalanceInfo = ""
    var extraArguments = ""

    var lastConnected: Date?

    var displayName: String { friendlyName.isEmpty ? host : friendlyName }
    var keychainAccount: String { id.uuidString }

    init() {}

    // Decode leniently so files written by older versions keep working when fields are added.
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func d<T: Decodable>(_ key: CodingKeys, _ value: inout T) {
            if let v = try? c.decode(T.self, forKey: key) { value = v }
        }
        d(.id, &id); d(.host, &host); d(.port, &port); d(.friendlyName, &friendlyName)
        d(.group, &group); d(.username, &username); d(.domain, &domain); d(.savePassword, &savePassword)
        d(.gateway, &gateway); d(.reconnect, &reconnect); d(.adminSession, &adminSession)
        d(.resolution, &resolution); d(.customWidth, &customWidth); d(.customHeight, &customHeight)
        d(.fullscreen, &fullscreen); d(.useAllMonitors, &useAllMonitors); d(.fitToWindow, &fitToWindow)
        d(.colorDepth, &colorDepth); d(.dynamicResolution, &dynamicResolution); d(.desktopScale, &desktopScale)
        d(.clipboard, &clipboard); d(.fileClipboard, &fileClipboard); d(.printers, &printers)
        d(.smartCards, &smartCards); d(.microphone, &microphone); d(.sound, &sound)
        d(.folders, &folders); d(.redirectHome, &redirectHome)
        d(.network, &network); d(.codec, &codec); d(.transport, &transport); d(.unlimitedFrames, &unlimitedFrames)
        d(.wallpaper, &wallpaper); d(.themes, &themes); d(.fontSmoothing, &fontSmoothing)
        d(.desktopComposition, &desktopComposition); d(.windowDrag, &windowDrag); d(.menuAnimations, &menuAnimations)
        d(.certificate, &certificate); d(.security, &security)
        d(.keyboardLayout, &keyboardLayout); d(.remoteApp, &remoteApp); d(.alternateShell, &alternateShell)
        d(.loadBalanceInfo, &loadBalanceInfo); d(.extraArguments, &extraArguments)
        d(.lastConnected, &lastConnected)
    }
}

struct Gateway: Codable, Hashable {
    var enabled = false
    var host = ""
    var port = 443
    var username = ""
    var domain = ""
    /// Use the PC's own credentials for the gateway.
    var useConnectionCredentials = true
    var bypassForLocal = true
}

struct SharedFolder: Codable, Hashable, Identifiable {
    var id = UUID()
    var name = ""
    var path = ""
}

enum Resolution: String, Codable, CaseIterable, Identifiable {
    case matchDisplay, matchWindow, r1280x720, r1366x768, r1600x900, r1920x1080, r1920x1200,
         r2560x1440, r2560x1600, r3440x1440, r3840x2160, custom
    var id: String { rawValue }
    var label: String {
        switch self {
        case .matchDisplay: return "與這個顯示器相同（預設）"
        case .matchWindow: return "與視窗大小相同"
        case .custom: return "自訂"
        default:
            let s = rawValue.dropFirst().split(separator: "x")
            return "\(s[0]) × \(s[1])"
        }
    }
    var size: (Int, Int)? {
        guard rawValue.hasPrefix("r") else { return nil }
        let s = rawValue.dropFirst().split(separator: "x").compactMap { Int($0) }
        return (s[0], s[1])
    }
}

enum ColorDepth: Int, Codable, CaseIterable, Identifiable {
    case bits32 = 32, bits24 = 24, bits16 = 16, bits15 = 15
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .bits32: return "最高品質（32 位元）"
        case .bits24: return "全彩（24 位元）"
        case .bits16: return "高彩（16 位元）"
        case .bits15: return "高彩（15 位元）"
        }
    }
}

enum ClipboardDirection: String, Codable, CaseIterable, Identifiable {
    case both, toRemote, toLocal, off
    var id: String { rawValue }
    var label: String {
        switch self {
        case .both: return "雙向"
        case .toRemote: return "只能從 Mac 複製到遠端"
        case .toLocal: return "只能從遠端複製到 Mac"
        case .off: return "關閉"
        }
    }
    /// FreeRDP `direction-to` / `files-to` value.
    var freerdp: String {
        switch self {
        case .both: return "all"
        case .toRemote: return "remote"
        case .toLocal: return "local"
        case .off: return "off"
        }
    }
}

enum SoundMode: String, Codable, CaseIterable, Identifiable {
    case local, remote, never
    var id: String { rawValue }
    var label: String {
        switch self {
        case .local: return "在這台 Mac 播放"
        case .remote: return "在遠端電腦播放"
        case .never: return "不播放"
        }
    }
}

enum NetworkType: String, Codable, CaseIterable, Identifiable {
    case auto, lan, wan, broadbandHigh = "broadband-high", broadband, broadbandLow = "broadband-low", modem
    var id: String { rawValue }
    var label: String {
        switch self {
        case .auto: return "自動偵測"
        case .lan: return "區域網路 (LAN)"
        case .wan: return "WAN"
        case .broadbandHigh: return "高速寬頻"
        case .broadband: return "寬頻"
        case .broadbandLow: return "低速寬頻"
        case .modem: return "數據機"
        }
    }
}

enum GraphicsCodec: String, Codable, CaseIterable, Identifiable {
    case avc444, avc420, progressive, remoteFX, legacy
    var id: String { rawValue }
    var label: String {
        switch self {
        case .avc444: return "H.264 AVC444（全彩，建議）"
        case .avc420: return "H.264 AVC420（較省頻寬）"
        case .progressive: return "RemoteFX Progressive"
        case .remoteFX: return "RemoteFX"
        case .legacy: return "傳統點陣圖（不使用 GFX）"
        }
    }
}

enum Transport: String, Codable, CaseIterable, Identifiable {
    case udpPreferred, tcpOnly
    var id: String { rawValue }
    var label: String {
        switch self {
        case .udpPreferred: return "UDP 優先（TCP 備援）"
        case .tcpOnly: return "只用 TCP"
        }
    }
}

enum CertificatePolicy: String, Codable, CaseIterable, Identifiable {
    case trustOnFirstUse, ignore, strict
    var id: String { rawValue }
    var label: String {
        switch self {
        case .trustOnFirstUse: return "第一次連線時信任並記住"
        case .ignore: return "一律忽略（僅限信任的區域網路）"
        case .strict: return "嚴格驗證"
        }
    }
}

enum SecurityMode: String, Codable, CaseIterable, Identifiable {
    case auto, nla, tls, rdp
    var id: String { rawValue }
    var label: String {
        switch self {
        case .auto: return "自動協商"
        case .nla: return "NLA（網路層級驗證）"
        case .tls: return "TLS"
        case .rdp: return "RDP 標準安全性"
        }
    }
}
