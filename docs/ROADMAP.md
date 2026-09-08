# Roadmap

What Roost would have to grow to cover the feature set of a full commercial
notch companion — many agents, precise terminal jump, notifications off the
Mac, a real install story. Written as a checklist so it can be worked through
rather than admired.

Three kinds of entry:

- `[ ]` — work, with the files it lands in named.
- `[?]` — a **spike**: something to find out before it can be estimated. Every
  claim in this document that starts with "probably" is one of these.
- `[!]` — a **decision** that is not an engineering call. Nothing under it
  should be built until it is answered.

Ordering inside a section is dependency order. Ordering between sections is
not; see [Milestones](#milestones).

## Where Roost is today

| Capability | State |
|:--|:--|
| Answer permission prompts from the island | done — `PermissionRequest` hook, `Approval.swift`, `ApprovalCard.swift` |
| Answer questions and approve plans | done — `PreToolUse` on `AskUserQuestion` / `ExitPlanMode` |
| Nothing leaves the machine | done — one update check against GitHub every six hours, nothing else |
| Agents | 2 of 26 — Claude Code, Codex (`AgentKind.swift`) |
| Click a row to reach the session | app-level only — `SessionActivator` raises the owning application, no tab or pane |
| Usage windows | 5-hour and 7-day, Claude Code only — `Usage.swift`, `StatusLineInstall.swift` |
| Displays without a notch | 185 pt stand-in strip — `NSScreen+Notch.swift` |
| Two languages | done, switchable at runtime — `Strings.swift` |
| Install | ad-hoc signed DMG, manual quarantine clearing |

Everything below is what is missing from that table.

## One thing that is not a roadmap item

**Fixed.** `HookInstall.read` returned `[:]` both when a settings file was
absent and when it existed but did not parse, and every caller in `RoostModel`
wrote that result straight back. A `~/.claude/settings.json` with a comment in
it — or a missing comma, or a write cut half way — was therefore replaced by one
holding nothing but Roost's two hooks, taking the user's permissions, env and
MCP servers with it. (Not a trailing comma: `JSONSerialization` accepts those.)

`read` now returns `absent` / `parsed` / `unreadable`, only the first two can be
built on, and Settings names the file and disables the switch rather than
failing silently. Worth remembering while working through section 1: more
agents means more files to be wrong about.

---

## 1. Agents: from two to twenty-six

The target list, as a comparable product states it: Claude Code, Codex, ZCode,
Gemini CLI, Antigravity CLI, Cursor, Trae, OpenCode, MiMoCode, Droid, Qoder,
Qwen, Grok Build, Kimi Code, DeepSeek, Mistral Vibe, Copilot, CodeBuddy,
WorkBuddy, Kiro, Hermes, Amp, Pi Agent, Oh My Pi, Gajae Code, Kimi.

`AgentKind` is an enum with two cases and four hard-wired switches. Twenty-six
cases in that shape is twenty-six places to forget one. The shape has to change
before the list grows.

### 1.1 Make an agent data rather than a case

- [ ] Introduce `AgentDescriptor` in `RoostCore`: id, label, mark, config
      directory, hooks file, hook schema flavour, decision wire format,
      transcript layout, registry layout.
- [ ] Give it **capability flags** — `holdsPermissions`, `hasQuestions`,
      `hasPlanMode`, `hasRegistry`, `hasTranscript`, `reportsUsage` — and make
      every call site ask the flag instead of matching on the agent. The three
      switches in `AgentKind.swift` and the `session.agent == .claudeCode`
      guard in `SessionActivator.swift:38` are the ones that exist today.
- [ ] Load descriptors from a bundled JSON catalogue, so adding an agent that
      speaks a known protocol is a data change with a fixture, not a build.
- [ ] Keep `AgentKind` as a thin façade over the catalogue during the
      migration; the tests in `AgentTests.swift` are the safety net.
- [ ] `SessionScanner` currently reads one registry (`SessionRegistry.swift`).
      Make it fan out over every descriptor that has one, and keep the
      per-transcript modification-date cache per agent — N agents must not mean
      N times the disk reads on an idle machine.

### 1.2 Find out what each of the twenty-four actually exposes

Nothing here is knowable from the name. Each one falls into one of four tiers,
and the tier decides whether it can be answered from the island or only
watched. One spike per agent, each answering the same five questions:

1. Where is its config, and does it have a `hooks` block?
2. Does anything fire *before* a tool call, and can that call be held?
3. Does it write a registry of live sessions?
4. Does it write a transcript, and does the transcript say what is happening now?
5. What does a decision have to look like on the way back?

| Tier | Means | What Roost can show |
|:--|:--|:--|
| **A** | Speaks the Claude Code hook protocol (a fork, or close enough) | Everything: rows, state, held calls answered from the island |
| **B** | Writes a readable registry or transcript, no hooks | Rows and state, no answering |
| **C** | A GUI IDE with its own windows, not a CLI session | Open question — see [decisions](#decisions) |
| **D** | Nothing but a running process | Presence and elapsed time, little else |

- [?] Tier the twenty-four. Expect most Chinese-market CLIs (ZCode, Kimi Code,
      MiMoCode, Qwen, DeepSeek, CodeBuddy, WorkBuddy, Gajae Code, Oh My Pi) to
      be Claude Code forks reading `~/.<name>/settings.json` — if so they are
      one catalogue entry each and tier A comes almost free. **Verify before
      counting on it.**
- [?] Gemini CLI, OpenCode, Amp, Droid, Qoder, Hermes, Pi Agent, Mistral Vibe,
      Grok Build — own protocols. Tier B at best until proven otherwise.
- [?] Cursor, Trae, Kiro, Antigravity, Copilot are IDEs. They already have a
      window; the thing that blocks is a panel inside it. Whether the island
      has anything to add there is a product question, not a parsing one.
- [ ] Write the tiering up as `docs/agents.md`, one row per agent with its
      config path and evidence. That file is what the catalogue is generated
      against, and what stops the next person re-doing the same reading.

### 1.3 The interface, at twenty-six

- [ ] Marks. `AgentMark.swift` hand-draws each agent on an 11×11 pixel grid.
      That does not scale to twenty-six and should not try: keep drawn marks
      for the handful that are actually recognisable at 16 pt, and add a
      letterform fallback in the same pixel idiom for the rest.
- [ ] Settings. One switch per agent is a wall — `SettingsWindow.swift` is
      already 640 pt tall and scrolling. Replace the *Agents* section with a
      list of **detected** agents (config directory exists) and their wiring
      state, with undetected ones behind a disclosure.
- [ ] Detection has to be cheap and re-run when an agent is installed while
      Roost is running.
- [ ] `HookInstall.adding(agent:command:to:)` already installs whole agents.
      Confirm the sweep in `removing(command:from:)` still takes every entry
      back out when the file holds several agents' worth.
- [ ] Fixtures and a round-trip test per tier-A agent, mirroring `AgentTests`.

---

## 2. Precise terminal jump

Today `SessionActivator` climbs the process tree and raises the first ancestor
macOS considers a regular application. That is the right *default* — it needs
no list of terminal names — but it lands on the app, not on the tab, the split
or the tmux window. The target is: precise for iTerm2, Ghostty, Terminal.app,
Warp, WezTerm, Kitty, Zellij and IDE terminals; app activation with best-effort
tab matching for Alacritty, Hyper, Zed, Termius, cmux, Conductor.

### 2.1 The thing to match on

- [ ] Read the session's controlling terminal. `kinfo_proc.kp_eproc.e_tdev`
      gives the tty device number; `devname(3)` turns it into `/dev/ttys004`.
      `ProcessTree.swift` already does the sysctl and is the place for it.
- [ ] Add `TerminalTarget` to `RoostCore`: `(app, window, tab, pane)`, resolved
      from the tty plus the process chain. Pure, so it can be tested against
      recorded adapter output without a screen.
- [ ] Insert a resolution step in `SessionActivator` between the process tree
      and `activate(options:)`, with a strict fallback ladder — precise → tab
      match → app raise → nothing. **No path may be worse than today's.**

### 2.2 tmux and Zellij first

They come before the terminals, because a session inside tmux has the tty of a
tmux pane, and every terminal adapter below would otherwise match nothing.

- [ ] tmux: `tmux list-panes -a -F '#{pane_tty} #{session_name} #{window_index} #{pane_index}'`,
      match the tty, then `select-window` + `select-pane` + `switch-client`.
      Then resolve the *client's* tty and hand that to the terminal adapter —
      two hops, and the second is the ordinary case.
- [ ] Zellij: `zellij action go-to-tab-name`, same two-hop shape.

### 2.3 One adapter per terminal

Each is small and independent; each needs a spike first because the scripting
surface is what it is, not what would be convenient.

- [ ] iTerm2 — AppleScript, sessions carry `tty`. Best-documented of the set.
- [ ] Terminal.app — AppleScript, `tty of tab`.
- [ ] WezTerm — `wezterm cli list --format json` gives pane ids and ttys,
      `wezterm cli activate-pane --pane-id`. No AppleScript needed.
- [ ] Kitty — `kitty @ ls` then `kitty @ focus-window`, but only if the user
      has `allow_remote_control` on. Detect and say so rather than failing mute.
- [?] Ghostty — check what scripting surface exists in the current release.
- [?] Warp — check for a URL scheme or AppleScript dictionary.
- [?] VS Code / Cursor / Windsurf / Antigravity — probably window-title
      matching plus `code --reuse-window`; there is no terminal-tab API.
- [ ] Everything else — app raise, unchanged. That is already the behaviour, so
      this costs nothing but a catalogue row.

### 2.4 The part that will actually hurt

- [!] Driving another app by AppleScript needs Apple Events consent, one TCC
      prompt per target app, and a hardened-runtime entitlement
      (`com.apple.security.automation.apple-events`). A tool that asks for
      permission to control your terminal is a different-feeling tool than one
      that does not. Decide whether precise jump is opt-in per terminal.
- [ ] Whatever is decided: ask at the moment of the first jump, not at launch,
      and fall back to the app raise silently when refused.
- [ ] Shelling out to `wezterm` / `kitty` / `tmux` needs their paths resolved
      without a login shell. Do not inherit `PATH`; look in the usual places
      and cache.

---

## 3. Reaching you away from the Mac

- [!] "Nothing leaves your machine" is currently true and is stated on the
      badge in the readme. Anything that reaches a phone breaks it for whoever
      turns it on. The honest version: default off, the endpoint is the user's
      own, and the readme says exactly what is sent. Decide before building.
- [ ] Notification Center posts for `waiting` and `stalled`, mirroring the
      chirps in `Chirp.swift` — same debounce, same "first snapshot after
      launch says nothing" rule.
- [ ] A generic webhook (ntfy, Pushover, Bark, Gotify are all one POST) with a
      user-supplied URL. One code path, no accounts, no server of ours.
- [ ] Rate limiting, because a blocked session escalates and nobody wants three
      pushes about one prompt.

---

## 4. Usage and limits

`Usage.swift` and `StatusLineInstall.swift` cover Claude Code's 5-hour and
7-day windows by standing in the status line path.

- [?] Does Codex expose the same figures anywhere a wrapper can stand?
- [ ] Per-agent usage behind the `reportsUsage` capability flag, rather than
      the current single account-wide reading.
- [ ] Token and cost totals read from the transcripts Roost already parses —
      the same ground `ccusage` covers, at no extra IO, since
      `TranscriptReader` is already reading those files.
- [ ] A place to show it. The footer holds two bars; a fleet-wide breakdown
      needs somewhere else, and that somewhere is not the notch.

---

## 5. First run

Zero-config means the first launch already knows what is installed.

- [ ] Detect installed agents on first run, show what was found, offer to wire
      hooks for all of them in one action.
- [x] Refuse to write over a settings file that does not parse, and say which
      file it is — see the note at the top.
- [ ] `roost-hook --doctor`: prints what is wired, what is stale, whether the
      socket answers. One command to paste into an issue.

---

## 6. Distribution

- [!] Developer ID signing and notarisation need a paid Apple Developer
      account. Everything in this section depends on that one decision.
- [ ] Sign and notarise in `scripts/package-dmg.sh`, which removes the
      quarantine paragraph from the readme and from every release note.
- [ ] Homebrew cask. Trivial once notarised, ugly before.
- [ ] Sparkle for in-place updates — only meaningful with a real signature,
      which is why `UpdateCheck.swift` deliberately stops at a link today.

---

## 7. Footprint

The claim to be able to make is "native, under 100 MB, invisible when idle".
It is close to true now and the risk is section 1: twenty-six agents means
twenty-six registries and many more transcripts.

- [ ] A measurement script — RSS and idle CPU over a fixed session fixture —
      run before each release, with the numbers in the release notes.
- [ ] Cap the per-tick work regardless of agent count: stagger scans, and skip
      agents with no live sessions entirely.

---

## 8. Displays

- [ ] Verify the stand-in strip and the hover rect on an external monitor, in
      clamshell, and across a resolution change while the island is expanded.
- [?] Should the island follow the active screen, or stay on the built-in
      display? Following is what people expect and is more code.

---

## 9. Site and docs

Out of this repository, and worth saying so: a landing page, a docs site, a
comparison page, and the guide pages that answer the questions people actually
search for (notifications, usage, rate limits, cost). None of it is Swift, and
none of it should slow the sections above.

---

## Decisions

Not engineering calls. Each one changes what is built.

- [x] **Licence.** Settled: [PolyForm Noncommercial 1.0.0](../LICENSE), for
      everything after v0.2.0. Free for personal and noncommercial use, and for
      charities, schools, public research and government; use at a company
      needs a separate licence. Two things it does not do. It does not reach
      the releases up to v0.2.0 — those went out under MIT and stay MIT, so
      that code can still be forked and sold by anyone who has it. And it does
      not enforce itself: it is the legal footing for charging, not a
      mechanism. Source-available, not open source, which is why the readme no
      longer says otherwise.
- [!] **Price and the commerce around it.** Still open, and independent of
      everything else in this document. A price, per-Mac seats, a trial build,
      a licence key the app actually checks, a checkout, refunds, an add-a-Mac
      flow, support mail. The reference product does all of it for a one-time
      $14.99 with an affiliate scheme and a creator offer.
- [!] **IDE agents (tier C).** Cursor, Trae, Kiro, Antigravity and Copilot
      already have a window on screen. Does the island have anything to say
      about a panel inside a visible app? A number in a count, perhaps, and not
      much more.
- [!] **Phone notifications** — see section 3.
- [!] **Automation consent** for precise jump — see section 2.4.
- [!] **Notarisation** — see section 6.

---

## Milestones

**v0.2 — the shape.** Section 1.1 alone: `AgentDescriptor`, the capability
flags, the catalogue, the scanner fan-out, with the two existing agents
migrated onto it and every test still green. Nothing user-visible. Everything
after this is cheaper for it.

**v0.3 — the agents.** Sections 1.2 and 1.3. Tier the twenty-four, land every
tier-A agent that turns out to be a fork, ship the detected-agents list in
settings. This is where the headline number moves.

**v0.4 — the jump.** Section 2, in order: tty, then tmux, then iTerm2 and
Terminal.app, then the rest one at a time. Each adapter ships on its own.

**v0.5 — the reach.** Sections 3 and 4: notifications off the Mac, per-agent
usage, cost from transcripts.

**v1.0 — the install.** Section 6, plus 5, 7 and 8. Signed, notarised, in a
cask, with a first run that explains itself and a footprint number that is
measured rather than claimed.
