# Fidelune P1-T1 验证工程

用 Flutter 3.44.0 的 iOS 模板验证从 Windows 经云构建到 iPhone 签装和诊断的流程。原生桥接只负责生成可丢弃的测试数据、保存外部目录书签以及产生诊断证据。实测结果见[阶段 1 报告](../../docs/verification/PHASE1_POC_REPORT.md)。

## 云构建与制品

[P1-T1 unsigned iOS](https://github.com/SCUTLZH684/Fidelune/actions/workflows/p1-t1-ios.yml) 可手动运行。验证工程或工作流更新到 main 时也会触发。A、A-repeat、B 分别在独立的 macOS runner 冷构建。A 和 A-repeat 使用相同提交及构建号 1，B 使用相同的 Bundle ID 和构建号 2。工作流在打包前核对主程序无签名、arm64、Bundle ID、构建号和 Runner dSYM 的 UUID。

各 job 上传独立的 IPA、`build-info.txt` 和符号制品，保留 14 天。将各制品解压到不同目录。在 Windows 用 `Get-FileHash -Algorithm SHA256 .\fidelune-p1t1-unsigned.ipa` 与同目录的元数据比对。符号制品只含公开源码对应的云构建符号，访问范围和有效期由 GitHub Actions 控制。回收崩溃后保留匹配 UUID 的符号副本，避免制品到期后重建导致 UUID 不匹配。

## USB 签装与数据检查

1. 用数据线连接并解锁 iPhone，允许信任此电脑。确认开发者模式已开启。用 [Sideloadly 官网](https://sideloadly.io/) 的 Windows 版和它要求的 Apple 组件。用普通 Apple 账号在 Sideloadly 本机输入密码和验证码，选择 USB 设备和 A 的 IPA，启用刷新登记，保持默认 Bundle ID。首次打开如提示不受信任，在 iPhone 的「设置 → 通用 → VPN 与设备管理」信任自己的开发者身份。
2. 打开 A，确认显示构建 1。点「写入测试数据」，记下媒体摘要和组织记录标记。在「文件」App 的本机位置新建空测试目录，并在其中新建名为 `P1T1-marker` 的子目录。回到验证应用，点「选择外部测试目录」，选择这个子目录的上一级。确认显示书签摘要与「标记可读」。从应用切换器划掉应用后重新打开，核对三个值。
3. 用同一个账号、签名团队、Bundle ID 和签名设置，在 USB 上安装 B。保持 A 已安装。打开 B，确认显示构建 2，并在重新写入或重新选择前核对同一组值。核对 Sideloadly 实际签装时使用的 Bundle ID 与团队一致。
4. 对当前版本执行 Sideloadly 的主动刷新，复测启动与三项数据。记录刷新请求、安装结果、用时及描述文件的签发/到期信息。若描述文件到期时间未变化，记录本次签装成功及到期日变化未证实。保留测试包和数据，到期前自动刷新与自然到期后恢复分别记录。以设备上的实际描述文件和启动结果为准。

## Windows 诊断

使用 [pymobiledevice3 官方文档](https://doronz88.github.io/pymobiledevice3/) 安装工具。先确认 USB 配对，设备列表的标识留在本机。用下列命令过滤应用日志。在应用点「发送诊断日志」，检查收到 `FIDELUNE_P1T1 diagnostic marker`。

```powershell
python -m pymobiledevice3 syslog live --process-name Runner --match FIDELUNE_P1T1
```

点「验证崩溃回收」并确认，待系统生成诊断后，仅复制 Runner 的记录到仓库外的临时目录。命令默认保留手机上的报告。

```powershell
python -m pymobiledevice3 crash pull "$env:TEMP\Fidelune-P1-T1-crash" --match '^Runner[-_].*\.ips$'
```

检查报告属于 Fidelune P1-T1，Runner 镜像 UUID 与对应构建的 dSYM 一致。符号化可用同版本 Xcode 的 `atos` 加载 dSYM，提供镜像基址与故障栈帧地址。对于 JSON 格式的 `.ips`，栈帧绝对地址为匹配镜像基址加 `imageOffset`。如果 USB 回收失败，检查 iPhone「设置 → 隐私与安全性 → 分析与改进 → 分析数据」是否能导出对应报告，并在结果中注明来源。

仓库和公开报告只保留测试用例、耗时、公开构建标识与脱敏结论。Apple 账号、密码、验证码、设备标识、签名描述文件、配对文件、书签二进制、已签名 IPA 和原始设备日志均留在本机。
