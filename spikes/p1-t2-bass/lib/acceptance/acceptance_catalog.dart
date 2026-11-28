import '../models/audio_models.dart';

enum AcceptanceGroupId {
  speakerAntiPop('1. 扬声器防爆音与同规格无缝复测', '拔掉外接 DAC，复测暂停/Seek/切歌防爆音及独立 A/B 无缝听感'),
  usbDacRates('2. USB DAC 8 档原采样率（含 352.8 kHz）与无缝保持', '接上 TOPPING DX5 II，先运行 8 档自动握手，再人工核对 DAC 面板读数与稳定性'),
  lockAndRouting('3. 锁屏播控、热插拔与中断恢复复测', '验证锁屏卡片恢复、双向控件及热插拔/闹钟后 96 kHz 稳定保持'),
  dsdAndDop('4. DSD / DoP 安全闭环与硬件点灯（须先拔耳机）', '安全警示：涉及 DoP 测试必须先从 DAC/耳放物理拔下耳机，确认面板点亮后再最小音量试听');

  const AcceptanceGroupId(this.title, this.description);
  final String title;
  final String description;
}

class TestSubAction {
  const TestSubAction({
    required this.id,
    required this.label,
    required this.description,
    required this.fixtureFiles,
    this.dsdMode = DsdOutputMode.auto,
    this.playbackMode = PlaybackMode.sequential,
    this.requiresDopSafety = false,
    this.requiresVolumeBelowFull = false,
  });

  final String id;
  final String label;
  final String description;
  final List<String> fixtureFiles;
  final DsdOutputMode dsdMode;
  final PlaybackMode playbackMode;
  final bool requiresDopSafety;
  final bool requiresVolumeBelowFull;
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
    required this.requiresHeadphonesUnplugged,
    required this.observeGuide,
    required this.judgeGuide,
    required this.steps,
    required this.passCriteria,
    required this.failureTags,
    required this.subActions,
    this.supportsRateSweep = false,
    this.dacRateChecklistHz = const [],
  });

  final String id;
  final AcceptanceGroupId group;
  final String title;
  final String subtitle;
  final String estimatedTime;
  final bool requiresUsbDac;
  final bool requiresDopSafety;
  final bool requiresHeadphonesUnplugged;
  final String observeGuide;
  final String judgeGuide;
  final List<String> steps;
  final List<String> passCriteria;
  final List<String> failureTags;
  final List<TestSubAction> subActions;
  final bool supportsRateSweep;
  final List<int> dacRateChecklistHz;

  List<String> get fixtureFiles => subActions.isEmpty ? const [] : subActions.first.fixtureFiles;
  DsdOutputMode get desiredDsdMode => subActions.isEmpty ? DsdOutputMode.auto : subActions.first.dsdMode;
  PlaybackMode get desiredPlaybackMode => subActions.isEmpty ? PlaybackMode.sequential : subActions.first.playbackMode;
}

