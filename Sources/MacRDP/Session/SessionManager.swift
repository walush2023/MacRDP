import AppKit
import Foundation
import Network

/// Starts one `sdl-freerdp` process per session and tracks its state.
@MainActor
final class SessionManager: ObservableObject {
    enum State: Equatable {
        case connecting, connected, failed(String)
    }

    struct Failure: Identifiable {
        let id = UUID()
        let connectionID: UUID
        let title: String
        let message: String
        let logURL: URL
        let wrongPassword: Bool
        var openPrivacySettings = false
    }

    @Published private(set) var states: [UUID: State] = [:]
    @Published var failure: Failure?

    private var processes: [UUID: Process] = [:]
    private var relays: [UUID: LocalRelay] = [:]
    let logDirectory: URL

    init() {
        logDirectory = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/MacRDP", isDirectory: true)
        try? FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
    }

    func isRunning(_ id: UUID) -> Bool { processes[id] != nil }

    func logURL(for id: UUID) -> URL { logDirectory.appendingPathComponent("\(id.uuidString).log") }

    /// Locates sdl-freerdp: the copy bundled in the app, a user override, then Homebrew.
    static func freerdpBinary() -> URL? {
        var candidates: [String] = []
        if let custom = UserDefaults.standard.string(forKey: "freerdpPath"), !custom.isEmpty {
            candidates.append(custom)
        }
        candidates.append(Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/MacRDP Session.app/Contents/MacOS/sdl-freerdp").path)
        candidates += ["/opt/homebrew/bin/sdl-freerdp", "/usr/local/bin/sdl-freerdp"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    func connect(_ c: Connection, credentials: FreeRDPCommand.Credentials, store: ConnectionStore) {
        guard processes[c.id] == nil, states[c.id] == nil else { return }
        if c.gateway.enabled {
            launch(c, credentials: credentials, store: store)
            return
        }
        states[c.id] = .connecting
        Task { @MainActor in
            // Probing from the app itself makes macOS show its Local Network prompt for MacRDP;
            // sdl-freerdp then inherits the permission. It also gives a clearer error than FreeRDP.
            let result = await Self.probe(host: c.host, port: c.port)
            switch result {
            case .reachable:
                states[c.id] = nil
                launch(c, credentials: credentials, store: store)
            case .localNetworkDenied:
                states[c.id] = nil
                failure = Failure(connectionID: c.id, title: String(localized: "Local Network access needed"),
                                  message: String(localized: "Turn on MacRDP in System Settings → Privacy & Security → Local Network, then connect again."),
                                  logURL: logURL(for: c.id), wrongPassword: false, openPrivacySettings: true)
            case .unreachable(let why):
                states[c.id] = nil
                failure = Failure(connectionID: c.id, title: String(localized: "Can't reach \(c.displayName)"),
                                  message: String(localized: "\(c.host):\(String(c.port)) doesn't respond (\(why)). Check the address and port, and that Remote Desktop is on and the firewall allows port 3389 on the PC."),
                                  logURL: logURL(for: c.id), wrongPassword: false)
            }
        }
    }

    enum ProbeResult: Sendable { case reachable, localNetworkDenied, unreachable(String) }

    static func probe(host: String, port: Int, timeout: Double = 6) async -> ProbeResult {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else { return .unreachable(String(localized: "invalid port")) }
        let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        final class Once: @unchecked Sendable {
            private let lock = NSLock()
            private var done = false
            func first() -> Bool { lock.lock(); defer { lock.unlock() }; if done { return false }; done = true; return true }
        }
        let once = Once()
        return await withCheckedContinuation { cont in
            @Sendable func finish(_ r: ProbeResult) {
                guard once.first() else { return }
                conn.cancel()
                cont.resume(returning: r)
            }
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready: finish(.reachable)
                case .waiting(let err), .failed(let err):
                    if conn.currentPath?.unsatisfiedReason == .localNetworkDenied {
                        // The first attempt shows the system prompt; keep waiting for the user's answer.
                        return
                    }
                    if case .failed = state { finish(.unreachable(err.localizedDescription)) }
                default: break
                }
            }
            conn.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if conn.currentPath?.unsatisfiedReason == .localNetworkDenied {
                    finish(.localNetworkDenied)
                } else if case .waiting(let err) = conn.state {
                    finish(.unreachable(err.localizedDescription))
                } else {
                    finish(.unreachable(String(localized: "timed out")))
                }
            }
        }
    }

