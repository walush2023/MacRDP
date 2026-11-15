import Foundation
import Network

/// Relays one RDP connection (TCP + UDP) through MacRDP: sdl-freerdp connects to 127.0.0.1:<port>,
/// MacRDP forwards to the real host.
///
/// Why: macOS "Local Network" privacy is granted per executable. MacRDP gets the system prompt, but a
/// freshly built sdl-freerdp is denied silently with no prompt, so it could never reach a LAN host.
/// Loopback traffic is not restricted, so routing through the already-allowed app always works.
/// FreeRDP sends its UDP transport (MS-RDPEUDP) to the TCP peer address, so the UDP listener sits on the
/// same loopback port as the TCP one.
final class LocalRelay: @unchecked Sendable {
    let remoteHost: String
    let remotePort: UInt16
    private(set) var localPort: UInt16 = 0

    private let queue = DispatchQueue(label: "MacRDP.relay", qos: .userInteractive)
    private var tcpListener: NWListener?
    private var udpListener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]

    init(host: String, port: Int) {
        remoteHost = host
        remotePort = UInt16(clamping: port)
    }

    /// Opens matching TCP and UDP listeners on 127.0.0.1. `preferredPort` keeps the port stable per
    /// connection so FreeRDP's certificate store (keyed by host:port) stays meaningful.
    func start(preferredPort: UInt16) throws -> UInt16 {
        var candidates: [UInt16] = [preferredPort]
        for _ in 0..<20 { candidates.append(UInt16.random(in: 49152...65000)) }
        var lastError: Error = NWError.posix(.EADDRINUSE)
        for port in candidates {
            do {
                let tcp = try listener(port: port, udp: false)
                do {
                    let udp = try listener(port: port, udp: true)
                    tcpListener = tcp
                    udpListener = udp
                    localPort = port
                    return port
                } catch {
                    tcp.cancel()
                    lastError = error
                }
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    func stop() {
        queue.async { [self] in
            tcpListener?.cancel()
            udpListener?.cancel()
            connections.values.forEach { $0.cancel() }
            connections.removeAll()
        }
    }

    // MARK: Listeners

    private func listener(port: UInt16, udp: Bool) throws -> NWListener {
        let params: NWParameters
        if udp {
            params = .udp
        } else {
            let tcp = NWProtocolTCP.Options()
            tcp.noDelay = true
            params = NWParameters(tls: nil, tcp: tcp)
        }
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        params.allowLocalEndpointReuse = false
        let l = try NWListener(using: params)

        let ready = DispatchSemaphore(value: 0)
        final class Result: @unchecked Sendable { var error: Error? }
        let result = Result()
        l.stateUpdateHandler = { state in
            switch state {
            case .ready: ready.signal()
            case .failed(let e): result.error = e; ready.signal()
            default: break
            }
        }
        l.newConnectionHandler = { [weak self] inbound in
            self?.accept(inbound, udp: udp)
        }
        l.start(queue: queue)
        if ready.wait(timeout: .now() + 3) == .timedOut {
            l.cancel()
            throw NWError.posix(.ETIMEDOUT)
        }
        if let e = result.error {
            l.cancel()
            throw e
        }
        return l
    }

    private func accept(_ inbound: NWConnection, udp: Bool) {
        let params: NWParameters
        if udp {
            params = .udp
        } else {
            let tcp = NWProtocolTCP.Options()
            tcp.noDelay = true
            params = NWParameters(tls: nil, tcp: tcp)
        }
        let outbound = NWConnection(host: NWEndpoint.Host(remoteHost),
                                    port: NWEndpoint.Port(rawValue: remotePort)!, using: params)
        track(inbound); track(outbound)

        let closeBoth: @Sendable () -> Void = { [weak self] in
            inbound.cancel(); outbound.cancel()
            self?.queue.async {
                self?.connections[ObjectIdentifier(inbound)] = nil
                self?.connections[ObjectIdentifier(outbound)] = nil
            }
        }
        for c in [inbound, outbound] {
            c.stateUpdateHandler = { state in
                switch state {
                case .failed, .cancelled: closeBoth()
                default: break
                }
            }
        }
        inbound.start(queue: queue)
        outbound.start(queue: queue)
        if udp {
            pumpDatagrams(from: inbound, to: outbound, onClose: closeBoth)
            pumpDatagrams(from: outbound, to: inbound, onClose: closeBoth)
        } else {
            pumpStream(from: inbound, to: outbound, onClose: closeBoth)
            pumpStream(from: outbound, to: inbound, onClose: closeBoth)
        }
    }

    private func track(_ c: NWConnection) {
        connections[ObjectIdentifier(c)] = c
    }

    // MARK: Pumps

    private func pumpStream(from src: NWConnection, to dst: NWConnection, onClose: @escaping @Sendable () -> Void) {
        src.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { [weak self] data, _, isComplete, error in
            if let data, !data.isEmpty {
                dst.send(content: data, completion: .contentProcessed { sendError in
                    if sendError != nil { onClose(); return }
                    if isComplete || error != nil { onClose(); return }
                    self?.pumpStream(from: src, to: dst, onClose: onClose)
                })
            } else if isComplete || error != nil {
                onClose()
            } else {
                self?.pumpStream(from: src, to: dst, onClose: onClose)
            }
        }
    }

    private func pumpDatagrams(from src: NWConnection, to dst: NWConnection, onClose: @escaping @Sendable () -> Void) {
        src.receiveMessage { [weak self] data, _, _, error in
            if let data, !data.isEmpty {
                dst.send(content: data, completion: .idempotent)
            }
            if error != nil { onClose(); return }
            self?.pumpDatagrams(from: src, to: dst, onClose: onClose)
        }
    }
}
