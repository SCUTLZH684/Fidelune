# Fidelune P1-T2-BASS：iOS BASS 音频引擎、DAC 管理与集中验收套件

> 本目录是 **Fidelune 基于 Un4seen BASS 官方组件构建的完整 iOS Hi-Res 音频架构、USB DAC 会话管理与真机可视化集中验收应用**。
> 原先的 `libmpv` 实验目录 [spikes/p1-t2/](../p1-t2/) 与工作流 [p1-t2-ios.yml](../../.github/workflows/p1-t2-ios.yml) 保持完全不动。

## 1. 交付架构总览

- **原生引擎层**（`ios/Runner/Audio/`）：
  - `AudioEngineProtocols.swift`：独立于 BASS 的 Swift 协议边界（`AudioPlaybackBackend`、`DacSessionManaging`、`AudioEngineControlling`、`DiagnosticsSink`），隔离后续引擎替换成本。
  - `BassAudioEngine.swift`：BASS `2.4.18.3` + `BASSmix 2.4.13.1` + `BASSDSD 2.4.2` + `BASSFLAC` / `BASSWV` / `BASSAPE` / `BASSOPUS` 插件架构：
    - PCM 路径：`BASS_MIXER_QUEUE | BASS_MIXER_NONSTOP | BASS_MIXER_POSEX` + `BASS_MIXER_CHAN_NORAMPIN`，实现同采样率/声道真无缝拼接与 `15 ms` 软淡入淡出防爆音。
    - DoP 路径：`DopPassthroughStream.swift` 自定义 Float32 `STREAMPROC`，前置 `BASSDSD 2.4.2` 启用 `BASS_DSD_DOP`、前后 `0x05`/`0xFA` + `0x69` DoP 静音保护帧与逐帧标记位校对，`BASS_ATTRIB_NORAMP = 1`、`BASS_ATTRIB_DOWNMIX = 0`。
    - 安全暂停与休眠：切暂停/空闲 `3s` 后调用 `BASS_Pause()` 节能，恢复/切歌前调用 `BASS_Start()`。
  - `DacSessionManager.swift`：参考 `mtxmiller/LyrPlay` MIT 实测经验与 BASS 论坛规则：
    - 保持 `BASS_CONFIG_IOS_SESSION` 默认值（避免禁用会话管理引起路由切换无声）。
    - `AVAudioSession.sharedInstance()` 仅初始化激活一次 `.playback`（非混音），确保持续注册锁屏/控制中心。
    - 采样率采用混合协商：优先 `AVAudioSession.setPreferredSampleRate`（触发 BASS CoreAudio 监听器跟随），仅当 `BASS_INFO.freq` 未跟随或用户选择「强制 BASS 重建」时执行 `BASS_Init(..., BASS_DEVICE_FREQ | BASS_DEVICE_REINIT)`。
    - DoP 四重安全互锁：USB DAC 路由 + 系统音量 ≥ `99.9%`（KVO 实时看门狗拦截）+ 用户安全确认 + `carrierHz <= 768 kHz`。
  - `BassSelfTestRunner.swift`：9 项真 BASS 二进制机内/CI 自动校验（含 24-bit WAV / 192 kHz FLAC `BASSmix` 位精确 SHA-256、44.1 kHz / 96 kHz 0 帧误差真无缝边界、DSD64 / DSD128 DoP `0x05`/`0xFA` 标记核验、坏文件防崩溃等）。
  - `DiagnosticsLogger.swift`：输出应用内环形缓冲 + **「文件 → 我的 iPhone → Fidelune BASS」** 持久化日志 `p1t2-bass-evidence.jsonl` 与完整诊断导出包。
- **前端可视化验收与播放器层**（`lib/`）：
  - **集中验收页**：机器自动体检栏 + 四大分组 `H1~H3`、`D1~D2`、`P1~P3`、`R1~R3`，含步骤引导、通过标准、一键「启动测试音频」、失败原因标签、笔记与断点本地持久化。
  - **测试曲库页**：展示全部内置音频规格与直接单曲点播、采样率切换策略（混合/仅偏好/BASS 重建）、DSD 输出模式选择与硬件防爆音淡入时长调节。
  - **DAC / 路由监控页**：实时采样率协商追踪、设备端口状态与完整实时音频链路卡（Signal Path）。
  - **报告与日志导出页**：导出 JSON / Markdown 验收报告与 JSONL 证据日志至 iOS「文件」App 并支持一键复制汇总。

---

## 2. 下载、解密与 Sideloadly 安装指南（Windows）

