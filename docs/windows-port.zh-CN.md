# Roost on Windows

移植评估与实施计划。范围限定为**原生 Windows** —— PowerShell、cmd、Windows Terminal
里跑的会话，不含 WSL。

评估基于仓库 v0.2.0 的实测数据：4,872 行代码、164 个测试、hook 冷启动 9.4ms。
标注为推断的部分需要在 Windows 实机上验证。

---

## 结论

去掉 WSL 之后，**只剩一件"大"的事：UI 重写**。其余都是有明确终点的工作 ——
翻译一批纯函数、换四个系统调用、做一个悬浮窗。没有"做到一半发现方向错了"的那种风险。

| | |
|:--|:--|
| 可直接翻译 | 1,892 行纯逻辑，只依赖 Foundation |
| 必须重写 | 2,400 行 AppKit / SwiftUI，无一可留 |
| 平台实现 | 4 个核心文件：进程表、IPC、桌面端路径 |
| hook 预算 | 9.4 毫秒，每次工具调用都要付 |

---

## 一、费不费事

把"重写一遍"当成一件事来估会估错。它其实是三件独立的事，难度差了一个数量级：

| 工作 | 量级 | 为什么 |
|:--|:--|:--|
| 核心逻辑翻译 | 小 | 1,892 行几乎是纯函数：解析 JSONL、状态机、几何计算、字符串表。164 个测试可以直接当规格用 —— 翻译完跑通测试就算对 |
| 悬浮窗本身 | 中 | Win32 有现成能力（分层窗口、置顶、穿透、不抢焦点）。难在多显示器 + 每显示器 DPI，不难在画 |
| UI 与交互 | 大 | 2,400 行。像素吉祥物、六种状态、卡片命中测试、悬停展开动画 —— 全部重做，没有捷径 |

---

## 二、技术选型

Roost 有两个二进制，它们的约束完全相反，所以不该用同一套技术。

### hook：每次工具调用都要付的钱

`PreToolUse` 对每一次工具调用都触发，即使 Roost 立刻放行。当前 Swift 版实测 **9.4ms**
（1.15 MB 原生二进制），这笔开销加在每一条命令上。

| hook 实现 | 冷启动量级 | 结论 |
|:--|:--|:--|
| .NET 框架依赖 exe | 数十毫秒 | **排除** —— 每次调用都感觉得到 |
| .NET NativeAOT | ≈ 原生 | **可行** —— 与 UI 同语言，共用核心代码 |
| Rust / Go / C++ | ≈ 原生 | 可行，但核心逻辑要写两份 |

**选 NativeAOT。** 它让 hook 和 UI 共享同一份核心逻辑，同时拿到原生启动速度 ——
唯一不用把状态机写两遍的组合。上线前务必实测这个数字，别信估计。

### UI：一个透明、置顶、穿透、不抢焦点的窗口

这四条同时满足是选型的唯一标准，其余（好不好看、开发爽不爽）都排在后面。

| 方案 | 四条约束 | 说明 |
|:--|:--|:--|
| **WPF (.NET 8)** | 全满足 | `AllowsTransparency` + `WindowStyle=None` + `Topmost`，再补 `WS_EX_NOACTIVATE` / `WS_EX_TRANSPARENT`。成熟、例子多、矢量渲染适合画像素吉祥物。**推荐** |
| WinUI 3 | 卡在第一条 | 微软当前主推，但逐像素透明窗口恰恰是它最弱的一环。为了"用最新的"在这里挣扎不值得 |
| Win32 + Direct2D | 全满足 | `UpdateLayeredWindow` 是这类工具的经典做法，控制力最强，工作量也最大 |
| Tauri / Electron | 能满足 | 透明置顶都支持，但"不是 Electron"是 Roost 的卖点之一 |
| Avalonia | 能满足 | 唯一顺带给 Linux 的选项，但 Linux 端会撞上 Wayland 的老问题 |

**结论：C# / .NET 8，UI 用 WPF，hook 用 NativeAOT，核心逻辑一份共享。**

---

## 三、模块映射

