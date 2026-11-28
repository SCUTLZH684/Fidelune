# Fidelune P1-T2-BASS Build #8 定向修复、验证与真人复测指南

**报告日期**：2026-11-28  
**分支与提交**：`feat/p1-t2-bass` · 修复实现 `0c27e87` → 测试修复与全绿归档 `7acd9cd`（报告提交见后续 commit）  
**构建流水线**：[P1-T2 BASS unsigned iOS build & test — Run #9](https://github.com/SCUTLZH684/Fidelune/actions/runs/46109550619)（说明：Run #8 于 Flutter Widget 测试阶段检出 `CheckboxListTile` 缺少 `Material` 祖先及 `Scrollable` 查找器歧义；`7acd9cd` 修复后于 Run #9 全项通过并产包，故母包内 `CFBundleVersion` 为 `9`，桌面交付安装包按本轮验收序列命名为 **`Fidelune-BASS-Build8.ipa`**）  
**输入基线**：[Build #7 真机集中验收分析报告](P1_T2_BASS_ACCEPTANCE_ANALYSIS.md) · [Build #7 脱敏证据集](p1-t2-bass/) · [质量标准](../standards/QUALITY_BENCHMARKS.md)  
**声明原则**：严格区分**已证实事实**（已获真机证据或自动化测试验证）与**待真机复测验证假设**（高置信因果推论与对应修复，尚未在物理 iPhone 17 + TOPPING DX5 II 上重新实测）。

---

## 1. 交付产物与完整性校验

| 校验项 | 核验结果（实测） |
| --- | --- |
| 桌面交付安装包 | `Fidelune-BASS-Build8.ipa`（已保留同目录 Build #6 / Build #7 基线包及 `spikes/p1-t2/` 原 `libmpv` 基线） |
| 文件大小 | `23,631,408` bytes（较 Build #7 增长因新增 `352.8 kHz` 音源、扩展 `96k` 12 秒稳态曲目、`6s` 无缝对照组及 `6s` DSD64） |
| 未签名 IPA SHA-256 | `b86cfdc8385c8dc602071881813996ce55cc4d57ad6f9fd868a3f4cf0117d6b4`（与 `build-info.txt` 一致） |
| `fidelune-bass-dsyms.zip` SHA-256 | `badd74ef33420cf3a4efb058308e78fdeb66eed2b011b1be601ddd32c6468c50` |
| Bundle Identifier / Version | `io.github.scutlzh684.fideluneBass` / `CFBundleVersion = 9` / `MinimumOSVersion = 15.0` |
| 关键 Info.plist 配置 | `UISceneDelegateClassName = Runner.SceneDelegate`、`UIBackgroundModes = ['audio']`、无 `embedded.mobileprovision`（可直接拖入 Sideloadly 个人签名安装） |
| 原生 BASS arm64 框架（7 个） | `bass` (`2.4.18.3`)、`bassmix` (`2.4.13.1`)、`bassdsd` (`2.4.2`)、`bassflac` (`2.4.6.1`)、`basswv` (`2.4.7.4`)、`bassape` (`2.4.1`)、`bassopus` (`2.4.3.3`) 全部存在并核验 SHA-256 |
| 内置测试音源清单 | `fixtures-manifest.json`（共 `32` 个文件，含新增 `flac352800.flac` `1,058,400` 帧 / `flac96000.flac` `1,152,000` 帧；SHA-256 `61981c70a236822c99c47a1bd1c10bcad97d507a2aee1d620bfeb62315117408`） |

---

## 2. 本轮问题归因证据与实际代码修改

### 2.1 修复一：独占 `AVAudioSession`、锁屏控制（R2）与 USB DAC 采样率协商/保持（D1/D2/R1/R3/P1/P2）

- **查明的证据依据**：
  1. 官方文档 [`BASS_CONFIG_IOS_SESSION`](https://www.un4seen.com/doc/#bass/BASS_CONFIG_IOS_SESSION.html) 明确记载 BASS 默认启用 `BASS_IOS_SESSION_MIX | BASS_IOS_SESSION_BTHFP`，即每次 `BASS_Init` 与 `BASS_DEVICE_REINIT` 均会向系统写入 `.mixWithOthers`。
  2. `LyrPlay`（`AudioManager.swift:703-714`）及 Un4seen 官方论坛 Ian Luck 回复（Topic `#20785 #3`）证实：在 `.playback` 下保留 `.mixWithOthers` 会导致 App 失去系统主 Now Playing 资格（锁屏/灵动岛卡片消失）且与他人/系统音频共享 USB 音频会话（导致 `setPreferredSampleRate` 失效并被 `RouteConfigChange` 拉回 `44.1/48 kHz`）；正确做法是在 `BASS_Init` 前设置 `BASS_SetConfig(BASS_CONFIG_IOS_SESSION, 0)`，同时**不禁用** `BASS_IOS_SESSION_DISABLE` 以便 BASS 继续原生接管路由切换。
  3. Build #7 真机日志（`device-build-7-diagnostics.jsonl` 第 38–50 行）证实 DX5 II 跨频锁相实际耗时约 `750–800 ms`（`settleElapsedMs = 953–1003 ms`），而 Build #7 仅固定等待 `180 ms` 且空载 3 秒即触发 `BASS_Pause()` 停机。
- **实际修改**：
  - [BassAudioEngine.swift](../../spikes/p1-t2-bass/ios/Runner/Audio/BassAudioEngine.swift)：在 `initialize()`、`reinitBassDeviceSampleRateLocked()`、`reinitializeDeviceAfterMediaReset()` 中于 `BASS_Init` 前强制调用 `BASS_SetConfig(DWORD(BASS_CONFIG_IOS_SESSION), 0)`，并启用 `BASS_CONFIG_FLOATDSP = 1`、`BASS_CONFIG_DEV_NONSTOP = 1`、`BASS_CONFIG_GVOL_STREAM = 10000`；在 `openAndStartTrackLocked()` 与 `resume()` 协商采样率**前**先唤醒 `AVAudioSession` 与 `BASS_Start()`；将空闲自动休眠 `scheduleIdlePauseLocked()` 从 `3.0s` 放宽至 `30.0s`。
  - [DacSessionManager.swift](../../spikes/p1-t2-bass/ios/Runner/Audio/DacSessionManager.swift)、[AudioEngineProtocols.swift](../../spikes/p1-t2-bass/ios/Runner/Audio/AudioEngineProtocols.swift)：新增 `categoryOptions` 读取并移除 `try?` 静默吞错（保留 `sessionError` 与 `categoryOptionsRaw` 因果遥测）；将 `negotiateSampleRate` 升级为三阶段有界轮询（`already_matched` → `phase1_sessionPreferred` 每 `25 ms` 轮询至多 `450 ms` → `phase2_bassReinit` 至多 `1100 ms` → `phase3_sessionCycle` 休眠重置重锁至多 `600 ms` + 变更后 `80 ms` DAC 继电器静默稳定时间）；新增 `runUsbDacRateSweep()` 8 档全阶梯自动握手；新增播放中 USB PCM 意外降频检测（`dac-unexpected-rate-drop`）与防抖重锁恢复 `recoverUnexpectedUsbRateDrop()`。
  - [NowPlayingAndRemoteController.swift](../../spikes/p1-t2-bass/ios/Runner/Audio/NowPlayingAndRemoteController.swift) & [PlaybackQueueCoordinator.swift](../../spikes/p1-t2-bass/ios/Runner/Audio/PlaybackQueueCoordinator.swift)：将 `MPRemoteCommandCenter`、`UIApplication.shared.beginReceivingRemoteControlEvents()` 与 `MPNowPlayingInfoCenter`（含 `playbackState`）全部显式派发至 `DispatchQueue.main`，并对每 `250 ms` 进度刷新去重/节流（仅切歌、状态/路由变更或位置漂移 `>= 1.5s` 时更新）；系统中断结束后增加 `150 ms` 路由回收稳定延迟再触发恢复。

### 2.2 修复二：防爆音（H1/D1）与同规格实时无缝（H2/D2），且不破坏样值位精确性

- **查明的证据依据**：
  1. 官方文档 [`BASS_ATTRIB_NORAMP`](https://www.un4seen.com/doc/#bass/BASS_ATTRIB_NORAMP.html) 定义 `1 = 禁用淡入与淡出`，**`2 = 仅禁用淡入（保留 BASS 暂停/停止微斜坡）`**，Build #7 误设为 `1.0`；同时 Build #7 `seek()`（原第 532–538 行）在将 `BASS_ATTRIB_VOL` 置为 `0.0` **之前**就执行了 `BASS_ChannelPlay(mixerStream, 1)`。
  2. Build #7 `H2` 用例队列将 `continuous.wav` 直接接在 `gap-b.wav` 之后，且 `acceptance_catalog.dart` 引导误导测试者“先播 4 秒无缝拼接”（实际第 2 秒即进入 `continuous.wav` 触发混音淡入淡出咔哒声）；且 `tryQueueCompatibleTrackLocked` 在无缝切换前对同一文件重复打开两次且未启用 `BASS_ASYNCFILE`。
- **实际修改**：
  - [BassAudioEngine.swift](../../spikes/p1-t2-bass/ios/Runner/Audio/BassAudioEngine.swift)：正常从 `0.0s` 起播与同规格无缝预排队全程保持 `BASS_ATTRIB_VOL = 1.0`、`BASS_ATTRIB_NORAMP = 2.0`、`BASS_MIXER_CHAN_NORAMPIN`（**首采样点至尾采样点 100% 单位增益无损**）；仅在 `pause` / `seek` / 手动切歌瞬间执行 `rampDownAndDrainPcmLocked()`（先切 `NORAMP = 0.0`、滑落至 `0.0` 并轮询 `BASS_ChannelIsSliding` 完成 + `22 ms` 硬件缓冲排空后再暂停）；修复 `seek()` 顺序为先排空暂停 → `BASS_POS_MIXER_RESET`（并在邻近曲尾回拖时刷新已被预读的 `queuedNextSource`） → 先置 `VOL = 0.0` 再 `BASS_ChannelPlay(..., 1)` → `20 ms` 微淡入后恢复 `NORAMP = 2.0`；非无缝自然曲终利用 `BASS_MIXER_NONSTOP` 输出 `30 ms` 数字零再切换硬件采样率；预排队改用 `BASS_ASYNCFILE` 单次打开（仅 `mp3/ogg/aac` 保留 `PRESCAN`）。
  - [test_item_detail_screen.dart](../../spikes/p1-t2-bass/lib/screens/test_item_detail_screen.dart) & [player_library_screen.dart](../../spikes/p1-t2-bass/lib/screens/player_library_screen.dart)：所有进度 `Slider` 改为拖动期间仅更新本地显示值，仅在**松手 `onChangeEnd`** 时提交一次 `seek()`（消除拖动过程中连续触发数十次 seek 的脉冲噪）。
  - [PlaybackQueueCoordinator.swift](../../spikes/p1-t2-bass/ios/Runner/Audio/PlaybackQueueCoordinator.swift)：将 `backendDidAdvanceGaplessly` 中的 `UserDefaults` 持久化改为 `0.5s` 异步防抖，避免在缝隙瞬态抢占 I/O。

### 2.3 修复三：DoP 零丢帧标记对齐与播放期全程安全熔断（P1/P2/P3）

- **审查项落实**：
  1. **消除丢帧**：Build #7 `DopPassthroughStream.swift:257-260` 在静音后首个载荷帧标记冲突时通过 `srcOffsetFrames = 1; gotFrames -= 1` 直接丢弃 DSD 有效载荷帧。现改为在 [DopPassthroughStream.swift](../../spikes/p1-t2-bass/ios/Runner/Audio/DopPassthroughStream.swift) 维护 `pendingPayloadBuffer`，若 `firstMarker == lastEmittedMarker` 则先插入 **1 帧 `0x69` 静音对齐帧**翻转奇偶，然后从偏移 `0` 完整输出全部有效载荷（**0 丢帧、0 修改**），并使 `seek()` 字节偏移严格对齐 `channels * 4` 浮点帧边界；同步补全 DoP 暂停后 `resume()` 调用 `BASS_ChannelPlay(dop.outputHandle, 1)` 清除 `BASS_STREAMPROC_END` 状态的逻辑。
  2. **全程安全熔断**：在 `DopSafetyDialog`（[dop_safety_dialog.dart](../../spikes/p1-t2-bass/lib/widgets/dop_safety_dialog.dart)）强制第 1 项核心确认「**必须先从 DAC / 耳放物理拔下耳机**」；播放期间除系统音量 KVO（`< 100%` 立即停机）外，新增 [DacSessionManager.swift](../../spikes/p1-t2-bass/ios/Runner/Audio/DacSessionManager.swift) 路由变更全原因检测（无论断开、配置变化还是重配置，只要在 DoP 期间离开 USB DAC 或会话/BASS 采样率偏离目标载波即刻 `emergencySafetyHalt`）以及 [BassAudioEngine.swift](../../spikes/p1-t2-bass/ios/Runner/Audio/BassAudioEngine.swift) `100 ms` DoP 运行时看门狗定时器（持续校核路由、采样率、系统音量、通道音量及全局流增益）。

### 2.4 修复四：补齐 `352.8 kHz`、重构 `P3` 与精简定向复测界面（T1–T7）

- **测试音源补齐**（[fixtures.py](../../spikes/p1-t2-bass/tools/fixtures.py)）：
  - `PCM_LADDER_RATES` 补齐 `352800`（生成 24-bit 3s `flac352800.flac`，与 DSD128 DoP 载波同频，严禁以 `384 kHz` 替代）。
  - `flac96000.flac` 延长至 `12 秒`（供 `T4`/`T5` 热插拔与闹钟中断后完整播完核对不半途掉频）；`gap-a/b` 与 `continuous`、`gap96-a/b` 与 `continuous96` 均扩为 **`6 秒`（3s + 3s 非零点切割）**，并将 `dsd64.dsf` 设为 `6 秒`、`dsd128.dsf` 设为 `3 秒`。
- **防假通过硬门禁**（[acceptance_controller.dart](../../spikes/p1-t2-bass/lib/acceptance/acceptance_controller.dart)、[test_item_detail_screen.dart](../../spikes/p1-t2-bass/lib/screens/test_item_detail_screen.dart)）：
  - 若勾选任意阻塞异常标签，或 `T2` 尚有频点（含 `352.8 kHz`）未核对为「匹配」，界面立即禁用「通过并下一项」按钮；底层 `markResult()` 亦强制将含阻塞标签的误传 `passed` 拦截改判为 `failed`。
- **精简 `T1`–`T7` 定向复测工作流**（[acceptance_catalog.dart](../../spikes/p1-t2-bass/lib/acceptance/acceptance_catalog.dart)、[dac_monitor_screen.dart](../../spikes/p1-t2-bass/lib/screens/dac_monitor_screen.dart)、[AppDelegate.swift](../../spikes/p1-t2-bass/ios/Runner/AppDelegate.swift)）：
  - 持久化存储切换至 `fidelune-acceptance-state-v2.json` 隔离 Build #7 历史记录；移除原 `DacMonitorScreen` 中的无关底层毫秒调节滑块；将 `P3`（现 `T6`）拆为场景 A/B/C 三个独立动作按钮（场景 A 显式传入 `DsdOutputMode.dop` 且若当前已插 USB 且 100% 音量则 UI 阻止误触起播）；本轮聚焦 **7 项定向复测**，暂不进行 4 小时连续播放测试。

---

## 3. 自动化验证结果（CI Run #9 · Commit `7acd9cd`）

| 测试层级 | 执行环境与内容 | 实测结果 |
| --- | --- | --- |
| 音源生成与 Python 回归测试 | macOS-26 + `ffmpeg`/`ffprobe` (`tools/fixtures.py` + `tools/test_tools.py`) | **通过**：生成并 bit-verify 全部 `32` 个音源（含 `flac352800.flac`）；`Ran 3 tests in 1.025s` OK（含 Windows 本地运行同样 `3/3` 通过） |
| Flutter 静态分析与单元测试 | macOS-26 · Flutter `3.44.0`（`flutter analyze --no-pub` + `flutter test --no-pub`） | **通过**：`No issues found! (ran in 8.9s)`；**4/4** 测试全部通过（含阻塞标签锁、352.8k 缺失拦截、4 项 DoP 安全弹窗含拔耳机校验、`T6` 场景 A 显式传 `DsdOutputMode.dop`、8 档探测联动） |
| iOS Simulator Swift XCTests | `macos-26` Xcode `26.3` `arm64` Simulator（真实加载 `BASS`/`BASSmix`/`BASSDSD` 二进制） | **通过**：`Executed 10 tests, with 0 failures (0 unexpected)`（`BassAudioEngineTests` 9 项 + `RunnerTests` 1 项）：<br>① `testRealBassSelfTestsAgainstBundledFixtures`（`3.201s`）：运行扩展后的 **10 项真实 BASS 内核校验全部通过**（新增 `auto_dop_passthrough_integrity` 以 1021 帧素数块完整抽取 `DopPassthroughStream`，验证 **0 丢帧**、与原始 `BASSDSD` 载荷 SHA-256 100% 一致、`0x69` 静音校验通过，以及双次 `0.3333s` / `1.1001s` Seek 后 `0x05/0xFA` 奇偶 `0` 错误）；<br>② `testMultiPhaseUsbRateNegotiationPollsAndLocks352800Hz`：验证异步延时轮询最终锁定 `352800 Hz` 与 `categoryOptionsRaw == 0`；<br>③ `testRuntimeDopHaltsImmediatelyOnUnexpectedRateDropOrRouteChange`：验证 DoP 播中遇到 `RouteConfigChange` 降回 48k 及路由切回扬声器均立即熔断；<br>④ `testMidStreamUsbPcmRateDropTriggersRecovery`：验证 USB PCM 播中降频触发恢复回调；<br>⑤ 其余队列容错、DoP 启动门禁、热插拔清零及无缝兼容规则回归全绿。 |
| Release 打包与产物完整性校验 | macOS Release Archive + OpenSSL CMS 加解密回验 | **通过**：IPA / dSYM / `fixtures-manifest.json` / `pubspec.lock` / `bass_verified.json` 与桌面复制件 SHA-256 全匹配；7 个 BASS 框架与 `flac352800.flac` 已核验入包。 |

---

## 4. 严格边界声明：已证实事实 vs 待真机复测事项

| 分类 | 事项 | 依据来源 |
| --- | --- | --- |
| **已证实事实** | 10 项机内 BASS/BASSmix/BASSDSD 二进制检验（含 `DopPassthroughStream` 零丢帧/双次 Seek 奇偶严格交替、`192k/24b` 与 `48k/24b` 位精确还原、`44.1k/96k` `6s` 无缝 0 帧差拼接及 `flac352800.flac` 解码）通过 | CI Run #9 真二进制 Simulator XCTest 实测（`3.201s`，`10/10`） |
| **已证实事实** | 阻塞异常标签锁定禁用「通过」、`T2` 缺少 `352.8 kHz` 拦截通过、`T6` 场景 A 显式传递 `DsdOutputMode.dop`、`DopSafetyDialog` 4 项安全必选门禁通过 | CI Run #9 Flutter `4/4` Widget/Controller 实测 |
| **已证实事实** | DoP 运行时遇到 `RouteConfigChange` 降频或路由变更时立即触发 `emergencySafetyHalt`（Mock 适配层） | CI Run #9 XCTest 逻辑单元测试实测 |
| **待真机复测** | 取消 `.mixWithOthers`（`BASS_CONFIG_IOS_SESSION = 0`）后是否在物理 iPhone 17（iOS `27.2.1`）上恢复锁屏/控制中心卡片与双向控件（`T4`） | **高可信推论**（依据 `LyrPlay` 与 Un4seen 官方文档，待实机观察确认） |
| **待真机复测** | 独占 Session + 多阶段轮询（最长 `~1.5s`）能否在 DX5 II 上彻底消除 `96k`/`192k` 播中掉回 `44.1/48 kHz`、`176.4/352.8 kHz` 协商失败，以及热插拔/闹钟恢复后能否稳锁 `96 kHz`（`T2`/`T3`/`T5`） | **高可信假设**（待实机长时间观察 DX5 II 屏幕与回收 Build #8 日志中的 `categoryOptionsRaw`/`phaseReached` 字段实证） |
| **待真机复测** | DX5 II 物理支持 `352.8 kHz` PCM 及真实硬件面板点亮 `DSD64`、`DSD128` 指示灯、且耳放最低音量无白噪（`T2`/`T7`） | **完全未在真机测过**（Build #7 D1 漏测 `352.8 kHz`；P1/P2 被阻断未发射 DoP） |
| **待真机复测** | `NORAMP = 2` + `20 ms` 淡出排空 + `onChangeEnd` Seek + 单次 `BASS_ASYNCFILE` 预排队是否在真实人耳听感中消除暂停/Seek/切频/接缝爆音咔哒（`T1`/`T3`） | **待人耳主观复测**（离线数学位精确已通过，真实扬声器与 DX5 II 模拟级过渡须实耳验收） |
| **已知剩余风险** | ① 物理设备端（如 DX5 II 硬件本身或 iOS 特定系统服务强制触发的路由切换）仍存在极端驱动异常导致降频的可能，若发生将被日志明确捕获而不被静默重采样掩盖；<br>② 当前未做端到端物理 DAC SP/DIF 或 USB 回录硬件采样比对，且本轮刻意跳过 4 小时耐久测试（待本次核心项全部通过后再补充长稳）。 | 工程边界约定 |

---

## 5. 真人定向复测简要指引（约 8～10 分钟）

通过 Sideloadly 将桌面 `Fidelune-BASS-Build8.ipa` 安装至 iPhone 17 后，请按 App「集中验收」页顺序执行（**本轮无需进行 4 小时播放测试**）：

1. **先跑机器基线**：点击首页**「一键运行 10 项自动校验」**（确认 `10/10` 全部通过）。
2. **`T1`（扬声器 · 无外接）**：依次点动作 1/2/3——重点核对暂停、松手 Seek、切歌全无“啪/咔”爆音，且独立 6 秒 `gap-a → gap-b` 第 3 秒交界如 `continuous` 般平滑。
3. **`T2`（接 DX5 II · 调低耳放音量）**：先点**「一键自动探测 8 档采样率握手」**，再播 8 档队列对照 DX5 II 面板勾选全部 8 档（**必核 `352.8 kHz`**，切频仅短静音无爆音）。
4. **`T3`（DX5 II 96k 无缝与跨规格）**：盯住 DX5 II 屏幕 6 秒播 `gap96-a → gap96-b` 及跨规格队列，核对全程稳锁不半途掉回 44.1/48k、第 3 秒零咔哒。
5. **`T4`（锁屏卡片与双向控件）**：播 `96k/192k` 循环队列并锁屏，核对锁屏媒体组件显示与暂停/继续/上下曲/进度拖动生效，且期间 DAC 不掉回 48k。
6. **`T5`（热插拔与 10s 计时器中断）**：播 12 秒 `96 kHz` → 拔线秒停零外放 → 插回点继续并**播到曲终不掉频** → 用 10 秒计时器验证闹钟暂停/关闭恢复锁频，以及原暂停态不被闹钟误拉起。
7. **`T6`（⚠️ 先物理拔下耳机 · DoP 安全闭环）**：按页面**场景 A / B / C** 三个独立按钮分别验证（调低 1 格音量强开 DoP 被拦 → 调回 100% 起播后按音量减立即 0.1s 熔断 → 扬声器自动转 PCM 无白噪）。
8. **`T7`（⚠️ 先物理拔下耳机 · DSD64/128 DoP 点灯）**：iPhone 设好「其他设备」且音量 100% → 空载点击步骤 1/2 盯 DX5 II 屏幕点亮 `DSD64`/`DSD128` → 确认点灯后再把耳放拧到最低音量插耳机聆听步骤 1/2/3（纯音柔和无白噪，切回 PCM 正常出声）。

完成后进入「报告导出」分享导出报告与 `.jsonl` 日志以作最终闭环核验。
