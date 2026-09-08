import Foundation
import RoostCore

// One binary, three jobs, told apart by the arguments Roost wrote into the
// settings file it installed itself into: hold a Claude Code tool call for an
// answer, do the same for another agent and report where its sessions get to,
// or forward what a status line was told about the quota windows.

let arguments = Array(CommandLine.arguments.dropFirst())

func value(after flag: String) -> String? {
    guard let flag = arguments.firstIndex(of: flag),
          arguments.indices.contains(flag + 1) else { return nil }
    return arguments[flag + 1]
}

if arguments.contains(StatusLineInstall.flag) {
    runStatusLine(wrapping: value(after: StatusLineInstall.wrapFlag))
}

if let name = value(after: "--agent"), let agent = AgentKind(rawValue: name) {
    runAgentHook(agent)
}

runPreToolUse()