| 现有文件 | 行 | 处置 | Windows 侧 |
|:--|--:|:--|:--|
| `TranscriptReader` | 199 | 直译 | 纯文件读取 + JSON 解析。路径 `%USERPROFILE%\.claude\projects`，目录名一致 |
| `SessionState` `Session` `Escalation` `Announcer` | 223 | 直译 | 纯状态机与排序，测试可整套搬过去 |
| `Approval` `HookOutput` `HookInstall` `StatusLineInstall` | 493 | 直译 | 协议与 JSON 编辑。hook 事件名、载荷字段、决定形状三平台一致 |
| `Usage` `PlanPreview` `Strings` `Localization` | 357 | 直译 | 解析与文案表，无平台依赖 |
| `Chirp` | 94 | 直译 | 方波合成是纯数学，生成的 WAV 直接喂给 `SoundPlayer` |
| `IslandGeometry` `NotchMetrics` | 241 | 垫片 | 只依赖 CoreGraphics 的 `CGFloat`/`CGSize`，换成 `double` 与自定义结构 |
| `SessionRegistry` | 85 | 平台 | 存活检测：`sysctl(KERN_PROC)` → `OpenProcess` + `GetProcessTimes`。防 pid 复用的启动时间对比要保留 |
| `ProcessTree` | 35 | 平台 | 父进程链：`CreateToolhelp32Snapshot` + `Process32First/Next` 读 `th32ParentProcessID`。**必须额外比对创建时间**，见下 |
| `ApprovalClient` `ApprovalServer` | 241 | 平台 | Unix socket → 命名管道 `\\.\pipe\roost-<sid>`。`chmod 0600` 换成 `PipeSecurity` ACL 限本用户 —— 这条决定谁能批准工具调用，不能省 |
| `DesktopSessions` | 96 | 平台 | 桌面端记录路径换成 Windows 侧位置。会话标题与模型名靠它 |
| `SessionActivator` | 85 | 平台 | 会降级，见下 |
| 整个 UI 层 | 2,400 | 重写 | 像素网格美术可以照搬数据（`PixelChick` 就是字符串数组），绘制代码重写 |

---

## 四、两个硬问题，一个陷阱

### 跳回终端会降级

Windows 刻意限制 `SetForegroundWindow`：非前台进程通常无法把别的窗口提到前面，系统只会闪任务栏图标。
这是 macOS 上一行 `activate()` 就完成的事。

更麻烦的是 **Windows Terminal**：一个进程托管所有标签页，而它没有公开的"激活某个标签页"接口。
所以最好的结果是把终端窗口叫到前面，但停在用户当时在看的那个标签页上。

务实做法：先尝试提前台，失败就 `FlashWindowEx`，并且不要在文案里承诺"精确跳回"。

### SmartScreen 与打包

macOS 上是"右键打开"或清一次 quarantine，一句话说得清。Windows 上未签名的 exe 会触发
SmartScreen 拦截页，而且**声誉需要下载量累积** —— 新证书刚签出来时同样会被拦。

**不要用 MSIX 打包**：它的文件系统虚拟化会挡住读写 `%USERPROFILE%\.claude\settings.json`，
而那正是 Roost 装 hook 的地方。用普通解压即用，或 Inno Setup。

### 陷阱：Windows 的父进程 ID 会说谎

macOS 上父进程死了，子进程会被重挂到 `launchd` 下，父链始终有意义。
**Windows 不重挂**：父进程退出后 `th32ParentProcessID` 仍然留着那个数字，
而这个 pid 可能已经被分配给一个毫不相干的新进程。

顺着这样一条链往上爬，会爬到一个随机进程上，然后把一个无关的窗口叫到前台。
解法和现有代码防 pid 复用的技巧是同一个：**比较创建时间，父进程必须比子进程更早**，
否则这条链到此为止。`SessionRegistry` 里已经有这个思路（`startTimeTolerance`），
移植时要把它同时用到 `ProcessTree` 上 —— 而 macOS 版并不需要。

---

## 五、那条"假刘海"

**这个效果已经实现并且天天在跑。** `NSScreen.signalAnchorRect` 在没有刘海的显示器上
会回退到顶部居中的 185pt 替代条，每一台外接显示器都在走这个分支。
所以视觉与交互设计不用重做，要做的只是窗口。

但有一个 macOS 上不存在的设计决定要拍板：macOS 的刘海贴着菜单栏，那一条本来就是系统的地盘；
Windows 屏幕顶端是应用自己的标题栏，一条黑色悬浮条压在最大化窗口的标题栏上，观感完全不同。

- **贴顶** —— 最接近 macOS 的形态，但会盖住当前应用的标题栏和窗口按钮附近
- **浮起** —— 离顶部留 8–12px 间隙、带圆角和阴影，读作"一个悬浮控件"。**倾向这个**

### 必须处理的窗口细节

- **每显示器 DPI**：声明 `PerMonitorV2`，在 `WM_DPICHANGED` 时重算。混合 DPI 多显示器最容易出 bug
- **每屏一个窗口**：现有架构已经是"每个显示器一座岛"，直接沿用
- **穿透与命中**：现在是"可穿透的视觉面板 + 独立命中面板"两层，Win32 上可沿用，或用 `WM_NCHITTEST` 返回 `HTTRANSPARENT`
- **全屏应用**：独占全屏会盖住置顶窗口，无解，说明清楚即可
- **开机启动**：注册表 `HKCU\...\CurrentVersion\Run`，对应现在的 `SMAppService`

---

## 六、架构：一份还是两份

差别不在这次的工作量，而在之后每加一个 agent、每改一次协议要付几遍。

