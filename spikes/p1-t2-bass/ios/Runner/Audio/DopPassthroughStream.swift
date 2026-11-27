import Foundation
import os.lock

/// Wraps a BASSDSD (or pre-packaged DoP WAV) decoding channel inside a custom float32 STREAMPROC
/// that injects 0x05/0xFA + 0x69 DoP silence frames on start/seek/stop and guarantees strict
/// marker parity without volume ramping clicks.
final class DopPassthroughStream {
    private enum Phase {
        case leadSilence
        case activePayload
        case trailSilence
        case ended
    }

    private(set) var decoderHandle: HSTREAM
    private(set) var outputHandle: HSTREAM
    let carrierRateHz: Int
    let channels: Int
    let dsdRateHz: Int

    private var lock = os_unfair_lock_s()
    private var phase: Phase = .leadSilence
    private var leadFramesRemaining: Int = 0
    private var trailFramesRemaining: Int = 0
    private var lastEmittedMarker: UInt8 = 0xFA
    private var needsParityCheckAfterSilence = true
    private var scratchBuffer: [Float] = []
    private var pendingTrailCompletion: (() -> Void)?
    private var trailCompletionFired = false
    private var naturalEndFired = false

    var onNaturalEnd: (() -> Void)?

    private var retainedSelf: Unmanaged<DopPassthroughStream>?

    init?(
        filePath: String,
        isPrePackagedDopWav: Bool,
        leadSilenceMs: Int,
        logger: DiagnosticsSink
    ) {
        let decHandle: HSTREAM = filePath.withCString { cPath in
            if isPrePackagedDopWav {
                return BASS_StreamCreateFile(
                    DWORD(BASS_FILE_NAME),
                    cPath,
                    0,
                    0,
                    DWORD(BASS_SAMPLE_FLOAT | BASS_STREAM_DECODE | BASS_STREAM_PRESCAN)
                )
            } else {
                return BASS_DSD_StreamCreateFile(
                    DWORD(BASS_FILE_NAME),
                    cPath,
                    0,
                    0,
                    DWORD(BASS_DSD_DOP | BASS_SAMPLE_FLOAT | BASS_STREAM_DECODE),
                    0
                )
            }
        }

        guard decHandle != 0 else {
            let err = BASS_ErrorGetCode()
            logger.log(
                event: "dop-decoder-open-failed",
                category: "dop",
                message: "Failed to open DoP stream (\(filePath)): BASS error \(err)",
                fields: ["bassError": err]
            )
            return nil
        }

        var chInfo = BASS_CHANNELINFO()
        guard BASS_ChannelGetInfo(decHandle, &chInfo) != 0 else {
            BASS_StreamFree(decHandle)
            return nil
        }

        var dsdRateFloat: Float = 0
        if BASS_ChannelGetAttribute(decHandle, DWORD(BASS_ATTRIB_DSD_RATE), &dsdRateFloat) == 0 {
            dsdRateFloat = Float(chInfo.freq * 16)
        }

        self.decoderHandle = decHandle
        self.carrierRateHz = Int(chInfo.freq)
        self.channels = Int(chInfo.chans)
        self.dsdRateHz = Int(dsdRateFloat.rounded())
        let evenLead = max(0, (self.carrierRateHz * leadSilenceMs / 1000) & ~1)
        self.leadFramesRemaining = evenLead
        self.phase = evenLead > 0 ? .leadSilence : .activePayload
        self.scratchBuffer = [Float](repeating: 0, count: 4096 * max(1, self.channels))

        var out: HSTREAM = 0
        self.outputHandle = 0

        let ptr = Unmanaged.passRetained(self)
        self.retainedSelf = ptr
        out = BASS_StreamCreate(
            UInt32(self.carrierRateHz),
            UInt32(self.channels),
            DWORD(BASS_SAMPLE_FLOAT),
            dopStreamCallback,
            ptr.toOpaque()
        )
        guard out != 0 else {
            let err = BASS_ErrorGetCode()
            ptr.release()
            self.retainedSelf = nil
            BASS_StreamFree(decHandle)
            logger.log(
                event: "dop-output-create-failed",
                category: "dop",
                message: "Failed to create DoP output stream: BASS error \(err)",
                fields: ["bassError": err]
            )
            return nil
        }

        self.outputHandle = out
        // Disable any BASS ramping or downmixing on the DoP carrier stream.
        BASS_ChannelSetAttribute(out, DWORD(BASS_ATTRIB_NORAMP), 1.0)
        BASS_ChannelSetAttribute(out, DWORD(BASS_ATTRIB_DOWNMIX), 0.0)
        BASS_ChannelSetAttribute(out, DWORD(BASS_ATTRIB_VOL), 1.0)
    }

