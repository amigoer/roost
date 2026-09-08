<div align="center">

<img src="docs/icon.png" width="120" alt="Roost">

# Roost

**让你的 agent 会话，栖在刘海上。**

一个 macOS 菜单栏小工具，只用余光就能回答一个问题：
*我的哪个 Claude Code 会话停下来了，正在等我？*

<img src="https://img.shields.io/badge/macOS-14%2B-1c1206?style=flat-square" alt="macOS 14+">
<img src="https://img.shields.io/badge/Swift-6.0-FF9F0A?style=flat-square" alt="Swift 6.0">
<img src="https://img.shields.io/badge/UI-SwiftUI%20%2B%20AppKit-8E8E93?style=flat-square" alt="SwiftUI + AppKit">
<img src="https://img.shields.io/badge/%E4%BC%9A%E8%AF%9D%E6%95%B0%E6%8D%AE-%E4%B8%8D%E7%A6%BB%E5%BC%80%E4%BD%A0%E7%9A%84%20Mac-30D158?style=flat-square" alt="会话数据不离开你的 Mac">
<img src="https://img.shields.io/badge/license-MIT-64D2FF?style=flat-square" alt="MIT License">
<a href="https://linux.do/u/amigoer"><img src="https://img.shields.io/badge/linux.do-%40amigoer-1c1206?style=flat-square&logo=discourse&logoColor=white" alt="linux.do @amigoer"></a>

[English](README.md) · **简体中文**

</div>

<img src="docs/panel.png" alt="展开后的岛：五个会话，各自在做什么、做了多久">

---

## 为什么做它

长会话不会大声地失败。它问你一个问题、弹一次权限确认，或者悄悄卡在某个工具上，
然后就一直等着——等在那个你二十分钟前切走的窗口里。真正的代价不是那次中断，
是那二十分钟。

Roost 把这一件事放在你本来就会看的地方：刘海。没事发生时，刘海还是刘海；
有事要你处理时，它会长出来。

## 这只小鸡

一只吉祥物，六个表情，画在 15×12 的像素网格上。身体穿的是状态色——不用读任何图形，
一眼就知道**现在是什么情况**；轮廓和那只橙色的喙负责身份。眼神和右上角的像素徽标
说明具体是哪一种状态。

| | 状态 | 徽标 | 含义 |
|:--:|:--|:--:|:--|
| <img src="docs/mascot/running.png" width="52"> | `running` 运行中 | 蓝色，无徽标 | 正在输出或跑工具。冷色后退——干着活恰恰是你最不用操心的事。每秒跳一格像素。 |
| <img src="docs/mascot/waiting.png" width="52"> | `waiting` 等待回复 | 橙色 **?** | 停在只有你能回答的地方：提问、计划确认、权限弹窗。品牌橙只花在这一种状态上。 |
| <img src="docs/mascot/stalled.png" width="52"> | `stalled` 阻塞 | 红色 **!** | 一个工具调用超过宽限期还没回来。 |
| <img src="docs/mascot/done.png" width="52"> | `done` 已完成 | 绿色 **✓** | 这一轮结束了，没有什么在烧。 |
| <img src="docs/mascot/error.png" width="52"> | `error` 出错 | 红色 **✕** | 出问题了。 |
| <img src="docs/mascot/idle.png" width="52"> | `idle` 空闲 | 灰色 **z** | 放着太久已经算杂音，收进底部一行。 |

同一个标记出现在收起的岛和展开列表的每一行，两处永远一致。**菜单栏里刻意没有图标**
——上面再多一个图标，正是这个应用想要消灭的杂音。

## 一行里有什么

```
✳  perch · SVG 素材实现                          🐤  3m
   asked you a question
```

| 部件 | 说明 |
|:--|:--|
| Agent 标记 | 这是谁的会话。目前只有一种，位置先留着。 |
| `项目 · 标题` | 先是哪个仓库，再是哪个会话。"关不关我事"这个问题，仓库名回答得更快。 |
| 第二行 | 它**此刻**在干什么：工具名，加上一个人能看懂的参数——命令、文件、匹配模式，直接从转录里取。阻塞的行改成说明为什么停了。 |
| 模型 | 这个会话跑的是哪个模型，取自桌面端自己的会话记录。 |
| 吉祥物 | 状态，以及说明是哪一类停顿的徽标。 |
| 时长 | 阻塞的行数的是卡了多久；其余的数的是距离上次有动静多久——放久了的会话一眼就能认出来。 |

## 在刘海里直接批准

权限确认不用切走就能答。Roost 装一个 `PreToolUse` hook：Claude Code 把这次工具调用
按住，hook 去问 Roost，岛上就出现这次调用和 **Deny** / **Allow** 两个按钮。

<img src="docs/approval.png" alt="被按住的 Bash 调用，右侧是 Deny 和 Allow">

在设置里打开——*Answer permission prompts in the island*。它往
`~/.claude/settings.json` 里加一条指向 app 包内 `roost-hook` 的记录；同一个开关
关掉就删除，别人的 hook 一个都不动。

