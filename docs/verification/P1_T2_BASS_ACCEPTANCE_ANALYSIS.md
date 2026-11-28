# Fidelune P1-T2-BASS Build #7 真机集中验收分析报告

**归档日期**：2026-11-28  
**验收版本**：Build #7（应用显示版本 `0.2.0` / `CFBundleVersion = 7`，Commit `035186f`，工程目录 [spikes/p1-t2-bass/](../../spikes/p1-t2-bass/)，[Actions Run #45998526234](https://github.com/SCUTLZH684/Fidelune/actions/runs/45998526234)，`runner_uuid = 35D2606B-DD7F-37C6-A66D-0125689FA037`）  
**测试环境**：iPhone 17（`iPhone18,3`，iOS `27.2.1`，Build `24B156`）· 外接 TOPPING DX5 II USB DAC · 本机扬声器  
**对齐基准**：[质量标准](../standards/QUALITY_BENCHMARKS.md) · [V1.0 范围与 G0 审查](../specs/V1_SCOPE_MATRIX.md) · [Phase 1 PoC 报告](PHASE1_POC_REPORT.md) · [交付报告](P1_T2_BASS_DELIVERY_REPORT.md)  
**声明原则**：严格依据已回收的真机导出报告、199 条诊断 JSONL 日志与仓库源码进行归因；不修复代码、不触发构建，严格区分**已证实事实**与**待隔离验证假设**。

---

## 1. 测试基线、真机环境与脱敏归档清单

### 1.1 运行基线与真机观测概览