    deinit {
        if decoderHandle != 0 {
            BASS_StreamFree(decoderHandle)
        }
    }

    func releaseResources() {
        if outputHandle != 0 {
            BASS_ChannelStop(outputHandle)
            BASS_StreamFree(outputHandle)
            outputHandle = 0
        }
        if decoderHandle != 0 {
            BASS_StreamFree(decoderHandle)
            decoderHandle = 0
        }
        if let ptr = retainedSelf {
            retainedSelf = nil
            ptr.release()
        }
    }

    func currentPositionSeconds() -> Double {
        let decBytes = BASS_ChannelGetPosition(decoderHandle, DWORD(BASS_POS_BYTE))
        if decBytes == UInt64.max { return 0 }
        let outBuffered = BASS_ChannelGetData(outputHandle, nil, DWORD(BASS_DATA_AVAILABLE))
        let bufferedBytes: UInt64 = (outBuffered == DWORD.max) ? 0 : UInt64(outBuffered)
        let playedBytes = decBytes > bufferedBytes ? decBytes - bufferedBytes : 0
        return max(0, BASS_ChannelBytes2Seconds(decoderHandle, playedBytes))
    }

    func durationSeconds() -> Double {
        let lenBytes = BASS_ChannelGetLength(decoderHandle, DWORD(BASS_POS_BYTE))
        if lenBytes == UInt64.max { return 0 }
        let secs = BASS_ChannelBytes2Seconds(decoderHandle, lenBytes)
        return secs.isFinite && secs > 0 ? secs : 0
    }

    func seek(to seconds: Double, leadSilenceMs: Int) -> Bool {
        let targetBytes = BASS_ChannelSeconds2Bytes(decoderHandle, max(0, seconds))
        guard targetBytes != UInt64.max else { return false }
        os_unfair_lock_lock(&lock)
        let ok = BASS_ChannelSetPosition(decoderHandle, targetBytes, DWORD(BASS_POS_BYTE)) != 0
        if ok {
            let evenLead = max(2, (carrierRateHz * leadSilenceMs / 1000) & ~1)
            leadFramesRemaining = evenLead
            phase = .leadSilence
            needsParityCheckAfterSilence = true
        }
        os_unfair_lock_unlock(&lock)
        if ok {
            BASS_ChannelSetPosition(outputHandle, 0, DWORD(BASS_POS_BYTE))
        }
        return ok
    }

    func prepareResumeLeadSilence(ms: Int) {
        os_unfair_lock_lock(&lock)
        let evenLead = max(2, (carrierRateHz * ms / 1000) & ~1)
        leadFramesRemaining = evenLead
        phase = .leadSilence
        needsParityCheckAfterSilence = true
        os_unfair_lock_unlock(&lock)
    }

    func beginTrailSilenceAndStop(trailMs: Int, completion: @escaping () -> Void) {
        os_unfair_lock_lock(&lock)
        if phase == .ended {
            os_unfair_lock_unlock(&lock)
            completion()
            return
        }
        let evenTrail = max(4, (carrierRateHz * max(20, trailMs) / 1000) & ~1)
        trailFramesRemaining = evenTrail
        phase = .trailSilence
        pendingTrailCompletion = completion
        trailCompletionFired = false
        os_unfair_lock_unlock(&lock)
    }