const List<AcceptanceTestItem> acceptanceCatalog = [
  // Group 1
  AcceptanceTestItem(
    id: 'T1',
    group: AcceptanceGroupId.speakerAntiPop,
    title: '扬声器防爆音（暂停/拖动/切歌）与同规格 A/B 真无缝',
    subtitle: '针对 Build #7 H1 爆音与 H2 接缝测试失真的定向修复复测（无需外接 DAC）',
    estimatedTime: '约 1 分钟',
    requiresUsbDac: false,
    requiresDopSafety: false,
    requiresHeadphonesUnplugged: false,
    observeGuide: '听声是否出现清脆“啪/咔”脉冲爆音；听 6 秒无缝组第 3.0 秒接缝是否如连续原件般平滑无缺口。',
    judgeGuide: '暂停/继续/松手拖动进度/下一首全无爆音，且「拼接组 A→B」第 3.0 秒与「连续原件」听感一致即通过。',
    steps: [
      '按什么：拔掉 USB DAC（确保路由为「本机扬声器」），点「动作 1」，发声时依次按 暂停→继续→拖进度条松手→下一首。',
      '再按什么：依次点「动作 2（拼接组 6秒）」与「动作 3（连续原件 6秒）」分别试听第 3.0 秒前后是否一致。',
      '怎么判断：全过程无瞬间脉冲爆音，且动作 2 第 3 秒交界处听不出任何停顿或咔哒声。',
    ],
    passCriteria: [
      '暂停、继续、松手 Seek、手动下一首均平稳过渡，零脉冲爆音。',
      'gap-a → gap-b（6 秒拼接）第 3 秒交界处零咔哒、零缺口，与 continuous 原件听感一致。',
    ],
    failureTags: ['暂停爆音', '继续爆音', '拖动Seek爆音', '手动切歌爆音', '接缝有咔哒/间隙'],
    subActions: [
      TestSubAction(
        id: 't1_pop',
        label: '动作 1：播放防爆音测试 (poptest-a → b)',
        description: '持续稳态纯音，依次测 暂停 → 继续 → 拖进度松手 → 下一首',
        fixtureFiles: ['poptest-a.flac', 'poptest-b.flac'],
      ),
      TestSubAction(
        id: 't1_gap_ab',
        label: '动作 2：播放无缝拼接组 (gap-a → gap-b, 6秒)',
        description: '仅播 A→B（不再串联原件），重点听第 3.0 秒无缝过渡',
        fixtureFiles: ['gap-a.wav', 'gap-b.wav'],
      ),
      TestSubAction(
        id: 't1_gap_ref',
        label: '动作 3：播放连续原件对照 (continuous, 6秒)',
        description: '未切分连续参考音，用于对比动作 2 的第 3 秒听感',
        fixtureFiles: ['continuous.wav'],
      ),
    ],
  ),

  // Group 2
  AcceptanceTestItem(
    id: 'T2',
    group: AcceptanceGroupId.usbDacRates,
    title: 'USB DAC 8 档原采样率锁定（含 352.8 kHz）与切频过渡',
    subtitle: '验证独占 AudioSession + 轮询切频修复后，DX5 II 是否 8 档全跟随且切频不爆音',
    estimatedTime: '约 2 分钟',
    requiresUsbDac: true,
    requiresDopSafety: false,
    requiresHeadphonesUnplugged: false,
    supportsRateSweep: true,
    observeGuide: '先看机器自动握手 8 档状态，再对照 DX5 II 前面板每档读数（重点必核 352.8 kHz），并听切频时是否有爆音。',
    judgeGuide: '必须全部 8 档（含 352.8 kHz）在 DX5 II 屏幕都显示为「匹配」，且切频只有短暂静音、无刺耳爆音才可通过。',
    steps: [
      '按什么：连上 DX5 II（调低监听音量），先点下方「一键自动探测 8 档采样率握手」，等待约 2~4 秒。',
      '再按什么：点「动作 1：播 8 档全阶梯」逐首停 2 秒核对 DX5 II 屏幕，如切过太快可点「动作 2」单独核对 352.8 kHz。',
      '怎么判断：下方 8 档屏幕读数（44.1 ~ 384 kHz，含 352.8 kHz）全部点选为「匹配」，且无切频爆音。',
    ],
    passCriteria: [
      '8 档（44.1 / 48 / 88.2 / 96 / 176.4 / 192 / 352.8 / 384 kHz）机器握手与 DX5 II 屏幕读数均准确匹配。',
      '跨规格切换允许短静音重锁，不得产生脉冲爆音。',
    ],
    failureTags: ['DAC锁在48kHz', '352.8k/384k失效', '切频爆音', '切频吞音过多'],
    dacRateChecklistHz: [44100, 48000, 88200, 96000, 176400, 192000, 352800, 384000],
    subActions: [
      TestSubAction(
        id: 't2_ladder',
        label: '动作 1：播放 8 档全阶梯 (44.1 → 384 kHz)',
        description: '逐档核对 DX5 II 屏幕读数与切频听感',
        fixtureFiles: [
          'flac44100.flac',
          'flac48000.flac',
          'flac88200.flac',
          'flac96000.flac',
          'flac176400.flac',
          'flac192000.flac',
          'flac352800.flac',
          'flac384000.flac',
        ],
      ),
      TestSubAction(
        id: 't2_3528',
        label: '动作 2：单独复测 352.8 kHz (flac352800)',
        description: '单独锁定 DSD128 DoP 同源母频 352.8 kHz',
        fixtureFiles: ['flac352800.flac'],
      ),
    ],
  ),
  AcceptanceTestItem(
    id: 'T3',
    group: AcceptanceGroupId.usbDacRates,
    title: 'USB DAC 96 kHz 无缝稳态保持与跨规格 / 单声道切换',
    subtitle: '复测 Build #7 D2 半途掉频（96k→44.1k、192k→48k）与第 3 秒接缝表现',
    estimatedTime: '约 1.5 分钟',
    requiresUsbDac: true,
    requiresDopSafety: false,
    requiresHeadphonesUnplugged: false,
    observeGuide: '死盯 DX5 II 屏幕 6 秒：96k 拼接与连续播完过程中不得中途闪回 44.1/48k；跨规格队列逐首跟频。',
    judgeGuide: '6 秒全程稳锁 96 kHz 不闪烁、不掉频、第 3.0 秒零咔哒，且 96→192→48(双/单声道) 准确跟频无爆音。',
    steps: [
      '按什么：点「动作 1（96k 无缝拼接 6秒）」，盯住 DX5 II 屏幕从头到尾 6 秒，可再点「动作 2」对比连续原件。',
      '再按什么：点「动作 3（跨规格 96k→192k→48k 单/双声道）」观察屏幕依序切换至 96 → 192 → 48 kHz 并保持到曲终。',
      '怎么判断：全程不出现播到一半突然掉回 44.1/48 kHz，第 3.0 秒无缝无咔哒，切频/快切/单声道均正常出声无爆音。',
    ],
    passCriteria: [
      'gap96-a → gap96-b 全程 6 秒 DX5 II 稳锁 96 kHz，不失锁闪烁、不半途降频、无接缝咔哒。',
      '192 kHz 与 48 kHz（16b / 24b / 单声道）准确锁频，不降频且无爆音。',
    ],
    failureTags: ['播中掉回44.1/48k', '96k无缝咔哒或闪烁', '单声道异常', '爆音'],
    subActions: [
      TestSubAction(
        id: 't3_gap96',
        label: '动作 1：96k 无缝拼接 (gap96-a → gap96-b, 6秒)',
        description: '验证 96 kHz 6 秒全程稳锁且第 3 秒无缝切换',
        fixtureFiles: ['gap96-a.flac', 'gap96-b.flac'],
      ),
      TestSubAction(
        id: 't3_ref96',
        label: '动作 2：96k 连续原件对照 (continuous96, 6秒)',
        description: '连续 96 kHz 参考曲',
        fixtureFiles: ['continuous96.flac'],
      ),
      TestSubAction(
        id: 't3_cross',
        label: '动作 3：跨规格队列 (96k → 192k → 48k 16/24b/单声道)',
        description: '检验跨采样率不半途掉频与单声道兼容性',
        fixtureFiles: ['flac96000.flac', 'flac192000.flac', 'wav16.wav', 'wav24.wav', 'mono24.wav'],
      ),
    ],
  ),

  // Group 3
  AcceptanceTestItem(
    id: 'T4',
    group: AcceptanceGroupId.lockAndRouting,
    title: '后台与锁屏 / 控制中心媒体组件恢复及双向播控',
    subtitle: '复测 Build #7 R2 锁屏组件丢失与取消 .mixWithOthers 后的原生控件表现',
    estimatedTime: '约 1.5 分钟',
    requiresUsbDac: false,
    requiresDopSafety: false,
    requiresHeadphonesUnplugged: false,
    observeGuide: '锁屏上必须出现 Fidelune 媒体卡片（显示歌名/采样率）并响应暂停、播放、上一首、下一首与进度条拖动。',
    judgeGuide: '连播不断音，锁屏媒体卡片清晰可见、所有控件双向同步生效、无爆音，且后台不令 USB DAC 掉回 44.1/48k。',
    steps: [
      '按什么：点「动作 1（启动 96k/192k 循环队列）」（推荐插 USB DAC 一并核对锁屏采样率保持），上滑桌面听 10 秒后按电源键锁屏。',
      '观察什么：唤醒屏幕看锁屏是否有播放控制卡片；依次在锁屏点击：暂停 → 播放 → 下一首（切到 192k）→ 上一首 → 拖进度条。',
      '怎么判断：锁屏卡片正常显示、操控全部即时同步到 App 与 DAC（不掉回 48k），且切歌/拖动无爆音。',
    ],
    passCriteria: [
      '锁屏与控制中心正常展示曲目卡片与实时进度。',
      '锁屏暂停、播放、上一首、下一首、进度条拖动全部双向同步且无爆音。',
      '后台及锁屏切歌期间 USB DAC 仍稳锁原采样率（96 / 192 kHz）。',
    ],
    failureTags: ['锁屏仍无媒体组件', '锁屏控件无响应', '后台掉回44.1/48k', '锁屏切歌爆音'],
    subActions: [
      TestSubAction(
        id: 't4_lock',
        label: '动作 1：启动后台与锁屏队列 (96k ↔ 192k ↔ 44.1k)',
        description: '列表循环，包含 12 秒 96kHz 曲目，锁屏操作更从容',
        fixtureFiles: ['flac96000.flac', 'flac192000.flac', 'flac44100.flac', 'alac96.m4a'],
        playbackMode: PlaybackMode.repeatAll,
      ),
    ],
  ),
  AcceptanceTestItem(
    id: 'T5',
    group: AcceptanceGroupId.lockAndRouting,
    title: 'USB 热插拔防外放 + 插回 / 计时器中断后 96 kHz 稳定保持',
    subtitle: '使用 12 秒 96 kHz 曲目复测 Build #7 R1/R3 后半段掉频与中断恢复异常',
    estimatedTime: '约 1.5 分钟',
    requiresUsbDac: true,
    requiresDopSafety: false,
    requiresHeadphonesUnplugged: false,
    observeGuide: '拔线秒停绝不外放；插回继续后盯住 DX5 II 屏幕直到 12 秒播完，以及 10 秒计时器关闭续播后均稳定保持 96 kHz。',
    judgeGuide: '拔出零外放 + 插回恢复 96 kHz 不半途掉回 44.1k + 计时器中断结束后正常续播并锁在 96 kHz（手动暂停不被误拉起）。',
    steps: [
      '按什么（热插拔）：接好 USB DAC，点「动作 1（12秒 96k 循环）」，播到第 3 秒直接拔 USB 线 → 确认手机不外放 → 等 2 秒插回点「继续」盯到曲终。',
      '按什么（中断）：保持 96k 播放打开 iPhone「时钟」设 10 秒计时器，响铃时看音乐是否暂停，点关闭计时器看是否自动恢复 96 kHz。',
      '追加验证：手动暂停后用 5 秒计时器闹铃一次，关闭闹铃时原本暂停的音乐不得误自动起播。',
    ],
    passCriteria: [
      '拔出 USB DAC 秒停零外放；插回继续后 DX5 II 锁回 96 kHz 且不再中途掉回 44.1/48k。',
      '系统计时器中断暂停后关闭闹铃可自动续播并保持 96 kHz；手动暂停遇中断不误起播。',
    ],
    failureTags: ['拔出后意外外放', '插回/续播降回44.1/48k', '中断后不恢复或假播放', '原暂停被误拉起'],
    subActions: [
      TestSubAction(
        id: 't5_hold96',
        label: '动作 1：启动 96 kHz 12 秒稳态测试 (循环)',
        description: '专用于 USB 热插拔与闹钟中断后采样率保持验证',
        fixtureFiles: ['flac96000.flac', 'flac44100.flac'],
        playbackMode: PlaybackMode.repeatAll,
      ),
    ],
  ),

  // Group 4: DSD / DoP Safety-Gated
  AcceptanceTestItem(
    id: 'T6',
    group: AcceptanceGroupId.dsdAndDop,
    title: 'DoP 全程安全保护闭环（低音量拦截 + 播中降音量熔断 + 扬声器转 PCM）',
    subtitle: '修复 Build #7 P3 逻辑缺陷：3 个独立按钮分别验证强制 DoP 起播拦截与实时熔断',
    estimatedTime: '约 1 分钟',
    requiresUsbDac: false,
    requiresDopSafety: false,
    requiresHeadphonesUnplugged: true,
    observeGuide: '务必先物理拔掉耳机！场景 A 低音量下点击即弹安全拦截；场景 B 100% 播起后按音量减键 0.1 秒内立即静默停播；场景 C 扬声器安全出声。',
    judgeGuide: '3 个独立场景全部严格符合安全预期、任何情况下绝无 DoP 白噪脉冲即通过。',
    steps: [
      '安全前置：必须先从 DX5 II / 耳放物理拔下耳机！',
      '场景 A：接 USB DAC 时先按手机音量减键调低 1 格（<100%），点下方「场景 A（强制 DoP 拦截）」，核对是否立刻阻止并报错。',
      '场景 B：将手机音量调回 100%，点「场景 B（播中按音量减熔断）」解锁起播 dsd64（无耳机看界面运行），立即按一下手机音量减键，核对是否 0.1 秒内紧急停播。',
      '场景 C：拔掉 USB DAC（本机扬声器），点「场景 C（扬声器自动转 PCM）」，确认状态显示 DSD → PCM 且为柔和纯音。',
    ],
    passCriteria: [
      '低音量起播（强制 DoP）立即弹出 dop_volume_not_full 安全拦截，绝不透传残缺 DoP。',
      'DoP 播放期间按一下音量减键（或拔线）0.1 秒内立即紧急静音停止，无白噪漏出。',
      '扬声器路由下「自动模式」安全转为 PCM 输出，听感为柔和纯音。',
    ],
    failureTags: ['未拦截低音量DoP', '播中降音量未立即熔断', '扬声器误出白噪'],
    subActions: [
      TestSubAction(
        id: 't6_low_vol',
        label: '场景 A：验证低音量起播拦截（强制 DoP，先调低1格）',
        description: '必须先将 iPhone 侧边音量调低于 100%，再点击测试拦截',
        fixtureFiles: ['dsd64.dsf'],
        dsdMode: DsdOutputMode.dop,
        requiresDopSafety: false,
        requiresVolumeBelowFull: true,
      ),
      TestSubAction(
        id: 't6_mid_vol',
        label: '场景 B：验证播中降音量熔断（调回100%，起播后按音量-）',
        description: '确认已拔耳机！100% 音量解锁起播 DSD64 后立刻按音量减键触发熔断',
        fixtureFiles: ['dsd64.dsf'],
        dsdMode: DsdOutputMode.dop,
        requiresDopSafety: true,
      ),
      TestSubAction(
        id: 't6_speaker',
        label: '场景 C：验证非 USB 路由自动转 PCM（拔掉 USB 线点我）',
        description: '扬声器路由下自动安全转为 DSD → PCM 播放',
        fixtureFiles: ['dsd64.dsf'],
        dsdMode: DsdOutputMode.auto,
        requiresDopSafety: false,
      ),
    ],
  ),
  AcceptanceTestItem(
    id: 'T7',
    group: AcceptanceGroupId.dsdAndDop,
    title: 'DSD64 / DSD128 原生 DoP 点灯与 PCM ↔ DoP 切换（须先拔耳机）',
    subtitle: 'Build #7 未测项（P1+P2）首次真机硬件点灯核对，修复丢帧对齐后再试听',
    estimatedTime: '约 1.5 分钟',
    requiresUsbDac: true,
    requiresDopSafety: true,
    requiresHeadphonesUnplugged: true,
    observeGuide: '先看空载（不插耳机）下 DX5 II 面板是否点亮 DSD64 (2.82M) 与 DSD128 (5.64M)；确认锁灯无误后再用耳放最低音量插耳机试听！',
    judgeGuide: 'DX5 II 面板正确点亮 DSD64 与 DSD128（绝非 PCM176.4/352.8），耳放最小音量下听到温和纯音且切换 PCM↔DoP 无白噪爆音。',
    steps: [
      '第 1 步（务必先物理拔下耳机）：在 iOS 耳机安全把 USB 设备设为「其他设备」，手机音量调到 100%，将 DX5 II 耳放旋钮拧至最低（<-50dB）。',
      '第 2 步（空载看灯）：依次点「步骤 1（DSD64）」与「步骤 2（DSD128）」，仅盯住 DX5 II 屏幕确认点亮 DSD64 / DSD128。',
      '第 3 步（谨慎听音）：确认屏幕上确实点亮 DSD 后，确保耳放处于最低监听音量再插上耳机，重播步骤 1/2 及「步骤 3（混合切换）」，确认是纯音无白噪。',
    ],
    passCriteria: [
      'DX5 II 面板明确显示 DSD64 (2.82M) 与 DSD128 (5.64M)（非 PCM 指示）。',
      '最低耳放音量下听感为温和纯音，无刺耳全幅白噪。',
      'PCM 44.1k → DSD64 → DSD128 → PCM 96k 切换平稳，切回 PCM 后正常发声。',
    ],
    failureTags: ['只显示PCM未点亮DSD', 'DSD128不识别', '有刺耳白噪(立即拔线停播!)', 'PCM与DoP切换爆音'],
    subActions: [
      TestSubAction(
        id: 't7_dsd64',
        label: '步骤 1：空载点亮 DSD64 (176.4k DoP 载波, 6秒)',
        description: '确认已拔耳机、手机音量 100%，先看 DX5 II 屏幕是否点亮 DSD64',
        fixtureFiles: ['dsd64.dsf'],
        dsdMode: DsdOutputMode.dop,
        requiresDopSafety: true,
      ),
      TestSubAction(
        id: 't7_dsd128',
        label: '步骤 2：空载点亮 DSD128 (352.8k DoP 载波, 3秒)',
        description: '看 DX5 II 屏幕是否点亮 DSD128 / 5.64M',
        fixtureFiles: ['dsd128.dsf'],
        dsdMode: DsdOutputMode.dop,
        requiresDopSafety: true,
      ),
      TestSubAction(
        id: 't7_mixed',
        label: '步骤 3：混合切换 (44.1k PCM → DSD64 → DSD128 → 96k PCM)',
        description: '确认已点亮 DSD 后再低音量插耳机核对切换听感',
        fixtureFiles: ['flac44100.flac', 'dsd64.dsf', 'dsd128.dsf', 'flac96000.flac'],
        dsdMode: DsdOutputMode.dop,
        requiresDopSafety: true,
      ),
    ],
  ),
];
