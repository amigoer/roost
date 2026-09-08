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
        sounds.observe(sessions, spentWindow: spentUsage != nil)
    }

    /// The sessions as the island shows them.
    ///
    /// Three sources, each answering what only it can. The scan says which
    /// sessions exist and what they are doing. The hooks say *when* a turn
    /// turned, which the transcript does not record until the model has
    /// finished writing its answer -- fifteen seconds, measured, after you have
    /// finished reading it. And this process alone knows about a call of its
    /// own held at the gate: a session waiting on a card is waiting on you, and
    /// has to say so and sort like it.
    var sessions: [Session] {
        let all = ReportedSessions.sharpened(scanned, by: reported.turnMarks())
            + reported.sessions()
        guard !approvals.pending.isEmpty else { return Session.ordered(all) }
        return Session.ordered(all.map { session in
            guard let held = approvals.pending.first(where: { $0.sessionId == session.id })
            else { return session }
            return session.held(by: held)
        })
    }

    /// A newer published build, once one has been seen.
    var update: ReleaseInfo?

    /// What is left of the quota windows, whichever path last said so.
    ///
    /// Account-wide rather than per session: every session on this Mac spends
    /// the same five-hour window, so one reading describes all of them. Loaded
    /// from disk at launch, because the figure someone opens the island to
    /// check is most often one nothing has reported since the app started.
    private(set) var usage: Usage? = UsageStore.load()

    /// Whether anyone is looking at an island right now, which is the only
    /// thing that makes a minute-by-minute poll worth making.
    var isWatched = false

    func report(_ usage: Usage) {
        let merged = usage.merged(with: self.usage)
        self.usage = merged
        UsageStore.save(merged)
    }

    func report(_ session: SessionReport) {
        reported.receive(session)
        // A card for a session nobody had heard of yet appears with the report
        // that introduces it, so the sound has to follow it here too.
        announce()
    }

    /// The figure, while either path is switched on to keep it coming. With
    /// both off there is nothing behind the number and it should not be shown
    /// at all; how old it is, is the footer's business rather than this one's.
    var liveUsage: Usage? {
        guard readsStatusLine || checksUsageOnline else { return nil }
        return usage
    }

    /// Remembered across launches, and off until it is turned on.
    ///
    /// Besides the update check this is the only thing Roost sends anywhere, so
    /// it is not something to find already running.
    var checksUsageOnline = UserDefaults.standard.bool(forKey: usageOnlineKey) {
        didSet {
            UserDefaults.standard.set(checksUsageOnline, forKey: Self.usageOnlineKey)
            startPollingUsage()
            forgetUsageIfUnwatched()
        }
    }

    static let usageOnlineKey = "checksUsageOnline"

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
    /// Whether the status line command is installed, which is one of the two
    /// ways the quota windows reach this app.
    private(set) var readsStatusLine = false
    /// Agents whose settings file exists and could not be read. Roost writes
    /// over none of them, so the switches they govern are unavailable rather
    /// than off -- and saying which is the whole point of the line beside them.
    private(set) var unreadableSettings: Set<AgentKind> = []

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

        let claude = HookInstall.read()
        let codex = HookInstall.read(AgentKind.codex.hooksURL)
        var unreadable: Set<AgentKind> = []
        if claude.editable == nil { unreadable.insert(.claudeCode) }
        if codex.editable == nil { unreadable.insert(.codex) }
        unreadableSettings = unreadable

        // A file nothing of ours could be found in reads as off, which is true
        // either way: an unreadable one is also one Roost has never written to.
        let settings = claude.editable ?? [:]
        answersPrompts = HookInstall.isInstalled(agent: .claudeCode, command: hookCommand,
                                                 in: settings)
        readsStatusLine = StatusLineInstall.isInstalled(settings, command: hookCommand)
        watchesCodex = HookInstall.isInstalled(agent: .codex,
                                               command: hookCommand(for: .codex),
                                               in: codex.editable ?? [:])
    }

    /// Writes the user's own settings file, additively both ways.
    ///
    /// A file that could not be read is left alone. Turning a switch on is
    /// never worth replacing everything else in it, and the refresh is what
    /// puts the reason on screen beside the switch that just refused to move.
    func setAnswersPrompts(_ on: Bool) {
        guard let settings = HookInstall.read().editable else {
            refreshHookState()
            return
        }
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
        guard answersPrompts, let settings = HookInstall.read().editable else { return }
        let updated = HookInstall.adding(agent: .claudeCode, command: hookCommand, to: settings)
        guard !NSDictionary(dictionary: updated).isEqual(to: settings) else { return }
        try? HookInstall.write(updated)
        refreshHookState()
    }

    /// Writes Codex's own hooks file, by the same rules as Claude Code's.
    func setWatchesCodex(_ on: Bool) {
        let url = AgentKind.codex.hooksURL
        let command = hookCommand(for: .codex)
        guard let settings = HookInstall.read(url).editable else {
            refreshHookState()
            return
        }
        let updated = on
            ? HookInstall.adding(agent: .codex, command: command, to: settings)
            : HookInstall.removing(command: command, from: settings)
        try? HookInstall.write(updated, to: url)
        // Rows for sessions nothing is reporting on any more.
        if !on { reported.forget(.codex) }
        refreshHookState()
    }

    /// Wraps whatever status line is already configured, and unwraps it again.
    func setReadsStatusLine(_ on: Bool) {
        guard let settings = HookInstall.read().editable else {
            refreshHookState()
            return
        }
        let updated = on
            ? StatusLineInstall.adding(command: hookCommand, to: settings)
            : StatusLineInstall.removing(command: hookCommand, from: settings)
        try? HookInstall.write(updated)
        refreshHookState()
        forgetUsageIfUnwatched()
    }

    /// With nothing left to keep it current, the figure goes -- from screen and
    /// from disk. A number nobody asked for reappearing at the next launch is
    /// worse than no number at all.
    private func forgetUsageIfUnwatched() {
        guard !readsStatusLine, !checksUsageOnline else { return }
        usage = nil
        UsageStore.clear()
    }

    /// Asks Anthropic what is left, for as long as the switch is on.
    ///
    /// Every failure is silent and costs nothing but the next interval: an
    /// expired credential, no network, a refusal. What was last read stays on
    /// screen with the time it was read, which is the honest answer to a
    /// question nobody can currently answer better.
    func startPollingUsage() {
        usageTask?.cancel()
        guard checksUsageOnline else { return }
        usageTask = Task { [weak self] in
            var failures = 0
            // The first look after the switch is turned on is somebody asking
            // for the figure, so it does not wait behind the recheck interval.
            var asked = true
            while !Task.isCancelled {
                guard let self, self.checksUsageOnline else { return }
                let reading = await Self.poll(fresh: asked)
                asked = false
                if let reading {
                    self.report(reading)
                    failures = 0
                } else {
                    failures += 1
                }
                let delay = UsageAPI.delay(watched: self.isWatched || self.isPinned,
                                           failures: failures)
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    /// Off the main actor: the credential read can touch the keychain and the
    /// request is a request.
    ///
    /// The credential is held rather than re-read: it belongs to Claude Code,
    /// and reading another application's keychain item prompts for any build
    /// not on its access list. Once a minute was once a dialog a minute.
    private static func poll(fresh: Bool) async -> Usage? {
        let store = CredentialStore.shared
        guard let credential = fresh ? await store.refresh() : await store.current()
        else { return nil }
        return await UsageAPI.fetch(credential: credential)
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
    private var usageTask: Task<Void, Never>?

    /// A window near enough to full to be the loudest thing about the fleet.
    ///
    /// Below this the figure is background. Above it, it is what is going to
    /// stop the work, which is a louder fact than how many sessions happen to
    /// be running -- and a stale reading is not allowed to raise it, because
    /// escalating on a number nobody has confirmed for an hour is a false alarm
    /// with a countdown attached.
    var tightUsage: (label: Usage.WindowLabel, window: UsageWindow)? {
        guard let usage = liveUsage, usage.isFresh(), let binding = usage.binding,
              binding.window.used >= Usage.tight, !usage.hasReset(binding.window)
        else { return nil }
        return binding
    }

    /// A window with nothing left in it, while there is work for it to stop.
    ///
    /// A wall is only worth the island's shape when somebody is walking into
    /// it. On a Mac with nothing running, a spent window is a fact about later,
    /// and the notch stays the notch.
    var spentUsage: UsageWindow? {
        guard let usage = liveUsage, usage.isFresh(), let spent = usage.spent,
              !usage.hasReset(spent) else { return nil }
        return spent
    }

    /// A spent window blocks every session there is, which is blocked in the
    /// one sense the island means by the word. Ranked below the sessions' own
    /// reading: somebody waiting on a prompt is waiting on you, where a spent
    /// window is waiting on a clock.
    var level: SignalLevel {
        let sessions = SignalLevel.aggregate(self.sessions.map(\.state))
        guard sessions != .dormant, spentUsage != nil else { return sessions }
        return .blocked
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
        case .blocked:
            if blockedSessions.contains(where: { $0.state.face == .waiting }) { return .waiting }
            // Blocked with nothing blocked in it is the window's doing.
            if blockedSessions.isEmpty, spentUsage != nil { return .spent }
            return .stalled
        }
    }

    /// How wide the collapsed strip stands.
    ///
    /// Normally a function of how long something has been blocked. A spent
    /// window claims the escalated width whatever the clock says, because it is
    /// the one state whose right-hand slot holds a countdown rather than a
    /// digit: `4h48m` is 39pt in English and 48pt in Chinese, and the resting
    /// slot is 48pt including its padding. At the narrow width the clock ran
    /// into the edge of the island, and in Chinese it wrapped onto a second
    /// line and clipped against the notch.
    var tier: EscalationTier {
        let longest = blockedSessions.map(\.blockedFor).max() ?? 0
        let escalation = EscalationTier(blockedFor: longest)
        guard spentUsage != nil else { return escalation }
        return escalation == .calm ? .elevated : escalation
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
