import SwiftUI
import RoostCore

@MainActor
@Observable
final class RoostModel {
    var sessions: [Session] = []
    /// Tool calls held by the hook, waiting for an answer.
    let approvals = ApprovalCenter()

    /// A newer published build, once one has been seen.
    var update: ReleaseInfo?

    /// Remembered across launches, and on unless it is turned off.
    var checksForUpdates = UserDefaults.standard.object(forKey: updatesKey) as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(checksForUpdates, forKey: Self.updatesKey)
            if !checksForUpdates { update = nil }
        }
    }

    static let updatesKey = "checksForUpdates"

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }


    /// Set by the debug menu to force a state while detection is being tuned.
    var previewOverride: PreviewOverride?

    struct PreviewOverride: Equatable {
        var level: SignalLevel
        var tier: EscalationTier
        var blockedCount: Int
        var face: MascotFace
    }

    /// A held tool call keeps every island open: it is not something to answer
    /// only while the cursor happens to be on one particular notch.
    var isPinned: Bool { approvals.current != nil }

    func permissionMode(for sessionId: String) -> String? {
        sessions.first { $0.id == sessionId }?.permissionMode
    }

    private let scanner = SessionScanner()
    private var refreshTask: Task<Void, Never>?
    private var updateTask: Task<Void, Never>?

    var level: SignalLevel {
        if let previewOverride { return previewOverride.level }
        return SignalLevel.aggregate(sessions.map(\.state))
    }

    /// The face the collapsed island and the menu bar item wear: the one
    /// belonging to the loudest session.
    var face: MascotFace {
        if let previewOverride { return previewOverride.face }
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
        if let previewOverride { return previewOverride.tier }
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

    var runningCount: Int {
        visibleSessions.count { if case .running = $0.state { true } else { false } }
    }

    var blockedSessions: [Session] {
        sessions.filter { if case .blocked = $0.state { true } else { false } }
    }

    var blockedCount: Int {
        previewOverride?.blockedCount ?? blockedSessions.count
    }

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
                let scanned = await self.scanner.scan()
                self.sessions = scanned
                self.approvals.expireStale()
                // A stalled tool crosses the grace line without anything being
                // written, so state can change with no file event to react to.
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}
