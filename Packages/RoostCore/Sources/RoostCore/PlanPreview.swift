import Foundation

/// The top of a plan, flattened into lines a 470 pt card can show.
///
/// Not a markdown renderer. The island has room for five or six lines and no
/// room at all for a heading hierarchy, so the markup that would carry that
/// structure is spent instead on getting more of the plan's actual words on
/// screen. The conversation still has the whole thing.
public enum PlanPreview {
    /// Longest line the card can hold before the text starts colliding with
    /// its own right edge.
    public static let lineLimit = 70

    public struct Preview: Sendable, Hashable {
        public let lines: [String]
        /// Lines that did not fit, so the card can say there is more.
        public let remaining: Int
    }

    public static func make(_ plan: String, limit: Int) -> Preview {
        let all = flatten(plan)
        return Preview(lines: Array(all.prefix(limit)),
                       remaining: max(0, all.count - limit))
    }

    static func flatten(_ plan: String) -> [String] {
        plan.split(whereSeparator: \.isNewline).compactMap { raw in
            var line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { return nil }
            // A fence is scaffolding around code, and on its own line it says
            // nothing a reader of five lines needs.
            guard !line.hasPrefix("```") else { return nil }

            if line.hasPrefix("#") {
                line = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
            } else if let bullet = bulletBody(line) {
                line = "• " + bullet
            }

            line = line.replacingOccurrences(of: "**", with: "")
                .replacingOccurrences(of: "`", with: "")
                .trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { return nil }
            return line.count <= lineLimit ? line : line.prefix(lineLimit - 1) + "…"
        }
    }

    /// The text after a list marker, whether it is a dash, a star or a number.
    private static func bulletBody(_ line: String) -> String? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count))
        }
        let digits = line.prefix(while: \.isNumber)
        guard !digits.isEmpty else { return nil }
        let rest = line.dropFirst(digits.count)
        guard rest.hasPrefix(". ") || rest.hasPrefix(") ") else { return nil }
        return String(rest.dropFirst(2))
    }
}
