# Fidelune P1-T2-BASS：基于 BASS 的 iOS 音频架构与 DAC 集中验收交付报告

**交付分支**：`feat/p1-t2-bass`  
**对应工程目录**：[spikes/p1-t2-bass/](../../spikes/p1-t2-bass/)  
**使用说明**：[spikes/p1-t2-bass/README.md](../../spikes/p1-t2-bass/README.md)  
**最新全绿 CI 构建**：[Actions Run #45998526234 (Build #7)](https://github.com/SCUTLZH684/Fidelune/actions/runs/45998526234)（Job [140503935290](https://github.com/SCUTLZH684/Fidelune/actions/runs/45998526234/job/140503935290)，Commit `035186f9fe44ab4161d8db9c751f13a6b4fd0d4e`）  
**真机故障基线保留**：Build #6（[Actions Run #45983078555](https://github.com/SCUTLZH684/Fidelune/actions/runs/45983078555)，Commit `0d70fb8df7cada85b8a54a739cb68800a9710dce`）安装包与 iPhone 17 现场诊断日志已保留于 `%LOCALAPPDATA%\Fidelune\P1-T2-BASS\build-6\`、`device\build-6\` 及桌面 `Fidelune-BASS-Build6.ipa`。  
**基线保护情况**：已确认 `git diff codex/p1-t2 -- spikes/p1-t2 .github/workflows/p1-t2-ios.yml docs/verification/p1-t2` 输出为空，原 `libmpv` 实验代码、CI 与验收记录未做任何改动；`docs/research/` 下两份未跟踪 HTML 调研文件保持原样未修改。

---

## 1. 一句话总结与真机接收指南

本轮在保留原 `libmpv` 实验的前提下，完成了独立于原目录的 **BASS 完整 iOS Hi-Res 音频引擎、USB DAC 会话管理与集中真机验收套件**，已在 GitHub Actions `macos-26` + Xcode `26.3` + Flutter `3.44.0` 上完成从公式校验下载、FFmpeg 样本生成与位验证、Flutter 分析与控件测试、**iOS Simulator 真实 BASS 二进制 XCTests（7 项全过，含 9 项机内自检）** 到 **arm64 无签名 IPA 归档、7 个框架嵌入检验、`Runner.SceneDelegate` 场景类断言、dSYM UUID 匹配校验、OpenSSL CMS 加密与 Artifact 上传** 全链路全绿验证。

### Windows 端 IPA 交付结果与一键重验说明

本机已使用 QA 私钥（`%LOCALAPPDATA%\Fidelune\P1-T2\qa-artifact-key.pem`）完成 **Build #7** 产物解密与完整性核验，并已将可直接拖入 **Sideloadly** 的无签名 IPA 放置到桌面：

- **桌面安装包**：`C:\Users\l\OneDrive\Desktop\Fidelune-BASS-Build7.ipa`
- **文件大小**：`19,381,129` 字节
- **SHA-256**：`5b0fd7e640c8ed0fafedf2dfb0c4b1cd50c8eedb9bce04e63642aae622d000d6`（与 `build-info.txt` 一致）
- **保留的 Build #6 基线**：`C:\Users\l\OneDrive\Desktop\Fidelune-BASS-Build6.ipa`（`19,378,167` 字节，SHA-256 `17298da5eb73e2ecc401dd5b35791b7a6d8481dcc1dc157e093ee47a91fb51d0`）

如需在本地重新从 CI Artifact **`p1-t2-bass-ios-7`** 解密核验，可将压缩包解压至 `%LOCALAPPDATA%\Fidelune\P1-T2-BASS\build-7\` 后运行：

```powershell
$keyFile  = Join-Path $env:LOCALAPPDATA 'Fidelune\P1-T2\qa-artifact-key.pem'
$openssl  = 'C:\Program Files\Git\usr\bin\openssl.exe'
$buildDir = Join-Path $env:LOCALAPPDATA 'Fidelune\P1-T2-BASS\build-7'
Set-Location $buildDir

& $openssl cms -decrypt -binary -inform DER `
  -in .\fidelune-bass-unsigned.ipa.cms `
  -inkey $keyFile `
  -out .\fidelune-bass-unsigned.ipa

& $openssl cms -decrypt -binary -inform DER `
  -in .\fidelune-bass-dsyms.zip.cms `
  -inkey $keyFile `
  -out .\fidelune-bass-dsyms.zip

Get-FileHash -Algorithm SHA256 .\fidelune-bass-unsigned.ipa, .\fidelune-bass-dsyms.zip
Get-Content .\build-info.txt
```

直接用 **Sideloadly**（默认 Bundle ID `io.github.scutlzh684.fideluneBass`、免费个人 Apple ID、USB 数据线）侧载安装桌面 `Fidelune-BASS-Build7.ipa` 至 iPhone 17，并在手机「设置 → 通用 → VPN 与设备管理」信任证书即可开始启动与集中验收。

---

## 2. 成熟实现审计与第三方组件复用

### 2.1 官方 Un4seen BASS iOS 组件（构建期按 SHA-256 精确锁定拉取）

全部 7 个组件在 [bass_deps.json](../../spikes/p1-t2-bass/tools/bass_deps.json) 固定官方 URL 与压缩包 SHA-256，由 [fetch_bass.py](../../spikes/p1-t2-bass/tools/fetch_bass.py) 在 CI 构建期拉取并校验，不入 Git 仓库：

| 组件 | 实测版本号 | 官方下载包 | 压缩包 SHA-256（已验证） | 用途 |
| --- | --- | --- | --- | --- |
| `bass.xcframework` | `2.4.18.3` (`0x02041203`) | `bass24-ios.zip` | `087bdb8aec6735a8b8de21253e07270f647cfb7bb3e1f276efa7ba979d46836e` | 核心音频输出、Push/Pull 流、Plugin 系统与 CoreAudio 会话 |
| `bassmix.xcframework` | `2.4.13.1` (`0x02040D01`) | `bassmix24-ios.zip` | `06113c77b4ef9af5d8d244e7bd1285899f581ba72d6e6e10c05c14908df1566a` | `BASS_MIXER_QUEUE \| NONSTOP \| POSEX` 同规格无缝混音器 |
| `bassdsd.xcframework` | `2.4.2` | `bassdsd24-ios.zip` | `0a515018478e54a295a22b1999ce785e48440f273611f0d388c0e16b4033efc8` | DSF/DFF 解码、`BASS_DSD_DOP` 载波封装及原生 PCM 转换 |
| `bassflac.xcframework` | `2.4.6.1` | `bassflac24-ios.zip` | `57dd543278b63e75e6ecd236ee0b9afaf5d79e8ad0880a81d565d5d2ed4aed50` | FLAC 解码插件（44.1 ~ 384 kHz） |
| `basswv.xcframework` | `2.4.7.4` | `basswv24-ios.zip` | `a517de1f0adc13b811a077408770d1fb297a7b66fb4f3ce3cadb639a685ec058` | WavPack (`.wv`) 解码插件 |
| `bassape.xcframework` | `2.4.1` | `bassape24-ios.zip` | `21bedf9e4b70bf3a2ac25f1ce93d46ef1a5a4691cc262742dc9dbcaa55527cc7` | Monkey's Audio (`.ape`) 解码插件 |
| `bassopus.xcframework` | `2.4.3.3` | `bassopus24-ios.zip` | `33b44809e9e8aa7a949386213336d0b8fa73652ef058caa63aa7cea5d72c2a96` | Opus (`.opus`) 解码插件 |

**对官方头文件与 Mach-O 二进制的实证勘误（已踩坑并修正）**：
1. `BASS 2.4.18` 中 `BASS_StreamCreateFile` 与 `BASS_DSD_StreamCreateFile` 首参均改为 `DWORD filetype`（`BASS_FILE_NAME = 0`）。
2. `BASSmix 2.4.13` 移除旧版 `BASS_MIXER_NORAMPIN` 等常量，改用 `BASS_MIXER_CHAN_NORAMPIN`、`BASS_MIXER_CHAN_AUTOFREE`、`BASS_MIXER_CHAN_RAMPOUT` 与 `BASS_POS_MIXER_RESET`。
3. 我们反查了官方 `bass*.framework` 的 Mach-O 符号表，证实 5 个插件在真机 `arm64` 与模拟器切片中均在 `__TEXT,__text` 段导出 `BASSFLACplugin` / `BASSDSDplugin` / `BASSWVplugin` / `BASSAPEplugin` / `BASSOPUSplugin` 函数入口（配合 `BASS_PLUGIN_PROC = 1`）。且 CI 初版实测暴露：仅靠字符串 `"bassflac"` 调用 `BASS_PluginLoad` 在模拟器 XCTest 宿主机下返回 0；改为将全部 7 个框架链接入 `OTHER_LDFLAGS`、确保二进制可执行权限 `0755`，并采用 `BASS_PLUGIN_PROC` + `@rpath` + Bundle 路径多级加载并处理 `BASS_ERROR_ALREADY` 后，5 个插件在 Simulator 上全部加载通过。

### 2.2 开源参考项目（LyrPlay）与社区/行业经验筛选

针对 `mtxmiller/LyrPlay`（MIT License）实际源码、`1-bit` 相关 iOS Hi-Res 播放实现与 Un4seen 官方论坛记录进行交叉审查后，采纳与舍弃如下：

| 经验来源 | 真实审查结论 | 本轮工程决策 |
| --- | --- | --- |
| `LyrPlay` (`AudioPlayer.swift` L210, `AudioStreamDecoder.swift` L761) | 保持 `BASS_CONFIG_IOS_SESSION` 默认值，不设置 `BASS_IOS_SESSION_DISABLE`（规避 Topic #20785 路由切换后无声故障）；`AVAudioSession.sharedInstance().setPreferredSampleRate` 可触发 BASS CoreAudio StreamFormat 监听器自动更新 | **已采纳**：默认保留 BASS iOS 会话托管；采样率协商采用「先 `setPreferredSampleRate` + 半程等待，未匹配时回落 `BASS_DEVICE_FREQ \| BASS_DEVICE_REINIT`」，并开放三种策略开关供真机 A/B 对照 |
| `LyrPlay` (`AudioManager.swift` + `PlaybackSessionController.swift`) | 启动仅激活一次 `.playback` 非混音会话解锁 `MPRemoteCommandCenter`；切勿在路由变更回调中调用 `BASS_Free` + `BASS_Init`（iOS 18+ 崩溃风险，仅在 `mediaServicesWereResetNotification` 时重建）；恢复播放前调 `BASS_Start()` | **已采纳**：完整写入 `DacSessionManager.swift` 与 `BassAudioEngine.swift`，并加上 `BASS_ERROR_BUSY` 延迟重试 |
| `LyrPlay` 本地断点与省电机制 | 无流播放/暂停后 `BASS_Pause()` 避免音频线程空耗（Forum #10910） | **已采纳**：暂停与停止空闲 `3s` 后调用 `BASS_Pause()`，任何播控恢复前自动调用 `BASS_Start()` |
| `fidelune_iphone.html` 调研报告中的「音频会话禁用 + 完全自管」及 0.5% 随机测试噪音推断 | 报告部分建议与 Un4seen Topic #20785 冲突，且 `BASSmix` 默认参数未按 2.4.13 核对 | **未盲采**：经 LyrPlay 与 BASS 2.4.18.3 官方头文件验证后予以修正 |
| `1-bit` DAC 播放器实践与 DoP 安全边界 | 强调独立 Signal Path 四层链路可视化（音源 / 引擎 / 会话 / 外部硬件不可读边界）、DoP 下必须禁用系统与引擎音量衰减及 iOS「耳机安全」限幅 | **已采纳**：内建 DoP 四重安全互锁 + 30ms/40ms `0x69` DoP 静音保护帧 + 独立 `SignalPathCard` 明示「物理端系统不可读」 |

---

## 3. 本轮实现范围与架构设计

### 3.1 引擎可替换边界与目录结构

- **零 CocoaPods 洁净 iOS 壳**：沿用 `p1-t1` 无第三方依赖的 Flutter + Swift 原生通信（`MethodChannel` `fidelune/bass_audio` + `EventChannel` `fidelune/bass_events`），构建零 `Pods` 耦合、可完全离线复现（只需 `fetch_bass.py` 拉取 SHA-256 锁定官包）。
- **引擎替换隔离层**（[AudioEngineProtocols.swift](../../spikes/p1-t2-bass/ios/Runner/Audio/AudioEngineProtocols.swift)）：
  - UI、`PlaybackQueueCoordinator`、`DacSessionManager`、`NowPlayingAndRemoteController` 仅依赖 Swift 协议 `AudioPlaybackBackend` / `AudioSessionAdapter` / `DiagnosticsSink`，完全不直接引用 `BASS_*` C API。后续若切换其他解码/输出后端，只需替换实现 `AudioPlaybackBackend` 的类，上层队列、中断状态机、锁屏、验收 UI 无需重写。

### 3.2 原生核心能力清单（代码位置与已实现逻辑）

1. **格式解码与队列管理**（[PlaybackQueueCoordinator.swift](../../spikes/p1-t2-bass/ios/Runner/Audio/PlaybackQueueCoordinator.swift)）：
   - 支持 FLAC / WAV / ALAC (M4A) / WavPack (`.wv`) / APE / Opus / MP3 / AAC / DSF / DFF，含内嵌测试曲库与 iOS「文件」目录 `Music/` 用户自导入扫描。
   - 完整播放控制：播放、暂停、继续、停止、上一首（>3s 回曲首）、下一首、Seek、列表顺序/单曲循环/列表循环/随机四种模式、断点曲目与精确秒数持久化。
   - **坏文件防死循环熔断**：连续失败计数器在队列全部文件均无法打开/解码后立即停止并报错，且仅在真正推进播放 `>= 0.5s`、无缝切曲或自然播完后清零（已通过 `testConsecutiveCorruptTracksStopCleanlyWithoutInfiniteLoop`）。
2. **Bit-perfect 信号路径、同规格无缝与跨规格切换**（[BassAudioEngine.swift](../../spikes/p1-t2-bass/ios/Runner/Audio/BassAudioEngine.swift)）：
   - PCM 路径以 `BASS_SAMPLE_FLOAT | BASS_MIXER_QUEUE | BASS_MIXER_NONSTOP | BASS_MIXER_POSEX` 创建不重采样的 Float32 `BASSmix` 混音器，单通道采用 `BASS_MIXER_CHAN_NORAMPIN | BASS_MIXER_CHAN_AUTOFREE`，混音器增益锁定 `1.0`；兼容判定规则严格限定 **采样率 + 声道数 + 非 DSD** 一致方可使用 `BASS_MIXER_QUEUE` 队列无缝，跨规格（如 `44.1 → 96 kHz`、立体声 → 单声道、PCM ↔ DoP）绝不插入软件 SRC 强行无缝，而是先重配置采样率并留出可配置硬件锁相稳定窗（默认 `180 ms`）。
   - `BASS_SYNC_FREE | BASS_SYNC_ONETIME` 安全回收 `SyncContext`，`BASS_SYNC_END | BASS_SYNC_ONETIME` 在真实听觉播完时触发无缝/完播切曲（消除预解码超前切曲提示误差）。
3. **全场景防爆音保护**：
   - PCM 暂停、Seek、手动切歌使用短时长软件微淡入淡出（默认 `15 ms`，可调 `0~40 ms`）；同时为满足严格无损起播首样值对比，可通过设置项 `BASS_ATTRIB_NORAMP` 控制自然起播（且 `BASSmix` 源默认带 `BASS_MIXER_CHAN_NORAMPIN`）。
   - DoP 下强制禁用 `BASS_ATTRIB_NORAMP = 1` 与 `BASS_ATTRIB_DOWNMIX = 0`。
4. **DSD / DoP 封装与四重安全互锁**（[DopPassthroughStream.swift](../../spikes/p1-t2-bass/ios/Runner/Audio/DopPassthroughStream.swift)、[DacSessionManager.swift](../../spikes/p1-t2-bass/ios/Runner/Audio/DacSessionManager.swift)）：
   - 自定义 Float32 `STREAMPROC`，前置 `BASSDSD` 开启 `BASS_DSD_DOP | BASS_SAMPLE_FLOAT | BASS_STREAM_DECODE`（及直通预封装 24-bit DoP WAV），启停/Seek 自动注入与延续 `0x05 / 0xFA` + `0x69` DoP 静音保护帧，并做跨静音边界奇偶标记对齐校验。
   - 四重互锁缺一不可：`USBAudio` 路由 + `outputVolume >= 99.9%` + 前端 DoP 安全弹窗三项勾选确认 + `carrierHz <= 768 kHz`。播放 DoP 期间通过 KVO 实时监听 `AVAudioSession.outputVolume`，一旦低于 `99.9%` 立即硬停报错防止高频白噪输出；在「自动」模式下，非 USB 路由自动安全转为 PCM 解码并在信号链路上明确标示 `DSD → PCM`。
5. **路由切换、后台播控与中断恢复**（[NowPlayingAndRemoteController.swift](../../spikes/p1-t2-bass/ios/Runner/Audio/NowPlayingAndRemoteController.swift)）：
   - `AVAudioSession.routeChangeNotification`（`.oldDeviceUnavailable` 拔出 DAC 瞬间秒停防外放，并置 `pausedForRouteRemoval = true` 屏蔽后续过期系统恢复信号）、`.newDeviceAvailable` 更新 `DacCapabilityProfile`；`interruptionNotification` 区分来电/计时器打断，保留原暂停态不误自动起播，并同步更新 `MPNowPlayingInfoCenter` 与 `MPRemoteCommandCenter`（含进度条 Seek）。
6. **对人友好的集中验收界面与全链路展示**（[lib/](../../spikes/p1-t2-bass/lib/)）：
   - 顶部「一键运行 9 项自动校验」先行过滤底层二进制故障；手工部分按 **扬声器与防爆音 (`H1~H3`) → USB DAC 采样率 (`D1~D2`) → DSD/DoP 安全受控 (`P1~P3`) → 热插拔/后台/中断 (`R1~R3`)** 共 11 项分步引导。
   - 每项均给出前置硬件检查提示、操作步骤、明确通过标准、一键「启动本项测试音频」、常见失败标签快选、备注、重试计数、断点保存，以及 `D1` 专属 `44.1 ~ 384 kHz` DAC 面板读数逐档点选器。
   - 内建实时 `SignalPathCard`、单频点静默 DAC 采样率握手探测页、策略调优滑块与 Markdown / JSON / JSONL + 24-bit 回读 WAV 一键导出页。

---

## 4. 自动化验证实测结果

以下结果全部来自本轮实际执行的本地单元测试、[GitHub Actions Run #45983078555 (Build #6)](https://github.com/SCUTLZH684/Fidelune/actions/runs/45983078555) 以及黑屏修复后的 **[GitHub Actions Run #45998526234 (Build #7)](https://github.com/SCUTLZH684/Fidelune/actions/runs/45998526234)**（无一跳测、无放松断言）：

### 4.1 样本生成与 Python 校验工具（已通过）
- **`python3 tools/fixtures.py`**（CI Step 5，`macos-26` + Homebrew `ffmpeg`）：
  - 生成并逐文件用 `ffprobe` 与无损解码字节比对校验测试音源套件：FLAC 阶梯（`44.1 / 48 / 88.2 / 96 / 176.4 / 192 / 384 kHz`，含 >192kHz `-strict -2`）、`wav16`、`wav24`、`mono24`、`alac96.m4a`、`wv96.wv`、`opus48.opus`、`lossy.mp3`、`lossy.aac`、`poptest-a/b.flac`、`short.wav`、`silence-edge.wav`、44.1kHz 非零采样边界 `gap-a/b.wav + continuous.wav`、96kHz 24-bit 无缝对 `gap96-a/b.flac + continuous96.flac`、截断/损坏 FLAC（`truncated.flac`、`invalid.flac`、`invalid-2.flac`）、`dsd64.dsf`、`dop64.wav`、`dsd128.dsf`。
  - 全部无损样本均通过 FFmpeg 解回 Raw PCM 与源缓冲区逐字节一致断言，DoP 载波通过 `0x05`/`0xFA` 位反转还原 DSD 字节断言。
- **`python -m unittest discover -s spikes/p1-t2-bass/tools -v`**（本地 Windows Python 3.14 & CI Step 5 均运行通过）：
  - `Ran 2 tests ... OK`（覆盖 7 个 BASS manifest 完整性与 `compare_pcm.py` 零误差正对照、1-bit LSB 篡改负对照、5 帧零插帧负对照）。

### 4.2 Flutter 静态分析与控件/状态测试（已通过）
- **CI Step 6**（Flutter `3.44.0` / Dart `3.12.0`，锁定 `pubspec.lock`）：
  - `flutter pub get --enforce-lockfile`：通过
  - `flutter analyze --no-pub`：0 issues（通过）
  - `flutter test --no-pub`（[acceptance_and_ui_test.dart](../../spikes/p1-t2-bass/test/acceptance_and_ui_test.dart)）：4 项测试全过（控制器重试与 JSON 断点持久化、`DopSafetyDialog` 门禁解锁逻辑、`SignalPathCard` 重采样与硬件不可读告警、`FideluneBassApp` 导航及 H1 端到端 UI 状态流）。

### 4.3 Swift XCTests 与真实 BASS 二进制 iOS Simulator 自检（7 项 XCTest + 9 项机内检查全过）
- **CI Step 7**（Xcode `26.3`, iOS SDK `26.2`, `xcodebuild test -destination "platform=iOS Simulator,..." -only-testing:RunnerTests`）：
  - `RunnerTests`（1 test）：passed (`0.001s`)
  - `BassAudioEngineTests`（6 tests）：`Executed 6 tests, with 0 failures (0 unexpected) in 2.496 (2.498) seconds`
    1. `testGaplessCompatibilityRules`：同频/同声道兼容判定、跨频/跨声道/DoP 隔离判定、DoP 载波频计算
    2. `testDopSilenceFrameCodecParity`：`0x69` DoP 静音帧 Float32 封包与标记还原校验
    3. `testDopSafetyInterlocks`：扬声器拦截、音量 <100% 拦截、未勾选拦截、DSD512 拦截、合法 USB+100% 放行
    4. `testRouteRemovalClearsStaleInterruptionAndPauses`：`oldDeviceUnavailable` 拔出瞬间暂停 + 阻止后续 `shouldResume` 误拉起
    5. `testConsecutiveCorruptTracksStopCleanlyWithoutInfiniteLoop`：队列全部损坏下 `repeatAll` 熔断停止不死循环
    6. **`testRealBassSelfTestsAgainstBundledFixtures`**（对随包生成音源运行 [BassSelfTestRunner.swift](../../spikes/p1-t2-bass/ios/Runner/Audio/BassSelfTestRunner.swift) 全部 9 项真实 Un4seen BASS iOS Simulator 二进制检测，9/9 通过）：
       - `auto_bass_init`：`BASS 0x02041203` + `BASSmix 0x02040D01` + `bassflac` / `bassdsd` / `basswv` / `bassape` / `bassopus` 全部插件加载成功
       - `auto_format_decode`：全套正常/高采样率/DSD 音频打开、`BASS_ChannelGetInfo` 与解码读取全部通过
       - `auto_pcm24_bitexact`：`wav24.wav`（48kHz/24-bit）经 `BASSmix` Float32 管线还原 24-bit PCM 后 SHA-256 与源件完全一致
       - `auto_flac24_bitexact`：`flac192000.flac`（192kHz/24-bit）经 `BASSFLAC + BASSmix` 解码输出还原后 SHA-256 与源件完全一致
       - `auto_gapless_44k`：`gap-a.wav + gap-b.wav`（第 44,137 帧非零切割）经 `BASS_MIXER_QUEUE` 拼接后 0 帧插入/丢失，SHA-256 与 `continuous.wav` 完全一致
       - `auto_gapless_96k`：`gap96-a.flac + gap96-b.flac`（第 96,037 帧非零切割）经 `BASS_MIXER_QUEUE` 拼接后 0 帧插入/丢失，SHA-256 与 `continuous96.flac` 完全一致
       - `auto_dop_dsd64`：`dsd64.dsf` 经 `BASS_DSD_DOP` 解码验证 176.4 kHz 载波、2.8224 MHz DSD 速率、全段每帧 `0x05`/`0xFA` 严格交替（0 错误）+ `0x69` 静音帧校验
       - `auto_dop_dsd128`：`dsd128.dsf` 经 `BASS_DSD_DOP` 验证 352.8 kHz 载波、5.6448 MHz DSD 速率、全段 `0x05`/`0xFA` 严格交替（0 错误）
       - `auto_corrupt_resilience`：`invalid.flac` / `invalid-2.flac` 安全拒绝，`truncated.flac` 解码至有效尾后安全结束不崩溃
  >注：在 headless GitHub CI iOS Simulator 环境下，`BassAudioEngine.initialize()` 具备仅在 `#if targetEnvironment(simulator)` 下触发的 Device `0`（No sound）与 `BASS_ERROR_ALREADY` 兼容回退，真实硬件 `#if !targetEnvironment(simulator)` 不启用无声回退。

### 4.4 Unsigned Release IPA 与符号产物校验（Build #7 已通过）
- **CI Steps 8–10**（Run `#45998526234` / `macos26 20261117.0516.1` / `macOS 26.7.2` `arm64` / `Xcode 26.3 17C529` / iOS SDK `26.2`）：
  - `Runner.app` 无 `embedded.mobileprovision`、未预先代码签名、`lipo -archs` 为纯 `arm64`、`CFBundleIdentifier = io.github.scutlzh684.fideluneBass`、`CFBundleVersion = 7`、`MinimumOSVersion = 15.0`。
  - `UIApplicationSceneManifest.UISceneConfigurations.UIWindowSceneSessionRoleApplication[0].UISceneDelegateClassName = Runner.SceneDelegate`（CI 步骤 `plutil` 强制校验通过，本地解密 IPA `plistlib` 解析复核通过）。
  - `UIBackgroundModes[0] = audio`、`UIFileSharingEnabled = true`、`LSSupportsOpeningDocumentsInPlace = true`。
  - 7 个 BASS 动态框架全部嵌入 `Runner.app/Frameworks/` 且二进制 `lipo -archs` 为纯 `arm64`，本地解密 IPA 实测 SHA-256 与 `build-info.txt` 逐一匹配：
    - `bass`: `649535eb220d8f3e81a4d13a8b9bd5c4be85dcc55121dbb3245e1fa3c77fb898`
    - `bassmix`: `73e936fc8d79e9334cca936cfee3cf87743795e65272fbdef20329f1e66efe9d`
    - `bassdsd`: `354ccbe7c265755a7906f8474db8d0b38b8e5dd2df48817f2f1f2b63195671de`
    - `bassflac`: `d8efbca7ebceb54c5d6eb14b584ce931c1758163834e4c61d6bd27a7dbfac5aa`
    - `basswv`: `0a8cd1702c75981a122ac1c28b400ade2658d10fc8ee8e3c7497939e78118115`
    - `bassape`: `675eb704094160aa53740a608bef8ca4d4f9d49b4f73db505fde8e55d20ee53c`
    - `bassopus`: `61a27fa4930d9f52e213f82f725dfdc2a01bb5e7ae7b901dc63674312072cf6f`
  - `Runner` 与 `Runner.app.dSYM` UUID 精确匹配：`35D2606B-DD7F-37C6-A66D-0125689FA037`。
  - 本地解密包校验通过（`zipfile.testzip() is None`）：
    - `fidelune-bass-unsigned.ipa`：`19,381,129` 字节，SHA-256 `5b0fd7e640c8ed0fafedf2dfb0c4b1cd50c8eedb9bce04e63642aae622d000d6`
    - `fidelune-bass-dsyms.zip`：`39,160,171` 字节，SHA-256 `dd4fd22b6cb8e7e7827e02d5bae0373c86a8d482cd0a6ad8e7578f425bc9a7c1`
  - 已加密上传为 **`p1-t2-bass-ios-7`**，并复制验证通过的 IPA 至桌面 `C:\Users\l\OneDrive\Desktop\Fidelune-BASS-Build7.ipa`。

### 4.5 Build #6 真机黑屏根因定位（iPhone 17 / iOS 27.2.1）与 Build #7 修复详情
- **真机故障现象**：Build #6 通过 Sideloadly 安装到 iPhone 17（`iPhone18,3`，iOS `27.2.1`，Build `24B156`）后持续黑屏超过 60 秒（重装可稳定复现）。
- **真机实测证据采集**（通过 USB `usbmuxd` + `pymobiledevice3` 采集并留档于 `%LOCALAPPDATA%\Fidelune\P1-T2-BASS\device\build-6\`）：
  1. **`InstallationProxy` 应用配置快照（`user-apps.json`）**：设备上已安装 `io.github.scutlzh684.fideluneBass.YVH7RXG9RB`（`Fidelune BASS` `0.2.0` Build `6`）中，`UIApplicationSceneManifest.UISceneConfigurations.UIWindowSceneSessionRoleApplication[0].UISceneDelegateClassName` 被编译为了非法类名 **`".SceneDelegate"`**（模块名前缀为空，而可正常显示画面的 `P1-T1` 与原 `P1-T2` 均为 `"Runner.SceneDelegate"`）。
  2. **`HouseArrest` 应用沙盒启动日志（`fidelune-bass-diagnostics.jsonl`，808 字节）**：真实记录启动时刻在 **10 ms** 内相继输出两条日志：
     - `2026-11-27T12:04:29.482Z`：`session-startup-activated`（`route: "Speaker"`, `sampleRateHz: 48000`）
     - `2026-11-27T12:04:29.492Z`：`bass-initialized`（`bassVersion: "0x02041203"`, `bassMixVersion: "0x02040D01"`, `deviceRateHz: 48000`, `initCode: 0`, `missingPlugins: []`, `plugins: ["bassape","bassdsd","bassflac","bassopus","basswv"]`）
  3. **`CrashReports` 崩溃目录列表（`crash-ls.txt`）**：`2026-11-27` 当天无任何 `Runner` / `Fidelune BASS` 崩溃报告。
- **定位结论**：7 个 BASS 动态框架及全部 5 个解码插件在真机 iOS 27.2.1 上已被 Sideloadly 正确重签加载并快速完成初始化，**根本原因**是 [Info.plist](../../spikes/p1-t2-bass/ios/Runner/Info.plist#L51) 将 `UISceneDelegateClassName` 误写为 `$(PRODUCT_BUNDLE_NAME).SceneDelegate`（构建解析为空前缀 `.SceneDelegate`），导致 UIKit 启动时无法实例化继承自 `FlutterSceneDelegate` 的 `Runner.SceneDelegate` 来创建并呈现 `UIWindow`，进程保持存活但页面永久黑屏。
- **Build #7 修复清单（Commit `035186f9fe44ab4161d8db9c751f13a6b4fd0d4e`，未禁用任何核心音频能力）**：
  1. [Info.plist](../../spikes/p1-t2-bass/ios/Runner/Info.plist#L51)：将 `UISceneDelegateClassName` 修正为 `$(PRODUCT_MODULE_NAME).SceneDelegate`。
  2. [AppDelegate.swift](../../spikes/p1-t2-bass/ios/Runner/AppDelegate.swift#L21-L60) 与 [PlaybackQueueCoordinator.swift](../../spikes/p1-t2-bass/ios/Runner/Audio/PlaybackQueueCoordinator.swift#L42-L71)：补充 `app-launch` 生命周期日志、新增 `fixturesLock` 保护 `stageBundledFixtures()`、新增 `initLock` 串行化 `initializeEngine()`，并将启动期 `coordinator.initializeEngine()` 预热移至 `DispatchQueue.global(qos: .userInitiated).async` 后台执行，确保不阻塞主线程与首帧渲染。
  3. [main.dart](../../spikes/p1-t2-bass/lib/main.dart#L75-L98)：为 `_bootstrap()` 补充 20 秒超时、`try/catch` 异常捕获及失败重试横幅（`MaterialBanner`），避免异常卡在白/黑屏或加载态。
  4. [p1-t2-bass-ios.yml](../../.github/workflows/p1-t2-bass-ios.yml#L139)：在 CI 归档校验步骤新增 `plutil` 强制断言 `UISceneDelegateClassName = Runner.SceneDelegate`。

---

## 5. 尚未验证的能力清单（必须依赖真机与物理外设）

严格遵循实事求是不夸大原则：**以下能力尚未在 iPhone 17（iOS 27.2.1）与 TOPPING DX5 II 物理硬件上实际运行与观察，编译通过、XCTest 与 BASSmix/FFmpeg 数字回环通过均不代表物理端到端已通过**：

1. **Build #7 真机 UI 首帧与集中验收界面展示**：
   - 桌面 `Fidelune-BASS-Build7.ipa` 已验证内含 `UISceneDelegateClassName = "Runner.SceneDelegate"`，但尚未在物理 iPhone 17 上侧载运行以确认首屏正常渲染及无黑屏。
2. **端到端物理 USB DAC 原采样率输出与硬件 Bit-perfect**：
   - `flac44100` ~ `flac384000`（特别是 88.2 / 176.4 / 352.8 / 384 kHz）在连接 TOPPING DX5 II 后，iOS `AVAudioSession.setPreferredSampleRate` 与 `BASS_DEVICE_FREQ | BASS_DEVICE_REINIT` 实际协同效果、DAC 前面板实显采样率读数、以及苹果 CoreAudio USB 驱动在特定采样率下是否发生隐式位深截取或限幅，**必须以真机 `D1`/`D2` 及后续外部数字抓取（如 RME/SPDIF 环回比对）为准**。
3. **物理 DAC DoP DSD64 / DSD128 点灯与纯音听感**：
   - 尽管 BASSDSD 载波 `0x05`/`0xFA` 标记已在 Simulator 二进制层面验证 0 错误，但 iPhone USB Audio 输出路径是否完整保留最低 24-bit 无衰减/无 dither/无限幅、以及 TOPPING DX5 II 是否能真正锁定并点亮 DSD64 / DSD128（`P1`/`P2`），**待真机低音量安全门禁下实测**。
4. **真机扬声器与 USB DAC 实际听感防爆音**：
   - `15 ms` 软淡入淡出、`180 ms` 跨规格稳态静音窗、以及 `40 ms` `0x69` DoP 前后护帧在实际耳机/音箱上的听感是否完全消除“啪/咔”脉冲，**待 `H1` / `D2` / `P2` 真机听审**。
5. **物理 USB 热插拔、蓝牙路由与真实来电/闹钟中断**：
   - `R1` / `R3` 仅在单元测试用模拟通知验证过逻辑状态机；真机拔插瞬时无外放、重新插回 DX5 II 后采样率重协商稳定性、以及蓝牙耳机路由与真实系统电话/闹钟打断恢复，**待真机 `R1~R3` 与长跑稳定性验收**。

*(注：Build #6 真机 `HouseArrest` 日志已实证 Sideloadly 对 7 个未签名纯 `arm64` `.framework` 的递归重签与 `BASS 0x02041203` / 全部 5 个插件初始化可在 iPhone 17 iOS 27.2.1 正常完成，耗时 10 ms。)*

---

## 6. 已知风险与关键技术决策记录

### 6.1 已识别风险
1. **Un4seen BASS 商业授权与开源协议兼容性**：BASS 为闭源商业软件，个人非盈利免费，商业或含内购/广告分发前需向 Un4seen 购买对应 iOS 授权（且与纯 GPLv2/v3 代码不兼容）。当前仓库通过 Git 隔离、编译期拉取、QA 公钥加密产物与 Swift 协议抽象将后续替换或商业转签风险降至最低。
2. **iOS 系统「耳机安全 / 音量限幅」破坏 DoP（高危听力/硬件风险）**：iOS 检测到 USB 设备且默认归类为「耳机」或系统音量未满 100% 时，系统级 DSP 会篡改 PCM 低位导致 DoP 变成刺耳白噪。工程已在软件层增加 **非 USB 禁播 DoP + 音量 < 99.9% 硬截断与 KVO 看门狗 + 三项安全勾选框**，仍需操作者在 iOS 系统设置手动设为「其他设备」并将耳放调到低音量。
3. **iOS 公共 API 对物理端能力的不可知边界**：iOS `AVAudioSession` 无法枚举外接 DAC 支持采样率清单（需单频点试探），也无法回读最终发送给 DAC 的物理有效位深或 DSD 锁相状态。所有 UI 展示与报告已明确区分「音源实测 / 引擎观测 / 会话实读 / 外设不可读」。
4. **Sideloadly 多框架重签风险（Build #6 已部分消解）**：Build #6 真机 `fidelune-bass-diagnostics.jsonl` 已实证 Sideloadly 签装后 7 个框架可在 iOS 27.2.1 全部正常动态加载并完成 `BASS_Init` 与 5 插件初始化；Build #7 修复 `UISceneDelegateClassName` 后需在首次打开时确认 UI 渲染正常即可。

### 6.2 关键技术决策摘要
- **为什么选择「混合采样率策略」为默认选项**：LyrPlay 实测已证明在 iOS 上优先调 `AVAudioSession.setPreferredSampleRate` 可避免不必要重建；但不同 USB DAC 芯片响应时间差异较大，若 `AVAudioSession.sampleRate` 或 `BASS_INFO.freq` 在半程稳态后仍未对齐目标频率，混合策略才安全兜底触发 `BASS_DEVICE_FREQ | BASS_DEVICE_REINIT`（且 UI 保留策略切换滑块，方便真机如实排查是否出现回落重采样或短爆音）。
- **为什么同规格无缝用 `BASSmix` 而跨规格禁止强行无缝**：不同采样率混音必然引入 SRC（与 Bit-perfect 目标背道而驰）。工程将同采样率/同声道 PCM 路由给单频固定 `BASS_MIXER_QUEUE` 实现真正 0 帧差无缝；一旦下首采样率、声道或 DoP 状态变化，显式在播完边界停机重锁，用可控的硬件重配置窗口换取 100% 原采样率透传。
- **为什么放弃 `P1-T2` 原方案的随机噪声单跑脚本架构**：面向人类真机集中验收重构了视觉层级、进度记忆、失败快选标签、安全弹窗与报告/JSONL 导出体系，使 11 项手工验收一次上机可按优先级顺序推进并断点续测。
