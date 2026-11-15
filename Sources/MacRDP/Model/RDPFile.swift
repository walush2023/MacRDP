import Foundation

/// Import / export of Microsoft `.rdp` files (the common subset that Windows App and mstsc write).
enum RDPFile {
    static func parse(_ text: String) -> Connection {
        var kv: [String: String] = [:]
        for line in text.components(separatedBy: .newlines) {
            let parts = line.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3 else { continue }
            kv[parts[0].trimmingCharacters(in: .whitespaces).lowercased()] = String(parts[2])
        }
        var c = Connection()
        func int(_ k: String) -> Int? { kv[k].flatMap { Int($0.trimmingCharacters(in: .whitespaces)) } }
        func bool(_ k: String) -> Bool? { int(k).map { $0 != 0 } }

        if let addr = kv["full address"] {
            let (h, p) = splitHostPort(addr)
            c.host = h
            if let p { c.port = p }
        }
        if let p = int("server port") { c.port = p }
        if let user = kv["username"] {
            if let slash = user.firstIndex(of: "\\") {
                c.domain = String(user[..<slash])
                c.username = String(user[user.index(after: slash)...])
            } else { c.username = user }
        }
        if let d = kv["domain"], !d.isEmpty { c.domain = d }
        if let mode = int("screen mode id") { c.fullscreen = mode == 2 }
        if let w = int("desktopwidth"), let h = int("desktopheight"), w > 0, h > 0 {
            c.customWidth = w; c.customHeight = h
            c.resolution = Resolution.allCases.first { $0.size.map { $0 == (w, h) } ?? false } ?? .custom
        }
        if let b = int("session bpp"), let depth = ColorDepth(rawValue: b) { c.colorDepth = depth }
        if let v = bool("use multimon") { c.useAllMonitors = v }
        if let v = bool("smart sizing") { c.fitToWindow = v }
        if let v = bool("dynamic resolution") { c.dynamicResolution = v }
        if let v = int("desktopscalefactor"), v >= 100 { c.desktopScale = v }
        if let v = bool("redirectclipboard") { c.clipboard = v ? .both : .off; c.fileClipboard = c.clipboard }
        if let v = bool("redirectprinters") { c.printers = v }
        if let v = bool("redirectsmartcards") { c.smartCards = v }
        if let v = int("audiomode") { c.sound = v == 0 ? .local : (v == 1 ? .remote : .never) }
        if let v = int("audiocapturemode") { c.microphone = v == 1 }
        if let v = bool("autoreconnection enabled") { c.reconnect = v }
        if let v = bool("administrative session") ?? bool("connect to console") { c.adminSession = v }
        if let v = int("connection type") {
            c.network = [1: .modem, 2: .broadbandLow, 3: .broadband, 4: .wan, 5: .broadbandHigh, 6: .lan, 7: .auto][v] ?? .auto
        }
        if let v = bool("disable wallpaper") { c.wallpaper = !v }
        if let v = bool("disable themes") { c.themes = !v }
        if let v = bool("allow font smoothing") { c.fontSmoothing = v }
        if let v = bool("allow desktop composition") { c.desktopComposition = v }
        if let v = bool("disable full window drag") { c.windowDrag = !v }
        if let v = bool("disable menu anims") { c.menuAnimations = !v }
        if let g = kv["gatewayhostname"], !g.isEmpty {
            let (h, p) = splitHostPort(g)
            c.gateway.enabled = (int("gatewayusagemethod") ?? 1) != 0
            c.gateway.host = h
            if let p { c.gateway.port = p }
            c.gateway.bypassForLocal = int("gatewayusagemethod") == 2
            c.gateway.useConnectionCredentials = (int("promptcredentialonce") ?? 1) == 1
        }
        if let s = kv["alternate shell"], !s.isEmpty { c.alternateShell = s }
        if let s = kv["remoteapplicationprogram"], !s.isEmpty { c.remoteApp = s }
        if let s = kv["loadbalanceinfo"], !s.isEmpty { c.loadBalanceInfo = s }
        return c
    }

    static func export(_ c: Connection) -> String {
        var lines: [String] = []
        func s(_ k: String, _ v: String) { lines.append("\(k):s:\(v)") }
        func i(_ k: String, _ v: Int) { lines.append("\(k):i:\(v)") }
        s("full address", c.port == 3389 ? c.host : "\(c.host):\(c.port)")
        s("username", c.domain.isEmpty ? c.username : "\(c.domain)\\\(c.username)")
        i("screen mode id", c.fullscreen ? 2 : 1)
        if let (w, h) = c.resolution == .custom ? (c.customWidth, c.customHeight) : c.resolution.size {
            i("desktopwidth", w); i("desktopheight", h)
        }
        i("session bpp", c.colorDepth.rawValue)
        i("use multimon", c.useAllMonitors ? 1 : 0)
        i("smart sizing", c.fitToWindow ? 1 : 0)
        i("dynamic resolution", c.dynamicResolution ? 1 : 0)
        if c.desktopScale != 100 { i("desktopscalefactor", c.desktopScale) }
        i("redirectclipboard", c.clipboard == .off ? 0 : 1)
        i("redirectprinters", c.printers ? 1 : 0)
        i("redirectsmartcards", c.smartCards ? 1 : 0)
        i("audiomode", c.sound == .local ? 0 : (c.sound == .remote ? 1 : 2))
        i("audiocapturemode", c.microphone ? 1 : 0)
        i("autoreconnection enabled", c.reconnect ? 1 : 0)
        i("administrative session", c.adminSession ? 1 : 0)
        let ct: [NetworkType: Int] = [.modem: 1, .broadbandLow: 2, .broadband: 3, .wan: 4, .broadbandHigh: 5, .lan: 6, .auto: 7]
        i("connection type", ct[c.network] ?? 7)
        i("disable wallpaper", c.wallpaper ? 0 : 1)
        i("disable themes", c.themes ? 0 : 1)
        i("allow font smoothing", c.fontSmoothing ? 1 : 0)
        i("allow desktop composition", c.desktopComposition ? 1 : 0)
        i("disable full window drag", c.windowDrag ? 0 : 1)
        i("disable menu anims", c.menuAnimations ? 0 : 1)
        if c.gateway.enabled {
            s("gatewayhostname", c.gateway.port == 443 ? c.gateway.host : "\(c.gateway.host):\(c.gateway.port)")
            i("gatewayusagemethod", c.gateway.bypassForLocal ? 2 : 1)
            i("promptcredentialonce", c.gateway.useConnectionCredentials ? 1 : 0)
        }
        if !c.alternateShell.isEmpty { s("alternate shell", c.alternateShell) }
        if !c.remoteApp.isEmpty {
            i("remoteapplicationmode", 1); s("remoteapplicationprogram", c.remoteApp)
        }
        if !c.loadBalanceInfo.isEmpty { s("loadbalanceinfo", c.loadBalanceInfo) }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    static func splitHostPort(_ s: String) -> (String, Int?) {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("["), let end = t.firstIndex(of: "]") { // [ipv6]:port
            let host = String(t[t.index(after: t.startIndex)..<end])
            let rest = t[t.index(after: end)...]
            return (host, rest.hasPrefix(":") ? Int(rest.dropFirst()) : nil)
        }
        let parts = t.split(separator: ":")
        if parts.count == 2, let p = Int(parts[1]) { return (String(parts[0]), p) }
        return (t, nil)
    }
}
