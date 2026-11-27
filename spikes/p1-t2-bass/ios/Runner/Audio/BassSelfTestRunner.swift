import CryptoKit
import Foundation

struct SelfTestResult: Codable {
    let id: String
    let title: String
    let passed: Bool
    let durationMs: Int
    let summary: String
    let details: [String: String]

    func toDictionary() -> [String: Any] {
        [
            "id": id,
            "title": title,
            "passed": passed,
            "durationMs": durationMs,
            "summary": summary,
            "details": details,
        ]
    }
}

final class BassSelfTestRunner {
    private let logger: DiagnosticsSink

    init(logger: DiagnosticsSink = DiagnosticsLogger.shared) {
        self.logger = logger
    }

    func runAll(fixturesDirectory: URL) -> [SelfTestResult] {
        let manifest = loadManifest(fixturesDirectory: fixturesDirectory)
        var results: [SelfTestResult] = []
        results.append(runBassInitCheck())
        results.append(runFormatProbeCheck(fixturesDirectory: fixturesDirectory, manifest: manifest))
        results.append(runLosslessMixerBitExactCheck(
            id: "auto_pcm24_bitexact",
            title: "24-bit WAV 经 BASSmix 浮点管线零精度损失校验",
            fileName: "wav24.wav",
            bits: 24,
            expectedRate: 48000,
            fixturesDirectory: fixturesDirectory,
            manifest: manifest
        ))
        results.append(runLosslessMixerBitExactCheck(
            id: "auto_flac24_bitexact",
            title: "192 kHz / 24-bit FLAC 经 BASSFLAC + BASSmix 位精确校验",
            fileName: "flac192000.flac",
            bits: 24,
            expectedRate: 192000,
            fixturesDirectory: fixturesDirectory,
            manifest: manifest
        ))
        results.append(runGaplessMixerCheck(
            id: "auto_gapless_44k",
            title: "44.1 kHz/16-bit 同规格 BASS_MIXER_QUEUE 零帧差无缝校验",
            partA: "gap-a.wav",
            partB: "gap-b.wav",
            referenceName: "continuous.wav",
            rate: 44100,
            bits: 16,
            fixturesDirectory: fixturesDirectory,
            manifest: manifest
        ))
        results.append(runGaplessMixerCheck(
            id: "auto_gapless_96k",
            title: "96 kHz/24-bit FLAC 同规格 BASS_MIXER_QUEUE 零帧差无缝校验",
            partA: "gap96-a.flac",
            partB: "gap96-b.flac",
            referenceName: "continuous96.flac",
            rate: 96000,
            bits: 24,
            fixturesDirectory: fixturesDirectory,
            manifest: manifest
        ))
        results.append(runDopVerificationCheck(
            id: "auto_dop_dsd64",
            title: "DSD64 DoP (0x05/0xFA 交替标记 + 0x69 静音帧) 校验",
            fileName: "dsd64.dsf",
            expectedCarrierHz: 176400,
            expectedDsdHz: 2822400,
            fixturesDirectory: fixturesDirectory
        ))
        results.append(runDopVerificationCheck(
            id: "auto_dop_dsd128",
            title: "DSD128 DoP (352.8 kHz 载波 + 0x05/0xFA 交替标记) 校验",
            fileName: "dsd128.dsf",
            expectedCarrierHz: 352800,
            expectedDsdHz: 5644800,
            fixturesDirectory: fixturesDirectory
        ))
        results.append(runCorruptFileResilienceCheck(fixturesDirectory: fixturesDirectory))

        let passCount = results.filter { $0.passed }.count
        logger.log(
            event: "self-tests-completed",
            category: "selftest",
            message: "Automated BASS checks: \(passCount)/\(results.count) passed",
            fields: ["passed": passCount, "total": results.count]
        )
        return results
    }

