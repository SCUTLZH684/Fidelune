import Foundation

enum PlaybackMode: String, Codable, CaseIterable {
    case sequential
    case repeatAll
    case repeatOne
    case shuffle
}

enum DsdOutputMode: String, Codable, CaseIterable {
    case auto
    case dop
    case pcm
}

enum RateSwitchStrategy: String, Codable, CaseIterable {
    case hybrid
    case sessionPreferred
    case bassReinit
}

enum SessionModeOption: String, Codable, CaseIterable {
    case defaultMode
    case measurement
}

enum OutputRouteKind: String, Codable {
    case speaker = "Speaker"
    case receiver = "Receiver"
    case wiredHeadphones = "WiredHeadphones"
    case usbAudio = "USBAudio"
    case bluetoothA2dp = "BluetoothA2DP"
    case bluetoothLe = "BluetoothLE"
    case bluetoothHfp = "BluetoothHFP"
    case airPlay = "AirPlay"
    case hdmi = "HDMI"
    case lineOut = "LineOut"
    case unknown = "Unknown"

    var isWiredDacCapable: Bool {
        switch self {
        case .usbAudio, .hdmi, .lineOut:
            return true
        case .speaker, .receiver, .wiredHeadphones, .bluetoothA2dp, .bluetoothLe, .bluetoothHfp, .airPlay, .unknown:
            return false
        }
    }

    var supportsDop: Bool {
        self == .usbAudio
    }

    var displayLabel: String {
        switch self {
        case .speaker: return "本机扬声器"
        case .receiver: return "听筒"
        case .wiredHeadphones: return "有线耳机 / 转接线"
        case .usbAudio: return "USB DAC"
        case .bluetoothA2dp: return "蓝牙 A2DP"
        case .bluetoothLe: return "蓝牙 LE Audio"
        case .bluetoothHfp: return "蓝牙免提 (HFP)"
        case .airPlay: return "AirPlay"
        case .hdmi: return "HDMI"
        case .lineOut: return "Line Out"
        case .unknown: return "未知路由"
        }
    }
}

struct TrackSpec: Codable, Equatable {
    let id: String
    let title: String
    let artist: String
    let album: String
    let filePath: String
    let fileName: String
    let isBundledFixture: Bool
    let isPrePackagedDopWav: Bool

    init(
        id: String,
        title: String,
        artist: String = "Fidelune Test Signal",
        album: String = "Fidelune Acceptance",
        filePath: String,
        fileName: String,
        isBundledFixture: Bool = true,
        isPrePackagedDopWav: Bool = false
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.filePath = filePath
        self.fileName = fileName
        self.isBundledFixture = isBundledFixture
        self.isPrePackagedDopWav = isPrePackagedDopWav
    }

    init?(dictionary: [String: Any]) {
        guard let filePath = dictionary["filePath"] as? String,
              let fileName = dictionary["fileName"] as? String else {
            return nil
        }
        self.id = (dictionary["id"] as? String) ?? fileName
        self.title = (dictionary["title"] as? String) ?? fileName
        self.artist = (dictionary["artist"] as? String) ?? "Fidelune Test Signal"
        self.album = (dictionary["album"] as? String) ?? "Fidelune Acceptance"
        self.filePath = filePath
        self.fileName = fileName
        self.isBundledFixture = (dictionary["isBundledFixture"] as? Bool) ?? true
        self.isPrePackagedDopWav = (dictionary["isPrePackagedDopWav"] as? Bool) ?? (fileName == "dop64.wav")
    }
}

struct AudioFormatSignature: Codable, Equatable {
    let sampleRateHz: Int
    let channels: Int
    let validBits: Int
    let isDsd: Bool
    let dsdRateHz: Int
    let isDop: Bool
    let codecName: String

