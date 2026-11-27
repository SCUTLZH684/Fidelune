import '../models/audio_models.dart';

enum AcceptanceGroupId {
  speakerAndPop('扬声器与防爆音基础验证', '无需外接设备，先测同规格无缝、防爆音与坏文件跳过'),
  usbDacRates('USB DAC 原采样率与跨规格切换', '接上 TOPPING DX5 II，核对 DAC 屏幕采样率与无缝/跨规格切换'),
  dsdAndDop('DSD / DoP 安全受控验收', '强制安全检查：需关 iOS「连接到耳机」限幅、音量 100%、调低耳放监听'),
  routingAndSystem('热插拔、路由切换、后台与系统中断', '拔插 DAC、蓝牙/扬声器切换、锁屏控制与来电/计时器中断恢复');

  const AcceptanceGroupId(this.title, this.description);
  final String title;
  final String description;
}

class AcceptanceTestItem {
  const AcceptanceTestItem({
    required this.id,
    required this.group,
    required this.title,
    required this.subtitle,
    required this.estimatedTime,
    required this.requiresUsbDac,
    required this.requiresDopSafety,
    required this.requiresUnplugOrExternalAction,
    required this.steps,
    required this.passCriteria,
    required this.failureTags,
    required this.fixtureFiles,
    this.desiredDsdMode = DsdOutputMode.auto,
    this.desiredPlaybackMode = PlaybackMode.sequential,
    this.dacRateChecklistHz = const [],
  });

  final String id;
  final AcceptanceGroupId group;
  final String title;
  final String subtitle;
  final String estimatedTime;
  final bool requiresUsbDac;
  final bool requiresDopSafety;
  final bool requiresUnplugOrExternalAction;
  final List<String> steps;
  final List<String> passCriteria;
  final List<String> failureTags;
  final List<String> fixtureFiles;
  final DsdOutputMode desiredDsdMode;
  final PlaybackMode desiredPlaybackMode;
  final List<int> dacRateChecklistHz;
}

