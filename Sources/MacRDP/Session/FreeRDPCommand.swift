import Foundation

/// Turns a `Connection` into FreeRDP (sdl-freerdp 3.x) arguments.
/// The arguments are passed through stdin (`/args-from:stdin`), so passwords never show up in `ps`.
enum FreeRDPCommand {
    struct Credentials {
        var password: String?
        var gatewayPassword: String?
    }

    /// - Parameter relayPort: when set, FreeRDP connects to 127.0.0.1:relayPort (see `LocalRelay`)
    ///   and validates the certificate against the real host name.
    static func arguments(for c: Connection, credentials: Credentials,
                          home: String = NSHomeDirectory(), relayPort: UInt16? = nil) -> [String] {
        var a: [String] = []
        let host = c.host.trimmingCharacters(in: .whitespaces)

        // General
        if let relayPort {
            a.append("/v:127.0.0.1")
            a.append("/port:\(relayPort)")
            a.append("/server-name:\(host)")
        } else {
            a.append("/v:\(host)")
            if c.port != 3389 { a.append("/port:\(c.port)") }
        }
        if !c.username.isEmpty { a.append("/u:\(c.username)") }
        if !c.domain.isEmpty { a.append("/d:\(c.domain)") }
        if let p = credentials.password, !p.isEmpty { a.append("/p:\(p)") }
        if c.adminSession { a.append("+admin") }
        if c.reconnect {
            a.append("+auto-reconnect")
            a.append("/auto-reconnect-max-retries:20")
        }
        a.append("/title:\(c.displayName)")

        if c.gateway.enabled, !c.gateway.host.isEmpty {
            var g = ["g:\(c.gateway.host):\(c.gateway.port)"]
            if c.gateway.useConnectionCredentials {
                if !c.username.isEmpty { g.append("u:\(c.username)") }
                if !c.domain.isEmpty { g.append("d:\(c.domain)") }
                if let p = credentials.password, !p.isEmpty { g.append("p:\(p)") }
            } else {
                if !c.gateway.username.isEmpty { g.append("u:\(c.gateway.username)") }
                if !c.gateway.domain.isEmpty { g.append("d:\(c.gateway.domain)") }
                if let p = credentials.gatewayPassword, !p.isEmpty { g.append("p:\(p)") }
            }
            g.append("usage-method:\(c.gateway.bypassForLocal ? "detect" : "direct")")
            a.append("/gateway:" + g.joined(separator: ","))
        }

        // Display
        if c.useAllMonitors {
            a.append("/multimon")
        } else if c.fullscreen {
            a.append("/f")
        }
        switch c.resolution {
        case .matchDisplay, .matchWindow:
            break
        case .custom:
            a.append("/size:\(c.customWidth)x\(c.customHeight)")
        default:
            if let (w, h) = c.resolution.size { a.append("/size:\(w)x\(h)") }
        }
        if c.resolution == .matchWindow || c.dynamicResolution {
            a.append("+dynamic-resolution")
        }
        if c.fitToWindow { a.append("/smart-sizing") }
        a.append("/bpp:\(c.colorDepth.rawValue)")
        if c.desktopScale != 100 { a.append("/scale-desktop:\(c.desktopScale)") }

        // Devices & audio
        if c.clipboard == .off && c.fileClipboard == .off {
            a.append("-clipboard")
        } else {
            a.append("/clipboard:direction-to:\(c.clipboard.freerdp),files-to:\(c.fileClipboard.freerdp)")
        }
        if c.printers { a.append("/printer") }
        if c.smartCards { a.append("/smartcard") }
        if c.microphone { a.append("/microphone:sys:mac") }
        switch c.sound {
        case .local: a.append("/sound:sys:mac")
        case .remote: a.append("/audio-mode:server")
        case .never: a.append("/audio-mode:none")
        }
        for f in c.folders where !f.path.isEmpty {
            let name = f.name.isEmpty ? URL(fileURLWithPath: f.path).lastPathComponent : f.name
            a.append("/drive:\(name),\(f.path)")
        }
        if c.redirectHome { a.append("/drive:Mac,\(home)") }

        // Performance
        a.append("/network:\(c.network.rawValue)")
        switch c.codec {
        case .avc444: a.append("/gfx:AVC444")
        case .avc420: a.append("/gfx:AVC420")
        case .progressive: a.append("/gfx:progressive")
        case .remoteFX: a.append("/gfx:RFX")
        case .legacy: a.append("-gfx")
        }
        a.append(c.transport == .udpPreferred ? "/multitransport:udp-preferred" : "-multitransport")
        if c.unlimitedFrames { a.append("/frame-ack:0") }
        if !c.wallpaper { a.append("-wallpaper") }
        if !c.themes { a.append("-themes") }
        if !c.fontSmoothing { a.append("-fonts") }
        if c.desktopComposition { a.append("+aero") }
        if c.windowDrag { a.append("+window-drag") }
        if c.menuAnimations { a.append("+menu-anims") }

        // Security
        switch c.certificate {
        case .trustOnFirstUse: a.append("/cert:tofu")
        case .ignore: a.append("/cert:ignore")
        case .strict: break
        }
        if c.security != .auto { a.append("/sec:\(c.security.rawValue)") }

        // Advanced
        if !c.keyboardLayout.isEmpty { a.append("/kbd:layout:\(c.keyboardLayout)") }
        if !c.remoteApp.isEmpty { a.append("/app:program:\(c.remoteApp)") }
        if !c.alternateShell.isEmpty { a.append("/shell:\(c.alternateShell)") }
        if !c.loadBalanceInfo.isEmpty { a.append("/load-balance-info:\(c.loadBalanceInfo)") }
        a.append(contentsOf: splitArguments(c.extraArguments))
        return a
    }

    /// Splits user-typed extra arguments, honouring double quotes.
    static func splitArguments(_ s: String) -> [String] {
        var out: [String] = [], cur = "", quoted = false
        for ch in s {
            if ch == "\"" { quoted.toggle(); continue }
            if ch.isWhitespace && !quoted {
                if !cur.isEmpty { out.append(cur); cur = "" }
            } else { cur.append(ch) }
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }

    /// Same arguments with secrets masked, for logs and the "copy command" menu item.
    static func redacted(_ args: [String]) -> [String] {
        args.map { arg in
            if arg.hasPrefix("/p:") { return "/p:****" }
            if arg.hasPrefix("/gateway:") {
                return arg.split(separator: ",").map { $0.hasPrefix("p:") ? "p:****" : String($0) }
                    .joined(separator: ",")
            }
            return arg
        }
    }
}
