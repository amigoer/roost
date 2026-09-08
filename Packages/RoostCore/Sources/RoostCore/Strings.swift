import Foundation

/// Everything the interface says, in both languages, one line apart.
///
/// A table in Swift rather than `.strings` files: the choice in Settings has to
/// land on the spot rather than at the next launch, and with this few strings,
/// keeping the two languages next to each other is what stops them drifting.
public struct Strings: Sendable, Hashable {
    public let language: Language

    public init(_ language: Language) {
        self.language = language
    }

    private func pick(_ en: String, _ zh: String) -> String {
        switch language {
        case .english: en
        case .chinese: zh
        }
    }

    // MARK: - Settings

    public var settingsTitle: String { pick("Roost Settings", "Roost 设置") }
    public var settingsMenuItem: String { pick("Settings…", "设置…") }
    public var quit: String { pick("Quit Roost", "退出 Roost") }

    public var appSection: String { "Roost" }
    public var version: String { pick("Version", "版本") }
    public var update: String { pick("Update", "更新") }
    public func download(_ version: String) -> String { pick("Download \(version)", "下载 \(version)") }
    public var upToDate: String { pick("Up to date", "已是最新") }
    public var checkAutomatically: String { pick("Check automatically", "自动检查") }
    public var updatesNote: String {
        pick("Checks the public releases page every six hours and sends nothing but the request. Installing an update stays manual.",
             "每六小时看一次公开的发布页面，除了这个请求本身什么都不发送。更新仍然由你手动安装。")
    }

    public var openAtLogin: String { pick("Open at login", "开机时启动") }
    public var loginNeedsApproval: String { pick("Blocked in System Settings", "已被系统设置拦截") }
    public var openSystemSettings: String { pick("Open", "去打开") }
    public var loginNote: String {
        pick("A Roost that has not been launched is an invisible one: there is no Dock icon and no menu bar item to notice it missing by.",
             "没启动的 Roost 是看不见的：它没有 Dock 图标，也没有菜单栏图标，少了也不会有人发现。")
    }

    /// Stands in for any switch whose file cannot be written. Names the path,
    /// because that is the only part of this a person can act on.
    public func settingsUnreadable(_ path: String) -> String {
        pick("\(path) is not valid JSON. Roost writes over nothing it cannot read, so this stays off until the file parses.",
             "\(path) 不是有效的 JSON。Roost 不会覆盖读不懂的文件，所以在它能被解析之前这里一直是关的。")
    }
    public var revealSettings: String { pick("Reveal", "去查看") }

    public var approvalsSection: String { pick("Approvals", "权限确认") }
    public var answerPrompts: String { pick("Answer permission prompts in the island", "在岛上回答权限确认") }
    public var approvalsNote: String {
        pick("Adds two hooks to ~/.claude/settings.json, both pointing at the helper inside this app: one runs where a permission prompt is about to appear, the other catches the questions and plans no permission event fires for. Turning it off takes both back out. With Roost closed, or no answer within a minute, sessions prompt exactly as they do now.",
             "会往 ~/.claude/settings.json 里加两条 hook，都指向本应用内的 helper：一条在权限提示将要出现的地方运行，另一条接住提问和方案——它们不会触发任何权限事件。关掉它就把两条都去掉。Roost 没开着、或者一分钟内没人回答，会话照旧自己弹提示。")
    }

    public var agentsSection: String { pick("Agents", "智能体") }
    public func watchAgent(_ agent: AgentKind) -> String {
        pick("Watch \(agent.label) sessions too", "同时监视 \(agent.label) 会话")
    }
    public var codexNote: String {
        pick("Adds Roost's helper to ~/.codex/hooks.json, the way the approvals switch adds it to Claude Code's settings. Codex writes no registry of live sessions, so its rows are built from the events it announces, and its permission prompts are answered on the same card. Turning it off takes every entry back out.",
             "会往 ~/.codex/hooks.json 里加上 Roost 的 helper，和权限确认那个开关往 Claude Code 设置里加的是同一回事。Codex 不写活动会话清单，所以它的行由它主动上报的事件拼出来，权限提示也在同一张卡片上回答。关掉就把所有记录去掉。")
    }

    public var soundSection: String { pick("Sound", "声音") }
    public var playSounds: String { pick("Say it out loud", "用声音提示") }
    public var soundsNote: String {
        pick("Two synthesised chirps, no files: rising when a session stops on something only you can answer, falling when a turn ends. Nothing is said for the fleet already running when Roost opens.",
             "两声合成音，不用音频文件：会话停在只有你能回答的事情上时音调上行，一轮结束时下行。Roost 刚打开时已经在跑的会话不会出声。")
    }

