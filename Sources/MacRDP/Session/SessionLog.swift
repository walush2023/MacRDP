import Foundation

/// Collects sdl-freerdp's output into the connection log on a background queue.
///
/// - Keeps the file bounded: past `maxBytes` the file is started over (with the command line kept), so a
///   debug log level left on for days cannot fill the disk.
/// - Watches the output for the few markers MacRDP reacts to, so nothing ever has to read the log file
///   back (reading a multi-GB log on the main thread is what froze the app).
final class SessionLog: @unchecked Sendable {
    struct Markers: Sendable {
        var loggedOn = false
        var authFailed = false
        var unreachable = false
        var certificateError = false
    }

    let pipe = Pipe()
    let url: URL
    private let header: Data
    private let maxBytes: UInt64
    private let handle: FileHandle?
    private let lock = NSLock()
    private var written: UInt64 = 0
    private var _markers = Markers()
    private var onLogon: (@Sendable () -> Void)?
    private let eof = DispatchSemaphore(value: 0)

    var markers: Markers { lock.lock(); defer { lock.unlock() }; return _markers }

    init(url: URL, header: String, maxBytes: UInt64 = 32 * 1024 * 1024, onLogon: @escaping @Sendable () -> Void) {
        self.url = url
        self.header = Data(header.utf8)
        self.maxBytes = maxBytes
        self.onLogon = onLogon
        FileManager.default.createFile(atPath: url.path, contents: self.header)
        handle = try? FileHandle(forWritingTo: url)
        _ = try? handle?.seekToEnd()
        written = UInt64(self.header.count)

        pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            if data.isEmpty {
                h.readabilityHandler = nil
                self?.eof.signal()
                return
            }
            self?.append(data)
        }
    }

    private static let authErrors = ["LOGON_FAILURE", "AUTHENTICATION_FAILED", "WRONG_PASSWORD", "ACCOUNT_RESTRICTION",
                                     "PASSWORD_EXPIRED", "ACCOUNT_DISABLED", "ACCOUNT_LOCKED_OUT"]

    private func append(_ data: Data) {
        let text = String(decoding: data, as: UTF8.self)
        var fireLogon: (@Sendable () -> Void)?
        lock.lock()
        if !_markers.loggedOn, text.contains("Logon Info") || text.contains("gdi_init_ex") {
            _markers.loggedOn = true
            fireLogon = onLogon
            onLogon = nil
        }
        if Self.authErrors.contains(where: text.contains) { _markers.authFailed = true }
        if text.contains("Couldn't get socket ip address") || text.contains("ConnectLayer") { _markers.unreachable = true }
        if text.contains("certificate"), text.contains("ERROR") { _markers.certificateError = true }

        if written + UInt64(data.count) > maxBytes {
            try? handle?.truncate(atOffset: 0)
            handle?.write(header)
            handle?.write(Data("# (earlier output removed: log reached \(maxBytes / 1024 / 1024) MB)\n".utf8))
            written = UInt64(header.count)
        }
        handle?.write(data)
        written += UInt64(data.count)
        lock.unlock()
        fireLogon?()
    }

    /// Call once the child process has started: the app's copy of the pipe's write end must be closed,
    /// or the reader never sees end-of-file.
    func childStarted() {
        try? pipe.fileHandleForWriting.close()
    }

    /// Waits (briefly) until the child's last output has been written, then closes the file.
    /// Call off the main thread.
    func finish() {
        _ = eof.wait(timeout: .now() + 2)
        lock.lock(); try? handle?.close(); lock.unlock()
    }
}
