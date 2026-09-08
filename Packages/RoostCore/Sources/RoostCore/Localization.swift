import Foundation

/// The languages the interface speaks.
public enum Language: String, Sendable, Hashable, CaseIterable {
    case english = "en"
    case chinese = "zh-Hans"
}

/// What Settings offers. `system` is the default, so the app is already in the
/// right language the first time it opens and nobody has to choose.
public enum LanguageChoice: String, Sendable, Hashable, CaseIterable {
    case system
    case english
    case chinese

    public var language: Language {
        switch self {
        case .system: .preferred()
        case .english: .english
        case .chinese: .chinese
        }
    }
}

extension Language {
    /// Resolved from the user's ordered macOS language list the way the system
    /// resolves a bundle: the first entry this app can actually speak wins, so
    /// French above Chinese lands on Chinese rather than on English.
    ///
    /// Any Chinese counts, Traditional included: Simplified is nearer to what a
    /// Traditional reader wants than English is.
    public static func preferred(_ identifiers: [String] = Locale.preferredLanguages) -> Language {
        for identifier in identifiers {
            switch Locale(identifier: identifier).language.languageCode?.identifier {
            case "zh": return .chinese
            case "en": return .english
            default: continue
            }
        }
        return .english
    }
}
