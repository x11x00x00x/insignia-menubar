//
//  DiscordRPCService.swift
//  Insignia Menubar
//
//  Discord Rich Presence (same behavior as XBLBeacon).
//  Tries IPC first, then WebSocket to 127.0.0.1:6463–6472 (works when app is sandboxed).
//  Requires Discord desktop app to be running.
//

import Foundation

#if os(macOS)
import Darwin
#else
import Glibc
#endif

/// Discord RPC IPC opcodes
private enum DiscordRPCOpcode: UInt32 {
    case handshake = 0
    case frame = 1
    case close = 2
    case ping = 3
    case pong = 4
}

/// Same client ID as XBLBeacon so the same Discord app shows "Playing ..." for xb.live
private let discordClientID = "1451762829303742555"

struct DiscordUser {
    let username: String
    let id: String
}

private enum Transport {
    case ipc(fd: Int32)
    case websocket(URLSessionWebSocketTask)
}

enum DiscordRPCService {
    private static var transport: Transport?
    private static let queue = DispatchQueue(label: "com.insignia.discordrpc")
    private static let lock = NSLock()

    /// Discord IPC socket paths. Try /var/folders first (where Discord creates the socket on macOS), then $TMPDIR, /tmp.
    private static var possibleSocketPaths: [String] {
        var paths: [String] = []
        let env = ProcessInfo.processInfo.environment
        // 1) /var/folders/*/*/T – macOS per-user tmp, where Discord creates the socket (same as Node's TMPDIR when Discord runs)
        if let folders = try? FileManager.default.contentsOfDirectory(atPath: "/var/folders") {
            for d1 in folders where d1.count == 2 && !d1.hasPrefix(".") {
                let p1 = "/var/folders/\(d1)"
                guard let sub = try? FileManager.default.contentsOfDirectory(atPath: p1) else { continue }
                for d2 in sub where !d2.hasPrefix(".") {
                    let tDir = "\(p1)/\(d2)/T"
                    for i in 0...10 {
                        paths.append("\(tDir)/discord-ipc-\(i)")
                    }
                }
            }
        }
        // 2) Our process $TMPDIR (matches Discord when launched similarly)
        let prefix = (env["XDG_RUNTIME_DIR"] ?? env["TMPDIR"] ?? env["TMP"] ?? env["TEMP"] ?? "/tmp")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let base = prefix.isEmpty ? "/tmp" : (prefix.hasSuffix("/") ? String(prefix.dropLast()) : prefix)
        for i in 0...10 {
            paths.append("\(base)/discord-ipc-\(i)")
        }
        // 3) System /tmp
        for i in 0...10 {
            paths.append("/tmp/discord-ipc-\(i)")
        }
        // 4) Application Support
        if let home = env["HOME"] {
            let appSupport = "\(home)/Library/Application Support"
            paths.append(contentsOf: ["\(appSupport)/discord/ipc", "\(appSupport)/discord_ptb/ipc", "\(appSupport)/discord_development/ipc"])
        }
        return paths
    }

    /// Connect to Discord: try IPC first, then WebSocket to 127.0.0.1:6463–6472.
    static func connect(completion: @escaping (Result<DiscordUser, Error>) -> Void) {
        queue.async {
            lock.lock()
            if transport != nil {
                let user = DiscordPresenceStore.discordUser ?? DiscordUser(username: "Connected", id: "unknown")
                lock.unlock()
                DispatchQueue.main.async { completion(.success(user)) }
                return
            }
            lock.unlock()

            // 1) Try IPC – attempt connect() for each path (don't rely on fileExists; app may not see socket in some launch contexts)
            for path in possibleSocketPaths {
                let fd = connectToUnixSocket(path: path)
                if fd >= 0 {
                    lock.lock()
                    transport = .ipc(fd: fd)
                    lock.unlock()
                    let handshake: [String: Any] = ["v": 1, "client_id": discordClientID]
                    guard let payload = try? JSONSerialization.data(withJSONObject: handshake),
                          sendFrameIPC(fd: fd, opcode: .handshake, payload: payload) else {
                        closeConnection()
                        continue
                    }
                    _ = readFrameIPC(fd: fd)
                    let user = DiscordUser(username: "Connected", id: "unknown")
                    DiscordPresenceStore.discordUser = user
                    DiscordPresenceStore.presenceActive = false
                    // Keep connection alive: respond to Discord PING with PONG (like XBLBeacon / discord-rpc)
                    startIPCReadLoop(fd: fd)
                    DispatchQueue.main.async { completion(.success(user)) }
                    return
                }
            }

            // 2) Fallback: WebSocket to localhost (works when sandbox blocks IPC)
            for port in 6463...6472 {
                let sem = DispatchSemaphore(value: 0)
                var connectResult: Result<DiscordUser, Error>?
                connectWebSocket(port: port) { result in
                    connectResult = result
                    sem.signal()
                }
                _ = sem.wait(timeout: .now() + 6)
                if case .success(let user)? = connectResult {
                    DiscordPresenceStore.discordUser = user
                    DiscordPresenceStore.presenceActive = false
                    DispatchQueue.main.async { completion(.success(user)) }
                    return
                }
                closeConnection()
            }

            let error = NSError(domain: "DiscordRPC", code: -1, userInfo: [NSLocalizedDescriptionKey: "Discord is not running. Please start Discord and try again."])
            DispatchQueue.main.async { completion(.failure(error)) }
        }
    }