失败路径故意做得很无聊：Roost 没在跑、socket 不在、60 秒没人答——hook 什么都不输出，
会话就按它原来的方式弹窗。它可以让一次工具调用多等一会儿，但改不了这次调用的结果。

| 工具 | 会被按住吗 |
|:--|:--|
| `Read`、`Grep`、`Glob`、`TodoWrite` 等 | 从不。在 hook 里就滤掉了，常规路径不付任何跨进程代价。 |
| `Bash`、`WebFetch`、`mcp__*` 及其余 | 会——除非会话跑在 `bypassPermissions` 或 `plan` 模式下。 |
| `Write`、`Edit`、`MultiEdit`、`NotebookEdit` | 只在 `default` 模式下按住。accept-edits 的会话早就答过了。 |

岛本身是穿透的，所以按钮在两边都是几何：卡片按照命中测试读的同一组常量排版。
这个映射[有测试](Packages/RoostCore/Tests/RoostCoreTests/ApprovalTests.swift)保着，
因为点错卡片的哪一半，就等于答错了问题。

## 它怎么判断状态

没有常驻守护进程，不需要账号，不上报任何东西。Roost 只读你本来就有的文件：

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

Roost 唯一发出的请求是每 6 小时向 GitHub 的 releases API 查一次有没有新版本，
除了请求本身不带任何信息。有新版时齿轮上出现一个点、底部多一行提示；
安装仍然是手动的——ad-hoc 签名的包没有值得校验的签名，不该自己覆盖自己。
不想要的话在菜单里关掉 *Check automatically*。

## 升级策略

有会话阻塞时，岛会按 60 秒、300 秒两档变宽。徽标的闪烁频率全程不变——
因为真正打断主任务的是动画*频率*，而余光能捕捉到的是宽度。

## 设计约束

这些约束写在代码里，注释里也说明了原因：

1. **只有阻塞才会变大。** 刘海形状的改变只承载一个含义，永远不需要被解读。
2. **颜色表示状态，轮廓表示身份。** 一个状态一种颜色，同一状态内部不会再用颜色
   分级；保持不变的是像素轮廓和那只橙色的喙。
3. **绝不在挖孔区域作画。** 摄像头那块矩形永远留空。
4. **绝不吞掉本该给菜单栏的点击。** 面板完全忽略鼠标事件，悬停和点击来自
   全局监听器对命中矩形的判断。
5. **帧是免费的。** 所有动效都是跑在渲染服务上的 Core Animation。SwiftUI 的
   `repeatForever` 会每帧重算视图树，实测持续占用 13–16% CPU，常驻应用付不起。

## 交互

- **悬停**刘海展开列表（最多 6 行）。
- **点击任意一行**把桌面端窗口拉到前面。它**还做不到**定位到具体那次对话——这是
  现状，不是设计选择。进桌面端一共三条路由：`code/continue` 和 `code/needs-input`
  吃的是应用自己的 `local_` id，挂着账号级 gate，只会在日志里写
  `code entry deep link gated off`；第三条 `claude://resume` 是"重开一次**已经结束**
  的对话"，对着正在运行的会话发，它会**再起一个进程**去接管同一份转录，而这里列出
  的每一个会话都在运行。
- **点 Deny 或 Allow** 回答被按住的工具调用。有卡片在等的时候岛会自己保持展开，
  不需要鼠标一直停在那儿。
- **点面板右上角的齿轮**打开设置。右键点击刘海给的是同一个窗口外加"退出"——
  岛收起、没东西可点的时候用这个。
- 没有刘海的显示器会得到一条 185 pt 的替代条，位置就在刘海本该在的地方。

## 设置

<img src="docs/settings.png" width="460" alt="设置窗口">

真正需要你做选择的两件事在这里：要不要检查更新、要不要在岛上回答权限确认。
**退出也在这里**——accessory 应用没有 Dock 图标可以退。

这里没有任何东西可以设置岛的状态。状态是从会话实际在做什么推导出来的，
一个能覆盖它的开关只会撒谎。

## 安装

从 [Releases](https://github.com/amigoer/roost/releases) 下载 DMG，把 Roost 拖进
Applications。构建是 ad-hoc 签名而非公证过的，所以 macOS 会拦第一次启动——右键
选"打开"，或者：

```bash
xattr -dr com.apple.quarantine /Applications/Roost.app
```

需要 macOS 14 或更高版本。

## 构建

需要 macOS 14+、Xcode 16（Swift 6）和 [XcodeGen](https://github.com/yonaskolb/XcodeGen)。

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project Roost.xcodeproj -scheme Roost -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/Roost.app
```

Roost 是 accessory 应用：没有 Dock 图标，没有窗口，菜单栏里也没有图标——只有那个岛。
退出请右键点击刘海。

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

## 项目状态

早期阶段。能跑、能检测，但还没有做分发打包和签名。

## 许可证

[MIT](LICENSE)