    fileprivate func render(buffer: UnsafeMutableRawPointer?, requestedBytes: DWORD) -> DWORD {
        guard let buffer, requestedBytes > 0 else { return 0 }
        let frameSizeBytes = max(1, channels * MemoryLayout<Float>.size)
        let maxFrames = Int(requestedBytes) / frameSizeBytes
        if maxFrames == 0 { return 0 }

        let outPtr = buffer.bindMemory(to: Float.self, capacity: maxFrames * channels)
        var framesWritten = 0
        var endedStream = false
        var fireTrailCallback: (() -> Void)?
        var fireNaturalEnd = false

        os_unfair_lock_lock(&lock)

        // 1. Emit DoP 0x69 lead-in silence if scheduled
        if phase == .leadSilence {
            let count = min(maxFrames - framesWritten, leadFramesRemaining)
            emitSilenceFrames(into: outPtr, startFrame: framesWritten, count: count)
            framesWritten += count
            leadFramesRemaining -= count
            if leadFramesRemaining <= 0 {
                phase = .activePayload
            }
        }

        // 2. Read real DoP payload frames from BASSDSD
        if phase == .activePayload && framesWritten < maxFrames {
            let remainingFrames = maxFrames - framesWritten
            let neededFloats = remainingFrames * channels
            if scratchBuffer.count < neededFloats {
                scratchBuffer = [Float](repeating: 0, count: neededFloats)
            }

            let wantBytes = DWORD(remainingFrames * frameSizeBytes)
            let gotBytes: DWORD = scratchBuffer.withUnsafeMutableBytes { raw in
                guard let base = raw.baseAddress else { return 0 }
                return BASS_ChannelGetData(decoderHandle, base, wantBytes)
            }

            if gotBytes == DWORD.max || gotBytes == 0 {
                // End of DSD stream -> switch to short 0x69 trail to avoid cut click
                trailFramesRemaining = max(4, (carrierRateHz * 40 / 1000) & ~1)
                phase = .trailSilence
            } else {
                var gotFrames = Int(gotBytes) / frameSizeBytes
                var srcOffsetFrames = 0

                // Maintain strict alternating 0x05 / 0xFA marker parity across silence boundaries
                if needsParityCheckAfterSilence && gotFrames > 0 {
                    let firstMarker = DopFrameCodec.extractDopMarker(fromFloat: scratchBuffer[0])
                    if firstMarker == lastEmittedMarker && (firstMarker == 0x05 || firstMarker == 0xFA) {
                        srcOffsetFrames = 1
                        gotFrames -= 1
                    }
                    needsParityCheckAfterSilence = false
                }

                if gotFrames > 0 {
                    let copyFloats = gotFrames * channels
                    let dstOffset = framesWritten * channels
                    let srcOffset = srcOffsetFrames * channels
                    for i in 0..<copyFloats {
                        outPtr[dstOffset + i] = scratchBuffer[srcOffset + i]
                    }
                    let lastMarker = DopFrameCodec.extractDopMarker(
                        fromFloat: scratchBuffer[srcOffset + (gotFrames - 1) * channels]
                    )
                    if lastMarker == 0x05 || lastMarker == 0xFA {
                        lastEmittedMarker = lastMarker
                    }
                    framesWritten += gotFrames
                }
            }
        }

        // 3. Emit DoP 0x69 trail-out silence when pausing/stopping/ending
        if phase == .trailSilence && framesWritten < maxFrames {
            let count = min(maxFrames - framesWritten, trailFramesRemaining)
            emitSilenceFrames(into: outPtr, startFrame: framesWritten, count: count)
            framesWritten += count
            trailFramesRemaining -= count
            if trailFramesRemaining <= 0 {
                phase = .ended
                endedStream = true
                if !trailCompletionFired, let cb = pendingTrailCompletion {
                    trailCompletionFired = true
                    pendingTrailCompletion = nil
                    fireTrailCallback = cb
                } else if !naturalEndFired && pendingTrailCompletion == nil {
                    naturalEndFired = true
                    fireNaturalEnd = true
                }
            }
        } else if phase == .ended {
            endedStream = true
        }

        os_unfair_lock_unlock(&lock)

        if let cb = fireTrailCallback {
            DispatchQueue.main.async(execute: cb)
        }
        if fireNaturalEnd {
            DispatchQueue.main.async { [weak self] in
                self?.onNaturalEnd?()
            }
        }

        var result = DWORD(framesWritten * frameSizeBytes)
        if endedStream {
            result |= DWORD(BASS_STREAMPROC_END)
        }
        return result
    }

    private func emitSilenceFrames(into ptr: UnsafeMutablePointer<Float>, startFrame: Int, count: Int) {
        for f in 0..<count {
            let nextMarker: UInt8 = (lastEmittedMarker == 0x05) ? 0xFA : 0x05
            let val = DopFrameCodec.packDopSilenceFloat(marker: nextMarker)
            let base = (startFrame + f) * channels
            for ch in 0..<channels {
                ptr[base + ch] = val
            }
            lastEmittedMarker = nextMarker
        }
    }
}

private extension DopPassthroughStream {
    func initIfPlaceholder() {}
}

private func dopStreamCallback(
    handle: HSTREAM,
    buffer: UnsafeMutableRawPointer?,
    length: DWORD,
    user: UnsafeMutableRawPointer?
) -> DWORD {
    guard let user else { return DWORD(BASS_STREAMPROC_END) }
    let stream = Unmanaged<DopPassthroughStream>.fromOpaque(user).takeUnretainedValue()
    return stream.render(buffer: buffer, requestedBytes: length)
}
