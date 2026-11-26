# 客户端技术栈和成熟方案调研

阶段 0 · P0-T3 · 2026-11-26

**已确认的阶段 1 首选组合**为 Flutter + media_kit/libmpv，文件访问优先复用 Flutter 库并按需原生桥接，只读解析优先 TagLib + flutter_taglib，本地数据优先 SQLite + Drift。发起人确认 Flutter 首选，并认同后续 T3 路线。音频、文件和持久化的正式选型、版本、最低系统、格式清单以 G1 实测与发起人定案为准。质量与用例见[质量标准](../standards/QUALITY_BENCHMARKS.md)。

## 1. 客户端框架

依据成熟方案复用、Windows 自测效率、iOS 音频与文件桥接、启动及大列表、三平台演进比较。常见无损解码和 192 kHz/24 bit 的主要风险在输出配置、线程/缓冲和系统链路。万首标签扫描是 I/O 负载，高清封面主要占内存和解码资源，检索依赖数据库索引，滚动取决于渲染与帧预算，长播还涉及功耗与系统资源。以上是工程判断，尚无 Fidelune 性能数据；纯原生也需要同样处理这些瓶颈。

| 路线 | 取舍与切换条件 |
| --- | --- |
| **Flutter/Dart + 成熟音频库，必要时薄层原生** | iOS、Android、Windows 有官方支持。共享界面、业务逻辑和 Windows 本地开发，自定义交互灵活。引擎初始化、内存和适配苹果平台交互有额外成本。iOS 真机与正式构建仍由 macOS 工具链完成。Dart 层传播放指令、状态和曲库数据，底层解码、PCM、会话及设备控制留在原生侧，避免逐采样跨平台通道传输。 [支持平台](https://docs.flutter.dev/reference/supported-platforms) · [平台通道](https://docs.flutter.dev/platform-integration/platform-channels) |
| **Compose Multiplatform/Kotlin + 原生音频** | 第一框架备选。Android 生态和 iOS 原生互操作有优势，可共享 UI/逻辑，桌面 JVM 有运行时成本，iOS UI/组件生态相对年轻。 [官方支持平台](https://www.jetbrains.com/help/kotlin-multiplatform-dev/supported-platforms.html) |
| **SwiftUI/Swift 原生路线** | 最后兜底或对照。直接控制 Apple 系统 API 和原生交互，Windows 本地迭代受限，移植 Android、Windows 时承担较多 UI/业务重做。 [Apple SwiftUI](https://developer.apple.com/swiftui/) |
| React Native、.NET MAUI、Qt/QML | 已筛选的次选。RN 移动生态成熟，Windows 由 Microsoft 独立维护，包兼容需复核。MAUI 适合 C# 生态，Qt 适合 C++/QML 桌面且覆盖移动端。当前不展开原型。 [RN Windows](https://microsoft.github.io/react-native-windows/) · [.NET MAUI](https://learn.microsoft.com/dotnet/maui/supported-platforms) · [Qt](https://doc.qt.io/qt-6/supported-platforms.html) |

先量测一套 Flutter 原型。单个音频插件失效时，局部换后端或补 Swift 薄层。经定位和优化仍有不可接受的框架级启动、列表渲染或桥接性能问题时，再重验 Compose 或 SwiftUI。原调研引用的跨框架预印本（约 16,000 次测量）提供任务间表现不同的背景，不能套用成 Fidelune 数字。[预印本](https://arxiv.org/abs/2609.21544) · [Harmonoid](https://github.com/harmonoid/harmonoid) 是 Flutter 音乐播放器先例，可参考产品与架构。原调研记录其曾使用 mpv/FFmpeg，具体版本技术与许可需逐版本核对；PolyForm Strict 限制下不得把其源码作为可自由集成的依赖，也不能借其架构证明原生输出。

## 2. 自主音频引擎与输出控制

筛选依次看音质（无损解码、原生规格、无主动降精度）、稳定性、加载/跳转/缓冲和可合法分发，再看 HTTP/鉴权/字节范围、三端、后台与媒体控制、格式及绑定。来源适配负责认证、读取原始字节与缓冲。自主引擎负责解码及输出，第三方订阅使用提供方授权后端。界面可共享控制与展示，输出链路仍按平台和设备处理。

| 候选 | 能力、风险与定位 |
| --- | --- |
| **libmpv + media_kit** | 首测。FFmpeg 基础提供广泛本地格式（如 FLAC、ALAC、WAV、APE、WavPack）与 HTTP、自定义请求头、渐进缓冲、跳转和无缝控制。media_kit 有纯音频包。Windows WASAPI 独占属后续平台，iOS AudioUnit 的实际规格、配置注入和可读属性必测。media_kit 包的 MIT 许可不覆盖实际分发的 mpv/FFmpeg 二进制。审计对应构建的 GPL/LGPL 选项、链接方式、打包及义务后才可对外分发。 [mpv](https://github.com/mpv-player/mpv) · [media_kit](https://github.com/media-kit/media-kit) · [iOS 构建](https://github.com/media-kit/libmpv-darwin-build) · [FFmpeg 许可](https://ffmpeg.org/legal.html) |
| **SFBAudioEngine** | iOS 音质备选。MIT，Apple 平台、AVAudioEngine，提供多格式解码、无缝和处理链控制，项目记录 DSD/DoP 支持。标准播放接口文件 URL 与网络能力须按版本核对。需 Flutter 原生桥接，无 Android/Windows 后端。项目支持 DoP 不能推出 iPhone/DAC 端到端可用。 [源码与说明](https://github.com/sbooth/SFBAudioEngine) · [API 文档](https://sbooth.github.io/SFBAudioEngine/) |
| **just_audio** | Flutter 音乐播放备选，配合 audio_service/audio_session 做锁屏、后台与会话。Windows 依赖额外后端，公开接口对原生输出规格控制有限。 [播放库](https://pub.dev/packages/just_audio) · [audio_service](https://pub.dev/packages/audio_service) · [audio_session](https://pub.dev/packages/audio_session) |
| **mpv_audio_kit** | 音乐用途封装，原调研版本 0.8.0。文档列出网络/SMB、媒体会话、后台及输出格式控制；生态较小，iOS 独占输出未证实，观察。 [包文档](https://pub.dev/packages/mpv_audio_kit) |
| **libVLC、miniaudio** | libVLC 格式和协议成熟，暂无明确本项目收益。miniaudio 轻量可控，但需补更多解码、网络和播放器基础设施，暂不采用。 [VLC](https://github.com/videolan/vlc) · [miniaudio](https://github.com/mackron/miniaudio) |

### mpv 的重采样与 AVAudioSession

- **引擎层。** `gapless-audio=yes` 可能把第一首的设备规格留给后面的曲目，如 44.1 → 96 → 192 kHz 后两首可能被转到 44.1 kHz。默认 `weak` 一般在解码格式变化时重开输出，但可转换的 sample format 等情况下会复用，行为随版本变化。 `no` 禁用该无缝机制，输出仍受配置与设备限制。固定 `audio-samplerate` 在规格不同时可触发内部重采样。mpv 的无缝实现依赖已有输出缓冲，远程/缓存填充慢也可能使它耗尽。 [mpv 手册](https://mpv.io/manual/stable/#options-gapless-audio)
- **切歌策略。** 手动或自动切歌、暂停/继续、拖动、随机本身均不必然引起重采样。按相邻曲目的实际采样率、有效位深/样本格式、声道和输出兼容性决策。压缩码率与采样率是不同量；同一专辑也可能混规格。兼容时验证零额外间隙；不兼容时优先重新配置输出，允许必要间隔且不爆音。不靠固定输出采样率或强开无缝跨规格掩盖问题。
- **系统层。** 所查 mpv 上游 iOS AudioUnit 驱动配置 AudioUnit 流格式，其源码未见显式调用 `setPreferredSampleRate`。这只说明所查源码，Fidelune 锁定的二进制还需核查。即使解码端保持 192 kHz，系统混音或硬件协商仍可能落到 48 kHz，这是假设性示例。Apple 将采样率/缓冲 API 定义为偏好，一般在会话未激活时请求，激活后读实际值，路由或中断后重新检查。避免多个库反复覆盖类别、模式和激活状态。系统会话采样率、DAC 显示和有效样值证据分开记录。 [mpv AudioUnit 源码](https://github.com/mpv-player/mpv/blob/master/audio/out/ao_audiounit.m) · [Apple QA1631](https://developer.apple.com/library/archive/qa/qa1631/_index.html)
- **分支顺序。** ① 以候选原版产物和实际配置做基线并定位引擎转换、会话协商或物理输出。② 需要自行管理会话时，优先评估 Swift 层，验证 `audiounit-skip-session-management` 能否由 Dart 传入且确实生效。该补丁在 2026-06-25 合并到 Darwin 构建仓库的 PR #52，v0.7.1 列出该补丁，不能由此推断所选 media_kit 包实际内置它。③ 原生会话层仍无法满足时，评估定制 `ao_audiounit.m`，复用 Darwin 构建链并承担重编译、维护和许可成本，可在证实修复后考虑回馈上游。④ 若 iOS 仍有无法消除的输出、加载或稳定性缺陷，以同一验证矩阵改测 SFBAudioEngine，保留 Flutter UI。 [PR #52](https://github.com/media-kit/libmpv-darwin-build/pull/52) · [v0.7.1](https://github.com/media-kit/libmpv-darwin-build/releases/tag/v0.7.1)

## 3. 文件访问、存储与扫描

- **容器媒体目录。** 候选为 `Documents/Music/`，可用系统文档浏览配置或文件共享与原地打开配置暴露容器 `Documents`。用户用「文件」App 复制、移动、管理音乐，播放器读源文件并建立索引。专辑组织、索引纠错与缓存清理不改写或删除原始媒体。持久数据候选置 `Library/Application Support`（索引、组织成果、纠错标记、未过期的恢复记录、书签），可重建缩略图与临时缓冲放 `Library/Caches`。缓存可能被系统清理，容器也会随 Delete App 删除。系统 Offload 通常保留文档数据；正常覆盖更新、续签与换身份分别验证。外部原件不随 Fidelune 容器一并删除。产品须明确提醒，无强制备份。 [Apple 文件共享](https://developer.apple.com/documentation/bundleresources/information-property-list/uifilesharingenabled) · [原地打开](https://developer.apple.com/documentation/bundleresources/information-property-list/lssupportsopeningdocumentsinplace) · [iOS 储存空间](https://support.apple.com/en-us/108429)
- **外部目录。** iOS 13 起可以由用户通过系统 picker 授权整个目录及其内容。使用 scoped URL、协调读取、保存书签，恢复并处理 stale、撤权、移动、提供器不可用及重启。访问需平衡开始/结束调用，不能假定普通路径或持续后台监听有效。暂不可读时保留灰显索引和组织成果，重新授权/关联可恢复。推荐前台增量快照（启动、切回前台、进入视图按需检查，支持手动刷新），监听只作前台候选；后台播放也不代表可常驻监听。锁屏文件保护、文件仍打开/重新打开、提供器是否会整文件下载须实测。其他 App 私有目录不做全盘扫描。 [Apple 用户授权目录](https://developer.apple.com/documentation/uikit/providing-access-to-directories) · [File Protection](https://developer.apple.com/documentation/foundation/fileprotectiontype)
- **库候选。** `path_provider` 取容器路径，`dart:io` 遍历/读本地文件。 `file_picker` 首选 picker 候选，目录选择成功后须查持久授权和跨重启读取。 `dir_picker` 声称支持 iOS 持久授权、Android URI 和 Windows 目录及批量遍历，规模/API 成熟度待核验。Flutter 官方 `file_selector` 的当前支持表无 iOS 目录选择。若证据不足，以 Foundation/UIDocumentPicker 薄层兜底。 [path_provider](https://pub.dev/packages/path_provider) · [file_picker](https://pub.dev/packages/file_picker) · [dir_picker](https://pub.dev/packages/dir_picker) · [file_selector](https://pub.dev/packages/file_selector)

## 4. 远程来源与缓存 · 首版后

**已确认的产品边界。** 默认按需读取原始数据，可使用瞬态播放缓冲和自动失效的缓存。只有用户主动执行且来源允许时才永久下载；用户下载的文件进入原始媒体生命周期。缓存不进入曲库、不产生重复曲目，可自动释放，扫描应避免为读取标签而批量拉取完整文件。读取、缓存、下载的区别也适用于通过 iOS「文件」选择的提供器。提供器自行物化占位文件时无法承诺精确的字节数或释放时机。

- **缓存暂定方案。** 优先边读边播边缓存，首次起播不等待整曲下载；完整暂存可改善跳转与抗波动，但增加首次等待和空间。仅存原始数据，不进行有损转码。优先序为当前曲目连续播放 → 下一首 → 带宽允许时下下首 → 短期保留已听曲目 → 按容量、访问和距离释放远端条目。随机播放按实际计划顺序预取，跳转或连续切歌要取消过时的低优先请求。用户提出约两首的向前预取窗口，数量、部分或整曲、回听保留期受容量/带宽/服务许可约束，须实测调优。自动过程不显示为下载/删除任务；用户仍可操作容量设置与一键清理。个人云盘、SMB、Qobuz 可分别评估复用。首版仅落地实际存在的本地可重建缓存。
- **云盘。** 首选系统文件提供器（iCloud、Google Drive、OneDrive、Dropbox 等）。如果目录权限、占位文件或 provider 自动拉取使按需读取不可控，再评估官方 API。Google Drive 对适用 blob 提供原始内容和 HTTP Range，浏览/跳转需实测；`drive.readonly` 是 restricted scope，对外分发与验证/安全评估的适用条件要核对，优先最小授权。无自建后端边界不变。 [Apple 文件 App](https://support.apple.com/en-us/102238) · [Google 内容与字节范围](https://developers.google.com/workspace/drive/api/guides/manage-downloads) · [Google OAuth 范围](https://developers.google.com/workspace/drive/api/guides/api-specific-auth)
- **Wi-Fi 跨设备。** 发起人的目标包括源文件位于别的设备、向播放设备传数据。保留三条不同能力：远端渐进读取（Windows 共享 SMB 优先，WebDAV 备选，HTTP Range 提供按需读取/跳转，DLNA/UPnP 可考察）；用户主动整文件传输（Flutter 局域网 REST/HTTPS 的 LocalSend 可作参考）；音频输出（AirPlay 等）。校园 Wi-Fi 设备隔离、本地网络权限、连接和缓存均待专项验证。 [LocalSend](https://github.com/localsend/localsend) · [协议](https://github.com/localsend/protocol) · [Apple 局域网权限](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)
- **Qobuz。** 自购下载且由用户持有的无损音源可走自主引擎。订阅曲库需要合法服务授权。Roon 有正式接入先例，Qobuz Connect 不支持第三方 app 作控制端。历史指南（2014）曾建议缓存已听、临近结束预取下一首、过期清除、避免提前缓存整张专辑/页面，并上报实际播放。旧 API 条款涉及官方颁发凭证及禁止共享。当前政策、个人开发者申请、发行与纯客户端凭证保护均待确认。发起人曾提及 qobuz-dl、QobuzDownloaderX 的下载/播放思路，此处保留其推动透明缓存的设计背景。订阅自动删除不产生下载权，非官方接口和下载工具不作为实现依赖。 [历史指南](https://static.qobuz.com/apps/api/Qobuz-AppsGuidelines-V1.0.pdf) · [历史 API 条款](https://static.qobuz.com/apps/api/QobuzAPI-TermsofUse.pdf) · [Roon 集成](https://help.qobuz.com/en/articles/10208-integration-roon) · [Qobuz Connect](https://help.qobuz.com/en/articles/313603-can-qobuz-connect-be-used-via-a-third-party-app) · [订阅使用条款](https://www.qobuz.com/us-en/legal/terms)
- **Apple Music。** MusicKit 可提供现有订阅授权、曲库/歌单/搜索与播放控制。使用其授权播放后端，统一 UI 可显示状态和操作，自主引擎不接管受保护的音频。 `AudioVariant` 可提供包括最高 24 bit/192 kHz 的 Hi-Res Lossless 版本信息，实际输出和控制力、免费签名下完整能力均待确认。 [MusicKit](https://developer.apple.com/musickit/) · [AudioVariant](https://developer.apple.com/documentation/musickit/audiovariant)

## 5. 只读标签解析与曲库 I/O

- **首选 TagLib + flutter_taglib。** 复用成熟 C++ 解析与相关原生绑定，预期 iOS、Android、Windows。核查锁定版本对专辑、曲名、艺术家/专辑艺术家、作曲家、碟/曲号、年份、流派、歌词、封面、自定义标签、采样率、时长、码率和有效位深的实际覆盖。ALAC 属编码，标签处理跟容器走；DSF/DSD 的标签支持也要按格式、版本和绑定实测。TagLib 有可定制 IOStream，不代表 Flutter 绑定已公开远程读接口。绑定含写入能力，Fidelune 仅使用读取。 [TagLib](https://taglib.org/) · [flutter_taglib](https://github.com/axel10/flutter_taglib) · [I/O 接口](https://taglib.org/api/classTagLib_1_1IOStream.html)
- **备选。** Lofty（Rust，支持按配置跳过部分读取，如封面）在首选覆盖、稳定性或部署不足时评估，并核查 FFI/发行成本与格式覆盖。FFmpeg/libavformat 按特殊格式补充，Dart 的 audio_metadata_reader 是轻量对照。不存在已得到的同条件性能排名。 [Lofty](https://github.com/Serial-ATA/lofty-rs) · [FFmpeg](https://ffmpeg.org/) · [audio_metadata_reader](https://pub.dev/packages/audio_metadata_reader)
- **读取与扫描。** FLAC 的元数据块在音频帧之前，部分格式需尾部或分散随机读取。控制读取量，按需加载/适当尺寸解码封面并评估封面去重。用目录/文件状态快照找变化，仅新/变文件进有限并发的解析队列，后台解析，批量事务写入，可已解析即浏览；优先保障播放不被 I/O 抢占。固定可复现样本量测、校验失败、取消和重扫一致性。真实读取不同标签是解析职责；归并拼写差异、分碟、错标等候选与纠错交互由 Fidelune 负责，原始值保留。 [FLAC 规范 RFC 9639](https://www.rfc-editor.org/rfc/rfc9639.html) · [Navidrome 扫描代码](https://github.com/navidrome/navidrome/tree/master/scanner)

## 6. 数据库、检索和数据生命周期

| 决策 | 适用条件与待测点 |
| --- | --- |
| **SQLite + Drift** | 关系模型表达曲目、专辑、作者、分类、歌单与多对多关系，保存一份基础曲目信息并以稳定 ID 建立关系。Drift 提供类型安全查询、响应式更新、后台 Isolate 和迁移测试。Isar/ObjectBox 纳入比较，当前关系、检索和数据完整性需求可由 SQLite 满足。Kodi/Navidrome 提供设计参考，无服务端依赖。 [Drift](https://drift.simonbinder.eu/) · [Kodi](https://github.com/xbmc/xbmc) · [Navidrome](https://github.com/navidrome/navidrome) |
| **检索** | B-Tree/复合索引用于精确、范围、排序、外键关系和过期查找，借助查询计划验证。FTS5 倒排用于关键词、前缀、BM25，Trigram 用于中日文/子串。Trigram 的全文匹配对少于 3 个 Unicode 字符的子串不适用，设计短词回退并量测。大小写、全半角可用派生搜索文本标准化，原始标签值保持。准备本地发布构建确认 FTS5 可用；分页/按需首屏，忽略或取消陈旧结果。拼音、罗马音、容错拼写候选，当前无需独立搜索、向量或语义引擎。 [SQLite 查询规划](https://sqlite.org/queryplanner.html) · [FTS5](https://sqlite.org/fts5.html#the_trigram_tokenizer) |
| **一致性** | 扫描与手动操作按事务合并，启用并核查外键约束。SQLite WAL 允许读写并存但只有一个写入者，配合后台 Isolate 和有限批量事务，测试竞争、崩溃恢复及迁移。搜索索引应可从基础数据重建。普通路径不是稳定身份；文件移动/重连尽量重绑到原 ID，碰撞、路径复用、找不到或不可访问时保存组织成果并交由阶段 2 设计。 [SQLite 事务](https://sqlite.org/transactional.html) · [WAL](https://sqlite.org/wal.html) · [外键](https://sqlite.org/foreignkeys.html) · [Drift 迁移](https://drift.simonbinder.eu/migrations/) |
| **纠错方案 B，发起人已选定** | 方案 A 会随可恢复项过期一起丢弃纠错结果，重扫可能带回已纠正错误，已弃。B 以持久纠错标记控制索引，各次操作保留独立、可搜索、可单独恢复的记录，默认 30 天、用户可调。过期只移除常规恢复记录；重扫、清缓存不得解除纠错。删除与恢复都只操作索引。此处规定生命周期，表结构、稳定匹配、期限修改如何作用于存量、恢复冲突及备份合并留给 G2。 |

**交接。** 已归档 T3 全部候选、已采纳规则及备选触发条件。阶段 1 留存候选实测，包括真实音频包、混规格能力、持久文件访问、必要的绑定字段与搜索构建能力；见 P1-T2、P1-T3、P1-T5。正式 ADR、协议实现、数据库 Schema 与备份格式仍由后续门禁负责。
