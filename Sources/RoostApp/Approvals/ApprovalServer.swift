import Foundation
import RoostCore

/// Listens for the hook and hands each held tool call to the island.
///
/// One connection, one request, one reply. The hook is sitting in a blocking
/// read on the other end with a session stopped behind it, so nothing here may
/// wait on anything but the person.
final class ApprovalServer: @unchecked Sendable {
    private let handler: @Sendable (ApprovalRequest) async -> ApprovalReply
    private var listener: Int32 = -1

    init(handler: @escaping @Sendable (ApprovalRequest) async -> ApprovalReply) {
        self.handler = handler
    }

    func start() {
        guard bindSocket() else { return }
        // A dedicated thread: the accept loop blocks forever, which is not
        // something to hand a shared queue.
        let thread = Thread { [weak self] in self?.acceptLoop() }
        thread.name = "roost.approvals"
        thread.start()
    }

    func stop() {
        guard listener >= 0 else { return }
        close(listener)
        listener = -1
        unlink(ApprovalSocket.path())
    }

    private func bindSocket() -> Bool {
        let path = ApprovalSocket.path()
        try? FileManager.default.createDirectory(at: ApprovalSocket.directory(),
                                                 withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        // A socket file outlives the process that made it, so a leftover one
        // has to be cleared or bind fails for the rest of the machine's uptime.
        unlink(path)

        listener = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listener >= 0, var address = UnixAddress.make(path) else { return false }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, listen(listener, 16) == 0 else {
            close(listener)
            listener = -1
            return false
        }
        // Same user only. The socket decides what tools may run.
        chmod(path, 0o600)
        return true
    }

    private func acceptLoop() {
        while listener >= 0 {
            let connection = accept(listener, nil, nil)
            guard connection >= 0 else {
                if errno == EINTR { continue }
                return
            }
            serve(connection)
        }
    }

    private func serve(_ connection: Int32) {
        // The hook writes its request immediately; a connection that does not
        // is a bug or a stranger, and either way must not hold a task open.
        var window = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(connection, SOL_SOCKET, SO_RCVTIMEO, &window, socklen_t(MemoryLayout<timeval>.size))

        Task.detached { [handler] in
            defer { close(connection) }
            guard let line = ApprovalClient.readLine(fd: connection),
                  let request = try? JSONDecoder.wire.decode(ApprovalRequest.self, from: line)
            else { return }

            let reply = await handler(request)
            guard var data = try? JSONEncoder.wire.encode(reply) else { return }
            data.append(0x0A)
            data.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return }
                var sent = 0
                while sent < raw.count {
                    let n = write(connection, base.advanced(by: sent), raw.count - sent)
                    guard n > 0 else { return }
                    sent += n
                }
            }
        }
    }
}
