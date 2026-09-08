import Foundation
import RoostCore

// One binary, two jobs, told apart by the arguments Roost wrote into the
// settings file it installed itself into: stand between an agent and the
// person for a tool event, or forward what a status line was told about the
// quota windows.

let arguments = Array(CommandLine.arguments.dropFirst())

func value(after flag: String) -> String? {
    guard let flag = arguments.firstIndex(of: flag),
          arguments.indices.contains(flag + 1) else { return nil }
    return arguments[flag + 1]
}

if arguments.contains(StatusLineInstall.flag) {
    runStatusLine(wrapping: value(after: StatusLineInstall.wrapFlag))
}

// Unnamed means Claude Code: it was the only agent when this hook was first
// installed, and those settings files are still out there.
runToolHook(value(after: "--agent").flatMap(AgentKind.init(rawValue:)) ?? .claudeCode)
