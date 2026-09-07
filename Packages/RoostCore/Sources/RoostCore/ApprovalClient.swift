import Foundation

/// The hook's side of the wire: one request, one reply, one connection.
///
/// Every failure returns `nil` so the caller falls through to the session's own
/// prompt. Roost being absent, stopped or wedged must never be able to change
/// what a tool call does.
public enum ApprovalClient {
    public static func ask(_ request: ApprovalRequest,
                           path: String = ApprovalSocket.path(),
                           timeout: TimeInterval = ApprovalSocket.timeout) -> ApprovalReply? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        guard var address = UnixAddress.make(path) else { return nil }
        var window = timeval(tv_sec: Int(timeout), tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &window, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &window, socklen_t(MemoryLayout<timeval>.size))

        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0,
              var payload = try? JSONEncoder.wire.encode(request) else { return nil }
        payload.append(0x0A)

        guard payload.withUnsafeBytes({ raw -> Bool in
            var sent = 0
            while sent < raw.count {
                let n = write(fd, raw.baseAddress!.advanced(by: sent), raw.count - sent)
                guard n > 0 else { return false }
                sent += n
            }
            return true
        }) else { return nil }

        guard let line = readLine(fd: fd) else { return nil }
        return try? JSONDecoder.wire.decode(ApprovalReply.self, from: line)
    }

    /// One newline-terminated frame. Shared with the server: both ends of
    /// this wire agree that a message is a line.
    public static func readLine(fd: Int32, limit: Int = 64 * 1024) -> Data? {
        var data = Data()
        var byte: UInt8 = 0
        while data.count < limit {
            let n = read(fd, &byte, 1)
            guard n == 1 else { return data.isEmpty ? nil : data }
            if byte == 0x0A { return data }
            data.append(byte)
        }
        return data
    }
}

/// `sockaddr_un` without the pointer gymnastics at every call site.
public enum UnixAddress {
    public static func make(_ path: String) -> sockaddr_un? {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8.count < capacity else { return nil }
        _ = withUnsafeMutablePointer(to: &address.sun_path) { raw in
            raw.withMemoryRebound(to: CChar.self, capacity: capacity) { destination in
                path.withCString { strcpy(destination, $0) }
            }
        }
        return address
    }
}

extension JSONEncoder {
    public static let wire: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

extension JSONDecoder {
    public static let wire: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