    static func isGaplessCompatible(lhs: AudioFormatSignature, rhs: AudioFormatSignature) -> Bool {
        guard !lhs.isDsd && !rhs.isDsd && !lhs.isDop && !rhs.isDop else {
            return false
        }
        return lhs.sampleRateHz == rhs.sampleRateHz && lhs.channels == rhs.channels
    }

    static func dopCarrierHz(forDsdRate dsdRateHz: Int) -> Int {
        dsdRateHz > 0 ? dsdRateHz / 16 : 0
    }
}

struct EngineSettings: Codable, Equatable {
    var rateSwitchStrategy: RateSwitchStrategy = .hybrid
    var dacSettleDelayMs: Int = 80
    var pcmFadeMs: Int = 20
    var dopSilenceLeadMs: Int = 100
    var dopSilenceTrailMs: Int = 80
    var dsdPcmTargetRateHz: Int = 176400
    var sessionMode: SessionModeOption = .defaultMode
    var strictBitPerfectNoRampIn: Bool = true
    var rememberExactPosition: Bool = true

    func toDictionary() -> [String: Any] {
        [
            "rateSwitchStrategy": rateSwitchStrategy.rawValue,
            "dacSettleDelayMs": dacSettleDelayMs,
            "pcmFadeMs": pcmFadeMs,
            "dopSilenceLeadMs": dopSilenceLeadMs,
            "dopSilenceTrailMs": dopSilenceTrailMs,
            "dsdPcmTargetRateHz": dsdPcmTargetRateHz,
            "sessionMode": sessionMode.rawValue,
            "strictBitPerfectNoRampIn": strictBitPerfectNoRampIn,
            "rememberExactPosition": rememberExactPosition,
        ]
    }

    mutating func update(from dict: [String: Any]) {
        if let raw = dict["rateSwitchStrategy"] as? String, let val = RateSwitchStrategy(rawValue: raw) {
            rateSwitchStrategy = val
        }
        if let v = dict["dacSettleDelayMs"] as? Int {
            dacSettleDelayMs = max(0, min(1000, v))
        }
        if let v = dict["pcmFadeMs"] as? Int {
            pcmFadeMs = max(0, min(60, v))
        }
        if let v = dict["dopSilenceLeadMs"] as? Int {
            dopSilenceLeadMs = max(0, min(500, v))
        }
        if let v = dict["dopSilenceTrailMs"] as? Int {
            dopSilenceTrailMs = max(0, min(500, v))
        }
        if let v = dict["dsdPcmTargetRateHz"] as? Int, [44100, 48000, 88200, 96000, 176400, 192000].contains(v) {
            dsdPcmTargetRateHz = v
        }
        if let raw = dict["sessionMode"] as? String, let val = SessionModeOption(rawValue: raw) {
            sessionMode = val
        }
        if let v = dict["strictBitPerfectNoRampIn"] as? Bool {
            strictBitPerfectNoRampIn = v
        }
        if let v = dict["rememberExactPosition"] as? Bool {
            rememberExactPosition = v
        }
    }
}

struct DacCapabilityProfile: Codable, Equatable {
    let deviceName: String
    let portType: String
    let routeKind: OutputRouteKind
    let portUID: String
    let isUsbDac: Bool
    let currentSessionSampleRateHz: Int
    let preferredSampleRateHz: Int
    let bassDeviceSampleRateHz: Int
    let outputChannels: Int
    let maxOutputChannels: Int
    let outputVolume: Double
    let ioBufferDurationMs: Double
    let outputLatencyMs: Double
    let probedSupportedRatesHz: [Int]
    let supportsDopCandidate: Bool
    let physicalBitDepthReadable: Bool

