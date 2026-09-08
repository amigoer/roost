import SwiftUI
import RoostCore

@MainActor
@Observable
final class RoostModel {
    /// What the last scan read off disk.
    private(set) var scanned: [Session] = []
    /// Sessions Roost knows about only because their hooks said so.
    let reported = ReportedSessions()
    /// Tool calls held by the hook, waiting for an answer.
    let approvals = ApprovalCenter()
    /// The chirps, and whether they are wanted.
    let sounds = SoundBoard()

    /// Lets the announcer see the fleet as it is now.
    ///
    /// Safe to call as often as anything likes: it decides from the difference
    /// between two snapshots, so a second look at the same one says nothing.
    func announce() {
        sounds.observe(sessions)
    }

    /// The sessions as the island shows them: what the scan read, plus the one
    /// fact only this process has -- a call of its own held at the gate. A
    /// session waiting on a card is waiting on you, and has to say so and sort
    /// like it.
    var sessions: [Session] {
        let all = scanned + reported.sessions()
        guard !approvals.pending.isEmpty else { return Session.ordered(all) }
        return Session.ordered(all.map { session in
            guard let held = approvals.pending.first(where: { $0.sessionId == session.id })
            else { return session }
            return session.held(by: held)
        })
    }

    /// A newer published build, once one has been seen.
    var update: ReleaseInfo?

    /// What the last status line said about the quota windows.
    ///
    /// Account-wide rather than per session: every session on this Mac spends
    /// the same five-hour window, so the newest report describes all of them.
    private(set) var usage: Usage?

    func report(_ usage: Usage) {
        self.usage = usage
    }

    func report(_ session: SessionReport) {
        reported.receive(session)
        // A card for a session nobody had heard of yet appears with the report
        // that introduces it, so the sound has to follow it here too.
        announce()
    }

    /// The figure, while it is still describing the present. Nothing writes a
    /// status line once the last session closes, and a number left on screen
    /// after that is describing a window that has since moved on.
    var liveUsage: Usage? {
        guard showsUsage, let usage, usage.isFresh() else { return nil }
        return usage
    }