    func exportPcmCaptureWavs(fixturesDirectory: URL) -> [String: String] {
        let fm = FileManager.default
        guard let docs = try? fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else {
            return [:]
        }
        var exported: [String: String] = [:]

        if let s24Data = decodeSingleThroughMixer(
            fileURL: fixturesDirectory.appendingPathComponent("wav24.wav"),
            rate: 48000,
            channels: 2,
            bits: 24
        ) {
            let wavURL = docs.appendingPathComponent("bass-pcm24.wav")
            let wavBytes = buildWavHeader(dataBytes: s24Data.count, sampleRate: 48000, channels: 2, bitsPerSample: 24) + s24Data
            if (try? wavBytes.write(to: wavURL)) != nil {
                exported["pcm24"] = wavURL.path
            }
        }

        if let s16GapData = decodeGaplessPairThroughMixer(
            fileA: fixturesDirectory.appendingPathComponent("gap-a.wav"),
            fileB: fixturesDirectory.appendingPathComponent("gap-b.wav"),
            rate: 44100,
            channels: 2,
            bits: 16
        ) {
            let wavURL = docs.appendingPathComponent("bass-gap.wav")
            let wavBytes = buildWavHeader(dataBytes: s16GapData.count, sampleRate: 44100, channels: 2, bitsPerSample: 16) + s16GapData
            if (try? wavBytes.write(to: wavURL)) != nil {
                exported["gap"] = wavURL.path
            }
        }
        return exported
    }

    // MARK: - Individual Checks

