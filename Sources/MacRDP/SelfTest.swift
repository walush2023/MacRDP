import Foundation

/// Unit checks runnable without Xcode: `MacRDP --self-test` (exit code = number of failures).
/// (Swift Testing and XCTest both need Xcode; the Command Line Tools alone cannot run them.)
enum SelfTest {
    nonisolated(unsafe) static var failures = 0
    nonisolated(unsafe) static var current = ""

    static func run() -> Int32 {
        current = "FreeRDPCommandTests.defaultConnectionUsesUDPAndHighFPS"; FreeRDPCommandTests.defaultConnectionUsesUDPAndHighFPS()
        current = "FreeRDPCommandTests.displayDevicesAndFolders"; FreeRDPCommandTests.displayDevicesAndFolders()
        current = "FreeRDPCommandTests.relayRewritesTarget"; FreeRDPCommandTests.relayRewritesTarget()
        current = "FreeRDPCommandTests.clipboardFullyOff"; FreeRDPCommandTests.clipboardFullyOff()
        current = "FreeRDPCommandTests.gatewayAndRedaction"; FreeRDPCommandTests.gatewayAndRedaction()
        current = "FreeRDPCommandTests.extraArgumentsHonourQuotes"; FreeRDPCommandTests.extraArgumentsHonourQuotes()
        current = "RDPFileTests.parseCommonKeys"; RDPFileTests.parseCommonKeys()
        current = "RDPFileTests.roundTrip"; RDPFileTests.roundTrip()
        print(failures == 0 ? "All checks passed" : "\(failures) check(s) failed")
        return Int32(failures)
    }
}

func check(_ ok: @autoclosure () -> Bool, file: String = #fileID, line: Int = #line) {
    if !ok() {
        SelfTest.failures += 1
        print("FAIL \(SelfTest.current) at \(file):\(line)")
    }
}


enum FreeRDPCommandTests {
    static func defaultConnectionUsesUDPAndHighFPS() {
        var c = Connection()
        c.host = "10.0.0.5"
        c.username = "alice"
        let a = FreeRDPCommand.arguments(for: c, credentials: .init(password: "secret"), home: "/Users/x")
        check(a.first == "/v:10.0.0.5")
        check(a.contains("/u:alice"))
        check(a.contains("/p:secret"))
        check(a.contains("/f"))
        check(a.contains("/gfx:AVC444"))
        check(a.contains("/multitransport:udp-preferred"))
        check(a.contains("/frame-ack:0"))
        check(a.contains("/clipboard:direction-to:all,files-to:all"))
        check(a.contains("/sound:sys:mac"))
        check(!a.contains { $0.hasPrefix("/port:") })
    }

    static func displayDevicesAndFolders() {
        var c = Connection()
        c.host = "pc"
        c.port = 3390
        c.resolution = .r1920x1080
        c.fullscreen = false
        c.fitToWindow = true
        c.colorDepth = .bits16
        c.clipboard = .toRemote
        c.fileClipboard = .off
        c.sound = .never
        c.printers = true
        c.microphone = true
        c.transport = .tcpOnly
        c.folders = [SharedFolder(name: "Work", path: "/Users/x/Work")]
        c.redirectHome = true
        let a = FreeRDPCommand.arguments(for: c, credentials: .init(), home: "/Users/x")
        check(a.contains("/port:3390"))
        check(a.contains("/size:1920x1080"))
        check(!a.contains("/f"))
        check(a.contains("/smart-sizing"))
        check(a.contains("/bpp:16"))
        check(a.contains("/clipboard:direction-to:remote,files-to:off"))
        check(a.contains("/audio-mode:none"))
        check(a.contains("/printer"))
        check(a.contains("/microphone:sys:mac"))
        check(a.contains("-multitransport"))
        check(a.contains("/drive:Work,/Users/x/Work"))
        check(a.contains("/drive:Mac,/Users/x"))
    }

    static func relayRewritesTarget() {
        var c = Connection()
        c.host = "192.168.1.9"
        c.port = 3390
        let a = FreeRDPCommand.arguments(for: c, credentials: .init(), relayPort: 45000)
        check(a.first == "/v:127.0.0.1")
        check(a.contains("/port:45000"))
        check(a.contains("/server-name:192.168.1.9"))
        check(!a.contains("/port:3390"))
    }

    static func clipboardFullyOff() {
        var c = Connection()
        c.host = "pc"
        c.clipboard = .off
        c.fileClipboard = .off
        check(FreeRDPCommand.arguments(for: c, credentials: .init()).contains("-clipboard"))
    }

    static func gatewayAndRedaction() {
        var c = Connection()
        c.host = "pc"
        c.username = "bob"
        c.gateway = Gateway(enabled: true, host: "gw.example.com", port: 443, username: "gwuser",
                            domain: "", useConnectionCredentials: false, bypassForLocal: false)
        let a = FreeRDPCommand.arguments(for: c, credentials: .init(password: "pw", gatewayPassword: "gpw"))
        check(a.contains("/gateway:g:gw.example.com:443,u:gwuser,p:gpw,usage-method:direct"))
        let r = FreeRDPCommand.redacted(a)
        check(!r.joined().contains("pw,") && !r.contains("/p:pw"))
        check(r.contains("/p:****"))
    }

    static func extraArgumentsHonourQuotes() {
        check(FreeRDPCommand.splitArguments(#"/timeout:3000 "/shell:C:\Program Files\x.exe" +echo"#)
            == ["/timeout:3000", #"/shell:C:\Program Files\x.exe"#, "+echo"])
    }
}

enum RDPFileTests {
    static func parseCommonKeys() {
        let text = """
        full address:s:192.168.1.20:3390
        username:s:CORP\\alice
        screen mode id:i:1
        desktopwidth:i:2560
        desktopheight:i:1440
        session bpp:i:24
        redirectclipboard:i:0
        audiomode:i:2
        gatewayhostname:s:gw.corp.com
        gatewayusagemethod:i:1
        """
        let c = RDPFile.parse(text)
        check(c.host == "192.168.1.20")
        check(c.port == 3390)
        check(c.domain == "CORP")
        check(c.username == "alice")
        check(!c.fullscreen)
        check(c.resolution == .r2560x1440)
        check(c.colorDepth == .bits24)
        check(c.clipboard == .off)
        check(c.sound == .never)
        check(c.gateway.enabled && c.gateway.host == "gw.corp.com")
    }

    static func roundTrip() {
        var c = Connection()
        c.host = "pc.local"
        c.username = "u"
        c.resolution = .custom
        c.customWidth = 1700
        c.customHeight = 1000
        c.useAllMonitors = true
        let back = RDPFile.parse(RDPFile.export(c))
        check(back.host == "pc.local")
        check(back.resolution == .custom && back.customWidth == 1700 && back.customHeight == 1000)
        check(back.useAllMonitors)
    }
}