```
A · 单体重写                          B · 无头内核 + 薄壳

macOS UI      Windows UI              macOS UI  Windows UI  [TUI/Web]
 SwiftUI         WPF                   SwiftUI      WPF      几乎免费
    |             |                        \         |        /
核心逻辑      核心逻辑                       \        |       /
Swift 2472   C# 2472  <-- 两份              无头内核 · 单一二进制
164 测试     164 测试                    监听会话 · 装 hook · 一份测试

每加一个 agent、每改一次协议            协议只实现一次
都要做两遍                              新客户端只是一层壳

两条路都必须做的：Windows 悬浮窗 · 进程表 · 命名管道
UI 那 2,400 行在任何一条路上都要重写 —— 架构选择改变不了这一点
```

- **如果 Windows 是终点，选 A。** 单体 C# 重写更直接，没有 IPC 这层复杂度；
  NativeAOT 让 hook 与 UI 共享一份 C# 核心，重复只在 Swift 与 C# 之间。
- **如果之后还想要 Linux、TUI、SSH 远程或手机推送，选 B。** 额外代价是这次多设计一个本地 API，
  回报是之后每个客户端都变成一层壳。考虑到 Linux 上 GUI 本来就走不通而 TUI 走得通，
  B 其实顺手解决了 Linux。

---

## 七、分期

每期都有一个可验证的完成标志。

**1. 先做一根穿透的钉子**
不写 UI，不写核心。一个 C# 程序读 `%USERPROFILE%\.claude\sessions\*.json`，
用 `OpenProcess` + `GetProcessTimes` 判断存活，把结果打到控制台。
同时用 NativeAOT 编一个空 hook 测冷启动。
*完成标志：在 PowerShell 里开两个会话，两条都被列出来；关掉一个，它消失；hook 冷启动数字可接受。*

**2. 核心翻译，测试当规格**
把 1,892 行纯逻辑加 241 行几何翻成 C#，同时把 164 个测试一起翻过去。不碰任何 UI。
*完成标志：测试全绿，且能正确解析真实 transcript 得出与 macOS 版一致的状态。*

**3. 窗口先于内容**
做那条悬浮胶囊：透明、置顶、穿透、不抢焦点、多显示器、每显示器 DPI。里面先画一个色块。
*完成标志：混合 DPI 双显示器上拖来拖去不糊、不错位、不抢焦点。*

**4. 接上 hook 与卡片**
命名管道 + ACL，装 hook 到 `settings.json`，权限卡片、提问、方案三种卡片跑通。
*完成标志：在真实会话里点一次 Allow，命令真的跑起来。*

**5. 补齐与收尾**
吉祥物与状态色、用量条、声音、开机启动、更新检查、WSL 检测提示、打包与签名。
*完成标志：一个陌生人下载解压能用，且知道 WSL 暂不支持。*

---

## 八、v1 明确不做

- **WSL 会话** —— 检测到并说明，不实现
- **精确跳回终端标签页** —— Windows Terminal 没有公开接口，只把窗口叫到前面
- **Codex 支持** —— 协议已经通了，但先把一个 agent 做对
- **Linux** —— 如果选了架构 B，它会以 TUI 的形式自己长出来
- **代码签名证书** —— 先带着 SmartScreen 提示发，等确认有人用再买

### 关于 WSL 的范围说明

在 WSL 里跑的会话不会出现在岛上，原因是三条同时断：注册表里的 pid 是 Linux pid，
Windows 侧查不到；进程树跨两个内核；命名管道过不去边界。要支持它等于在 WSL 内部再跑一个 agent，
是另一个项目。

但**沉默是最坏的处理方式**。一个 WSL 用户装上 Roost，看到一座永远空着的岛，
得出的结论是"这软件坏了"，而不是"它不支持我的用法"。

成本几乎为零的做法：启动时检测 `wsl.exe` 是否存在，有的话在设置窗口里放一行说明。

---

## 九、仍需在 Windows 上验证

以下是推断，不是实测 —— 这份评估是在 macOS 上做的。

已确认的部分：CLI 二进制里 darwin 481 处 / linux 317 处 / win32 217 处，
并处理 `USERPROFILE` 与 `APPDATA`，配置目录同样叫 `.claude`。

待验证：

1. Windows 上是否同样写 `~/.claude/sessions/<pid>.json`，其中的 pid 是否是 Windows pid
2. transcript 的目录编码规则在反斜杠路径下是什么样（macOS 上把 `/` 和 `.` 都压成 `-`，盘符和冒号怎么处理未知）
3. 桌面端在 Windows 上把会话记录写在哪里，字段是否一致 —— 决定行里有没有标题和模型名
4. NativeAOT 编出的 hook 实测冷启动是多少毫秒
5. Windows Terminal 的进程链形状：shell → `OpenConsole.exe` → `WindowsTerminal.exe` 是否稳定成立

前两条最关键 —— 如果 Windows 上的 pid 语义和 macOS 不同，整个"哪些会话还活着"的判断都要换实现。
**第一期那根钉子就是为了尽早撞上它们。**