    private func launch(_ c: Connection, credentials: FreeRDPCommand.Credentials, store: ConnectionStore) {
        guard let bin = Self.freerdpBinary() else {
            failure = Failure(connectionID: c.id, title: String(localized: "FreeRDP not found"),
                              message: String(localized: "Run scripts/build-freerdp.sh, or set the path to sdl-freerdp in Settings."),
                              logURL: logURL(for: c.id), wrongPassword: false)
            return
        }
        var relayPort: UInt16?
        if !c.gateway.enabled, UserDefaults.standard.object(forKey: "useRelay") as? Bool ?? true {
            let relay = LocalRelay(host: c.host, port: c.port)
            let preferred = UInt16(40000 + Int(c.id.uuid.0) % 100 * 100 + Int(c.id.uuid.1) % 100)
            if let port = try? relay.start(preferredPort: preferred) {
                relays[c.id] = relay
                relayPort = port
            }
        }
        let args = FreeRDPCommand.arguments(for: c, credentials: credentials, relayPort: relayPort)
        let log = logURL(for: c.id)
        let id = c.id
        let sessionLog = SessionLog(url: log, header: "# " + FreeRDPCommand.redacted(args).joined(separator: " ") + "\n") {
            Task { @MainActor in
                if self.processes[id] != nil { self.states[id] = .connected }
            }
        }

        let p = Process()
        p.executableURL = bin
        p.arguments = ["/args-from:stdin"]
        var env = ProcessInfo.processInfo.environment
        env["SDL_VIDEO_MAC_FULLSCREEN_SPACES"] = "1"
        p.environment = env
        let stdin = Pipe()
        p.standardInput = stdin
        p.standardOutput = sessionLog.pipe
        p.standardError = sessionLog.pipe

        let name = c.displayName
        p.terminationHandler = { proc in
            let status = proc.terminationStatus
            DispatchQueue.global().async {
                sessionLog.finish()
                let markers = sessionLog.markers
                Task { @MainActor in self.finished(id: id, status: status, name: name, markers: markers) }
            }
        }
        do {
            try p.run()
        } catch {
            relays.removeValue(forKey: id)?.stop()
            failure = Failure(connectionID: id, title: String(localized: "Couldn't start FreeRDP"), message: error.localizedDescription,
                              logURL: log, wrongPassword: false)
            return
        }
        sessionLog.childStarted()
        let payload = args.joined(separator: "\n") + "\n"
        stdin.fileHandleForWriting.write(Data(payload.utf8))
        try? stdin.fileHandleForWriting.close()

        processes[id] = p
        states[id] = .connecting
        store.markConnected(id)
    }

    func disconnect(_ id: UUID) {
        processes[id]?.terminate()
    }

    func disconnectAll() {
        processes.values.forEach { $0.terminate() }
    }

    private func finished(id: UUID, status: Int32, name: String, markers: SessionLog.Markers) {
        processes[id] = nil
        relays.removeValue(forKey: id)?.stop()
        let log = logURL(for: id)
        let wasConnected = states[id] == .connected || markers.loggedOn
        states[id] = nil

        if markers.authFailed {
            failure = Failure(connectionID: id, title: String(localized: "Couldn't sign in to \(name)"),
                              message: String(localized: "The user name or password is wrong, or the account isn't allowed to sign in."), logURL: log, wrongPassword: true)
        } else if !wasConnected && status != 0 {
            var msg = String(localized: "The connection failed (code \(String(status))).")
            if markers.unreachable {
                msg = String(localized: "Can't reach the PC. Check the address and port, that Remote Desktop is on, and that MacRDP is allowed in System Settings → Privacy & Security → Local Network.")
            } else if markers.certificateError {
                msg = String(localized: "The certificate couldn't be verified. Under Advanced → Server certificate, choose \"Trust and remember on first connection\".")
            }
            failure = Failure(connectionID: id, title: String(localized: "Couldn't connect to \(name)"), message: msg, logURL: log, wrongPassword: false)
        }
    }
}
