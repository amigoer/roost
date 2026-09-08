import Foundation
import RoostCore

// One binary, two jobs, told apart by the arguments Roost wrote into the
// user's settings: hold a tool call for an answer, or forward what a status
// line was told about the quota windows.

let arguments = Array(CommandLine.arguments.dropFirst())

if arguments.contains(StatusLineInstall.flag) {
    let wrapped = arguments.firstIndex(of: StatusLineInstall.wrapFlag).flatMap {
        arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil
    }
    runStatusLine(wrapping: wrapped)
}

runPreToolUse()