const List<AcceptanceTestItem> acceptanceCatalog = [
  // Group 1: Speaker & Anti-Pop
  AcceptanceTestItem(
    id: 'H1',
    group: AcceptanceGroupId.speakerAndPop,
    title: '扬声器防爆音：暂停、继续、拖动进度与手动切歌',
    subtitle: '使用高电平稳态纯音验证，彻底排除原 libmpv 方案的切歌/暂停爆音',
    estimatedTime: '约 1 分钟',
    requiresUsbDac: false,
    requiresDopSafety: false,
    requiresUnplugOrExternalAction: false,
    steps: [
      '拔掉外接 DAC，确保路由为「本机扬声器」，将手机音量调至舒适中低档。',
      '点击下方「启动测试音频」播放 poptest-a.flac（持续 440Hz 纯音）。',
      '在发声过程中依次按「暂停」→ 等待 1 秒 →「继续」→ 拖动进度条至中点 → 直接按「下一首」切到 poptest-b.flac。',
    ],
    passCriteria: [
      '暂停、继续、进度拖动、手动切歌全过程仅听到干净平滑过渡，无脉冲“啪/咔”爆音。',
      '界面响应跟手，无卡顿或假播放。',
    ],
    failureTags: ['暂停爆音', '继续爆音', '拖动Seek爆音', '手动切歌爆音'],
    fixtureFiles: ['poptest-a.flac', 'poptest-b.flac'],
  ),
  AcceptanceTestItem(
    id: 'H2',
    group: AcceptanceGroupId.speakerAndPop,
    title: '同规格真正无缝听感（A → B vs 连续原件）',
    subtitle: '对比 continuous.wav 与分片 gap-a.wav → gap-b.wav（非零采样边界切割）',
    estimatedTime: '约 1 分钟',
    requiresUsbDac: false,
    requiresDopSafety: false,
    requiresUnplugOrExternalAction: false,
    steps: [
      '点击「启动测试音频」，系统将先播放 4 秒无缝拼接的 gap-a → gap-b，随后可对比 continuous.wav。',
      '重点聆听第 1 秒刚过（gap-a 到 gap-b 交界处）的连贯性。',
      '同时观察实时链路卡片的「下一首预排队」状态（应在 A 播放时显示已预排队 gap-b）。',
    ],
    passCriteria: [
      'gap-a → gap-b 过渡完全听不出停顿、重复或咔哒声，与 continuous.wav 听感一致。',
      '自动切歌瞬间进度条与曲名同步切换至 gap-b.wav。',
    ],
    failureTags: ['接缝有间隙', '接缝有咔哒声', '未自动切换'],
    fixtureFiles: ['gap-a.wav', 'gap-b.wav', 'continuous.wav'],
  ),
  AcceptanceTestItem(
    id: 'H3',
    group: AcceptanceGroupId.speakerAndPop,
    title: '全格式兼容与损坏/截断文件安全跳过',
    subtitle: '依次验证 ALAC / WAV / WavPack / Opus / MP3 / AAC、坏文件跳过与连续正常续播',
    estimatedTime: '约 1 分钟',
    requiresUsbDac: false,
    requiresDopSafety: false,
    requiresUnplugOrExternalAction: false,
    steps: [
      '点击「启动测试音频」，依次播放 alac96、wv96、opus48、lossy.mp3、lossy.aac、两个损坏 FLAC、截断 FLAC 及末尾正常 flac44100。',
      '等待队列自动跑完，无需手动干预。',
    ],
    passCriteria: [
      'ALAC / WavPack / Opus / MP3 / AAC 均正常出声。',
      '两个损坏 FLAC 自动跳过且无死循环卡死；截断 FLAC 播放完可解码部分后安全进入末尾正常曲目。',
    ],
    failureTags: ['某格式不出声', '坏文件卡死', '崩溃闪退'],
    fixtureFiles: [
      'alac96.m4a',
      'wv96.wv',
      'opus48.opus',
      'lossy.mp3',
      'lossy.aac',
      'invalid.flac',
      'invalid-2.flac',
      'truncated.flac',
      'short.wav',
      'flac44100.flac',
    ],
  ),

  // Group 2: USB DAC Native Sample Rates
  AcceptanceTestItem(
    id: 'D1',
    group: AcceptanceGroupId.usbDacRates,
    title: 'USB DAC 识别与全阶梯原采样率切换 (44.1 → 384 kHz)',
    subtitle: '验证外接 TOPPING DX5 II 是否逐首精准跟随音源采样率，绝不锁定在 48 kHz',
    estimatedTime: '约 2 分钟',
    requiresUsbDac: true,
    requiresDopSafety: false,
    requiresUnplugOrExternalAction: false,
    steps: [
      '插上 USB-C 线连接 TOPPING DX5 II（切换为 USB 输入，先调低耳放输出音量）。',
      '点击「启动测试音频」，依次自动播放 44.1 / 48 / 88.2 / 96 / 176.4 / 192 / 384 kHz 7 首 FLAC。',
      '每首切歌后停留 2 秒，对照 DX5 II 屏幕读数，在下方逐档勾选实际是否匹配（或用「上一首/下一首」微调确认）。',
    ],
    passCriteria: [
      'DX5 II 屏幕逐首显示与音源一致的采样率（至少 44.1 ~ 192 kHz 必须 100% 匹配，384 kHz 如实记录设备是否支持）。',
      '跨采样率切歌允许短暂重锁静音间隔（默认 180 ms），但不得有刺耳脉冲爆音或吞掉开头过多声音。',
      '信号链路面板显示「无应用层重采样」，iOS 会话采样率与音源一致。',
    ],
    failureTags: ['DAC锁在48kHz', '高频档位失效', '切频爆音', '切频吞音'],
    fixtureFiles: [
      'flac44100.flac',
      'flac48000.flac',
      'flac88200.flac',
      'flac96000.flac',
      'flac176400.flac',
      'flac192000.flac',
      'flac384000.flac',
    ],
    dacRateChecklistHz: [44100, 48000, 88200, 96000, 176400, 192000, 384000],
  ),
  AcceptanceTestItem(
    id: 'D2',
    group: AcceptanceGroupId.usbDacRates,
    title: 'USB DAC 混合规格、同采样率位深/声道与无缝队列',
    subtitle: '检验 96 kHz 同规格无缝 + 44.1→96→192→48 跨规格切换 + 16/24-bit 与单声道',
    estimatedTime: '约 1.5 分钟',
    requiresUsbDac: true,
    requiresDopSafety: false,
    requiresUnplugOrExternalAction: false,
    steps: [
      '保持连接 USB DAC，点击「启动测试音频」。',
      '队列先播 gap96-a.flac → gap96-b.flac（96kHz/24bit 无缝切换，观察 DX5 II 不得失锁闪烁），再自动跨规格切到 192kHz → 48kHz 16-bit → 48kHz 24-bit → 48kHz 单声道。',
      '可测试 1 次快按「下一首」和 1 次拖动进度，观察防爆音与最新命令优先响应。',
    ],
    passCriteria: [
      '96kHz 同规格切换时 DX5 II 保持 96 kHz 稳定锁定且无缝过渡；跨规格切换时屏幕准确跟随。',
      '手动切换、快切与拖动进度均无爆音、不卡死。',
    ],
    failureTags: ['96k无缝闪烁', '单声道异常', '快切错乱', '爆音'],
    fixtureFiles: [
      'gap96-a.flac',
      'gap96-b.flac',
      'flac192000.flac',
      'wav16.wav',
      'wav24.wav',
      'mono24.wav',
    ],
  ),

  // Group 3: DSD / DoP Safety-Gated
  AcceptanceTestItem(
    id: 'P1',
    group: AcceptanceGroupId.dsdAndDop,
    title: 'DSD64 原生 DoP 点灯测试 (2.8224 MHz → 176.4 kHz 载体)',
    subtitle: '验证 BASSDSD 2.4.2 DoP 输出能否让 DX5 II 正确识别并点亮 DSD 指示',
    estimatedTime: '约 30 秒',
    requiresUsbDac: true,
    requiresDopSafety: true,
    requiresUnplugOrExternalAction: false,
    steps: [
      '务必先调低 DX5 II 耳放监听音量（如 -40 dB 以下），在 iOS「设置 → 声音与触感反馈 → 耳机安全」将 USB 设备设为「其他设备」，并将 iPhone 音量调到 100%。',
      '点击「启动测试音频」（系统会自动完成安全核验弹窗）。',
      '观察 DX5 II 屏幕显示是否从 PCM 切为「DSD 2.82M / DSD64」，然后缓缓调大一点点耳放音量聆听 431Hz/553Hz 纯正测试音。',
    ],
    passCriteria: [
      'DX5 II 面板明确显示 DSD64 / 2.82 MHz（绝非 PCM 176.4 kHz 或 48 kHz）。',
      '听感为左右声道清晰的温和纯音，无刺耳白噪或底噪爆裂。',
      '暂停与停止时平稳静音，无刺耳爆音。',
    ],
    failureTags: ['只显示PCM176.4', '只显示48k', '刺耳白噪', '启停爆音'],
    fixtureFiles: ['dsd64.dsf'],
    desiredDsdMode: DsdOutputMode.dop,
  ),
  AcceptanceTestItem(
    id: 'P2',
    group: AcceptanceGroupId.dsdAndDop,
    title: 'DSD128 DoP 点灯与 PCM ↔ DoP ↔ PCM 安全切换',
    subtitle: '验证 352.8 kHz DoP 载体及 PCM 与 DoP 互相切换的防爆音静音帧保护',
    estimatedTime: '约 1 分钟',
    requiresUsbDac: true,
    requiresDopSafety: true,
    requiresUnplugOrExternalAction: false,
    steps: [
      '保持耳放低监听音量与 iPhone 100% 音量。',
      '点击「启动测试音频」播放队列：flac44100.flac → dsd64.dsf → dsd128.dsf → flac96000.flac。',
      '观察每首切换时 DX5 II 是否依次显示：44.1 PCM → DSD64 → DSD128 (5.64M) → 96 PCM。',
    ],
    passCriteria: [
      'DSD64 与 DSD128 均正确点亮 DSD，且切回 96 kHz PCM 后正常退出 DSD 模式。',
      'PCM ↔ DoP 切换过程有短暂静音过渡，无大声爆鸣或单侧尖叫。',
    ],
    failureTags: ['DSD128不识别', '切回PCM无声', '切换爆音'],
    fixtureFiles: ['flac44100.flac', 'dsd64.dsf', 'dsd128.dsf', 'flac96000.flac'],
    desiredDsdMode: DsdOutputMode.dop,
  ),
  AcceptanceTestItem(
    id: 'P3',
    group: AcceptanceGroupId.dsdAndDop,
    title: 'DoP 安全拦截与非 USB 路由 DSD → PCM 自动降级',
    subtitle: '验证音量低于 100% 或拔掉 DAC 时，系统绝不错误透传 DoP 导致白噪',
    estimatedTime: '约 1 分钟',
    requiresUsbDac: false,
    requiresDopSafety: false,
    requiresUnplugOrExternalAction: true,
    steps: [
      '场景 A（若已连 USB DAC）：将 iPhone 侧边音量按低一格（< 100%），切到「强制 DoP」后播放 dsd64.dsf，确认是否被立刻拦截阻止并弹出安全提示。',
      '场景 B：切回「自动 (USB DAC 优先 DoP)」，拔掉 DAC 用扬声器播放 dsd64.dsf。',
    ],
    passCriteria: [
      '音量不满 100% 时强制 DoP 立即拦截报错，绝不向 DAC 发送残缺 DoP 造成白噪。',
      '扬声器下自动模式安全转为 PCM 播放并清晰标注「DSD → PCM（非原生 DoP）」，听感正常。',
    ],
    failureTags: ['未拦截低音量DoP', '扬声器播DoP出白噪'],
    fixtureFiles: ['dsd64.dsf'],
    desiredDsdMode: DsdOutputMode.auto,
  ),

  // Group 4: Hot-Plug, Background & Interruptions
  AcceptanceTestItem(
    id: 'R1',
    group: AcceptanceGroupId.routingAndSystem,
    title: 'USB DAC 热插拔防外放与重插恢复',
    subtitle: '验证拔出 DAC 秒停防外放，插回 DAC 后手动继续能恢复原曲原采样率',
    estimatedTime: '约 1 分钟',
    requiresUsbDac: true,
    requiresDopSafety: false,
    requiresUnplugOrExternalAction: true,
    steps: [
      '接好 USB DAC，点击「启动测试音频」播放 96 kHz FLAC。',
      '播放至第 2～3 秒时直接拔掉 USB-C DAC，确认手机扬声器不会突然外放声音。',
      '等待 3 秒后重新插回 USB DAC，观察路由刷新为 USB DAC 后点击「继续播放」。',
    ],
    passCriteria: [
      '拔出 DAC 瞬间立即安全暂停，零意外扬声器外放。',
      '插回 DAC 后路由状态正确更新，手动继续从断点恢复播放且 DX5 II 重新显示 96 kHz。',
    ],
    failureTags: ['拔出后意外外放', '插回后假播放无声', '插回降回48k'],
    fixtureFiles: ['flac96000.flac', 'flac44100.flac'],
  ),
  AcceptanceTestItem(
    id: 'R2',
    group: AcceptanceGroupId.routingAndSystem,
    title: '后台播放与锁屏控制中心双向同步',
    subtitle: '验证锁屏息屏连续播放、切歌、暂停/继续与进度条控制（支持任意路由）',
    estimatedTime: '约 1.5 分钟',
    requiresUsbDac: false,
    requiresDopSafety: false,
    requiresUnplugOrExternalAction: true,
    steps: [
      '点击「启动测试音频」（列表循环），按 Home/上滑返回桌面静听 20 秒，再按电源键锁屏。',
      '在锁屏界面核对曲名、艺术家、进度条，并依次在锁屏上操作：暂停 → 继续 → 下一首 → 拖动进度条。',
      '解锁返回 App 核对界面进度与锁屏操作是否完全同步。',
    ],
    passCriteria: [
      '后台与锁屏全程不断音、无卡顿；锁屏信息与进度准确。',
      '锁屏暂停、继续、切歌、进度拖动全部生效，且无爆音。',
    ],
    failureTags: ['锁屏断音', '锁屏控件无响应', '锁屏切歌爆音'],
    fixtureFiles: ['flac44100.flac', 'alac96.m4a', 'flac192000.flac', 'lossy.aac'],
    desiredPlaybackMode: PlaybackMode.repeatAll,
  ),
  AcceptanceTestItem(
    id: 'R3',
    group: AcceptanceGroupId.routingAndSystem,
    title: '系统中断（来电 / 计时器 / 闹钟）暂停与恢复',
    subtitle: '验证播放中触发中断能暂停，结束允许恢复时从原位置续播（并保住采样率）',
    estimatedTime: '约 1.5 分钟',
    requiresUsbDac: false,
    requiresDopSafety: false,
    requiresUnplugOrExternalAction: true,
    steps: [
      '点击「启动测试音频」播放列表循环，打开 iPhone「时钟」设置一个 10 秒计时器（或使用另一手机来电）。',
      '计时器响铃时观察音乐是否自动暂停；等待铃声停止/点击关闭计时器（或挂断来电）。',
      '再手动暂停播放后测一次短闹钟，验证原本处于暂停状态时结束后不会自己突然起播。',
    ],
    passCriteria: [
      '播放中遇中断立即暂停；中断结束且系统允许恢复时，从原位置自动或正常续播，不出现假播放无声。',
      '原本手动暂停的状态遇中断结束后保持暂停，不误自动起播。',
    ],
    failureTags: ['中断后不恢复', '恢复假播放无声', '原暂停被误拉起'],
    fixtureFiles: ['flac44100.flac', 'flac96000.flac'],
    desiredPlaybackMode: PlaybackMode.repeatAll,
  ),
];