    func toDictionary() -> [String: Any] {
        [
            "deviceName": deviceName,
            "portType": portType,
            "routeKind": routeKind.rawValue,
            "portUID": portUID,
            "isUsbDac": isUsbDac,
            "currentSessionSampleRateHz": currentSessionSampleRateHz,
            "preferredSampleRateHz": preferredSampleRateHz,
            "bassDeviceSampleRateHz": bassDeviceSampleRateHz,
            "outputChannels": outputChannels,
            "maxOutputChannels": maxOutputChannels,
            "outputVolume": outputVolume,
            "ioBufferDurationMs": ioBufferDurationMs,
            "outputLatencyMs": outputLatencyMs,
            "probedSupportedRatesHz": probedSupportedRatesHz,
            "supportsDopCandidate": supportsDopCandidate,
            "physicalBitDepthReadable": physicalBitDepthReadable,
        ]
    }
}

struct SignalPathSnapshot: Codable, Equatable {
    let sourceCodec: String
    let sourceSampleRateHz: Int
    let sourceValidBits: Int
    let sourceChannels: Int
    let sourceIsDsd: Bool
    let sourceDsdRateHz: Int
    let enginePipelineMode: String
    let engineOutputSampleRateHz: Int
    let engineOutputChannels: Int
    let engineFloatPrecision: String
    let engineVolumeGain: Double
    let mixerFlags: String
    let gaplessNextTrackQueued: Bool
    let gaplessNextTrackName: String?
    let sessionCategory: String
    let sessionMode: String
    let sessionRequestedRateHz: Int
    let sessionActualRateHz: Int
    let bassDeviceRateHz: Int
    let routeKind: OutputRouteKind
    let routeName: String
    let outputVolume: Double
    let resampledBySystem: Bool
    let bitPerfectCandidate: Bool
    let dopActive: Bool
    let hardwareDisplayUnverifiedNote: String
    let statusSummary: String

    func toDictionary() -> [String: Any] {
        [
            "sourceCodec": sourceCodec,
            "sourceSampleRateHz": sourceSampleRateHz,
            "sourceValidBits": sourceValidBits,
            "sourceChannels": sourceChannels,
            "sourceIsDsd": sourceIsDsd,
            "sourceDsdRateHz": sourceDsdRateHz,
            "enginePipelineMode": enginePipelineMode,
            "engineOutputSampleRateHz": engineOutputSampleRateHz,
            "engineOutputChannels": engineOutputChannels,
            "engineFloatPrecision": engineFloatPrecision,
            "engineVolumeGain": engineVolumeGain,
            "mixerFlags": mixerFlags,
            "gaplessNextTrackQueued": gaplessNextTrackQueued,
            "gaplessNextTrackName": gaplessNextTrackName as Any,
            "sessionCategory": sessionCategory,
            "sessionMode": sessionMode,
            "sessionRequestedRateHz": sessionRequestedRateHz,
            "sessionActualRateHz": sessionActualRateHz,
            "bassDeviceRateHz": bassDeviceRateHz,
            "routeKind": routeKind.rawValue,
            "routeName": routeName,
            "outputVolume": outputVolume,
            "resampledBySystem": resampledBySystem,
            "bitPerfectCandidate": bitPerfectCandidate,
            "dopActive": dopActive,
            "hardwareDisplayUnverifiedNote": hardwareDisplayUnverifiedNote,
            "statusSummary": statusSummary,
        ]
    }

    static var idle: SignalPathSnapshot {
        SignalPathSnapshot(
            sourceCodec: "-",
            sourceSampleRateHz: 0,
            sourceValidBits: 0,
            sourceChannels: 0,
            sourceIsDsd: false,
            sourceDsdRateHz: 0,
            enginePipelineMode: "空闲",
            engineOutputSampleRateHz: 0,
            engineOutputChannels: 0,
            engineFloatPrecision: "-",
            engineVolumeGain: 1.0,
            mixerFlags: "-",
            gaplessNextTrackQueued: false,
            gaplessNextTrackName: nil,
            sessionCategory: "-",
            sessionMode: "-",
            sessionRequestedRateHz: 0,
            sessionActualRateHz: 0,
            bassDeviceRateHz: 0,
            routeKind: .unknown,
            routeName: "未启动",
            outputVolume: 1.0,
            resampledBySystem: false,
            bitPerfectCandidate: false,
            dopActive: false,
            hardwareDisplayUnverifiedNote: "iOS 无法回读外接 DAC 真实物理位深与 DSD 锁定灯状态，须以 DAC 面板与硬件测试为准。",
            statusSummary: "就绪"
        )
    }
}