### 步骤 A：下载云构建加密制品
1. 打开 GitHub Actions 工作流：[P1-T2 BASS unsigned iOS build & test](https://github.com/SCUTLZH684/Fidelune/actions/workflows/p1-t2-bass-ios.yml)。
2. 进入对应最新绿色构建，下载 Artifact：`p1-t2-bass-ios-<构建号>`。
3. 解压到本地目录（例如 `%LOCALAPPDATA%\Fidelune\P1-T2-BASS\build-<构建号>`）。

### 步骤 B：解密 IPA 并核对 SHA-256
使用本机已有 QA 私钥（`%LOCALAPPDATA%\Fidelune\P1-T2\qa-artifact-key.pem`）与 Git 自带 OpenSSL 解密：

```powershell
$keyFile = Join-Path $env:LOCALAPPDATA 'Fidelune\P1-T2\qa-artifact-key.pem'
$openssl = 'C:\Program Files\Git\usr\bin\openssl.exe'
$buildDir = Join-Path $env:LOCALAPPDATA 'Fidelune\P1-T2-BASS\build-<构建号>'
Set-Location $buildDir

& $openssl cms -decrypt -binary -inform DER `
  -in .\fidelune-bass-unsigned.ipa.cms `
  -inkey $keyFile `
  -out .\fidelune-bass-unsigned.ipa

Get-FileHash -Algorithm SHA256 .\fidelune-bass-unsigned.ipa
Select-String -Path .\build-info.txt -Pattern 'fidelune-bass-unsigned.ipa'
```

确认输出哈希与 `build-info.txt` 完全一致。

### 步骤 C：使用 Sideloadly 免费 Apple ID 安装到 iPhone
1. 通过 USB 数据线将 iPhone 连接 Windows 电脑并解锁屏幕「信任此电脑」。
2. 打开 **Sideloadly**，拖入解密后的 `fidelune-bass-unsigned.ipa`。
3. 保持默认 Bundle ID（`io.github.scutlzh684.fideluneBass`）与免费个人签名模式，点击 **Start** 安装。
4. 安装后在 iPhone 打开 **设置 → 通用 → VPN 与设备管理**，信任你的 Apple ID 开发者证书。
5. 首次启动 App 后，界面顶部的 **「自动化引擎与位精确自检（9 项）」** 会先自动跑完真实 BASS 二进制核验，无需人工介入。

---

## 3. DoP 测试前的硬件与 iOS 安全设置

在运行 `P1` / `P2` DoP 测试前，请**务必按顺序完成以下设置**（防止 DoP 流因系统限幅/数字衰减变成全幅度高频白噪损坏听力或耳机）：
1. **调低耳放物理音量**：先将 **TOPPING DX5 II** 或耳放监听音量旋钮调到极低档（例如 `-40 dB` 以下）。
2. **关闭 iOS 耳机安全限幅**：进入 iPhone **设置 → 声音与触感反馈 → 耳机安全 → USB 音频配件**，将连接设备类型设为 **「其他设备」**（切勿设为「耳机」，否则 iOS 会触发耳机音量限幅修改数字样值）。
3. **调满 iPhone 音量**：将 iPhone 侧边音量调至 **100%**（App 内 DoP 门禁会自动实时校验，低于 `99.9%` 会立即拦截并停止输出）。

---

## 4. 真机验收项目概览

| 编号 | 分组 | 核心验收点 |
| --- | --- | --- |
| **H1** | 扬声器与防爆音 | `poptest-a/b` 纯音下暂停、继续、拖动 Seek、手动切歌零脉冲爆音 |
| **H2** | 扬声器与防爆音 | `gap-a → gap-b` 同规格 44.1 kHz 真无缝对比 `continuous.wav` |
| **H3** | 扬声器与防爆音 | ALAC / WAV / WavPack / Opus / MP3 / AAC 播放与双坏文件 + 截断文件自动跳过 |
| **D1** | USB DAC 原采样率 | DX5 II 连接下 `44.1 / 48 / 88.2 / 96 / 176.4 / 192 / 384 kHz` 逐档核对 |
| **D2** | USB DAC 混合规格 | `96 kHz` 同规格无缝 + `192→48 kHz` 16/24-bit 与单声道跨规格切换 |
| **P1** | DSD / DoP 安全受控 | `dsd64.dsf` 点亮 DX5 II `DSD 2.82M / DSD64`，平稳纯音无白噪 |
| **P2** | DSD / DoP 安全受控 | `PCM 44.1 → DSD64 → DSD128 (5.64M) → PCM 96` 互相安全切换 |
| **P3** | DSD / DoP 安全受控 | 低音量拦截 DoP + 非 USB 路由下安全自动降级 `DSD → PCM` |
| **R1** | 热插拔、路由与中断 | 播放中拔掉 DAC 秒停防外放，插回后恢复原采样率续播 |
| **R2** | 热插拔、路由与中断 | 退后台 + 锁屏连续播放与锁屏控制双向同步 |
| **R3** | 热插拔、路由与中断 | 10 秒计时器 / 来电中断暂停与允许后恢复续播 |

---

## 5. 回收验收报告与诊断日志

验收结束后（或在任一测试项出现问题时）：
1. 在 App 顶部切换至 **「报告导出」** 标签页，点击 **「导出 JSON/Markdown 报告与 JSONL 日志」**。
2. 在 iPhone 的 **「文件」App → 浏览 → 我的 iPhone → Fidelune BASS** 中找到：
   - `p1t2-bass-evidence.jsonl`（全量实时诊断事件流）
   - `fidelune-acceptance-report-*.json`（结构化结果与每项失败标签/备注）
   - `fidelune-acceptance-report-*.md`（可读版验收报告）
3. 也可在连接 USB 调试电脑时实时抓取系统日志：
   ```powershell
   python -m pymobiledevice3 syslog live --process-name Runner --match FIDELUNE_BASS
   ```
4. 本地离线校验工具单元与 PCM 比较器：
   ```powershell
   python -m unittest discover -s spikes/p1-t2-bass/tools -v
   ```
