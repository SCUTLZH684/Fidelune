# 无 Mac 的 iOS 构建、签名与真机调试

阶段 0 · P0-T1、P0-T2 · 2026-11-26

发起人已确认阶段 1 优先用 **Windows → GitHub Actions macOS/Xcode → 未签名 IPA → Sideloadly 免费签名、USB 安装 → iPhone 真机 → pymobiledevice3 回收日志**。这是验证路线，项目尚无构建、安装、续签或诊断实测记录。集中审查见 [G0](../specs/V1_SCOPE_MATRIX.md#g0-门禁审查)。

## P0-T1 · 开发与测试基线

| 项目 | 发起人提供的事实 | 待办或边界 |
| --- | --- | --- |
| 真机 | iPhone 17 标准版，iOS 27.2.1 | 开测时记录设置中的实际版本、构建号与可用存储。 |
| 开发机与连接 | 2024 款联想拯救者 Y7000P（Windows），有 USB 数据线和校园 Wi-Fi，无本地 Mac | USB 是主路径。校园网可能隔离同网设备，尚未验证。Wi-Fi 不作为 USB 构建、安装或诊断的前置依赖。 |
| 签名 | 普通 Apple ID，未购买此前提到的商用签名，无已确认可用的付费开发者账号或企业签名 | 验证账号认证、个人签名配额、设备信任和实际可用权限。 |
| 音源 | 尚未准备，按需下载 | 用合法取得或可分发的测试文件。格式、采样率、位深、切歌与杂乱标签样本见[质量标准](../standards/QUALITY_BENCHMARKS.md)。 |
| 有线 | 原道 Orig in，TOPPING DX5 II + PARA 2，水月雨梦回 2 待购 | 发起人已有 iPhone 通过 USB 接 DX5 II 正常播放 44.1～192 kHz 音源的经验。该经验确认可播放性，Fidelune 实际输出采样率、有效位深和 Bit-perfect 仍待测。 |
| 无线 | Enco X4 已售，当前无确认可用的蓝牙耳机或 AirPlay 接收端 | 蓝牙须借用或另行安排并补测。AirPlay 已延后，无需为阶段 1 购置设备。 |

## P0-T2 · 云构建和安装

- **首选 GitHub Actions。** 归档时仓库 `SCUTLZH684/Fidelune` 为公开仓库，标准 GitHub 托管 runner 的公开仓库用量免计算分钟费。私有仓库受计划用量、macOS 计费和预算限制，制品与缓存另有配额。记录 runner 镜像、Xcode 和 SDK、Flutter 版本、原生依赖版本或哈希、构建变体、制品哈希及产物大小。按排队、构建、制品上传下载、签名安装分别计时。单次冷构建与增量构建耗时目前未知。备选 Codemagic 的个人计划公开列出每月 500 分钟 macOS M2 免费构建额度，团队计划和超额另计。正式 iOS 构建使用 macOS/Xcode 工具链。 [GitHub 用量](https://docs.github.com/en/billing/concepts/product-billing/github-actions) · [Runner 镜像](https://github.com/actions/runner-images) · [Codemagic 计价](https://docs.codemagic.io/billing/pricing/) · [Flutter iOS 环境](https://docs.flutter.dev/platform-integration/ios/setup)
- **制品。** 云端编译并打包供自签的未签名 IPA，同时在受控位置留存与测试构建匹配的 dSYM。签名安装在 Windows 本地完成，仓库、CI、日志和发布制品均不保存账号口令或二次验证码。编译成功后还要分别核对 IPA 结构、最低 OS、设备架构、实际签名后应用身份及所需能力。模板用于参考构建方法，使用前审阅工作流和依赖。 [ipa-builder](https://github.com/adro0303/ipa-builder) · [SwiftUI 模板](https://github.com/hoangnd107/ios-swiftui-app-template) · [Flutter 模板](https://github.com/hoangnd107/flutter-app-template) · [Agent iOS 模板](https://github.com/collinsomniac/ios-agent-app-template)
- **个人签名的官方基线。** Apple Personal Team 的 provisioning profile 自签发起 7 天后到期，最多 10 个 App ID 和 3 台注册测试设备（两者各自同样 7 天到期），每台最多安装 3 个此类 App。高级能力受会员及 entitlement 限制。Apple 文档描述的是 Xcode 个人测试流程，以下工具是第三方实现。首装检查 Developer Mode、设备信任、Windows 设备驱动、2FA 和可用名额。请用一致的签名身份和 bundle ID 测试覆盖安装、续签与数据保留，切换团队或工具时索引、媒体与书签保留须单独验证。 [Apple 个人开发者账号](https://developer.apple.com/help/account/basics/about-your-developer-account/) · [Developer Mode](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)

| 路线 | 适用场景与代价 | 切换条件 |
| --- | --- | --- |
| **Sideloadly + USB**（首选） | Windows 本地签名安装，占用 Fidelune 自身的侧载名额。工具非完整开源。电脑守护进程支持 USB 或首次配对后的同网 Wi-Fi 刷新，电脑需参与，校园网不作保证。根据工具文档检查 Apple 驱动及 iTunes/iCloud 要求。 | USB 主线先区分账号、驱动、设备信任、包结构、签名权限和工具兼容问题，再切备用工具。 [官方 FAQ](https://sideloadly.io/faq) |
| **SideStore**（日常续签候选） | 开源，首次设置后尝试手机端签名/续签。需按工具版本配置配对、网络和本机 VPN（如 LocalDevVPN），与 Clash Mi 的共存情况待测。认证成功、应用安装、刷新后能启动是三个独立结果。 | 在 Sideloadly 主线跑通后按需验证。若 VPN、Apple 认证或刷新不可靠，保留 Sideloadly。 [项目](https://github.com/SideStore/SideStore) · [文档](https://docs.sidestore.io/) |
| **AltStore Classic + AltServer**（安装备选） | Windows 侧 AltServer，USB 或同一局域网运行，AltStore 本身占一个名额。 | Sideloadly 无法稳定签名/安装或刷新时试用。 [Windows 安装文档](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows) |
| **GitHub Releases + 群友自行签名**（小范围分发候选） | 发布可自签制品与说明，各人使用自己的账号承担安装、名额、续签与本地数据保留。SideStore 源可作后续可选分发入口。 | 先证明同一构建可重复验证、签名与安装，并在发布前完成依赖许可检查。 |
| **付费 Apple Developer Program**（正式备选） | 官方列 USD 99/年或当地等价费用。TestFlight 每个构建最多 90 天，外部测试涉及审核。Ad Hoc 依赖登记测试设备及对应描述文件。 | 免费路线持续失效或无法满足群友交付，向发起人提交证据并由其决定是否购买。第三方商用签名有证书撤销、持续性与容器迁移风险，未落实的企业签名不作为开发或分发依赖。 [会员费用与条件](https://developer.apple.com/help/account/membership/program-enrollment/) · [TestFlight](https://developer.apple.com/testflight/) · [设备与 Ad Hoc](https://developer.apple.com/help/account/devices/devices-overview/) |

**社区证据。** 2026-11-24 的 Windows + iOS 27.2.1 个案报告 iLoader 登录 403、SideStore 认证/双重验证异常，Sideloadly 能签装 SideStore，随后解决其中的登录问题，但完整安装/续签仍需各自核验。另有同系统用户报告 iLoader 登录成功、SideStore 内登录失败。此类个案用于排查，不能保证发起人设备上的结果。 [讨论 #1771](https://github.com/orgs/SideStore/discussions/1771) · [问题 #1772](https://github.com/SideStore/SideStore/issues/1772) · [问题 #1755](https://github.com/SideStore/SideStore/issues/1755)

### Windows 本地开发加速候选

| 候选 | 公开能力与验证边界 |
| --- | --- |
| [xtool](https://github.com/xtool-org/xtool) | 原生路线优先考察，WSL/Linux 上使用 Swift、SwiftUI、SwiftPM，项目文档提供编译、个人签名与真机部署路径。Xcode 项目、资源处理与工具链完整性仍需核对。 [文档](https://xtool.sh/documentation/xtool/) |
| [xcross](https://github.com/arxdeus/xcross) | Flutter / Compose 路线可考察。项目声称支持 Windows 上本地开发构建、部署、断点和热重载。Flutter 正式 Release 仍依赖 Mac 或云 macOS。按具体版本实测，不能替代主线。 [项目说明](https://xcross.sh/) |
| [MobAI / ios-builder](https://github.com/MobAI-App/ios-builder) | 云构建（Actions、Codemagic、Bitrise）、模拟器与 Flutter/RN 真机热重载候选。采用前评估额外服务依赖、费用与实际迭代收益。 |
| [Slipway](https://github.com/0xSteph/slipway) | 基于 xtool、go-ios 等整合 SwiftUI 构建、部署和设备管理的 VS Code 候选。 |

先用可复现的云构建测量实际迭代耗时和诊断能力；本地工具只在实测出现明显瓶颈后单独评估。

## P1-T1 · 验证用例与回收证据

以下为待执行用例。阶段 0 仅归档。

1. **构建与首次安装。** 在已有远端仓库接入最小验证构建，使用 Windows 拉取有效制品，在相同 USB 条件下验证签名、首次安装、退出再启动。记录工具版本、构建阶段耗时、失败环节、可复现步骤和已验证的 entitlement，并至少复核一次同身份覆盖安装。
2. **日志与崩溃。** 优先用 [pymobiledevice3](https://github.com/doronz88/pymobiledevice3) 通过已配对 USB 读设备信息、实时系统/应用日志、回收可符号化的崩溃报告。截图、进程、性能与开发者服务按需检验，不把项目的支持列表视为实测。不同系统和服务可能需 Developer Mode、RSD 隧道或匹配开发镜像，iOS 27.2 有兼容问题报告。保留构建与 dSYM 对应关系。若工具服务不可用，尝试设备可导出的系统崩溃报告及应用自身可导出的诊断日志，并记录无法获取的证据。日志须去除凭证、设备标识和私有文件路径。 [排障指南](https://github.com/doronz88/pymobiledevice3/blob/master/docs/guides/troubleshooting.md) · [iOS 27.2 兼容报告](https://github.com/doronz88/pymobiledevice3/issues/1966) · [Apple 崩溃诊断](https://developer.apple.com/documentation/xcode/diagnosing-issues-using-crash-reports-and-device-logs)
3. **续签与数据生命周期。** 在可丢弃的测试容器中写入独立的媒体、组织数据和外部目录书签，核对正常覆盖安装和续签前后均可读取，区分主动测试刷新与实际到期后恢复。更换签名身份、Offload、Delete 的测试使用独立副本并与 P1-T3 联动。不能因新包启动成功就认定原容器仍在。
4. **准出判据。** G1 至少应有可重现的「Windows → 云构建 → 签装 → 真机运行 → 诊断回收」证据。长期刷新、跨工具容器保留和群友安装维护仍分别记录。链路失败先定位层级，再按上表切换，不跳过 G1。

**交接。** P0-T1 基线已记录，P0-T2 的首选与备选已归档。账号可签名、校园网互通、构建耗时、续签、日志回收和数据保留均待测。G0 获确认后接续 P1-T1。