    private static func connectToUnixSocket(path: String) -> Int32 {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return -1 }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = path.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            Darwin.close(fd)
            return -1
        }
        _ = pathBytes.withUnsafeBufferPointer { buf in
            memcpy(&addr.sun_path, buf.baseAddress, buf.count)
        }
        let ptr = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { $0 }
        }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let result = Darwin.connect(fd, ptr, len)
        if result != 0 {
            Darwin.close(fd)
            return -1
        }
        return fd
    }

    private static func connectWebSocket(port: Int, completion: @escaping (Result<DiscordUser, Error>) -> Void) {
        let urlString = "ws://127.0.0.1:\(port)/?v=1&client_id=\(discordClientID)"
        guard let url = URL(string: urlString) else {
            completion(.failure(NSError(domain: "DiscordRPC", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid WebSocket URL"])))
            return
        }
        var request = URLRequest(url: url)
        request.setValue("https://localhost", forHTTPHeaderField: "Origin")
        let task = URLSession.shared.webSocketTask(with: request)
        task.resume()
        lock.lock()
        transport = .websocket(task)
        lock.unlock()
        // Verify connection by sending a no-op SET_ACTIVITY (clear); only report success if send succeeds
        let args: [String: Any] = ["pid": ProcessInfo.processInfo.processIdentifier]
        let frame: [String: Any] = ["cmd": "SET_ACTIVITY", "args": args]
        guard let data = try? JSONSerialization.data(withJSONObject: frame),
              let json = String(data: data, encoding: .utf8) else {
            completion(.failure(NSError(domain: "DiscordRPC", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid payload"])))
            return
        }
        task.send(.string(json)) { error in
            if let error = error {
                lock.lock()
                transport = nil
                lock.unlock()
                completion(.failure(error))
            } else {
                completion(.success(DiscordUser(username: "Connected", id: "unknown")))
            }
        }
    }

    private static func sendFrameIPC(fd: Int32, opcode: DiscordRPCOpcode, payload: Data) -> Bool {
        var op = opcode.rawValue.littleEndian
        var len = UInt32(payload.count).littleEndian
        var header = Data(bytes: &op, count: 4)
        header.append(Data(bytes: &len, count: 4))
        let ok = header.withUnsafeBytes { ptr in
            Darwin.write(fd, ptr.baseAddress, header.count) == header.count
        }
        guard ok else { return false }
        return payload.withUnsafeBytes { ptr in
            Darwin.write(fd, ptr.baseAddress, payload.count) == payload.count
        }
    }

    /// Run on background thread; responds to PING with PONG so Discord keeps the connection and shows presence.
    private static func startIPCReadLoop(fd: Int32) {
        DispatchQueue.global(qos: .utility).async {
            while true {
                guard let (opcode, payload) = readFrameIPC(fd: fd) else { break }
                if opcode == DiscordRPCOpcode.ping.rawValue {
                    sendPongFromReadLoop(payload: payload)
                }
                if opcode == DiscordRPCOpcode.close.rawValue { break }
            }
        }
    }

    private static func sendPongFromReadLoop(payload: Data) {
        queue.async {
            lock.lock()
            defer { lock.unlock() }
            if case .ipc(let fd) = transport {
                _ = sendFrameIPC(fd: fd, opcode: .pong, payload: payload)
            }
        }
    }

    private static func readFrameIPC(fd: Int32) -> (opcode: UInt32, payload: Data)? {
        var header = [UInt8](repeating: 0, count: 8)
        var total = 0
        while total < 8 {
            let n = header.withUnsafeMutableBytes { ptr in
                Darwin.read(fd, ptr.baseAddress!.advanced(by: total), 8 - total)
            }
            if n <= 0 { return nil }
            total += n
        }
        let opcode = header.withUnsafeBufferPointer { buf in
            buf.baseAddress!.withMemoryRebound(to: UInt32.self, capacity: 1) { $0.pointee }
        }
        let length = header.withUnsafeBufferPointer { buf in
            (buf.baseAddress! + 4).withMemoryRebound(to: UInt32.self, capacity: 1) { $0.pointee }
        }
        let len = Int(length.littleEndian)
        guard len >= 0, len <= 1024 * 1024 else { return nil }
        var payload = Data(count: len)
        total = 0
        while total < len {
            let n = payload.withUnsafeMutableBytes { ptr in
                Darwin.read(fd, ptr.baseAddress!.advanced(by: total), len - total)
            }
            if n <= 0 { return nil }
            total += n
        }
        return (opcode.littleEndian, payload)
    }

    private static func sendFrame(opcode: DiscordRPCOpcode, payload: Data) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        switch transport {
        case .ipc(let fd):
            return sendFrameIPC(fd: fd, opcode: opcode, payload: payload)
        case .websocket(let task):
            // WebSocket transport sends JSON only (no opcode header)
            guard let json = String(data: payload, encoding: .utf8) else { return false }
            let sem = DispatchSemaphore(value: 0)
            var sent = false
            task.send(.string(json)) { error in
                sent = (error == nil)
                sem.signal()
            }
            _ = sem.wait(timeout: .now() + 3)
            return sent
        case .none:
            return false
        }
    }

    static func setActivity(details: String, state: String, startTimestamp: Date, largeImageKey: String, largeImageText: String, smallImageKey: String, smallImageText: String) -> Bool {
        // Match discord-rpc / XBLBeacon: timestamps in milliseconds (Discord RPC accepts ms)
        let startMs = Int64(startTimestamp.timeIntervalSince1970 * 1000)
        let activity: [String: Any] = [
            "details": details,
            "state": state,
            "timestamps": ["start": startMs],
            "assets": [
                "large_image": largeImageKey,
                "large_text": largeImageText,
                "small_image": smallImageKey,
                "small_text": smallImageText
            ]
        ]
        let args: [String: Any] = ["pid": ProcessInfo.processInfo.processIdentifier, "activity": activity]
        // Include nonce so Discord correlates the request (same as discord-rpc library)
        let nonce = UUID().uuidString
        let frame: [String: Any] = ["cmd": "SET_ACTIVITY", "args": args, "nonce": nonce]
        guard let data = try? JSONSerialization.data(withJSONObject: frame) else { return false }
        return queue.sync { sendFrame(opcode: .frame, payload: data) }
    }

    static func clearActivity() -> Bool {
        let args: [String: Any] = ["pid": ProcessInfo.processInfo.processIdentifier]
        let nonce = UUID().uuidString
        let frame: [String: Any] = ["cmd": "SET_ACTIVITY", "args": args, "nonce": nonce]
        guard let data = try? JSONSerialization.data(withJSONObject: frame) else { return false }
        return queue.sync { sendFrame(opcode: .frame, payload: data) }
    }

    static func disconnect() {
        queue.async {
            closeConnection()
        }
    }

    private static func closeConnection() {
        lock.lock()
        switch transport {
        case .ipc(let fd):
            if fd >= 0 { Darwin.close(fd) }
        case .websocket(let task):
            task.cancel(with: .goingAway, reason: nil)
        case .none:
            break
        }
        transport = nil
        lock.unlock()
    }

    static var connected: Bool {
        lock.lock()
        let ok = transport != nil
        lock.unlock()
        return ok
    }
}
