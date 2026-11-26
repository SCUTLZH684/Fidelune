# 阶段 1 真机验证报告

## P1-T1 · 无 Mac 的 iOS 构建、签装与诊断

首次验证于 2026-11-26 在 Windows 和 iPhone 17 上执行。依据 [G0 审查](../specs/V1_SCOPE_MATRIX.md#g0-门禁审查)及[阶段 0 验证用例](../research/IOS_BUILD_SIGN_RESEARCH.md#p1-t1--验证用例与回收证据)。工程、复跑步骤及操作说明见[验证目录](../../spikes/p1-t1/)。

### 云构建与制品

**实测通过。** 提交 `ca24b65262ce5dbe13b5af131748b7d4fbe812b5` 触发三个独立的 GitHub 托管冷构建。三次均通过锁定依赖解析、静态分析、Flutter 界面测试、无签名归档、IPA 打包和上传。Windows 本地也通过静态分析和 1 项 Flutter 界面测试。 [Actions 运行](https://github.com/SCUTLZH684/Fidelune/actions/runs/45827734376)

- runner 标签 `macos-15`，arm64。A 使用镜像 `20261123.0558.1`，A-repeat 和 B 使用 `20261118.0550.1`。已核对 macOS 15.8.2（24H232）、Xcode 26.3（17C529）、iPhoneOS SDK 26.2、Flutter stable 3.44.0（框架 `559ffa3f75`、引擎 `4c525dac5e`）、Dart 3.12.0。
- 三包均为 Release，应用版本 0.1.0，Bundle ID 为 `io.github.scutlzh684.fideluneP1t1`，最低系统为 iOS 14.0，Runner 为 arm64。工作流核对应用根目录无 `embedded.mobileprovision` 或 `_CodeSignature`，Runner 无签名且 Mach-O UUID 与其 dSYM 一致。包内 `Flutter.framework` 和 `App.framework` 保有各自的签名资源。没有 iOS 第三方原生插件。依赖锁文件 SHA-256 为 `dd2633a64a69c47d57d6fb26584b103be0ca955334f5c09328d73ef44d94bef9`。

计时单位为秒。排队按运行创建至 job 开始计算，job 总计含 Checkout、清理等步骤。上传列分别列出 IPA 与 dSYM 的用时。三次均为冷构建，未测缓存命中或增量构建。

| 构建 | 排队 | Flutter 设置 | 依赖、分析、测试 | Xcode 归档 | 校验和打包 | 上传 IPA / dSYM | job 总计 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| [A](https://github.com/SCUTLZH684/Fidelune/actions/runs/45827734376/job/139936126896) | 3 | 59 | 25 | 43 | 7 | 2 / 2 | 145 |
| [A-repeat](https://github.com/SCUTLZH684/Fidelune/actions/runs/45827734376/job/139936127159) | 4 | 111 | 91 | 148 | 18 | 3 / 4 | 386 |
| [B](https://github.com/SCUTLZH684/Fidelune/actions/runs/45827734376/job/139936127489) | 3 | 89 | 47 | 101 | 12 | 2 / 1 | 265 |

**Windows 下载实测通过。** A、A-repeat、B 在 GitHub 连接器提供的下载通道用时分别为 6.471、14.843、8.246 秒。Windows 校验了三个 ZIP 的完整性，三个 IPA 的 SHA-256 均与各自的构建元数据一致。A、B 的 dSYM 下载分别用时 29.502、39.061 秒，SHA-256 均匹配。GitHub 制品存储直连曾在 60 秒时超时，另一连接下载 A 成功但耗时 160.521 秒。

| 构建 | 构建号 | IPA 字节数 | IPA SHA-256 | Runner UUID |
| --- | ---: | ---: | --- | --- |
| A | 1 | 6174103 | `f37dff914ec2816d7bffde99a4f63a8ca574cd13c895a5da3c867981a3a11c7b` | `48860625-063C-3FE9-8279-3281A7B832D3` |
| A-repeat | 1 | 6174103 | `e8dc5a262cdcd397cbc44a76a6699b77685077ee45d445f190ff738023792107` | `48860625-063C-3FE9-8279-3281A7B832D3` |
| B | 2 | 6174100 | `0eeb96cfd683db08180570ca24b3145b89b74ed33df809fc5f1578750f44d628` | `E658AE7E-3387-3406-B8C8-5AE2405CF51F` |

**构建内容可复现。** A 与 A-repeat 的 48 个非目录 ZIP 条目路径和解压后的逐文件 SHA-256 全部相同，Runner UUID 一致。**整包字节一致性未通过。** 两份 IPA 哈希不同，25 个文件条目的 ZIP 时间戳不同。

### 真机与 USB

**设备与服务实测通过。** Windows 版本 26H2（26300），Apple Mobile Device Service 正常运行。pymobiledevice3 11.64.0 通过已配对的 USB 读取 iPhone 17（`iPhone18,3`，iOS 27.2.1，24B156）。开发者模式已开启，可用存储已在本机核对。USB 上可打开实时日志流和崩溃报告列表服务。签装使用本机 Sideloadly v0.72。

### 免费签装与首次运行

**实测通过。** 发起人用免费 Apple 账号，经 Sideloadly 的 Apple ID 模式和 USB 安装 A，看到 Done，打开应用并确认界面显示构建 1。Windows 通过 USB 核对了构建号和对应的开发描述文件。Sideloadly 默认签装后实际 Bundle ID 带工具添加的后缀。完整签名身份和设备标识留在本机。

以下时间为北京时间。Actions 于 11 月 26 日 21:17:38 创建，USB 于 21:27:48.752 首次观测到构建 1，端到端 10 分 10.752 秒，包含制品下载重试和人工操作等待。初次描述文件于当日 21:27:39 签发，到 12 月 3 日 21:27:39，实际有效期 604800 秒，设备返回 `get-task-allow=true`。从签发到 USB 观测约 9.752 秒。Sideloadly 的 Start 到 Done 未独立计时。

**退出重开和崩溃后重开实测通过。** 构建 1 首次显示空状态，写入了独立 WAV 样本与组织 JSON，并在系统目录选择器中保存独立测试目录书签。发起人划掉应用后重开，再触发受控崩溃并重开。三次截图的媒体摘要、组织标记、书签摘要均相同，外部目录标记可读。公开报告留存比对结论。

### USB 日志与受控崩溃

**实测通过。** pymobiledevice3 在 Windows 读到 `FIDELUNE_P1T1 diagnostic marker` 与 `FIDELUNE_P1T1 controlled crash`，设备日志时间分别为 21:30:12.118873 与 21:30:24.333579。随后通过 USB 回收构建 1 的 21941 字节 `.ips`，类型 `EXC_BREAKPOINT`，信号 `SIGTRAP`。报告记录 21:30:24.4100，Windows 于 21:30:27.440197 读到，按设备与 Windows 时间戳相差约 3.030 秒。崩溃中 Runner 镜像 UUID 与本机 A 的 dSYM 匹配。Windows 使用该 dSYM 符号表把故障栈上的 Runner 帧 `0x824c` 定位到 `controlledCrash() + 84` 字节，验证了函数级符号定位。

### 覆盖安装与三项数据保留

**实测通过。** 发起人保留 A，用相同的免费签名身份经 USB 安装 B。Start 到 Done 约 12 秒，由发起人计时。Windows 于 11 月 26 日 21:33:34.216 从 USB 观察到构建 2，设备记录的实际 Bundle ID 和签名团队均与 A 相同。打开 B 即显示构建 2，媒体摘要、组织标记、书签摘要均与 A 相同，目录标记仍可读。两版截图的比较在重新写入或重新选择之前完成。

覆盖安装后，USB 读到同一应用新增的描述文件，签发于 11 月 26 日 21:33:25，有效期 604800 秒，到期为 12 月 3 日 21:33:25，较 A 延后 346 秒。以下同包重签另作验证。

### 同包主动重签与延期

**实测通过。** 发起人在 Sideloadly 重新载入同一份 B，使用同一免费 Apple 账号、实际 Bundle ID 和 USB 安装。Start 到 Done 用时 9 秒，由发起人计时。应用再次启动后仍显示构建 2，三个测试值与覆盖安装前后的截图相同，目录标记可读。

USB 观察到同一签名团队、同一应用的新描述文件，于 11 月 26 日 21:37:41 签发，有效期 604800 秒，到期为 **2026-12-03 21:37:41（北京时间）**，比覆盖安装时的描述文件延后 **256 秒**。最早在 21:37:46.566 读到新文件，同时核对设备仍安装构建 2。

### 长期补测与 G1 交接

| 用例 | 状态 | 保留的补测条件 |
| --- | --- | --- |
| Sideloadly 守护进程临期自动刷新 | 尚未验证 | 下一有效期临近时保持本机守护进程和 USB 设备可用。比对描述文件到期时间，并重开应用核对三个测试值。 |
| 自然到期后的恢复 | 尚未验证 | 在另一个周期让测试包自然到期，观察启动表现。保留原应用，用同一身份重签 B，检查新描述文件、启动和三项数据。 |
| 跨工具、跨签名身份及群友安装 | 尚未验证 | 已实测通过 GitHub Actions 下载公开未签名制品，并在一台设备完成个人签装。另一账号、设备或工具作为独立验证。 |

公开归档使用云构建记录与脱敏实测数据。原始截图、崩溃报告、设备与签名标识、描述文件及已签名 IPA 均未提交。三个已校验未签名 IPA、构建元数据及 A、B 的匹配符号保存在本机 `%LOCALAPPDATA%\Fidelune\P1-T1`。后续签装可使用桌面的 B。已清理本轮构建缓存、重复下载和用于本机诊断的临时敏感副本。

P1-T1 的云构建、免费签装、真机运行、覆盖安装、主动延期和诊断证据已获得，可交给 G1 汇总。G1 整体还需要阶段 1 的音频、沙盒及选型证据。

## P1-T2 · iOS 高保真音频与系统控制

### 设备与验证配置

目标为 iPhone 17（USB 已识别为 `iPhone18,3`，iOS 27.2.1）、本机扬声器及 TOPPING DX5 II USB 输入。蓝牙待借测，AirPlay 按已确认范围延后。构建、签装、用例及回收见[验证工程](../../spikes/p1-t2/README.md)。质量判定沿用 [P0-T4](../standards/QUALITY_BENCHMARKS.md#p1-t2-音频与路由用例)。

基线使用 Flutter 3.44.0、`media_kit 1.2.6` 及官方 `media_kit_libs_ios_audio 1.1.4`。后者的发布包 Makefile 指向 Darwin `v0.6.0` 的 `ios-universal-audio-default`，归档 SHA‑256 为 `8b8de92dc5482b8950c18bce6b8fa90204fd15af18f371acc9f5be07a4234e49`。上游构建锁列出 mpv `0.36.0`、FFmpeg `6.0`。真机日志应另读运行时版本。此构建早于 Darwin 的会话管理跳过补丁，mpv 0.36.0 的公开直通选项没有 DSD。iOS AudioUnit 上游在开启输出时配置播放会话与输出声道，无源采样率偏好请求。这些是源码定位线索。 [Darwin 构建锁](https://github.com/media-kit/libmpv-darwin-build/blob/v0.6.0/downloads.lock) · [mpv 0.36.0 AudioUnit](https://github.com/mpv-player/mpv/blob/v0.36.0/audio/out/ao_audiounit.m) · [mpv 0.36.0 选项](https://github.com/mpv-player/mpv/blob/v0.36.0/DOCS/man/options.rst)

### 已回收的本机证据

**样本和比较工具实测通过。** Windows 上以 FFmpeg 9.1 生成并解析 22 个合成素材。逐个验证无损解码 PCM、两段无缝素材拼回连续原件、两个坏文件无解码输出、DSF 与 DoP 载体规格、DoP 标志和逐声道载荷。24 位 WAV 原件及无缝连续原件通过比较器的阳性对照，缺少 B 段、在边界插入五帧、单个 24 位样值最低位变化分别被检出。结果的适用范围是合成输入和工具对照。 [样本规格与 SHA-256](p1-t2/fixtures-windows-ffmpeg-9.1.json) · [比较器对照结果](p1-t2/pcm-comparator-controls.json)

**云构建、下载和校验实测通过。** 构建 2 在 macOS 15.8.2 完成 Flutter 分析及 iOS 归档，打包加密时因切换目录后仍用相对路径而失败。修正路径后构建 3 等待 macOS 15 runner，构建 4 改用 macOS 26.7.2（arm64），继续使用 Xcode 26.3、iPhoneOS SDK 26.2、Flutter 3.44.0、Dart 3.12.0 及 CocoaPods 1.17.0。样本验证、静态分析、无签名归档、动态 Mpv 框架、Runner 与 dSYM UUID 比对及加密制品上传均通过。构建 2、4 的 Mpv 二进制 SHA-256 相同。 [构建 2](https://github.com/SCUTLZH684/Fidelune/actions/runs/45835258060) · [构建 4](https://github.com/SCUTLZH684/Fidelune/actions/runs/45837212603)

构建 4 下载使用 GitHub 连接器通道，Windows 传输耗时 36.633 秒。GitHub ZIP 的 SHA-256、解密后的 IPA 和 dSYM 的 SHA-256 均匹配。核对了 IPA 内应用无主签名资料、Bundle ID、构建号 4、背景音频配置以及 22 个文件的 SHA-256。Runner UUID 为 `AC37C6B7-6A5F-33E8-BB5A-514023160C9E`。包内合成素材由 FFmpeg 9.0.2 生成，四个比较用 WAV 与 Windows 参考副本逐文件一致。 [构建 4 元数据](p1-t2/build-4-info.txt) · [构建 4 样本清单](p1-t2/fixtures-build-4.json)

### 真机与证据状态

| 验收项 | 状态 | 判定依据 |
| --- | --- | --- |
| iPhone 通过 USB 识别 | 实测通过 | Windows 使用 P1-T1 的 pymobiledevice3 11.64.0 读取型号和系统版本。 |
| P1-T2 签装、启动及 USB 证据回收 | 实测通过 | USB 核对已安装构建 4。22:26:43（北京时间）收到启动事件，并通过 House Arrest 取回应用内日志。运行时为 mpv 0.36.0、FFmpeg 6.0，默认 `gapless-audio=weak`。 |
| DX5 II USB FLAC 阶梯 | 实测失败，源采样率匹配 | 六首期间 DAC 均为 48 kHz。引擎与 USB 会话分层见下文。 |
| USB 混合规格、快切与跳转 | 实测通过基本操作，手动切歌爆音失败 | 自动过渡试听未出现爆音。下一首、上一首及跳转有日志，发起人报告手动「下一首」有爆音且未卡住。此次无随机命令日志。 |
| 扬声器 FLAC 阶梯、自动跨规格过渡 | 实测通过出声和受控试听 | 六档均出声、未听到爆音。系统会话规格与源有差异，见下表。 |
| 扬声器 WAV、ALAC、MP3、AAC、短曲、源内静音 | 实测通过解码和续播 | 逐轨解码与引擎有记录，发起人观察到最后正常 FLAC。数字样值和源内静音轨迹另测。 |
| DSF 默认和请求直通 | 实测通过 DSF 解码，原生 DSD/DoP 失败 | 两种设置均解码为 PCM，DX5 II 显示 PCM 48 kHz。 |
| 预封装 DoP WAV | 尚未验证 | 第三次操作的日志仍为 DSF，文件 `dop64.wav` 未出现。 |
| 同规格无缝试听 | 实测通过受控试听 | 发起人对比连续原件与 A → B，未听到额外停顿或突响。 |
| 应用 PCM 样值及零额外间隙、零丢样 | 尚未验证 | 受控试听与引擎的稳定采样率不足以判定。暂停前尚未完成两个手机 WAV 回读。硬件无缝需另取独立输出证据。 |
| 背景、锁屏及锁屏媒体命令 | 实测通过基本控制，手动切歌爆音失败 | 发起人确认主屏及锁屏继续，暂停、续播、切歌、进度均有效；锁屏切歌有爆音。 |
| USB DAC 拔出防外放 | 实测通过 | 发起人拔出后听不到外放；系统路由变更、应用暂停有配对证据。接回 DAC 后手动续播的独立验证待测。 |
| 系统计时器中断 | 实测通过暂停，恢复失败 | 计时器结束通知允许续播，应用未恢复。 |
| 来电、闹钟与四小时长播 | 尚未验证 | 计时器的结果单独记录。四小时在正式候选包重验。 |
| 损坏、截断和连坏续播 | 实测通过 | 截断文件部分可解码，随后报错。各全坏文件尝试一次，继续短曲、静音边界和正常 FLAC。 |
| DAC 接收的有效位深和端到端 Bit-perfect | 当前不可测 | DX5 II 显示证据对应模式与采样率。尚无独立数字捕获或等效样值校验手段。 |
| 蓝牙 | 当前不可测 | 尚无可借测设备，后续补测。 |

源文件解析、mpv 解码和引擎输出、AVAudioSession、DAC 显示、独立样值测量分别归档。引擎报告的样本容器格式与有效位深分别取证。无值、初始空闲和中断状态不填作实际正在输出的规格。只在原版实现有明确失败证据后，按 [G1 的备选顺序](../research/TECH_STACK_COMPARISON.md#mpv-的重采样与-avaudiosession)定位并复测。

### 构建 4 · 扬声器 FLAC 阶梯

11 月 26 日 22:28:16（北京时间）启动阶梯。发起人听到从 44.1 至 192 kHz 的六段测试音，报告没有爆音。引擎使用 `audiounit`，默认 `weak`。以各曲启动后解码和 AudioUnit 传入格式同时有效的快照为准，切换期间带上一曲旧值的读数不计。

| 音源 kHz / 有效位深 | mpv 解码 | mpv 写入 AudioUnit | iOS 扬声器会话 |
| --- | --- | --- | --- |
| 44.1 / 16 bit | 44.1 kHz，s16，立体声 | 44.1 kHz，s16，立体声 | 48 kHz，2 声道 |
| 48 / 24 bit | 48 kHz，s32，立体声 | 48 kHz，s32，立体声 | 48 kHz，2 声道 |
| 88.2 / 24 bit | 88.2 kHz，s32，立体声 | 88.2 kHz，s32，立体声 | 48 kHz，2 声道 |
| 96 / 24 bit | 96 kHz，s32，立体声 | 96 kHz，s32，立体声 | 48 kHz，2 声道 |
| 176.4 / 24 bit | 176.4 kHz，s32，立体声 | 176.4 kHz，s32，立体声 | 48 kHz，2 声道 |
| 192 / 24 bit | 192 kHz，s32，立体声 | 192 kHz，s32，立体声 | 48 kHz，2 声道 |

引擎六次按源速率重新配置 AudioUnit。除 48 kHz 外，引擎写入的速率与会话速率分离。结合该版本 AudioUnit 驱动的客户端流格式，差异定位在 AudioUnit 写入之后的系统扬声器路径。快照验证采样率及样本封装，扬声器数模转换端的物理规格与样值未知。 [扬声器证据](p1-t2/device-build-4-speaker.jsonl) · [mpv 输出驱动](https://github.com/mpv-player/mpv/blob/v0.36.0/audio/out/ao_audiounit.m)

日志还记录了 media_kit 原版磁盘缓存打开失败，以及验证界面把读到的 `audio-format=no` 回写时被 mpv 选项解析器拒绝。前者未阻止六首播放。后者保留了起始默认值，但可能污染用过回读组之后的同进程对照。回读与音频套组因此需按各自的独立输出条件验证。 [mpv 0.36.0 选项解析](https://github.com/mpv-player/mpv/blob/v0.36.0/options/m_option.c)

### 构建 4 · DX5 II USB、DSF 与手动切歌

22:32:14（北京时间）开始完整 USB 阶梯。稳定快照的路由为 `USBAudio`，App 层的六档解码及写入 AudioUnit 的速率和封装均与扬声器组表中的两列相同。六档的会话实际均为 48 kHz、两声道，`preferredSampleRate=0`。发起人在 DX5 II 观察到六档均为 48 kHz，因此 44.1、88.2、96、176.4、192 kHz 五档的原生速率验收失败。此差异定位于 mpv 写入 AudioUnit 之后。后续对照在设备为 USB 且播放器停止时调用 `AVAudioSession.setPreferredSampleRate`，再由同一 stock AudioUnit 输出。 [USB 日志](p1-t2/device-build-4-usb.jsonl) · [Apple 会话偏好](https://developer.apple.com/library/archive/qa/qa1631/_index.html)

混合组观察到 48 kHz/16 bit WAV 解码为 s16，某些相邻曲复用前曲 s32 输出。24 bit WAV 解码和输出均为 s32。单声道 24 bit WAV 解码为 mono，引擎输出为 stereo，和 0.36.0 AudioUnit 双声道路由的映射分支一致。无逐样值证据时保留有效精度结论。发起人确认自动切换未听到爆音、手动「下一首」有爆音、未卡死。相同问题还在锁屏扬声器切歌出现。日志显示部分手动跨规格换曲重建了输出，同规格邻接也有复用。当前试听无法把爆音逐次对齐到重建事件，对照应分别检验同规格直接切歌、先暂停再切及恢复。 [USB 日志](p1-t2/device-build-4-usb.jsonl) · [mpv 0.36.0 AudioUnit](https://github.com/mpv-player/mpv/blob/v0.36.0/audio/out/ao_audiounit.m)

DSF 为 DSD64，2.8224 Mbit/s/声道的 1 bit 源。运行时将其解为 352.8 kHz、`floatp`、立体声 PCM 并写给 AudioUnit。请求 `audio-spdif=dsd` 后观察到相同处理，iOS 会话与 DAC 显示均维持 PCM 48 kHz。第三个已记录套组仍为 DSF，独立预封装 DoP 载波需重新点对应按钮。 [USB 日志](p1-t2/device-build-4-usb.jsonl)

22:37:32（北京时间）在第一首播放中拔出 DAC。系统报告旧设备不可用及中断开始，路由变为 `Speaker`，应用约 67 ms 后记录暂停、位置 3.036009 秒。这个间隔为应用事件差。发起人未听到外放。 [USB 日志](p1-t2/device-build-4-usb.jsonl)

### 构建 4 · 其他格式、后台和锁屏

22:38:46（北京时间）开始格式组。ALAC、WAV、MP3、AAC 均有对应的解码和 AudioUnit 快照。截断 FLAC 先播放可读部分，22:39:14 报解码错误后跳过。两个全坏文件各报识别失败一次，后续短曲、静音边界样本和最后 FLAC 都打开并运行。发起人确认到达最后一首。 [格式和系统控制日志](p1-t2/device-build-4-controls.jsonl)

22:39:39 应用进入后台时第一首约在 2.932 秒，心跳时已至 6.543 秒，随后继续跨曲。锁屏系统命令有暂停、播放、前后切歌及多次定位记录。发起人确认均有效，连续播放未意外中断，切歌依然可听到爆音。路由在选定快照保持扬声器，会话为 48 kHz。 [格式和系统控制日志](p1-t2/device-build-4-controls.jsonl)

### 构建 4 · 无缝试听及计时器中断

22:42:58 起三次交替播放连续原件与同规格 A → B。日志记录三种文件均使用 AudioUnit。发起人未听到接缝的额外停顿或突响。数字边界的零间隙和零丢样留待 WAV 回读与外部采集。 [无缝和计时器日志](p1-t2/device-build-4-gap-and-timer.jsonl)

发起人用系统「计时器」设置 1 分钟。22:45:02.437 收到中断开始，播放停在 ALAC 的 2.176 秒。22:45:02.793 收到结束及 `shouldResume=true`，应用仍暂停，22:45:13 的位置未变，和发起人的观察一致。此前拔 DAC 只有开始通知。构建 4 在发起人重新开播新测试组时仍保留这个旧状态，下一次中断开始没有据当时正在播放的状态设置恢复意图。这个缺陷可解释本次未恢复。 [USB 日志](p1-t2/device-build-4-usb.jsonl) · [无缝和计时器日志](p1-t2/device-build-4-gap-and-timer.jsonl)

### 暂停交接 · 2026-11-26

发起人要求先记录并暂停。iPhone 最后核对安装构建 4。原始设备日志、已经校验的未签名 IPA、匹配 dSYM 和 QA 私钥留在本机 `%LOCALAPPDATA%\Fidelune\P1-T2`。公开仓库保留所用样本、构建校验和脱敏日志。已清理失败下载和重复解包文件。使用已归档锁文件重跑的构建 5 成功。 [构建 5](https://github.com/SCUTLZH684/Fidelune/actions/runs/45839027977)

复测版提交 `a26107f` 已推送，暂停时构建 6 已进入样本生成。该版保持原版音频引擎，加入 USB 单曲会话请求、同规格手动切歌对照，去除无效的音频格式回写，并关闭本地样本中已报错的磁盘缓存。计时器恢复的状态修正另留本机草稿，编译与真机复测待恢复任务。 [构建 6](https://github.com/SCUTLZH684/Fidelune/actions/runs/45841315564)

恢复时优先用一个签装版本完成 USB 请求速率、实际 DAC 读数、同规格切歌与暂停后切歌、拔出后重开再遇计时器的对照。尚需完成预封装 DoP、两份手机 PCM 回读、随机、来电、真实闹钟与 DAC 接回续播。蓝牙和端到端数字样值核验各自需要对应设备。P1-T2 仍有质量缺陷及开放用例，G1 未定案。
