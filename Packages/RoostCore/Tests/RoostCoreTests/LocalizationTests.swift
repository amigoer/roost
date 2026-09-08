import XCTest
@testable import RoostCore

final class LocalizationTests: XCTestCase {
    func testSystemChineseWins() {
        XCTAssertEqual(Language.preferred(["zh-Hans-CN", "en-US"]), .chinese)
        XCTAssertEqual(Language.preferred(["zh-Hant-TW"]), .chinese)
    }

    func testSystemEnglishWins() {
        XCTAssertEqual(Language.preferred(["en-GB", "zh-Hans-CN"]), .english)
    }

    func testFallsThroughToTheFirstLanguageItSpeaks() {
        XCTAssertEqual(Language.preferred(["fr-FR", "de-DE", "zh-Hans-CN"]), .chinese)
        XCTAssertEqual(Language.preferred(["fr-FR", "en-US"]), .english)
    }

    func testUnknownAndEmptyListsFallBackToEnglish() {
        XCTAssertEqual(Language.preferred(["fr-FR"]), .english)
        XCTAssertEqual(Language.preferred([]), .english)
    }

    func testAnExplicitChoiceIgnoresTheSystem() {
        XCTAssertEqual(LanguageChoice.english.language, .english)
        XCTAssertEqual(LanguageChoice.chinese.language, .chinese)
    }

    func testChoicesSurviveAsDefaults() {
        for choice in LanguageChoice.allCases {
            XCTAssertEqual(LanguageChoice(rawValue: choice.rawValue), choice)
        }
    }

    func testEnglishPluralisesSessions() {
        let english = Strings(.english)
        XCTAssertEqual(english.sessionCount(1), "1 session")
        XCTAssertEqual(english.sessionCount(2), "2 sessions")
        XCTAssertEqual(Strings(.chinese).sessionCount(1), "1 个会话")
    }

    func testElapsedStaysShortInBothLanguages() {
        let english = Strings(.english)
        XCTAssertEqual(english.elapsed(30), "<1m")
        XCTAssertEqual(english.elapsed(5 * 60), "5m")
        XCTAssertEqual(english.elapsed(2 * 3600), "2h")
        XCTAssertEqual(english.elapsed(2 * 3600 + 5 * 60), "2h05m")
        XCTAssertEqual(english.elapsed(3 * 86400), "3d")

        let chinese = Strings(.chinese)
        XCTAssertEqual(chinese.elapsed(30), "<1分")
        XCTAssertEqual(chinese.elapsed(5 * 60), "5分")
        XCTAssertEqual(chinese.elapsed(2 * 3600), "2时")
        XCTAssertEqual(chinese.elapsed(2 * 3600 + 5 * 60), "2时05分")
        XCTAssertEqual(chinese.elapsed(3 * 86400), "3天")
    }

    /// Every block reason has to say something in either language: an empty
    /// lede would leave a blocked row with no reason on it at all.
    func testEveryBlockReasonIsTranslated() {
        let reasons: [BlockReason] = [
            .permissionPrompt(tool: "Bash"), .permissionPrompt(tool: nil),
            .question, .planApproval,
            .agentNeedsInput(label: "Explore"), .agentNeedsInput(label: nil),
            .stalledTool(name: "WebFetch"),
        ]
        for language in Language.allCases {
            let strings = Strings(language)
            for reason in reasons {
                XCTAssertFalse(strings.label(for: reason).isEmpty, "\(language) \(reason)")
            }
        }
    }

    /// The two languages are written a line apart, and this is what catches a
    /// line that never got its second half.
    func testTheTwoLanguagesActuallyDiffer() {
        let english = Strings(.english)
        let chinese = Strings(.chinese)
        let sentences: [(String, String)] = [
            (english.settingsTitle, chinese.settingsTitle),
            (english.settingsMenuItem, chinese.settingsMenuItem),
            (english.quit, chinese.quit),
            (english.version, chinese.version),
            (english.update, chinese.update),
            (english.upToDate, chinese.upToDate),
            (english.checkAutomatically, chinese.checkAutomatically),
            (english.updatesNote, chinese.updatesNote),
            (english.approvalsSection, chinese.approvalsSection),
            (english.answerPrompts, chinese.answerPrompts),
            (english.approvalsNote, chinese.approvalsNote),
            (english.languageSection, chinese.languageSection),
            (english.interfaceLanguage, chinese.interfaceLanguage),
            (english.languageNote, chinese.languageNote),
            (english.nothingNeedsYou, chinese.nothingNeedsYou),
            (english.noLiveSessions, chinese.noLiveSessions),
            (english.wantsToRunIn, chinese.wantsToRunIn),
            (english.noArguments, chinese.noArguments),
            (english.deny, chinese.deny),
            (english.allow, chinese.allow),
            (english.working, chinese.working),
            (english.turnEnded, chinese.turnEnded),
        ]
        for (en, zh) in sentences {
            XCTAssertFalse(en.isEmpty)
            XCTAssertNotEqual(en, zh, "still English: \(en)")
        }
    }

    /// A language is named in its own language, so someone stuck in the wrong
    /// one can still find the way back.
    func testLanguageNamesReadTheSameInBothLanguages() {
        for language in Language.allCases {
            XCTAssertEqual(Strings(language).name(of: .english), "English")
            XCTAssertEqual(Strings(language).name(of: .chinese), "简体中文")
        }
    }
}