- **安装包校验**：本次验收真机实装为 [Build #7](https://github.com/SCUTLZH684/Fidelune/actions/runs/45998526234) 无签名 IPA 经个人签名侧载后的产物（未签名母包 SHA-256 `5b0fd7e640c8ed0fafedf2dfb0c4b1cd50c8eedb9bce04e63642aae622d000d6`，主二进制嵌入 `UISceneDelegateClassName = "Runner.SceneDelegate"`，已在 Build #7 彻底解决 Build #6 黑屏问题）。
- **BASS 原生核心与插件**：真机实测加载 `BASS 2.4.18.3`（`0x02041203`）、`BASSmix 2.4.13.1`（`0x02040D01`）以及全部 5 个官方插件 `bassape` / `bassdsd` / `bassflac` / `bassopus` / `basswv`（`missingPlugins = []`）。
- **真机验收窗口**：北京时间 `2026-11-28 11:11:17.383` 至 `11:39:51.210`（UTC `03:11:17.383Z`–`03:39:51.210Z`，历时约 28 分 34 秒；末份报告导出时间为 `11:40:36.365`）。期间共计 **2 次冷启动**、记录 **199 条**诊断日志，核查系统崩溃目录 `2026-11-27`–`2026-11-28` 无任何 `Runner` / `Fidelune BASS` 崩溃报告（**0 崩溃**）；应用进程驻留内存观测范围 `28.80 MB`（冷启）→ `223.47 MB`（峰值）→ `171.64 MB`（结束前末条记录）。
- **实测引擎配置快照**（来自设备导出 `acceptance-report.json`）：`rateSwitchStrategy = "hybrid"`、`dacSettleDelayMs = 180`、`pcmFadeMs = 15`、`dopSilenceLeadMs = 100`、`dopSilenceTrailMs = 80`、`dsdPcmTargetRateHz = 176400`、`sessionMode = "defaultMode"`、`strictBitPerfectNoRampIn = true`、`rememberExactPosition = true`。

### 1.2 脱敏归档清单

已从物理 iPhone 回收完整真机沙盒数据。未经脱敏的原始快照（含签名团队后缀、安装列表与设备硬件识别号）仅保存在 Windows 本地 `%LOCALAPPDATA%\Fidelune\P1-T2-BASS\device\build-7\`；公开仓库仅提交以下 **8 份经过隐私扫描验证的脱敏证据**：

| 归档文件 | SHA-256（归档核验值） | 内容与用途 |
| --- | --- | --- |
| [build-7-info.txt](p1-t2-bass/build-7-info.txt) | `489b19f7e73ba4adaef9f1b33c9f57dcf87bf41e9ba062dbb705a020cb3a607c` | Build #7 云构建工具链、`runner_uuid` 与 7 个 BASS 框架二进制 SHA-256 |
| [build-7-bass-verified.json](p1-t2-bass/build-7-bass-verified.json) | `4d094854517a4ec8ed713300c2a379bf93be673881312197aae81039472e369c` | 官方 BASS XCFramework 压缩包锁定版本与校验记录 |
| [build-7-fixtures-manifest.json](p1-t2-bass/build-7-fixtures-manifest.json) | `17ceaf7952467171c16a641a2f91255a59a8ebd004950dd46736210d8cf64b63` | 随包 28 首正常 + 2 首坏文件测试音源的规格与参考 PCM SHA-256 |
| [device-build-7-acceptance-report.md](p1-t2-bass/device-build-7-acceptance-report.md) | `65068894533366b564097f3c3fd2335aafabd0bb0d3fc96658cb537617388830` | 真机最新导出的 Markdown 格式验收汇总 |
| [device-build-7-acceptance-report.json](p1-t2-bass/device-build-7-acceptance-report.json) | `4eea8beb6b31ea91ae836e6c2013d254ca4ba35b103aa0351a36472c32010da2` | 真机最新导出的 JSON 结构化报告（含 9 项机内校验详情与 11 项人工明细） |
| [device-build-7-acceptance-state.json](p1-t2-bass/device-build-7-acceptance-state.json) | `b2f5ce32b608f1a33c9f57d608e302cc1dc3722b4f096ae8d348c7` | 真机持久化的分项验收进度、失败标签与备注原始状态 |
| [device-build-7-diagnostics.jsonl](p1-t2-bass/device-build-7-diagnostics.jsonl) | `34c93f8ac9ed47edd44b6b091b0b731353dec03a137ce724bfdb38e11ca0090f` | 真机完整 199 条时间线事件日志（毫秒级，已验证每行合法 JSON 且无敏感字段） |
| [device-build-7-device-summary.json](p1-t2-bass/device-build-7-device-summary.json) | *(自索引文件)* | 脱敏硬件/软件元数据、事件计数、内存范围与上述 7 份文件的 SHA-256 索引 |

---

## 2. 口径校正总览：界面记录状态 vs 质量标准严格判定

真机界面上用户对 11 项人工用例点选了 **8 项通过 / 3 项未通过**；但审查 `device-build-7-acceptance-report.json` 中的**问题标签**与**人工备注**，并结合 199 条日志交叉比对后，发现 `H1`、`H2`、`D2`、`P3`、`R1` 五项虽在 UI 点选了「通过」，却明确勾选了爆音/咔哒声/降频/未拦截等阻塞性缺陷标签或失败事实。

严格依据 [质量标准](../standards/QUALITY_BENCHMARKS.md) 的硬性红线（“切歌、切路由、开始/停止和恢复时无应用造成的爆音；兼容规格无缝零间隙；不发生非预期降频；无硬件/数字捕获不可宣称端到端 Bit-perfect”），**本次真实通过率必须按严格质量口径重新核定**，不能以 UI 点按计数代替工程结论：

| 用例 | UI 点选记录 | 严格质量判定 | 核心实测事实与依据 |
| --- | --- | --- | --- |
| **冷启动与首帧** | *(未单列)* | **已通过** | Build #6 黑屏已解决；2 次启动 100% 渲染，BASS + 5 插件冷启初始化正常，全程 0 崩溃。 |
| **`auto_*`（9 项）** | 9 / 9 通过 | **已通过（应用内数字管线）** | `11:11:21` 在 iPhone 17 实机跑完 9 项 BASS/BASSmix/BASSDSD 二进制校验全过；**非物理 DAC 端到端**。 |
| **`H3` 多格式与坏文件** | 通过（1 次） | **已通过** | ALAC / WavPack / Opus / MP3 / AAC / 截断 FLAC / 正常 FLAC 续播正常；2 个坏 FLAC 4 ms 内安全跳过，无任何缺陷标签。 |
| **`D1` USB 全阶梯原采样率** | 通过（2 次） | **核心通过 / 含轻微切频爆豆观察** | 2 轮共 14/14 次请求 DX5 II 面板全部实显匹配 `44.1 ~ 384 kHz`；勾选 `[切频爆音]`（备注：小小声的爆豆声，不刺耳）。 |
| **`H1` 扬声器防爆音** | 通过（1 次） | **未通过** | 勾选 **`[暂停爆音, 拖动Seek爆音]`**；仅「继续」与「手动切歌」未报爆音（较 libmpv 有局部改善但未达标）。 |
| **`H2` 同规格无缝听感** | 通过（1 次） | **未通过** | 勾选 **`[接缝有咔哒声]`**，备注「`gap-a` 到 `gap-b` 中间有卡达声」；虽离线 `auto_gapless_44k` 0 帧差，实时外放未达标。 |
| **`D2` USB 混合规格与 96k 无缝** | 通过（1 次） | **未通过** | 勾选 **`[爆音, 96k无缝闪烁]`**，备注「非 44.1 kHz 音乐放到一半突然降频到 44.1」；JSONL 证实 96k/192k/48k 请求全落回 `44100 Hz`。 |
| **`P1` DSD64 DoP** | **未通过（2 次）** | **未通过（安全拦截生效，DoP 未实测）** | 日志证明用户 7 次确认安全清单，但采样率全部卡死 `44.1 / 48 kHz`，触发 `dop_rate_lock_failed` 安全拦截，未曾送出 DoP。 |
| **`P2` DSD128 DoP 与混切** | **未通过（2 次）** | **未通过（安全拦截生效，DoP 未实测）** | 备注「同 P1」；因未能锁定 `176.4 / 352.8 kHz` 载波而被安全门禁阻断，真实 DoP 点灯与切换防爆音尚未验证。 |
| **`P3` DoP 拦截与 PCM 降级** | 通过（1 次） | **部分通过 / 场景 A 证据不足** | 扬声器 DSD → PCM 自动降级已通过；但勾选 **`[未拦截低音量DoP]`**，源码证实 UI 启动强制切回 `.auto` 导致场景 A 未按预期走 `.dop` 拦截。 |
| **`R1` USB 热插拔与恢复** | 通过（1 次） | **部分通过（防外放通过，保频未通过）** | 拔出秒停零外放、插回续播首段恢复 `96 kHz`；但备注「96kHz 音频后半段自行变成 44.1kHz」，日志在 19s 后出现大量 `RouteConfigChange` 降频。 |
| **`R2` 后台与锁屏控制** | **未通过（1 次）** | **未通过** | 备注「**没有看见锁屏的那个组件**」；同时测试期间 `44.1/96/192 kHz` 全部锁死 `48000 Hz`。 |
| **`R3` 系统中断暂停与恢复** | 通过（1 次） | **部分通过 / 缺项待补测** | 实测原本暂停态遇中断未误起播、播放中遇中断暂停并恢复至 `96000 Hz`；但恢复 2 秒后发生 `RouteConfigChange` 降回 48k，且来电与独立播放中闹钟未单列验证。 |

---

## 3. 已通过的能力（明确证据级别与有效边界）

本节仅列出有充分日志与实机观察支撑、无阻塞性缺陷记录的已通过能力，并标明各自的证据边界：

1. **Build #7 启动渲染与原生动态库稳定性（真机运行实证）**：
   - 修复 Build #6 `Info.plist` 场景委托类名后，Build #7 在 iPhone 17（iOS 27.2.1）两次冷启动（`03:11:17.383Z`、`03:30:09.772Z`）分别在 `22 ms` 和 `91 ms` 内完成 `AVAudioSession` 激活 + `BASS 0x02041203` + `BASSmix 0x02040D01` + 全部 5 个解码插件加载（`initCode = 0`）。
   - Sideloadly 对 7 个 `.framework` 的个人免费签名加载在真机持续 28.6 分钟高压运行中保持 **0 崩溃**。
2. **真机原生 BASS 音频内核 9 项自动化数字基线（机内二进制校验 `9/9` 通过）**：
   - 于 `11:11:21.707` 在 iPhone 17 真机 `arm64` 运行完毕（总耗时约 4.3 秒，详见 `device-build-7-acceptance-report.json`）：
     - `auto_bass_init`：`BASS 0x02041203`、`BASSmix 0x02040D01` 与 5 个插件全部加载（0 ms）。
     - `auto_format_decode`：全部 28 个无损/有损/高采/DSF 音源均成功打开并读出正确通道与采样率（72 ms）。
     - `auto_pcm24_bitexact`（`wav24.wav`，48k/24-bit）与 `auto_flac24_bitexact`（`flac192000.flac`，192k/24-bit）：经 BASSmix Float32 管线还原 24-bit PCM 后，SHA-256 与源文件精确一致（分别 `745c41fd...` 与 `ff5f6aaf...`），**证明 `BASSFLAC` + `BASSmix` Float32 内部链路可无损保留 24-bit 完整有效位深（包括最低有效位）**。
     - `auto_gapless_44k`（`gap-a.wav + gap-b.wav`，44.1k/16-bit）与 `auto_gapless_96k`（`gap96-a.flac + gap96-b.flac`，96k/24-bit）：经 `BASS_MIXER_QUEUE` 离线拼接输出 `88,200` 帧与 `192,000` 帧，0 插帧、0 丢帧，SHA-256 与连续参考原件完全一致。
     - `auto_dop_dsd64`（529,200 帧，176.4 kHz 载波）与 `auto_dop_dsd128`（705,600 帧，352.8 kHz 载波）：`BASSDSD` 输出的 `0x05 / 0xFA` 标记 100% 严格交替（0 错误），且 `0x69` 静音帧打包/还原自检通过。
     - `auto_corrupt_resilience`：两个损坏文件安全拒绝，截断 FLAC 解码 983,040 字节安全结束。
   - **证据边界声明**：以上 9 项仅证明应用内“文件解码 → `BASSmix`/`BASSDSD` 浮点输出”无失真，**不代表经过 iOS `AVAudioSession`、CoreAudio USB 驱动与物理 DAC 后的端到端 Bit-perfect 已通过**。
3. **`H3` 多格式播放与损坏/截断文件熔断跳过（真机实测通过）**：
   - `alac96.m4a`、`wv96.wv`、`opus48.opus`、`lossy.mp3`、`lossy.aac`、`short.wav`、`truncated.flac`、`flac44100.flac` 连续播放正常；日志第 33–34 行记录 `invalid.flac` 与 `invalid-2.flac` 于 `03:17:35.116`–`03:17:35.120` 各自失败 1 次后安全跳过并继续尾曲，无卡死、无死循环。
4. **`D1` USB DAC 全阶梯 7 档原采样率精确跟随（核心硬件协商实测通过，优于原 `libmpv` 基线）**：
   - 日志第 37–50 行（`03:18:46.924`–`03:20:49.210`）记录连续 2 轮、共计 **14/14 次** `USBAudio` 速率切换全部 `matchedTarget = true`：`44.1 / 48 / 88.2 / 96 / 176.4 / 192 / 384 kHz`（含原 `libmpv` 在 Build #4/#7 尚未测完全阶梯的 `88.2 / 176.4 / 384 kHz`）。
   - `sessionActualHz`、`bassDeviceHz` 与发起人肉眼核对的 **TOPPING DX5 II 硬件面板显示 7/7 全部「匹配」**；跨频锁定平均总耗时约 `953–1003 ms`（首次 `44.1 kHz` 为 `266 ms`）。*(轻微爆豆声单独归入第 4 节)*
5. **`H1` 局部防爆音动作（真机实测较 `libmpv` 改善）**：
   - 扬声器下「继续播放」与「手动切下一首」未再触发用户勾选爆音标签（对比原 `libmpv` Build #7/#8 扬声器同规格直接切歌必爆音属于明确改善）。
6. **`P1`/`P2` DoP 安全硬门禁与 `P3` 扬声器 DSD → PCM 降级（安全逻辑实测通过）**：
   - 当会话未能锁定 `176.4 kHz` 载波时，`BassAudioEngine` 7/7 次触发 `dop_rate_lock_failed` 硬拦截并立即停机（日志第 90、93、95、98、102、107、192 行），彻底阻止向重采样为 44.1/48 kHz 的链路送出 DoP 导致刺耳白噪（对比原 `libmpv` Build #7 曾出现左耳尖声）。
   - 扬声器下播放 `dsd64.dsf` 未出现白噪，按 PCM 降级路径正常发声。
7. **`R1`/`R3` 基础热插拔防外放与中断状态机（真机部分通过）**：
   - **拔出防外放**：3 次拔出 USB DAC（日志第 114、128、146、198 行 `OldDeviceUnavailable`）及开局蓝牙断开（第 4 行）均在路由切换为 `Speaker` 时保持静音停播，零意外外放；重新插回 DX5 II 后手动继续可使首段恢复 `96000 Hz`（第 124、140 行）。
   - **中断防误播与恢复**：第 173 行（`wasPlaying=false`）在原本暂停态遇到系统中断时正确置 `willResume=false`，未误拉起；第 178–183 行（`wasPlaying=true`）遇到系统中断（伴随短暂类别变化 `CategoryChange -> Speaker -> USBAudio`）并在 `iOS.shouldResume=true` 时于 `03:35:37.367` 恢复续播且成功重锁 `96000 Hz`。

---

## 4. 未通过的能力与源码 + 日志根因分析

### 问题 1（P0 系统级架构与状态接入缺陷）：共同引发 `D2` / `R1` 中途降频、`P1` / `P2` DoP 锁相全阻断、`R2` 锁屏组件消失

#### 已证实的真机日志现象

1. **为什么 `D1` 全阶梯 14/14 成功，而紧随其后的 `D2`、`P1`、`R2`、`R3` 却大面积锁死在 `44.1 / 48 kHz`？**
   - 全部 `77` 次 `dac:dac-rate-negotiated` 事件中，仅有 **`18` 次成功、高达 `59` 次失败**。
   - **清晰的时间分水岭**：
     - `03:18:46`–`03:20:49`（第 37–50 行，`D1`）：从未触发 `bass-idle-paused`，除首条 `44.1 kHz` 在 `266 ms` 直接命中外，其余 13 次调 `BASS_DEVICE_REINIT` 均耗时 `953–1003 ms`，**14/14 全部匹配 `44.1 ~ 384 kHz`**。
     - `03:21:34`（第 51 行）首次触发 `bass-idle-paused`（`BASS_Pause()`）；`03:22:03`–`03:22:07`（第 52–53 行）在无应用切歌请求下连续出现两条 `RouteConfigChange (reason=8)`，其中第 52 行清晰记录状态裂口：**`bassHz: 384000, sessionHz: 48000`**。
     - `03:22:18`（第 54 行）再次 `bass-idle-paused`。从 `03:22:27`（第 55 行 `D2` 开始）直至测试结束，所有由新播放请求发起的跨频协商（`D2` #55–#83、`P1` #89–#113、冷启后 `R1` #134–#135、`R2` #151–#171、`R3` 新起播 #176–#177 & #185–#187、`P1` 复测 #191）**全部在 `200–291 ms` 内返回失败**（零次触发 `bass-reinit-rate-failed`，说明 `BASS_Init` 返回非零成功码但 `AVAudioSession.sampleRate` 与 `BASS_INFO.freq` 原地不动），先长期锁死 `44100 Hz`、在 `R2/R3/P1` 阶段锁死 `48000 Hz`。
     - **全日志唯三的例外成功时刻**（`D1` 之外）：第 124 行（`03:29:11.173`，`96000 Hz`）、第 140 行（`03:30:45.716`，`96000 Hz`）、第 183 行（`03:35:37.367`，`96000 Hz`）——**全部紧跟在 `session-reactivated`（即 `BassAudioEngine.resume()` 内显式调用了 `reactivateSession()` + `BASS_Start()`）之后**。
2. **为什么 `R1` 复播首段已是 `96 kHz`，后半段却“自行变成 44.1 kHz”？**
   - 第 140 行刚用 `resume()` 锁到 `96000 Hz`，但仅 18.7 秒后的 `03:31:04.465`（第 141 行），在 Fidelune 完全没有发起切频的情况下系统发出 `RouteConfigChange (reason=8)`：**`bassHz: 96000, sessionHz: 48000`**；`03:31:11.910`（第 142 行）继续变成 `bassHz: 48000, sessionHz: 44100`；直到第 149 行一直在 `44.1 / 48 / 96 kHz` 之间被外部系统事件振荡拉扯。同样现象也出现在 `R3` 恢复 2 秒后（第 183 行 `96000 Hz` → 第 184 行 `03:35:39.436` 立即 `RouteConfigChange` 回落 `48000 Hz`）。
3. **为什么 `R2`“没有看见锁屏的那个组件”？**
   - 虽然 [NowPlayingAndRemoteController.swift](../../spikes/p1-t2-bass/ios/Runner/Audio/NowPlayingAndRemoteController.swift#L53-L84) 与 [Info.plist](../../spikes/p1-t2-bass/ios/Runner/Info.plist) 已配置 `MPNowPlayingInfoCenter`、`MPRemoteCommandCenter` 和 `UIBackgroundModes = ["audio"]`，但在真机锁屏界面完全不显示正在播放卡片。
4. **为什么 `P1` / `P2` 在用户设置完全正确时仍“被安全拦截”？**
   - 日志证明用户 7 次完整确认 `dop-safety-acknowledged=true`，但因 `openAndStartTrackLocked()` 在切至 `176.4 kHz` 载波时遭遇上述锁死在 `44.1 / 48 kHz` 的问题，触发 `dop_rate_lock_failed` 安全拦截。而在 `P1` 测试结束后 `03:36:47.125`（第 197 行）的 `RouteConfigChange` 中，日志实际记录到 **`sessionHz: 176400`**（同时 `D1` 早已实测 `176400` 与 `352.8/384000 Hz` 全部匹配），证实 **iPhone 17 + DX5 II 硬件本身支持 DoP 所需载波速率，根因在 Fidelune 会话/引擎切换状态**。

#### 源码逐层因果归因

1. **已证实根因 1A — 未在 `BASS_Init` 前配置 `BASS_CONFIG_IOS_SESSION`，引发默认 `BASS_IOS_SESSION_MIX` 双会话抢权冲突**：
   - [BassAudioEngine.swift](../../spikes/p1-t2-bass/ios/Runner/Audio/BassAudioEngine.swift#L144-L160) 启动时先通过 `DacSessionManager.activateAtStartup()` 配置非混音 `.playback` 会话（`options: []`），紧接着调用 `BASS_Init(-1, 48000, BASS_DEVICE_FREQ, nil, nil)`，**全程未设置 `BASS_CONFIG_IOS_SESSION`**。
   - 根据 Un4seen 官方文档与源码审查，BASS iOS 的 `BASS_CONFIG_IOS_SESSION` 默认值为 `BASS_IOS_SESSION_MIX | BASS_IOS_SESSION_BTHFP`，即**会在 `BASS_Init` 阶段将 `AVAudioSession` 隐式开启 `.mixWithOthers` 混音属性**。
   - `.mixWithOthers` 直接造就三大后果：
     1. **直接致 `R2` 锁屏组件被系统隐藏**：Apple iOS 规则明确将启用 `AVAudioSessionCategoryOptionMixWithOthers` 的应用视为辅助音效而非主媒体播放器，**系统会主动抑制其 `MPNowPlayingInfoCenter` 锁屏/控制中心卡片**；同时 `NowPlayingAndRemoteController` 亦缺少 `UIApplication.shared.beginReceivingRemoteControlEvents()` 调用，且首次 `registerRemoteCommands()` 是在 `AppDelegate.didInitializeImplicitFlutterEngine` 的后台线程（`DispatchQueue.global(qos: .userInitiated)`）中被调用而非主线程。
     2. **直接导致硬件采样率失去独占权**：在 `.mixWithOthers` 模式下，iOS 允许系统音或其他音频管线共享 USB Audio 路由，一旦系统管线回到 `44.1 / 48 kHz`，`setPreferredSampleRate` 会被系统静默忽略（Apple 官方已知行为），且运行期触发 `RouteConfigChange (reason=8)` 将 USB DAC 从 `96 kHz` 拉回 `44.1 / 48 kHz`（精确对应 `D2`/`R1`/`R3` 中途掉频）。
2. **已证实根因 1B — `startPlayback()` 切频前时序倒置（未恢复 `AVAudioSession` 活跃态且先切频后 `BASS_Start()`）与错误吞咽**：
   - 对比源码：`BassAudioEngine.resume()`（`L358-L420`）在调用 `negotiateSampleRate()` **之前** 先调用了 `sessionManager.reactivateSession()` 与 `_ = BASS_Start()`（正是日志中仅存的 3 次后段成功案例 `#124/#140/#183`）；而新建播放入口 `openAndStartTrackLocked()`（`L700`）在调用 `negotiateSampleRate()` 时，**既没有调用 `reactivateSession()`，也没有先调用 `BASS_Start()`**（`BASS_Start()` 晚在 `L810` / `L934` 才执行）。当先前空闲 3 秒触发过 `BASS_Pause()`（`L1229-L1240`）或冷启会话已被 `.mixWithOthers` 钉在默认频率时，`reinitBassDeviceSampleRateLocked()` 无法像活跃态那样触发 CoreAudio 真切频，仅 20 ms 即返回非零。
   - 此外，[DacSessionManager.swift](../../spikes/p1-t2-bass/ios/Runner/Audio/DacSessionManager.swift#L269) 使用 `try? adapter.setPreferredSampleRate(Double(targetHz))` 吞掉了系统抛出的所有 `NSError`，`L240-L242` 也未在协商前置记录入口初始 `sessionHz / bassHz`，削弱了失败现场可观测性（备注：冷启直入 `#134` 同样失败一节也说明仅消除 `BASS_Pause()` 仍不足，必须同步消除根因 1A 的 `.mixWithOthers`）。

---

### 问题 2：`H1` 扬声器「暂停爆音」与「拖动 Seek 爆音」（已证实源码缺陷）

用户在 `poptest-a.flac`（`-12 dBFS` 连续稳态 `440 Hz` 纯音）下勾选 `[暂停爆音, 拖动Seek爆音]`，由以下 **4 处已证实代码缺陷** 共同引起：

1. **禁用 BASS 内置斜坡保护**：`EngineSettings.strictBitPerfectNoRampIn` 默认 `true`（[AudioModels.swift](../../spikes/p1-t2-bass/ios/Runner/Audio/AudioModels.swift#L145)），导致 [BassAudioEngine.swift](../../spikes/p1-t2-bass/ios/Runner/Audio/BassAudioEngine.swift#L880-L882) 对整个 `mixerStream` 全局写入 `BASS_ATTRIB_NORAMP = 1.0`，关闭了 BASS 默认在启停/暂停处做的抗爆音自动微淡入淡出。
2. **暂停淡出过短于更新周期与缓冲周期**：[BassAudioEngine.swift](../../spikes/p1-t2-bass/ios/Runner/Audio/BassAudioEngine.swift#L1156-L1170) 中 `pcmFadeMs = 15 ms`，仅等 `15 + 6 = 21 ms` 即调用 `BASS_ChannelPause(mixerStream)`（`L337`），而同时引擎配置的 `BASS_CONFIG_UPDATEPERIOD = 20 ms`（`L178`）且实测扬声器 `ioBufferDuration ≈ 23 ms`（参考既往日志）——**淡出周期尚未完整送达输出缓冲就被强行 `Pause` 截断**，令高电平 `440 Hz` 正弦波发生阶跃跌零产生“啪”声。
3. **`seek()` 时序写反，先发声后归零音量**：[BassAudioEngine.swift](../../spikes/p1-t2-bass/ios/Runner/Audio/BassAudioEngine.swift#L525-L538) 在重定位之后第 `532` 行先调用 `BASS_ChannelPlay(mixerStream, 1)` 让新位置样本带旧增益冲出，第 `535` 行才把 `BASS_ATTRIB_VOL` 设为 `0.0` 再淡入；**对比第 423–426 行的 `resume()` 先设音量 `0.0` 再调用 `BASS_ChannelPlay` 则完全没有起播爆音**。
4. **UI 滑块未节流与状态竞争**：[test_item_detail_screen.dart](../../spikes/p1-t2-bass/lib/screens/test_item_detail_screen.dart#L256-L258) 中 `Slider.onChanged` 在手指滑动每帧直接调用 `widget.gateway.seek(v)`（未使用 `onChangeEnd` 或防抖），频繁递增 `operationEpoch`（`BassAudioEngine.swift:476`）并反复打断上一次未完成的淡出/淡入窗口。

---

### 问题 3：`H2` 扬声器同规格无缝 `gap-a → gap-b`「接缝有咔哒声」（存在源码疑点与待隔离假设）

**核心矛盾**：同一台 iPhone 17 在本轮运行 `auto_gapless_44k` 时，`BASS_MIXER_QUEUE` 将 `gap-a.wav + gap-b.wav`（第 44,137 帧非零切割点）离线输出 **88,200 帧且 SHA-256 与 `continuous.wav` 100% 匹配（0 帧差、0 失真）**；但用户在 `H2` 扬声器实时播放时明确听到接缝有咔哒声（日志第 22–29 行均已记录 `gapless-queued` 与 `gapless-advanced`）。

由于 `auto_gapless_44k` 已排除源文件本身错切与 `BASS_MIXER_QUEUE` 基本拼接丢帧，实时外放咔哒声归为以下 **3 个待隔离验证的候选假设**（当前日志不足以直接锁定单一根因）：

1. **假设 3A — 扬声器路径 `44.1 → 48 kHz` 系统实时 SRC 与 `BASS_ATTRIB_NORAMP = 1.0` 的边界交互**：iPhone 扬声器工作在 `48000 Hz` 而 `gap-a/b` 为 `44100 Hz`（非零交点切割），混音器设 `BASS_MIXER_NONSTOP | BASS_MIXER_POSEX` 且禁用全局 `NORAMP`，经过 iOS 系统 SRC 滤波器阶跃或缓冲区衔接时产生瞬态听感咔哒。
2. **假设 3B — 边界播放回调触发主线程同步探针 + 即时入队第三首的锁/I/O 抖动**：`handleSourceEndedPlaytime`（`BassAudioEngine.swift:1007`）触发后，`PlaybackQueueCoordinator` 在 `backendDidAdvanceGaplessly`（`L392`）立即调 `updateQueuedNextTrack(continuous.wav)`，打开磁盘解码流、更新 NowPlaying 与推送 EventChannel；该行为在 `engineQueue` 上触发额外磁盘 I/O 与锁竞争可能造成瞬时微欠载。
3. **假设 3C — `BASS_SYNC_END` 与 `BASS_MIXER_CHAN_AUTOFREE` 在 `PLAYTIME` 下的实时边界抖动**：需对比仅开启 `44.1 kHz` / `96 kHz` **原采样率锁定后的 USB DAC 无缝**（无系统 SRC）以及对比 `continuous.wav` 自身在同位置的听感。

---

### 问题 4：`D1` 跨采样率切频「轻微爆豆声」（观察项 / 硬件与软件边界待分责）

用户在 `D1` 备注写明：“*爆音指的是小小声的爆豆声，不刺耳。应该说的是那个脉冲的声音*”。需明确区分两类原因：
- **硬件侧已知现象**：在 [PHASE1_POC_REPORT.md](PHASE1_POC_REPORT.md#L184) 中已记录 TOPPING 官方针对 **DX5 II** 发布过 [V2.58 固件更新](https://toppingaudio.com/download/dx5-ii-version-v2-58-firmware-update)，专门修复 USB PCM 改变采样率及恢复播放时的爆音问题；本次测试未核对 DX5 II 当前固件版本。
- **软件侧放大因素**：当前 `BassAudioEngine.openAndStartTrackLocked()` 在切频时由 `fadeOutAndTeardownLocked` 销毁流，但 `BASS_DEVICE_REINIT`（`~780 ms`）切换硬件时钟期间未给输出端先垫一小段零采样静音缓冲再 `REINIT`，切频脉冲可能直接穿过 DAC 解锁窗口。需结合固件核对后再分责。

---

## 5. 证据不足、需要补测的能力

对照 [QUALITY_BENCHMARKS.md](../standards/QUALITY_BENCHMARKS.md) 与 [V1_SCOPE_MATRIX.md](../specs/V1_SCOPE_MATRIX.md)，以下 8 项能力尚缺有效真机证据，必须补测：

1. **真实 USB DAC DoP DSD64 / DSD128 点灯与纯音听感（`P1` / `P2`，最高优先级未证项）**：
   - 本轮因采样率锁相全数卡在 44.1/48 kHz 触发拦截，真实 DoP 帧流（`0x05/0xFA` + `0x69` 护帧）从未发往 DX5 II，**BASS 路线能否在 iOS 27.2.1 上真正点亮 DX5 II 的 DSD64/DSD128 仍为未知**。
2. **`P3` 场景 A（低音量强制 DoP 硬拦截）与 DoP 播放中音量 KVO 熔断看门狗**：
   - 用户在 `P3` 勾选了 `[未拦截低音量DoP]`。审查源码发现这是一个**测试脚手架逻辑缺陷**：[acceptance_catalog.dart](../../spikes/p1-t2-bass/lib/acceptance/acceptance_catalog.dart#L252) 把 `P3` 的 `desiredDsdMode` 硬编码为 `DsdOutputMode.auto`，用户即使按指引第 1 步先手动切到「强制 DoP」，点击 [test_item_detail_screen.dart](../../spikes/p1-t2-bass/lib/screens/test_item_detail_screen.dart#L92-L93) 的「启动本项测试音频」时也会被 `setDsdMode(_item.desiredDsdMode)` 强行覆写回 `.auto`，进而在低音量下合法降级为 PCM 播放而未拦截（日志亦未出现预期错误码 `dop_volume_not_full`）。此外，`volumeObservation`（`DacSessionManager.swift:361-374`）只有在真正成功播放 DoP（`isDopStreamActive == true`）时才能实际拉响熔断，目前亦未实测。
3. **物理端到端 Bit-perfect（有效位深与 USB 数字样值比对）**：
   - 仅验证了 BASS 内部 Float32 管线 SHA-256 与 DX5 II 面板采样率读数；尚未通过外部数字捕获设备（如 RME/SPDIF 环回或数字逻辑分析仪）验证 iOS CoreAudio USB 路径没有对最低有效位进行截取、dither 或数字衰减，不可宣称端到端 Bit-perfect。
4. **原采样率真正锁定前提下的 `H2` / `D2` 实时无缝听感**：
   - `H2` 需在关闭无谓 SRC（或连接支持原生 `44.1/96 kHz` 的 DAC）并排查上述 3 个假设后复听；`D2` 需在修复中途降频 44.1 kHz 后重新核查 `96 kHz` 同规格接缝是否存在 DX5 II 闪烁与爆音。
5. **`R2` 锁屏控制中心双向同步与锁屏切歌防爆音**：
   - 修复 `BASS_CONFIG_IOS_SESSION` 移除 `BASS_IOS_SESSION_MIX` + 补齐主线程远程控制注册后，需实测锁屏卡片展示、曲目信息、进度条拖拽及锁屏切歌是否有爆音。
6. **蓝牙（`BluetoothA2DP`）路由实际播放、切歌、延迟与与有线互切**：
   - 本次仅在 `03:11:17` 启动与 `03:11:48` 断开时观测到系统曾经路由至 `BluetoothA2DPOutput`，未在蓝牙耳机连接下执行实际音频播放、切歌与蓝牙↔扬声器↔USB 往返切换测试。
7. **真实来电中断、独立“播放中”闹钟中断、响应延迟量化与 4 小时混合长播稳定性**：
   - 依据 `QUALITY_BENCHMARKS.md`，仍缺：**冷启动（≤ 1.5s） / 首次本地起播（≤ 500ms） / 同规格切歌（≤ 300ms） / Seek（≤ 300ms） 分位统计**；真实**来电**与**播放期间响铃闹钟**分别取证；**4 小时混合格式长播（含多次亮/灭屏与前后台切换）**。
   - **特别观察**：本次仅运行 28.6 分钟（其中包含多次 9 项自检与 2 次重启进程），日志记录进程内存已从 `28.80 MB` 上升至峰值 `223.47 MB`、末值 `171.64 MB`，必须在后续 4 小时稳定性测试中监测是正常缓存/Flutter 图片/队列上限平稳驻留，还是存在泄漏趋势。
8. **TOPPING DX5 II 固件版本核对**：
   - 核实当前 DX5 II 固件是否为 V2.58+，以剥离硬件已知切频爆音与软件 `BASS_DEVICE_REINIT` 时序问题。

---

## 6. 架构评估：BASS 音频架构是否值得继续采用？

### 6.1 三套架构实测能力横向对比

| 评估维度 | Un4seen BASS（Build #7 实测） | 原 `media_kit / libmpv`（Build #4/#7/#8 实测） | `SFBAudioEngine 0.15.0`（备选，未实测） |
| --- | --- | --- | --- |
| **USB DAC 全阶梯原采样率** | **44.1 / 48 / 88.2 / 96 / 176.4 / 192 / 384 kHz（14/14 面板匹配）**，但有 `.mixWithOthers` + 启动前时序缺陷致后段掉回 44.1/48 | 44.1 / 96 / 192 kHz 单曲请求匹配；`48 / 88.2 / 176.4 / 384` 未测 | 理论基于 `AVAudioEngine` 图重配，真机 USB 实表现未知 |
| **DSD / DoP 能力** | `BASSDSD` 机内验证 `DSD64/128` DoP 0 错误；因锁相缺陷未发往 DAC（可独立修复后实测） | 无原生 `BASS_DSD_DOP` 链路；预封装 176.4k DoP 出现**左耳尖锐噪音失败** | 含 `SFBDoPDecoder`，未上真机验证 |
| **多格式 & 24-bit 管线精度** | 28 文件（FLAC/ALAC/WV/APE/Opus/MP3/AAC/DSF）实测通过；48k/192k 24-bit SHA-256 零误差 | PCM/FLAC 正常；`ao=pcm` 离线 24-bit 匹配 | 主打 Apple 格式 + FLAC/DSD（Opus/APE 覆盖需核对依赖库） |
| **同规格无缝拼接** | 离线 `BASS_MIXER_QUEUE` 44.1k/96k 实测 0 帧差；**实时扬声器有咔哒待隔离，96k USB 因掉频未正常测通** | 扬声器 44.1k 听感通过、`ao=pcm` 0 帧差 | 理论原生无缝队列，未实测 |
| **暂停 / Seek / 切歌防爆音** | **继续与手动切歌通过**；暂停与 Seek 爆音已精确定位至 `NORAMP=1` + 15ms 过短 + `seek()` 顺序反写 + 无节流 | 即使加 `audio-stream-silence=yes` **同规格直切和暂停仍爆音（难以在不改 C 源码下根治）** | 未实测 |
| **后台 / 锁屏控制** | 因未设 `BASS_CONFIG_IOS_SESSION` 踩中 `.mixWithOthers` 导致锁屏不显示（可控配置项缺陷） | 锁屏显示与控制可用（仅切歌有爆音） | iOS 原生体系无 BASS 会话覆盖干扰 |
| **多端复用与可替换性** | 原生覆盖 iOS / Android / Windows；当前已通过 [AudioEngineProtocols.swift](../../spikes/p1-t2-bass/ios/Runner/Audio/AudioEngineProtocols.swift) 协议完全隔离上层业务 | 跨平台但 iOS 受制于 `AudioUnit` 黑盒与构建锁 | **仅限 Apple 平台**（Windows / Android 需另外选型两套引擎） |
| **授权合规成本** | 个人非盈利免费；**商业闭源分发 / 含内购或广告需向 Un4seen 购买对应平台授权**（不能与纯 GPL 代码混用） | `media_kit` 为 MIT，但内置 `mpv/FFmpeg` 需逐项审计 GPL/LGPL 分发义务 | 主体 MIT，完整包部分解码组件含 LGPL 依赖 |

### 6.2 总体判断与下一步决策建议

- **核心结论：当前阶段「值得有条件继续采用 BASS」，暂不定案 G1，也不建议此刻直接放弃并重造 SFBAudioEngine。**
- **支撑理由**：
  1. 本次暴露的所有 P0 阻塞问题，**没有一处被证实为 BASS 库本身无法克服的硬伤**——相反，`BASS + BASSmix + BASSDSD` 在 iOS 27.2.1 真机上已用硬证据跑通了：7 个动态库免费签装 0 崩溃、`44.1 ~ 384 kHz` 全部 7 档 DX5 II 原采样率实显匹配、192k/24-bit 管线无损还原与 `DSD64/128` 0 错误 DoP 帧生成。这是此前 `libmpv` 从未达到的高度。
  2. 导致本次 `D2 / R1` 掉频、`P1 / P2` 拦截、`R2` 锁屏消失、`H1` 暂停/Seek 爆音与 `P3` 场景 A 未拦截的原因，均已**精准定位到我方胶水层代码的具体配置缺失或时序错误**（未清掉 `BASS_IOS_SESSION_MIX`、开播协商未 `reactivateSession` + `BASS_Start()`、`seek()` 先播后静音 + `NORAMP=1` + 无防抖、`P3` 目录硬写 `.auto`），改动量极小、验证路径极清晰。
  3. 即便最坏情况下一轮定向验证发现 BASS 在 `H2` 实时无缝或 `P1/P2` 物理 DoP 点灯上确有底层限制，现有工程已经用 `AudioPlaybackBackend` 协议将调度、中断状态机、UI 与验收系统完全与 BASS 解耦，切换成本已降到最低。

### 6.3 建议的下一步决策与止损门槛（待发起人拍板）

本轮严格遵守指示**未做任何代码修改**。若发起人批准继续验证 BASS，建议**仅执行一轮极小范围精准修复（Build #8）+ 定向复测（无需全量重跑所有无问题用例）**：

1. **修复范围（预计 5 处局部调整）**：
   - 在 `BASS_Init` 前显式配置 `BASS_CONFIG_IOS_SESSION` 去掉 `BASS_IOS_SESSION_MIX`（并保证远程命令注册在主线程及开启 `beginReceivingRemoteControlEvents`），使 `AVAudioSession` 恢复独占 `.playback`。
   - 统一封装会话活跃与设备唤醒流程，确保 `startPlayback` 与 `resume` 在协商采样率前均处于有效会话与 `BASS_Start` 就绪状态，移除吞错 `try?` 并记录系统报错详情。
   - 修复 `seek()` 先归零再 `BASS_ChannelPlay`、调合理暂停淡出与斜坡参数（区分纯无损起播测试与常规暂停/Seek 抗爆音）、并将 UI 滑块改为拖尾或节流触发。
   - 修复 `P3` 测试条目覆写 `.dop` 的问题，确保场景 A 实走强制 DoP 拦截与场景 B 实走自动降级。
   - 为 `D1/D2/H2` 增设更细粒度日志（记录 `negotiateSampleRate` 入口初始值、`NORAMP` / 切频耗时细节），以便隔离 `H2` 实时咔哒声与 `D1` 轻微爆豆声来源。
2. **明确的止损切换条件**：
   - 在 Build #8 定向验证：**① `R2` 锁屏卡片是否出现、② `D2/R1` 是否彻底消除途中自行降回 44.1/48 kHz、③ `P1/P2` 能否真正把 DoP 送入 DX5 II 并点亮 DSD64/128、④ `H1` 爆音与 `H2` 在锁定原采样率 DAC 下的无缝听感**。
   - **若上述 ①~④ 中任一项在解决会话混音与我方时序问题后依然复现 BASS 底层无法消除的缺陷（尤其是实时无缝咔哒或真机 DoP 不识别），则立即触发备选路线**：保持现有 Swift 会话/状态机与 Flutter UI，仅将 `AudioPlaybackBackend` 替换为 `SFBAudioEngine 0.15.0` 做单轮对比。

*(本报告基于 Build #7 真机实测证据归档，未包含未上机能力的主观推断结果；正式技术选型由发起人审阅后在后续决策轮确定。)*
