# Fidelune P1-T2 iOS 音频验证

验证报告见[阶段 1 实测报告](../../docs/verification/PHASE1_POC_REPORT.md)。工程用原版 media_kit/libmpv 解码与输出。Swift 桥接读取 iOS 会话、转发系统控制并保存诊断。首跑使用包内原始输出配置，保持默认 gapless，不请求固定采样率。

## 签装

1. 在 Windows 从 [P1-T2 Actions](https://github.com/SCUTLZH684/Fidelune/actions/workflows/p1-t2-ios.yml) 下载对应构建。解包、解密后，用 `Get-FileHash` 比对 IPA 的 SHA-256 与 `build-info.txt`。保留构建号及对应符号。
2. 用 P1-T1 的 Sideloadly、免费 Apple 账号、默认 Bundle ID 和 USB 安装 IPA。连接并解锁 iPhone，打开 **Fidelune P1-T2**。等「选择测试组」出现。
3. 打开 USB 诊断，命令见下文。DAC 和电脑都需要接同一手机时，使用已验证的 USB 集线器，或在测试后接回电脑读取文件。连接 DAC 后先调低 DX5 II 或耳放的监听音量。做 DoP 对照时保留引擎 100% 音量，若 iPhone 的 USB 路由允许数字音量控制，使用其满刻度并记录。监听音量继续由 DX5 II 或耳放控制。

公开 CI 的 IPA 和符号使用 QA 公钥加密，供本机签装验证。使用对应本机私钥运行以下命令。私钥及解密后的制品保存在本机 QA 目录。

```powershell
$probeDir = Join-Path $env:LOCALAPPDATA 'Fidelune\P1-T2'
$openssl = 'C:\Program Files\Git\usr\bin\openssl.exe'
& $openssl cms -decrypt -binary -inform DER -in fidelune-p1t2-unsigned.ipa.cms `
  -inkey (Join-Path $probeDir 'qa-artifact-key.pem') -out fidelune-p1t2-unsigned.ipa
Get-FileHash -Algorithm SHA256 .\fidelune-p1t2-unsigned.ipa
```

## 真机最短操作

保持初始设置「gapless 原版默认」及 DSD 直通请求关闭。每组有问题时，点「记取证点」，记下轨名及现象。手机录屏可记录界面时间，DAC 显示可用另一台设备拍屏或手记。系统静音间隔、实际 DAC 模式和听感分别记录。

| ID | 操作 | 判断标准 |
| --- | --- | --- |
| A1 | 接 DX5 II，选 USB 输入。点「FLAC 阶梯」，让六首自动播完，按顺序记 DAC 每首显示。 | FLAC 解码与引擎输出按曲对照 44.1、48、88.2、96、176.4、192 kHz。DAC 逐首显示 PCM 及对应采样率。每段有声，过渡无爆音。实际位深与样值单独核验。 |
| A2 | 点「混合规格」让其自动播完。再点一次，快按三下「下一首」，点「随机」「跳到中点」「播放 / 暂停」两次。 | 自动和手动换曲都核对轨名、解码、引擎、会话与 DAC。44.1→96→192→48 后，同为 48 kHz 的 24/16/24 bit、立体声/单声道逐项核对。允许设备重锁的必要间隔，记长短及有无爆音。快速请求以最后有效动作对应的曲目为准，随机与跳转实际生效。 |
| A3 | 点「格式与坏文件」让其播完。 | ALAC、WAV、MP3、AAC 正常出声。截断文件可能先播放可解码部分，观察错误与跳过。两个全坏文件应各有原因且只经过一次，越过短曲和含源内静音的曲目，到最后正常 FLAC。 |
| A4 | 各播放三次「连续参照」与「无缝 A → B」，并记录同一路由边界。 | 连续文件与两段拼合的源 PCM 相同，切点为第 44,137 帧。试听仅判可闻间隙或瞬态。如能采样，和连续参照对齐比较边界，量出插入、丢失帧及异常瞬态。零额外间隙须由样值证据判定。 |
| A5 | 点「DSF」，记 DAC 显示。打开「下次 DSF 请求 DSD 直通」再播一次。最后点「已封装 DoP」。 | 分别记引擎解码/输出及 DAC 显示 PCM、DSD64、静音或错误。176.4 kHz PCM 与 DSD64 需分辨。预封装 WAV 只检验传递载波的能力。 |
| A6 | 拔 DAC，扬声器再跑 A1、A3、A4。 | 切换后应标明扬声器路由。逐首核对解码和系统可读规格，记实际转化及声音。扬声器实际数模输入规格及有效位深单列。 |
| A7 | 分别点「PCM 24 源样值回读」和「PCM A → B 边界回读」。每组停表后点「停止」，取出文档目录中的对应 WAV。 | 回读组应无声，日志 `current-ao=pcm`，两份回读的采样率、声道、帧数与有效样值须逐项匹配原件。回读结果适用于该 PCM 文件输出，USB 实际路径另测。 |
| A8 | 如「下一首」有爆音，点「手动切歌同规格」，等 2～3 秒，在第一段发声时按「下一首」。同组再重开一次，对比先暂停、等一秒、再按「下一首」的听感。 | 分别记录暂停、切歌和恢复时的异常。日志检查同为 48 kHz/24 bit/立体声时 AudioUnit 是否重建。显式暂停只作定位对照。 |
| A9 | 基线跑完后接 DX5 II，依次点底部「请求 44.1 kHz」「请求 96 kHz」「请求 192 kHz」。每次读 DAC 屏幕。需要时再点「请求 176.4 kHz / DoP」。 | 核对 Swift 请求、激活后的会话实际值、引擎输出、DAC 模式/采样率四列。每组为独立单曲。退出重开 App 后再测原版默认组。 |
| S1 | 点「系统控制 / 循环」，返回主屏约 30 秒，再锁屏约 30 秒。依次用锁屏或控制中心暂停、继续、切歌、拖进度，再回 App。 | 持续出声，锁屏和后台的轨、状态、位置一致，系统命令与实际变更可配对，路由和规格无意外变化。 |
| S2 | 保持循环，从另一台设备打一次来电，另设一次系统闹钟。分别结束中断并观察续播。再在已暂停的状态重试一次中断。 | 记通知时刻、恢复提示、应用位置和声音。中断开始应停，结束按系统提示和用户播放意图续播，已暂停的情形不自启，无重复起播或爆音。 |
| S2a | 复现构建 4 的顺序。播放中拔出 DAC，回播放器点「系统控制 / 循环」，再设一分钟计时器。计时器响后关闭。 | 拔出后无外放。明确重开播放后，若计时器结束通知允许恢复，应从原位置续播。日志应区分路由移除、后来开始的新播放与计时器中断。 |
| S3 | 低音量时播放并拔 DAC，等待后接回，再手动播放。 | 拔出后暂停且无意外外放，接回记录路由和规格，手动恢复后继续正确曲目，无爆音。 |
| S4 | 设备空闲时循环 4 小时，期间数次切前后台与锁屏。结束后导出日志。 | 记录轨切换、30 秒存活和内存采样、暂停与崩溃信号。无非预期中断、崩溃或持续内存增长。 |

仅在默认组出现足以定位的差异时，选择 `yes` 或 `no`，用同一路由和同一组复跑。记录默认值及实际读回值。G1 前单独保留蓝牙和外部数字采集的可用性。

## 证据回收

```powershell
python -m pymobiledevice3 syslog live --process-name Runner --match FIDELUNE_P1T2
```

App 在「文件 → 我的 iPhone → Fidelune P1-T2」写入 `p1t2-evidence.jsonl`。测试后可通过文件分享或 USB House Arrest 取回。以每段的 `launch` 构建号和 `suite-start` 为分段，`unixTime` 用于与照片对齐，`uptimeSeconds` 用于比较应用事件的先后。切换时若 `pathStable=false`，等同轨稳定快照再对照。无值以 `null` 表示。空闲/中断时原生会话读数未必代表正在输出。

证据记录分为源文件清单、libmpv 解码和 AudioUnit 输出参数、AVAudioSession 以及 DAC 外部显示。诊断日志的应用输出格式是 libmpv 所报告的样式，无 PCM 样值或有效位深担保。系统 preferred 值是当时读取的会话偏好。App 的默认组未设置这个值。DAC 显示采样率或模式。端到端 Bit-perfect 需对实际数字样值逐一比较。

合成样本可用 Python 3 和带 `libmp3lame` 的 FFmpeg 重生。运行 `python tools/fixtures.py` 生成测试素材与清单。生成器验证无损编码解回的 PCM、两段无缝素材的拼合、无效文件的解码错误及 DSD/DoP 容器规格。不同 FFmpeg 版本的文件哈希可能不同，以该构建随包清单为准。Git 保留生成器及验证证据，生成音频在构建制品中。

从工程目录运行以下回读比对。先与构建清单核对用于比对的 WAV 参考文件，确认同一版测试数据。比较使用有符号 32 位整数容器，保留源有效位。文件按完整帧比对，无缝测试额外寻找边界前后锚点并检查边界窗口。外部数字采集的前后延迟和对齐需另记录。

```powershell
python tools/compare_pcm.py pcm24 C:\path\p1t2-pcm24.wav
python tools/compare_pcm.py gap C:\path\p1t2-gap.wav
```