    public var usageSection: String { pick("Usage", "用量") }
    public var readStatusLine: String {
        pick("Read the figure from your status line", "从 status line 读用量")
    }
    public var statusLineNote: String {
        pick("Locally, and only while a session is rendering one: the desktop app renders none, and a Mac with nothing running renders none either. Whatever status line you already run keeps running, unchanged, and turning this off puts it back exactly as it was.",
             "只在本机，而且只有会话正在渲染 status line 时才有：桌面 App 不渲染，什么都没跑的 Mac 也不渲染。你原本的 status line 照常运行、输出不变；关掉它就原样还回去。")
    }
    public var checkUsageOnline: String {
        pick("Ask Anthropic what is left", "向 Anthropic 查询剩余用量")
    }
    public var usageOnlineNote: String {
        pick("Besides the update check, the only thing Roost sends anywhere. About once a minute it asks api.anthropic.com for your own account's figures, using the token Claude Code already keeps in your keychain — read, never refreshed and never written back. Nothing about your sessions goes with it. Reading the token raises a keychain prompt the first time, and again after an update.",
             "除了更新检查，这是 Roost 唯一往外发的东西。大约每分钟向 api.anthropic.com 问一次你自己账号的用量，用的是 Claude Code 已经存在钥匙串里的令牌 —— 只读，不刷新、也不写回。会话的任何信息都不会跟着出去。第一次读令牌会弹一次钥匙串授权，更新之后会再弹一次。")
    }

    public var languageSection: String { pick("Language", "语言") }
    public var interfaceLanguage: String { pick("Interface", "界面") }
    public var languageNote: String {
        pick("Follows your Mac's language until you pick one here. The switch lands immediately, everywhere.",
             "在这里选定之前跟随系统语言。切换立刻生效，界面各处同时改变。")
    }

    public func name(of choice: LanguageChoice) -> String {
        switch choice {
        // A language is named in its own language: someone who cannot read the
        // current one still has to find their way out.
        case .system: pick("System", "跟随系统")
        case .english: "English"
        case .chinese: "简体中文"
        }
    }

    // MARK: - Island

    public var nothingNeedsYou: String { pick("Nothing needs you", "没有需要你的事") }
    public var noLiveSessions: String { pick("No live sessions", "没有活着的会话") }
    public func idleCount(_ count: Int) -> String { pick("\(count) idle", "\(count) 个闲置") }
    public func updateAvailable(_ version: String) -> String {
        pick("Roost \(version) available", "Roost \(version) 可更新")
    }

    /// The quota windows, named as short as the footer allows.
    public var fiveHour: String { pick("5h", "5时") }
    public var sevenDay: String { pick("7d", "7天") }
    public func percent(_ used: Double) -> String { "\(Int((used * 100).rounded()))%" }
    public func resetsIn(_ seconds: Int) -> String {
        pick("resets in \(elapsed(seconds))", "\(elapsed(seconds))后重置")
    }

    public func waitingCount(_ count: Int) -> String { pick("\(count) waiting", "\(count) 个等待中") }
    public func runningCount(_ count: Int) -> String { pick("\(count) running", "\(count) 个运行中") }
    public func sessionCount(_ count: Int) -> String {
        pick("\(count) session\(count == 1 ? "" : "s")", "\(count) 个会话")
    }

    // MARK: - Approval card

    public var wantsToRunIn: String { pick("  wants to run in  ", "  请求运行于  ") }
    public var noArguments: String { pick("no arguments", "无参数") }
    public var deny: String { pick("Deny", "拒绝") }
    public var allow: String { pick("Allow", "允许") }

    // MARK: - Question card

    /// Stands in when a question arrives without the short chip Claude Code
    /// usually puts above it.
    public var questionChip: String { pick("Question", "问题") }

    // MARK: - Plan card

    public var planChip: String { pick("Plan", "方案") }
    public var approve: String { pick("Approve", "通过") }
    /// Sends the plan back rather than rejecting the work: the session stays in
    /// plan mode and asks what to change.
    public var revise: String { pick("Revise", "修改") }
    public func moreLines(_ count: Int) -> String {
        pick("+\(count) more line\(count == 1 ? "" : "s")", "还有 \(count) 行")
    }

    // MARK: - Session row

    public var working: String { pick("working", "工作中") }
    public var turnEnded: String { pick("turn ended", "本轮结束") }

    /// What a blocked session is blocked on, in the words the row shows.
    public func label(for reason: BlockReason) -> String {
        switch reason {
        case .permissionPrompt(let tool):
            tool.map { pick("needs permission: \($0)", "需要授权：\($0)") }
                ?? pick("needs permission", "需要授权")
        case .question:
            pick("asked you a question", "问了你一个问题")
        case .planApproval:
            pick("waiting on plan approval", "等你确认方案")
        case .agentNeedsInput(let label):
            label.map { pick("\($0) needs input", "\($0) 需要输入") }
                ?? pick("needs input", "需要输入")
        case .stalledTool(let name):
            pick("stalled on \(name)", "卡在 \(name)")
        }
    }

    /// How long, in as few characters as the 34 pt column allows.
    public func elapsed(_ seconds: Int) -> String {
        if seconds < 60 { return pick("<1m", "<1分") }
        let minutes = seconds / 60
        if minutes < 60 { return pick("\(minutes)m", "\(minutes)分") }
        let hours = minutes / 60
        guard hours < 24 else { return pick("\(hours / 24)d", "\(hours / 24)天") }
        let rest = minutes % 60
        guard rest > 0 else { return pick("\(hours)h", "\(hours)时") }
        let padded = String(format: "%02d", rest)
        return pick("\(hours)h\(padded)m", "\(hours)时\(padded)分")
    }
}
