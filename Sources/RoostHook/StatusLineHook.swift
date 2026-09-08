import Foundation
import RoostCore

/// The status line command. Claude Code hands it the only payload on this
/// machine that carries the quota windows, so Roost stands in that path --
/// and then gets out of the way.
///
/// Whatever was configured before still prints the line: the same payload goes
/// to its stdin and its output straight to ours. Roost's own part is a write to
/// a socket nobody waits on, because this runs on every render of a line the
/// user is looking at.
func runStatusLine(wrapping wrapped: String?) -> Never {
    let payload = FileHandle.standardInput.readDataToEndOfFile()

    if let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
       let usage = Usage.read(statusLine: json) {
        ApprovalClient.report(usage)
    }

    guard let wrapped, let command = StatusLineInstall.wrappedCommand(in: wrapped) else { exit(0) }
    exit(forward(payload, to: command))
}

/// Runs the wrapped command with the payload on its stdin, letting it write
/// straight to ours. A command that will not start prints nothing and succeeds:
/// a status line is not worth an error message where a status line goes.
private func forward(_ payload: Data, to command: String) -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", command]
    process.standardOutput = FileHandle.standardOutput
    process.standardError = FileHandle.standardError

    let input = Pipe()
    process.standardInput = input
    guard (try? process.run()) != nil else { return 0 }

    try? input.fileHandleForWriting.write(contentsOf: payload)
    try? input.fileHandleForWriting.close()
    process.waitUntilExit()
    return process.terminationStatus
}