enum DopSafetyFailure: Error, Equatable {
    case nonUsbRoute(OutputRouteKind)
    case carrierRateUnsupported(Int)
    case midStreamRateDrop(expectedHz: Int, actualHz: Int)
    case systemVolumeNotFull(Double)
    case userSafetyNotAcknowledged

    var code: String {
        switch self {
        case .nonUsbRoute: return "dop_requires_usb_dac"
        case .carrierRateUnsupported: return "dop_carrier_rate_exceeded"
        case .midStreamRateDrop: return "dop_midstream_rate_drop"
        case .systemVolumeNotFull: return "dop_volume_not_full"
        case .userSafetyNotAcknowledged: return "dop_safety_unacknowledged"
        }
    }

    var message: String {
        switch self {
        case .nonUsbRoute(let route):
            return "DoP 安全熔断/拦截：仅支持外接 USB DAC，当前路由已变为 \(route.displayLabel)。"
        case .carrierRateUnsupported(let rate):
            return "DoP 载波采样率 \(rate) Hz 超出 iOS UAC2 上限（768 kHz）。"
        case .midStreamRateDrop(let expectedHz, let actualHz):
            return "DoP 实时安全熔断：播放期间采样率从 \(expectedHz) Hz 意外变为 \(actualHz) Hz（会破坏 DoP 标记并产生全幅白噪），已紧急静音停止。"
        case .systemVolumeNotFull(let vol):
            return "安全拦截：DoP 要求 iPhone 系统输出音量必须为 100%（当前 \(Int((vol * 100).rounded()))%），否则会破坏 DoP 标记并产生全幅白噪。请先物理拔下耳机/调低耳放音量，再将 iPhone 音量调至最大。"
        case .userSafetyNotAcknowledged:
            return "请先完成 DoP 听力与设备安全确认（务必先物理拔下耳机，先观察 DAC 屏幕确认点亮 DSD 后再调最低音量插耳机）。"
        }
    }
}

enum DopFrameCodec {
    /// Packs a 24-bit DoP silence frame (0x05 0x69 0x69 or 0xFA 0x69 0x69) into IEEE float32 [-1, 1).
    static func packDopSilenceFloat(marker: UInt8) -> Float {
        let u24: UInt32 = (UInt32(marker) << 16) | 0x0000_6969
        let s24: Int32 = (u24 & 0x0080_0000) != 0
            ? Int32(bitPattern: u24 | 0xFF00_0000)
            : Int32(u24)
        return Float(Double(s24) / 8_388_608.0)
    }

    /// Recovers the upper 8-bit DoP marker byte from a BASS float32 sample.
    static func extractDopMarker(fromFloat sample: Float) -> UInt8 {
        let s24 = Int32((Double(sample) * 8_388_608.0).rounded())
        let clamped = max(-8_388_608, min(8_388_607, s24))
        let u24 = UInt32(bitPattern: clamped) & 0x00FF_FFFF
        return UInt8((u24 >> 16) & 0xFF)
    }

    /// Extracts the 24-bit integer sample from BASS float32 (scaled by 2^23).
    static func floatToSigned24(_ sample: Float) -> Int32 {
        let s24 = Int32((Double(sample) * 8_388_608.0).rounded())
        return max(-8_388_608, min(8_388_607, s24))
    }

    /// Extracts the 16-bit integer sample from BASS float32 (scaled by 2^15).
    static func floatToSigned16(_ sample: Float) -> Int16 {
        let s16 = Int32((Double(sample) * 32_768.0).rounded())
        return Int16(max(-32_768, min(32_767, s16)))
    }
}