    /// Remembered across launches, and on unless it is turned off.
    var checksForUpdates = UserDefaults.standard.object(forKey: updatesKey) as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(checksForUpdates, forKey: Self.updatesKey)
            if !checksForUpdates { update = nil }
        }
    }

    static let updatesKey = "checksForUpdates"

    /// Remembered across launches; `system` until someone picks otherwise, so
    /// a first launch already speaks the language the Mac does.
    var languageChoice = LanguageChoice(rawValue: UserDefaults.standard.string(forKey: languageKey) ?? "") ?? .system {
        didSet { UserDefaults.standard.set(languageChoice.rawValue, forKey: Self.languageKey) }
    }

    static let languageKey = "language"

    var language: Language { languageChoice.language }

    /// Every word the interface says, in the language that is current.
    var strings: Strings { Strings(language) }

    /// Whether the approval hook is installed. Read from disk on demand rather
    /// than watched: it changes only when something here writes it.
    private(set) var answersPrompts = false
    /// Whether Codex has been told to talk to Roost.
    private(set) var watchesCodex = false
    /// Whether the status line command is installed, which is the only way the
    /// quota windows reach this app at all.
    private(set) var showsUsage = false

    var hookCommand: String {
        Bundle.main.bundleURL.appending(path: "Contents/MacOS/roost-hook").path
    }

    /// The same helper, told which agent it is standing in for. Quoted because
    /// an agent runs a hook through a shell and an app can be renamed into a
    /// path with a space in it.
    func hookCommand(for agent: AgentKind) -> String {
        agent == .claudeCode ? hookCommand : "'\(hookCommand)' --agent \(agent.rawValue)"
    }

    /// Read from the system rather than remembered: the user can switch a
    /// login item off in System Settings, and this app would never hear.
    private(set) var opensAtLogin = LoginItem.isEnabled

    func setOpensAtLogin(_ on: Bool) {
        LoginItem.set(on)
        opensAtLogin = LoginItem.isEnabled
    }

    func refreshHookState() {
        opensAtLogin = LoginItem.isEnabled
        let settings = HookInstall.read()
        answersPrompts = HookInstall.isInstalled(agent: .claudeCode, command: hookCommand,
                                                 in: settings)
        showsUsage = StatusLineInstall.isInstalled(settings, command: hookCommand)
        watchesCodex = HookInstall.isInstalled(agent: .codex,
                                               command: hookCommand(for: .codex),
                                               in: HookInstall.read(AgentKind.codex.hooksURL))
    }

    /// Writes the user's own settings file, additively both ways.
    func setAnswersPrompts(_ on: Bool) {
        let settings = HookInstall.read()
        let updated = on
            ? HookInstall.adding(agent: .claudeCode, command: hookCommand, to: settings)
            : HookInstall.removing(command: hookCommand, from: settings)
        try? HookInstall.write(updated)
        refreshHookState()
    }

    /// Brings an older install up to date.
    ///
    /// Answering used to mean one `PreToolUse` hook and now means two events,
    /// so a settings file written by an earlier version has the switch on and
    /// half the wiring -- which holds nothing at all, quietly. Repairing it is
    /// not a new decision: the switch is already on, and this only writes what
    /// turning it on today would have written.
    func repairHooks() {
        guard answersPrompts else { return }
        let settings = HookInstall.read()
        let updated = HookInstall.adding(agent: .claudeCode, command: hookCommand, to: settings)
        guard !NSDictionary(dictionary: updated).isEqual(to: settings) else { return }
        try? HookInstall.write(updated)
        refreshHookState()
    }

    /// Writes Codex's own hooks file, by the same rules as Claude Code's.
    func setWatchesCodex(_ on: Bool) {
        let url = AgentKind.codex.hooksURL
        let command = hookCommand(for: .codex)
        let settings = HookInstall.read(url)
        let updated = on
            ? HookInstall.adding(agent: .codex, command: command, to: settings)
            : HookInstall.removing(command: command, from: settings)
        try? HookInstall.write(updated, to: url)
        // Rows for sessions nothing is reporting on any more.
        if !on { reported.forget(.codex) }
        refreshHookState()
    }

    /// Wraps whatever status line is already configured, and unwraps it again.
    func setShowsUsage(_ on: Bool) {
        let settings = HookInstall.read()
        let updated = on
            ? StatusLineInstall.adding(command: hookCommand, to: settings)
            : StatusLineInstall.removing(command: hookCommand, from: settings)
        try? HookInstall.write(updated)
        // A figure from before the switch describes a window nobody is
        // reporting on any more.
        if !on { usage = nil }
        refreshHookState()
    }

    var currentVersion = Bundle.main
        .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"



    /// A held tool call keeps every island open: it is not something to answer
    /// only while the cursor happens to be on one particular notch.
    var isPinned: Bool { approvals.current != nil }

    /// How much room the held call takes above the rows, and zero when there is
    /// none. Read by the view and by the hit test, which must agree.
    var heldHeight: CGFloat { IslandGeometry.Held.height(approvals.current?.kind) }

    private let scanner = SessionScanner()
    private var refreshTask: Task<Void, Never>?
    private var updateTask: Task<Void, Never>?

    var level: SignalLevel {
        SignalLevel.aggregate(sessions.map(\.state))
    }

    /// The face the collapsed island and the menu bar item wear: the one
    /// belonging to the loudest session.
    var face: MascotFace {
        // Something is held at the gate: that is the loudest fact there is.
        if approvals.current != nil { return .waiting }
        switch level {
        case .dormant: return .idle
        case .running: return .running
        case .done: return .done
        case .blocked: return blockedSessions.contains { $0.state.face == .waiting }
            ? .waiting
            : .stalled
        }
    }

    var tier: EscalationTier {
        let longest = blockedSessions.map(\.blockedFor).max() ?? 0
        return EscalationTier(blockedFor: longest)
    }

    /// Everything except conversations left idle long enough to be clutter.
    /// A `done` session is still alive, so recent ones stay listed: you may have
    /// replied a minute ago and still be working in it.
    var visibleSessions: [Session] {
        sessions.filter { !$0.isStale() }
    }

    var staleCount: Int { sessions.count - visibleSessions.count }

    /// Whether the panel ends in a footer, which decides how tall it is. The
    /// view and the hit test both read this so they cannot disagree.
    var hasFooter: Bool { staleCount > 0 || update != nil || liveUsage != nil }

    var runningCount: Int {
        visibleSessions.count { if case .running = $0.state { true } else { false } }
    }

    var blockedSessions: [Session] {
        sessions.filter { if case .blocked = $0.state { true } else { false } }
    }

    var blockedCount: Int { blockedSessions.count }

    func startCheckingForUpdates() {
        updateTask?.cancel()
        updateTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkForUpdate()
                try? await Task.sleep(for: .seconds(UpdateCheck.interval))
            }
        }
    }

    /// `force` is the menu asking directly, which works even with the periodic
    /// check switched off.
    func checkForUpdate(force: Bool = false) async {
        guard checksForUpdates || force else { return }
        guard let latest = await UpdateCheck.fetch() else { return }
        update = UpdateCheck.isNewer(latest.version, than: currentVersion) ? latest : nil
    }

    func startRefreshing() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.scanned = await self.scanner.scan()
                self.approvals.expireStale()
                self.reported.expire()
                self.announce()
                // A stalled tool crosses the grace line without anything being
                // written, so state can change with no file event to react to.
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}
