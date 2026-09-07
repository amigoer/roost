<div align="center">

<img src="docs/icon.png" width="120" alt="Roost">

# Roost

**Your agent sessions, perched on the notch.**

A macOS menu-bar companion that answers one question from the corner of your eye:
*which of my Claude Code sessions has stopped and is waiting on me?*

<img src="https://img.shields.io/badge/macOS-14%2B-1c1206?style=flat-square" alt="macOS 14+">
<img src="https://img.shields.io/badge/Swift-6.0-FF9F0A?style=flat-square" alt="Swift 6.0">
<img src="https://img.shields.io/badge/UI-SwiftUI%20%2B%20AppKit-8E8E93?style=flat-square" alt="SwiftUI + AppKit">
<img src="https://img.shields.io/badge/read--only-no%20hooks%2C%20no%20network-30D158?style=flat-square" alt="Read-only">
<img src="https://img.shields.io/badge/license-MIT-64D2FF?style=flat-square" alt="MIT License">

**English** · [简体中文](README.zh-CN.md)

</div>

---

## Why

A long agent session does not fail loudly. It asks a question, raises a permission
prompt, or quietly stalls on a tool — and then waits, in a window you tabbed away
from twenty minutes ago. The cost is not the failure; it is the twenty minutes.

Roost keeps exactly that one fact where you already look: the notch. Nothing is
happening? The notch stays the notch. Something needs you? It grows.

## The chick

One mascot, six faces, on a 15×12 pixel grid. The body is brand orange in every
live state and grey only when idle, so hue is always identity — never urgency.
State is carried by the eyes and by a badge in the top-right corner.

| | State | Badge | What it means |
|:--:|:--|:--:|:--|
| <img src="docs/mascot/running.png" width="52"> | `running` | — | Producing output or running a tool. Hops one pixel, once per second. |
| <img src="docs/mascot/waiting.png" width="52"> | `waiting` | amber **?** | Stopped on something only you can answer: a question, a plan, a permission prompt. |
| <img src="docs/mascot/stalled.png" width="52"> | `stalled` | red **!** | A tool call has been outstanding past the grace period. |
| <img src="docs/mascot/done.png" width="52"> | `done` | green **✓** | The turn ended. Nothing is burning. |
| <img src="docs/mascot/error.png" width="52"> | `error` | red **✕** | Something failed. |
| <img src="docs/mascot/idle.png" width="52"> | `idle` | grey **z** | Left alone long enough to be clutter. Folded into a single footer line. |

The same mark appears in three places and never disagrees with itself: the menu
bar item, the collapsed island, and every row of the expanded list.

## How it reads state

No hooks to install, no daemon, no network. Roost only reads files you already
have:

| Source | Used for |
|:--|:--|
| `~/.claude/sessions/*.json` | Which sessions are live. A registry file outlives its process, so each PID is confirmed against the kernel's own process start time. |
| `~/.claude/projects/**/<id>.jsonl` | The last 256 KB of the transcript: the dangling tool call, the last stop reason, the last semantic timestamp. |
| `~/Library/Application Support/Claude/claude-code-sessions/local_*.json` | Human titles, when the session came from the desktop app. |

Nothing is written to the transcript at the moment a prompt appears, so a
dangling tool call plus elapsed time is the only evidence available:

- `AskUserQuestion` and `ExitPlanMode` are, by definition, waiting on a person —
  they count as blocked the instant they are seen.
- Every other tool gets a **45 second** grace period first, because a long build
  is not a blocked session.
- Transcripts are parsed only when the file's modification date changes; state is
  re-derived from cached facts every tick, so a tool crossing the grace line is
  noticed without re-reading anything.

Sessions that have been `done` for **30 minutes** stop being listed and collapse
into an `N idle` footer.

## Escalation

While something is blocked, the island widens on a timer — 60 s, then 300 s. The
badge blinks at one fixed rate throughout, because animation *frequency* is what
disrupts a primary task; width is what peripheral vision actually picks up.

## Design rules

The code enforces these, and the comments say so:

1. **Only blocked grows.** A change of shape at the notch carries exactly one
   meaning and never has to be interpreted.
2. **Hue is identity.** The body never changes colour to signal urgency.
3. **Nothing is drawn in the cutout.** The camera's rectangle is reserved, always.
4. **Clicks meant for the menu bar are never swallowed.** The panel ignores mouse
   events entirely; hover and clicks come from a global monitor against a hit rect.
5. **Frames are free.** All motion is Core Animation on the render server. A
   `repeatForever` SwiftUI animation re-evaluates the view tree every frame and
   measured at 13–16 % CPU sustained, which an always-on app cannot spend.

## Interaction

- **Hover** the notch to expand the list (up to 6 rows).
- **Click a blocked row** to jump to the session that has waited longest.
- **Click any other row** to raise the desktop app.
- Displays without a notch get a 185 pt stand-in strip, centred where a notch
  would be.

## Build

Requires macOS 14+, Xcode 16 (Swift 6) and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project Roost.xcodeproj -scheme Roost -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/Roost.app
```

Roost is an accessory app: no Dock icon, no window, just the menu bar item and
the island. Quit it from the menu bar.

Run the core tests with:

```bash
swift test --package-path Packages/RoostCore
```

## Layout

```
Sources/RoostApp/
  Notch/       Overlay panel, cutout geometry, global hover monitor
  UI/          Island shape, collapsed strip, session rows, mascot art
  Resources/   App icon, generated from the same pixel grid
Packages/RoostCore/
  Session, SessionState, Escalation, NotchMetrics    pure model
  SessionRegistry, SessionScanner, TranscriptReader  detection, tested
```

`RoostCore` is deliberately free of AppKit so the detection and geometry can be
unit tested without a screen.

## Development

The menu bar item carries a debug menu that forces any state — dormant, running,
done, waiting, stalled, error, and the escalated variants — so the visual design
can be judged without waiting for a real session to produce it.

## Status

Early. It runs, it detects, it has not been packaged or signed for distribution.

## License

[MIT](LICENSE)
