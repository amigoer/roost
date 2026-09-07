import Foundation

/// How hard the blocked signal pushes, as a function of how long it has been ignored.
///
/// Peripheral-display research is clear that animation *frequency* is what
/// disrupts a primary task, so the badge blinks at one rate whatever the tier
/// and escalation rides on the island's width instead. Hue is already spoken
/// for: it says which state the session is in, not how long it has been there.
public enum EscalationTier: Int, Sendable, Hashable, Comparable, CaseIterable {
    /// Base width.
    case calm = 0
    /// Wider. Same blink rate.
    case elevated = 1
    /// Auto-peek once to name the session, then collapse back.
    case peek = 2

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    public static let elevatedAfter: TimeInterval = 60
    public static let peekAfter: TimeInterval = 300

    public init(blockedFor duration: TimeInterval) {
        switch duration {
        case ..<Self.elevatedAfter: self = .calm
        case ..<Self.peekAfter: self = .elevated
        default: self = .peek
        }
    }
}
