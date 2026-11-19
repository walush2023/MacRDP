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
        case .matchDisplay: return String(localized: "Same as this display (default)")
        case .matchWindow: return String(localized: "Same as window size")
        case .custom: return String(localized: "Custom")
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
        case .bits32: return String(localized: "Highest quality (32-bit)")
        case .bits24: return String(localized: "True color (24-bit)")
        case .bits16: return String(localized: "High color (16-bit)")
        case .bits15: return String(localized: "High color (15-bit)")
        }
    }
}

enum ClipboardDirection: String, Codable, CaseIterable, Identifiable {
    case both, toRemote, toLocal, off
    var id: String { rawValue }
    var label: String {
        switch self {
        case .both: return String(localized: "Both directions")
        case .toRemote: return String(localized: "Mac to remote only")
        case .toLocal: return String(localized: "Remote to Mac only")
        case .off: return String(localized: "Off")
        }
    }
    /// FreeRDP `direction-to` / `files-to` value.
    var freerdp: String {
        switch self {
        case .both: return String(localized: "all")
        case .toRemote: return String(localized: "remote")
        case .toLocal: return String(localized: "local")
        case .off: return String(localized: "off")
        }
    }
}

enum SoundMode: String, Codable, CaseIterable, Identifiable {
    case local, remote, never
    var id: String { rawValue }
    var label: String {
        switch self {
        case .local: return String(localized: "On this Mac")
        case .remote: return String(localized: "On the remote PC")
        case .never: return String(localized: "Never")
        }
    }
}

enum NetworkType: String, Codable, CaseIterable, Identifiable {
    case auto, lan, wan, broadbandHigh = "broadband-high", broadband, broadbandLow = "broadband-low", modem
    var id: String { rawValue }
    var label: String {
        switch self {
        case .auto: return String(localized: "Detect automatically")
        case .lan: return String(localized: "LAN")
        case .wan: return "WAN"
        case .broadbandHigh: return String(localized: "High-speed broadband")
        case .broadband: return String(localized: "Broadband")
        case .broadbandLow: return String(localized: "Low-speed broadband")
        case .modem: return String(localized: "Modem")
        }
    }
}

enum GraphicsCodec: String, Codable, CaseIterable, Identifiable {
    case avc444, avc420, progressive, remoteFX, legacy
    var id: String { rawValue }
    var label: String {
        switch self {
        case .avc444: return String(localized: "H.264 AVC444 (full color, recommended)")
        case .avc420: return String(localized: "H.264 AVC420 (less bandwidth)")
        case .progressive: return "RemoteFX Progressive"
        case .remoteFX: return "RemoteFX"
        case .legacy: return String(localized: "Legacy bitmaps (no GFX)")
        }
    }
}

enum Transport: String, Codable, CaseIterable, Identifiable {
    case udpPreferred, tcpOnly
    var id: String { rawValue }
    var label: String {
        switch self {
        case .udpPreferred: return String(localized: "UDP preferred (TCP fallback)")
        case .tcpOnly: return String(localized: "TCP only")
        }
    }
}

enum CertificatePolicy: String, Codable, CaseIterable, Identifiable {
    case trustOnFirstUse, ignore, strict
    var id: String { rawValue }
    var label: String {
        switch self {
        case .trustOnFirstUse: return String(localized: "Trust and remember on first connection")
        case .ignore: return String(localized: "Always ignore (trusted LAN only)")
        case .strict: return String(localized: "Strict")
        }
    }
}

enum SecurityMode: String, Codable, CaseIterable, Identifiable {
    case auto, nla, tls, rdp
    var id: String { rawValue }
    var label: String {
        switch self {
        case .auto: return String(localized: "Negotiate automatically")
        case .nla: return String(localized: "NLA (Network Level Authentication)")
        case .tls: return "TLS"
        case .rdp: return String(localized: "Standard RDP security")
        }
    }
}