    private func runBassInitCheck() -> SelfTestResult {
        let t0 = Date()
        let bassVer = BASS_GetVersion()
        let mixVer = BASS_Mixer_GetVersion()
        let state = BassPluginRegistry.ensureAllPluginsLoaded(logger: logger)
        let pluginHandles = state.loaded
        let missing = state.missing
        let errorSummary = state.errors
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ", ")
        let ok = (bassVer >= 0x02041200) && (mixVer >= 0x02040D00) && missing.isEmpty
        return SelfTestResult(
            id: "auto_bass_init",
            title: "BASS 2.4.18+ / BASSmix 2.4.13+ 与 5 个官方插件动态加载",
            passed: ok,
            durationMs: elapsedMs(since: t0),
            summary: ok
                ? "BASS 0x\(String(format: "%08X", bassVer)) / BASSmix 0x\(String(format: "%08X", mixVer)) 及全部 5 个插件加载成功"
                : "插件加载缺失: \(missing.joined(separator: ", ")) (\(errorSummary))",
            details: [
                "bassVersion": String(format: "0x%08X", bassVer),
                "bassMixVersion": String(format: "0x%08X", mixVer),
                "loadedPlugins": pluginHandles.keys.sorted().joined(separator: ", "),
                "missingPlugins": missing.joined(separator: ", "),
                "pluginErrors": errorSummary,
            ]
        )
    }

    private func runFormatProbeCheck(fixturesDirectory: URL, manifest: [String: Any]) -> SelfTestResult {
        let t0 = Date()
        let sources = (manifest["sources"] as? [String: [String: Any]]) ?? [:]
        var checked = 0
        var failures: [String] = []

        for (fileName, meta) in sources.sorted(by: { $0.key < $1.key }) {
            if (meta["intentional_invalid"] as? Bool) == true { continue }
            if fileName == "truncated.flac" { continue }
            let url = fixturesDirectory.appendingPathComponent(fileName)
            guard FileManager.default.fileExists(atPath: url.path) else {
                failures.append("\(fileName): 文件缺失")
                continue
            }

            let ext = url.pathExtension.lowercased()
            let handle: HSTREAM = url.path.withCString { cPath in
                if ext == "dsf" || ext == "dff" {
                    return BASS_DSD_StreamCreateFile(
                        DWORD(BASS_FILE_NAME),
                        cPath,
                        0,
                        0,
                        DWORD(BASS_DSD_DOP | BASS_SAMPLE_FLOAT | BASS_STREAM_DECODE),
                        0
                    )
                }
                return BASS_StreamCreateFile(
                    DWORD(BASS_FILE_NAME),
                    cPath,
                    0,
                    0,
                    DWORD(BASS_STREAM_DECODE | BASS_SAMPLE_FLOAT | BASS_STREAM_PRESCAN)
                )
            }
            if handle == 0 {
                failures.append("\(fileName): 打开失败 (BASS err \(BASS_ErrorGetCode()))")
                continue
            }
            defer { BASS_StreamFree(handle) }
            var info = BASS_CHANNELINFO()
            guard BASS_ChannelGetInfo(handle, &info) != 0, info.freq > 0, info.chans > 0 else {
                failures.append("\(fileName): ChannelGetInfo 无效")
                continue
            }
            var sampleBuf = [Float](repeating: 0, count: 1024)
            let got = sampleBuf.withUnsafeMutableBytes { raw in
                BASS_ChannelGetData(handle, raw.baseAddress, DWORD(raw.count))
            }
            if got == DWORD.max || got == 0 {
                failures.append("\(fileName): 解码读数据失败")
                continue
            }
            checked += 1
        }

        let ok = failures.isEmpty && checked >= 15
        return SelfTestResult(
            id: "auto_format_decode",
            title: "全格式解码与信息校验（FLAC/ALAC/WAV/WavPack/Opus/MP3/AAC/DSF）",
            passed: ok,
            durationMs: elapsedMs(since: t0),
            summary: ok ? "已通过全部 \(checked) 个测试音源的打开、声道/采样率读取与解码" : failures.joined(separator: "; "),
            details: [
                "checkedCount": "\(checked)",
                "failures": failures.joined(separator: "; "),
            ]
        )
    }

    private func runLosslessMixerBitExactCheck(
        id: String,
        title: String,
        fileName: String,
        bits: Int,
        expectedRate: Int,
        fixturesDirectory: URL,
        manifest: [String: Any]
    ) -> SelfTestResult {
        let t0 = Date()
        let sources = (manifest["sources"] as? [String: [String: Any]]) ?? [:]
        guard let meta = sources[fileName],
              let expectedSha = meta["source_pcm_sha256"] as? String else {
            return SelfTestResult(
                id: id,
                title: title,
                passed: false,
                durationMs: elapsedMs(since: t0),
                summary: "manifest.json 中缺少 \(fileName) 参考哈希",
                details: [:]
            )
        }

        let fileURL = fixturesDirectory.appendingPathComponent(fileName)
        guard let pcmBytes = decodeSingleThroughMixer(fileURL: fileURL, rate: expectedRate, channels: 2, bits: bits) else {
            return SelfTestResult(
                id: id,
                title: title,
                passed: false,
                durationMs: elapsedMs(since: t0),
                summary: "通过 BASSmix 解码 \(fileName) 失败",
                details: [:]
            )
        }

        let actualSha = sha256Hex(pcmBytes)
        let ok = (actualSha == expectedSha)
        return SelfTestResult(
            id: id,
            title: title,
            passed: ok,
            durationMs: elapsedMs(since: t0),
            summary: ok
                ? "BASSmix 浮点输出还原为 \(bits)-bit PCM 后 SHA-256 与参考源文件完全一致"
                : "SHA-256 不匹配：期望 \(expectedSha.prefix(12))，实际 \(actualSha.prefix(12))",
            details: [
                "file": fileName,
                "expectedSha256": expectedSha,
                "actualSha256": actualSha,
                "decodedBytes": "\(pcmBytes.count)",
            ]
        )
    }

    private func runGaplessMixerCheck(
        id: String,
        title: String,
        partA: String,
        partB: String,
        referenceName: String,
        rate: Int,
        bits: Int,
        fixturesDirectory: URL,
        manifest: [String: Any]
    ) -> SelfTestResult {
        let t0 = Date()
        let sources = (manifest["sources"] as? [String: [String: Any]]) ?? [:]
        guard let meta = sources[referenceName],
              let expectedSha = meta["source_pcm_sha256"] as? String,
              let expectedFrames = meta["frames"] as? Int else {
            return SelfTestResult(
                id: id,
                title: title,
                passed: false,
                durationMs: elapsedMs(since: t0),
                summary: "manifest.json 中缺少参考 \(referenceName)",
                details: [:]
            )
        }

        guard let combined = decodeGaplessPairThroughMixer(
            fileA: fixturesDirectory.appendingPathComponent(partA),
            fileB: fixturesDirectory.appendingPathComponent(partB),
            rate: rate,
            channels: 2,
            bits: bits
        ) else {
            return SelfTestResult(
                id: id,
                title: title,
                passed: false,
                durationMs: elapsedMs(since: t0),
                summary: "BASS_MIXER_QUEUE 拼接解码失败",
                details: [:]
            )
        }

        let actualFrames = combined.count / (2 * (bits / 8))
        let actualSha = sha256Hex(combined)
        let ok = (actualFrames == expectedFrames) && (actualSha == expectedSha)
        return SelfTestResult(
            id: id,
            title: title,
            passed: ok,
            durationMs: elapsedMs(since: t0),
            summary: ok
                ? "拼接输出 \(actualFrames) 帧（零插帧、零丢帧），SHA-256 与连续参考 \(referenceName) 完全一致"
                : "帧数或哈希不一致（实际帧 \(actualFrames)/期望 \(expectedFrames)）",
            details: [
                "expectedFrames": "\(expectedFrames)",
                "actualFrames": "\(actualFrames)",
                "expectedSha256": expectedSha,
                "actualSha256": actualSha,
            ]
        )
    }

    private func runDopVerificationCheck(
        id: String,
        title: String,
        fileName: String,
        expectedCarrierHz: Int,
        expectedDsdHz: Int,
        fixturesDirectory: URL
    ) -> SelfTestResult {
        let t0 = Date()
        let url = fixturesDirectory.appendingPathComponent(fileName)
        let handle: HSTREAM = url.path.withCString { cPath in
            BASS_DSD_StreamCreateFile(
                DWORD(BASS_FILE_NAME),
                cPath,
                0,
                0,
                DWORD(BASS_DSD_DOP | BASS_SAMPLE_FLOAT | BASS_STREAM_DECODE),
                0
            )
        }
        guard handle != 0 else {
            return SelfTestResult(
                id: id,
                title: title,
                passed: false,
                durationMs: elapsedMs(since: t0),
                summary: "BASS_DSD_StreamCreateFile 打开失败（错误 \(BASS_ErrorGetCode())）",
                details: [:]
            )
        }
        defer { BASS_StreamFree(handle) }

        var info = BASS_CHANNELINFO()
        guard BASS_ChannelGetInfo(handle, &info) != 0 else {
            return SelfTestResult(id: id, title: title, passed: false, durationMs: elapsedMs(since: t0), summary: "读取通道信息失败", details: [:])
        }
        var dsdRateFloat: Float = 0
        _ = BASS_ChannelGetAttribute(handle, DWORD(BASS_ATTRIB_DSD_RATE), &dsdRateFloat)

        let chans = Int(info.chans)
        var floatBuf = [Float](repeating: 0, count: 4096 * max(1, chans))
        var totalFrames = 0
        var markerErrors = 0
        var expectedMarker: UInt8 = 0x05

        while true {
            let bytesRead: DWORD = floatBuf.withUnsafeMutableBytes { raw in
                BASS_ChannelGetData(handle, raw.baseAddress, DWORD(raw.count))
            }
            if bytesRead == DWORD.max || bytesRead == 0 {
                break
            }
            let frames = Int(bytesRead) / (chans * MemoryLayout<Float>.size)
            for f in 0..<frames {
                for ch in 0..<chans {
                    let marker = DopFrameCodec.extractDopMarker(fromFloat: floatBuf[f * chans + ch])
                    if marker != expectedMarker {
                        markerErrors += 1
                    }
                }
                expectedMarker = (expectedMarker == 0x05) ? 0xFA : 0x05
            }
            totalFrames += frames
        }

        // Verify 0x69 DoP silence helper round-trip
        let m05 = DopFrameCodec.extractDopMarker(fromFloat: DopFrameCodec.packDopSilenceFloat(marker: 0x05))
        let mFA = DopFrameCodec.extractDopMarker(fromFloat: DopFrameCodec.packDopSilenceFloat(marker: 0xFA))
        let silenceOk = (m05 == 0x05 && mFA == 0xFA)

        let ok = Int(info.freq) == expectedCarrierHz &&
            Int(dsdRateFloat.rounded()) == expectedDsdHz &&
            totalFrames > 0 &&
            markerErrors == 0 &&
            silenceOk

        return SelfTestResult(
            id: id,
            title: title,
            passed: ok,
            durationMs: elapsedMs(since: t0),
            summary: ok
                ? "载波 \(info.freq) Hz，DSD \(Int(dsdRateFloat.rounded())) Hz，全段 \(totalFrames) 帧 DoP 标记 100% 严格交替（0 错误）"
                : "DoP 校验异常：freq=\(info.freq), dsdRate=\(Int(dsdRateFloat)), frames=\(totalFrames), markerErrors=\(markerErrors)",
            details: [
                "carrierHz": "\(info.freq)",
                "dsdRateHz": "\(Int(dsdRateFloat.rounded()))",
                "verifiedFrames": "\(totalFrames)",
                "markerErrors": "\(markerErrors)",
                "silence0x69ParityOk": "\(silenceOk)",
            ]
        )
    }

    private func runCorruptFileResilienceCheck(fixturesDirectory: URL) -> SelfTestResult {
        let t0 = Date()
        var failures: [String] = []
        for bad in ["invalid.flac", "invalid-2.flac"] {
            let path = fixturesDirectory.appendingPathComponent(bad).path
            let h = path.withCString { cPath in
                BASS_StreamCreateFile(DWORD(BASS_FILE_NAME), cPath, 0, 0, DWORD(BASS_STREAM_DECODE | BASS_SAMPLE_FLOAT))
            }
            if h != 0 {
                BASS_StreamFree(h)
                failures.append("\(bad) 意外返回非零句柄")
            }
        }

        let truncPath = fixturesDirectory.appendingPathComponent("truncated.flac").path
        let truncH = truncPath.withCString { cPath in
            BASS_StreamCreateFile(DWORD(BASS_FILE_NAME), cPath, 0, 0, DWORD(BASS_STREAM_DECODE | BASS_SAMPLE_FLOAT))
        }
        var truncDecodedBytes = 0
        if truncH != 0 {
            var buf = [Float](repeating: 0, count: 4096)
            while true {
                let got: DWORD = buf.withUnsafeMutableBytes { raw in
                    BASS_ChannelGetData(truncH, raw.baseAddress, DWORD(raw.count))
                }
                if got == DWORD.max || got == 0 { break }
                truncDecodedBytes += Int(got)
            }
            BASS_StreamFree(truncH)
        }

        let ok = failures.isEmpty
        return SelfTestResult(
            id: "auto_corrupt_resilience",
            title: "坏文件拒绝与截断文件安全解码容错校验",
            passed: ok,
            durationMs: elapsedMs(since: t0),
            summary: ok
                ? "两个坏文件均安全拒绝，截断 FLAC 安全解码 \(truncDecodedBytes) 字节后正常结束无崩溃"
                : failures.joined(separator: "; "),
            details: [
                "truncatedDecodedBytes": "\(truncDecodedBytes)",
                "failures": failures.joined(separator: "; "),
            ]
        )
    }

    // MARK: - Decode Helpers

    private func decodeSingleThroughMixer(fileURL: URL, rate: Int, channels: Int, bits: Int) -> Data? {
        let src: HSTREAM = fileURL.path.withCString { cPath in
            BASS_StreamCreateFile(
                DWORD(BASS_FILE_NAME),
                cPath,
                0,
                0,
                DWORD(BASS_STREAM_DECODE | BASS_SAMPLE_FLOAT | BASS_STREAM_PRESCAN)
            )
        }
        guard src != 0 else { return nil }
        defer { BASS_StreamFree(src) }

        let mixer = BASS_Mixer_StreamCreate(
            UInt32(rate),
            UInt32(channels),
            DWORD(BASS_SAMPLE_FLOAT | BASS_STREAM_DECODE | BASS_MIXER_END)
        )
        guard mixer != 0 else { return nil }
        defer { BASS_StreamFree(mixer) }

        guard BASS_Mixer_StreamAddChannel(mixer, src, DWORD(BASS_MIXER_CHAN_NORAMPIN)) != 0 else {
            return nil
        }
        return drainMixerToSignedPcmData(mixer: mixer, bits: bits, channels: channels)
    }

    private func decodeGaplessPairThroughMixer(
        fileA: URL,
        fileB: URL,
        rate: Int,
        channels: Int,
        bits: Int
    ) -> Data? {
        let srcA: HSTREAM = fileA.path.withCString { cPath in
            BASS_StreamCreateFile(
                DWORD(BASS_FILE_NAME),
                cPath,
                0,
                0,
                DWORD(BASS_STREAM_DECODE | BASS_SAMPLE_FLOAT | BASS_STREAM_PRESCAN)
            )
        }
        let srcB: HSTREAM = fileB.path.withCString { cPath in
            BASS_StreamCreateFile(
                DWORD(BASS_FILE_NAME),
                cPath,
                0,
                0,
                DWORD(BASS_STREAM_DECODE | BASS_SAMPLE_FLOAT | BASS_STREAM_PRESCAN)
            )
        }
        guard srcA != 0, srcB != 0 else {
            if srcA != 0 { BASS_StreamFree(srcA) }
            if srcB != 0 { BASS_StreamFree(srcB) }
            return nil
        }

        let mixer = BASS_Mixer_StreamCreate(
            UInt32(rate),
            UInt32(channels),
            DWORD(BASS_SAMPLE_FLOAT | BASS_STREAM_DECODE | BASS_MIXER_QUEUE | BASS_MIXER_END)
        )
        guard mixer != 0 else {
            BASS_StreamFree(srcA)
            BASS_StreamFree(srcB)
            return nil
        }
        defer { BASS_StreamFree(mixer) }

        let flags = DWORD(BASS_MIXER_CHAN_NORAMPIN | BASS_MIXER_CHAN_AUTOFREE)
        guard BASS_Mixer_StreamAddChannel(mixer, srcA, flags) != 0,
              BASS_Mixer_StreamAddChannel(mixer, srcB, flags) != 0 else {
            return nil
        }
        return drainMixerToSignedPcmData(mixer: mixer, bits: bits, channels: channels)
    }

    private func drainMixerToSignedPcmData(mixer: HSTREAM, bits: Int, channels: Int) -> Data {
        var out = Data()
        var floatBuf = [Float](repeating: 0, count: 4096 * max(1, channels))
        while true {
            let bytesRead: DWORD = floatBuf.withUnsafeMutableBytes { raw in
                BASS_ChannelGetData(mixer, raw.baseAddress, DWORD(raw.count))
            }
            if bytesRead == DWORD.max || bytesRead == 0 {
                break
            }
            let sampleCount = Int(bytesRead) / MemoryLayout<Float>.size
            if bits == 24 {
                out.reserveCapacity(out.count + sampleCount * 3)
                for i in 0..<sampleCount {
                    let s24 = DopFrameCodec.floatToSigned24(floatBuf[i])
                    let u = UInt32(bitPattern: s24)
                    out.append(UInt8(u & 0xFF))
                    out.append(UInt8((u >> 8) & 0xFF))
                    out.append(UInt8((u >> 16) & 0xFF))
                }
            } else {
                out.reserveCapacity(out.count + sampleCount * 2)
                for i in 0..<sampleCount {
                    let s16 = DopFrameCodec.floatToSigned16(floatBuf[i])
                    let u = UInt16(bitPattern: s16)
                    out.append(UInt8(u & 0xFF))
                    out.append(UInt8((u >> 8) & 0xFF))
                }
            }
        }
        return out
    }

    private func loadManifest(fixturesDirectory: URL) -> [String: Any] {
        let manifestURL = fixturesDirectory.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return obj
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func elapsedMs(since start: Date) -> Int {
        Int((Date().timeIntervalSince(start) * 1000.0).rounded())
    }

    private func buildWavHeader(dataBytes: Int, sampleRate: Int, channels: Int, bitsPerSample: Int) -> Data {
        var header = Data()
        let byteRate = sampleRate * channels * (bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        let chunkSize = 36 + dataBytes

        func appendU32(_ v: UInt32) {
            var le = v.littleEndian
            header.append(Data(bytes: &le, count: 4))
        }
        func appendU16(_ v: UInt16) {
            var le = v.littleEndian
            header.append(Data(bytes: &le, count: 2))
        }

        header.append(contentsOf: "RIFF".utf8)
        appendU32(UInt32(chunkSize))
        header.append(contentsOf: "WAVE".utf8)
        header.append(contentsOf: "fmt ".utf8)
        appendU32(16)
        appendU16(1)
        appendU16(UInt16(channels))
        appendU32(UInt32(sampleRate))
        appendU32(UInt32(byteRate))
        appendU16(UInt16(blockAlign))
        appendU16(UInt16(bitsPerSample))
        header.append(contentsOf: "data".utf8)
        appendU32(UInt32(dataBytes))
        return header
    }
}
