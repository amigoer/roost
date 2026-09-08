import XCTest
@testable import RoostCore

/// Reading a settings file has to tell "there is nothing here" apart from
/// "there is something here I cannot read".
///
/// They used to be the same answer, and every caller writes back what it read:
/// a `settings.json` with a comment in it -- or a missing comma, or a write cut
/// half way -- was replaced by one holding nothing but Roost's own hooks,
/// taking the user's permissions, env and MCP servers with it.
final class HookFileTests: XCTestCase {
    private var directory = URL(fileURLWithPath: "/dev/null")

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "roost-hookfile-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func file(_ contents: String) throws -> URL {
        let url = directory.appending(path: "settings-\(UUID().uuidString).json")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testAbsentFileIsSomethingToWrite() {
        let editable = HookInstall.read(directory.appending(path: "nothing.json")).editable
        XCTAssertEqual(editable?.isEmpty, true)
    }

    func testValidSettingsComeBackWhole() throws {
        let url = try file(#"{"model": "opus", "permissions": {"allow": ["Bash"]}}"#)
        XCTAssertEqual(HookInstall.read(url).editable?["model"] as? String, "opus")
        XCTAssertNotNil(HookInstall.read(url).editable?["permissions"])
    }

    /// The bug, in the shapes a real settings file actually goes wrong in.
    ///
    /// A comment first, because `settings.json` is strict JSON and the habit
    /// of commenting one comes straight from every editor config that is not.
    /// Note what is *missing* from this list: a single trailing comma, which
    /// `JSONSerialization` accepts. Only what it rejects can strand a switch.
    func testMalformedSettingsAreNeverWrittenOver() throws {
        XCTAssertNil(HookInstall.read(try file("{\n  // mine\n  \"model\": \"opus\"\n}")).editable)
        XCTAssertNil(HookInstall.read(try file(#"{"model": "opus" "hooks": {}}"#)).editable)
        XCTAssertNil(HookInstall.read(try file(#"{"model": "opus", "hooks": {"#)).editable)
    }

    /// Valid JSON is not the same as settings. An array parses and still has
    /// nothing to merge into.
    func testJSONThatIsNotAnObjectIsLeftAloneToo() throws {
        XCTAssertNil(HookInstall.read(try file("[1, 2, 3]")).editable)
    }

    /// Nothing in it to lose, so nothing to protect -- and refusing here would
    /// strand every switch behind a file a crashed editor left at zero bytes.
    func testEmptyAndBlankFilesCountAsAbsent() throws {
        XCTAssertEqual(HookInstall.read(try file("")).editable?.isEmpty, true)
        XCTAssertEqual(HookInstall.read(try file("\n   \n")).editable?.isEmpty, true)
    }

    /// A directory where a settings file should be cannot be read and cannot
    /// be written either, which is the point: the refusal is about the path,
    /// not about the parse.
    func testSomethingUnreadableThatIsNotJSONAtAll() throws {
        let url = directory.appending(path: "settings.json")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        XCTAssertNil(HookInstall.read(url).editable)
    }

    /// The switches read their state from the same call. An unreadable file
    /// must report nothing installed rather than guess, because the repair
    /// path writes whenever it believes the switch is already on.
    func testAnUnreadableFileInstallsNothing() throws {
        let command = "/Applications/Roost.app/Contents/MacOS/roost-hook"
        let settings = HookInstall.read(try file(#"{"hooks": {,}}"#)).editable ?? [:]
        XCTAssertFalse(HookInstall.isInstalled(agent: .claudeCode, command: command, in: settings))
        XCTAssertFalse(StatusLineInstall.isInstalled(settings, command: command))
    }
}
