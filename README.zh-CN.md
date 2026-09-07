<div align="center">

<img src="docs/icon.png" width="120" alt="Roost">

# Roost

**让你的 agent 会话，栖在刘海上。**

一个 macOS 菜单栏小工具，只用余光就能回答一个问题：
*我的哪个 Claude Code 会话停下来了，正在等我？*

<img src="https://img.shields.io/badge/macOS-14%2B-1c1206?style=flat-square" alt="macOS 14+">
<img src="https://img.shields.io/badge/Swift-6.0-FF9F0A?style=flat-square" alt="Swift 6.0">
<img src="https://img.shields.io/badge/UI-SwiftUI%20%2B%20AppKit-8E8E93?style=flat-square" alt="SwiftUI + AppKit">
<img src="https://img.shields.io/badge/%E5%8F%AA%E8%AF%BB-%E6%97%A0%20hook%20%C2%B7%20%E6%97%A0%E7%BD%91%E7%BB%9C-30D158?style=flat-square" alt="只读">
<img src="https://img.shields.io/badge/license-MIT-64D2FF?style=flat-square" alt="MIT License">
<a href="https://linux.do/u/amigoer"><img src="https://img.shields.io/badge/linux.do-%40amigoer-1c1206?style=flat-square&logo=discourse&logoColor=white" alt="linux.do @amigoer"></a>

[English](README.md) · **简体中文**

</div>

---

## 为什么做它

长会话不会大声地失败。它问你一个问题、弹一次权限确认，或者悄悄卡在某个工具上，
然后就一直等着——等在那个你二十分钟前切走的窗口里。真正的代价不是那次中断，
是那二十分钟。

Roost 把这一件事放在你本来就会看的地方：刘海。没事发生时，刘海还是刘海；
有事要你处理时，它会长出来。

## 这只小鸡

一只吉祥物，六个表情，画在 15×12 的像素网格上。身体在所有活跃状态下恒定为品牌橙，
只有空闲时转灰——所以颜色永远表示身份，而不是紧急程度。状态由眼神和右上角的
像素徽标承载。

| | 状态 | 徽标 | 含义 |
|:--:|:--|:--:|:--|
| <img src="docs/mascot/running.png" width="52"> | `running` 运行中 | — | 正在输出或跑工具。每秒跳一格像素。 |
| <img src="docs/mascot/waiting.png" width="52"> | `waiting` 等待回复 | 橙色 **?** | 停在只有你能回答的地方：提问、计划确认、权限弹窗。 |
| <img src="docs/mascot/stalled.png" width="52"> | `stalled` 阻塞 | 红色 **!** | 一个工具调用超过宽限期还没回来。 |
| <img src="docs/mascot/done.png" width="52"> | `done` 已完成 | 绿色 **✓** | 这一轮结束了，没有什么在烧。 |
| <img src="docs/mascot/error.png" width="52"> | `error` 出错 | 红色 **✕** | 出问题了。 |
| <img src="docs/mascot/idle.png" width="52"> | `idle` 空闲 | 灰色 **z** | 放着太久已经算杂音，收进底部一行。 |

同一个标记出现在三个位置且永远互相一致：菜单栏图标、收起的岛、展开列表的每一行。

## 它怎么判断状态

不用装 hook，没有常驻守护进程，不联网。Roost 只读你本来就有的文件：

| 来源 | 用途 |
|:--|:--|
| `~/.claude/sessions/*.json` | 哪些会话还活着。注册文件会比进程活得久，所以每个 PID 都要和内核记录的进程启动时间对上才算数。 |
| `~/.claude/projects/**/<id>.jsonl` | 转录文件末尾 256 KB：悬空的工具调用、最后的 stop reason、最后一条语义时间戳。 |
| `~/Library/Application Support/Claude/claude-code-sessions/local_*.json` | 会话标题，桌面端发起的会话才有。 |

权限弹窗出现的那一刻，转录里什么都不会写，所以“悬空的工具调用 + 已等待时长”
是唯一可用的证据：

- `AskUserQuestion` 和 `ExitPlanMode` 按定义就是在等人，一看见就直接算阻塞。
- 其他工具先给 **45 秒**宽限期——一次慢编译不等于一个卡住的会话。
- 只有文件修改时间变了才重新解析转录；状态每一拍都从缓存的事实重新推导，
  所以工具跨过宽限线这件事不需要重读任何文件就能发现。

`done` 状态超过 **30 分钟**的会话不再单独列出，折叠成底部的 `N idle` 一行。

## 升级策略

有会话阻塞时，岛会按 60 秒、300 秒两档变宽。徽标的闪烁频率全程不变——
因为真正打断主任务的是动画*频率*，而余光能捕捉到的是宽度。

## 设计约束

这些约束写在代码里，注释里也说明了原因：

1. **只有阻塞才会变大。** 刘海形状的改变只承载一个含义，永远不需要被解读。
2. **颜色表示身份。** 身体不会为了表达紧急而改色。
3. **绝不在挖孔区域作画。** 摄像头那块矩形永远留空。
4. **绝不吞掉本该给菜单栏的点击。** 面板完全忽略鼠标事件，悬停和点击来自
   全局监听器对命中矩形的判断。
5. **帧是免费的。** 所有动效都是跑在渲染服务上的 Core Animation。SwiftUI 的
   `repeatForever` 会每帧重算视图树，实测持续占用 13–16% CPU，常驻应用付不起。

## 交互

- **悬停**刘海展开列表（最多 6 行）。
- **点击阻塞行**跳到等待最久的那个会话。
- **点击其他行**唤起桌面端。
- 没有刘海的显示器会得到一条 185 pt 的替代条，位置就在刘海本该在的地方。

## 构建

需要 macOS 14+、Xcode 16（Swift 6）和 [XcodeGen](https://github.com/yonaskolb/XcodeGen)。

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project Roost.xcodeproj -scheme Roost -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/Roost.app
```

Roost 是 accessory 应用：没有 Dock 图标，没有窗口，只有菜单栏图标和那个岛。
退出请走菜单栏。

跑核心测试：

```bash
swift test --package-path Packages/RoostCore
```

## 目录结构

```
Sources/RoostApp/
  Notch/       覆盖面板、挖孔几何、全局悬停监听
  UI/          岛形状、收起条、会话行、吉祥物美术
  Resources/   App 图标，由同一份像素网格生成
Packages/RoostCore/
  Session、SessionState、Escalation、NotchMetrics     纯模型
  SessionRegistry、SessionScanner、TranscriptReader   检测逻辑，带测试
```

`RoostCore` 刻意不依赖 AppKit，这样检测和几何计算不需要屏幕就能做单元测试。

## 开发

菜单栏图标带一个调试菜单，可以强制切到任意状态——dormant、running、done、
waiting、stalled、error 以及升级后的变体——这样不必等真实会话出现就能判断视觉效果。

## 项目状态

早期阶段。能跑、能检测，但还没有做分发打包和签名。

## 许可证

[MIT](LICENSE)
