"""Build deterministic, bit-verified audio test fixtures for Fidelune BASS verification."""

from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path
import shutil
import struct
import subprocess
from tempfile import TemporaryDirectory
import wave


ROOT = Path(__file__).resolve().parents[1] / "fixtures"
PCM_LADDER_RATES = [44100, 48000, 88200, 96000, 176400, 192000, 352800, 384000]


def ffmpeg(*args: object) -> bytes:
    cmd = ["ffmpeg", "-v", "error", "-nostdin", *map(str, args)]
    proc = subprocess.run(cmd, capture_output=True, check=False)
    if proc.returncode != 0:
        err = proc.stderr.decode("utf-8", errors="replace").strip()
        raise subprocess.CalledProcessError(
            proc.returncode, cmd, output=proc.stdout, stderr=proc.stderr
        ) if not err else RuntimeError(f"ffmpeg failed ({proc.returncode}) for {cmd}: {err}")
    return proc.stdout


def supported_encoders() -> set[str]:
    out = subprocess.check_output(["ffmpeg", "-v", "error", "-encoders"], text=True)
    encoders: set[str] = set()
    for line in out.splitlines():
        parts = line.split()
        if len(parts) >= 2 and len(parts[0]) == 6:
            encoders.add(parts[1])
    return encoders


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def write_wav(path: Path, rate: int, bits: int, channels: int, data: bytes) -> None:
    with wave.open(str(path), "wb") as f:
        f.setparams((channels, bits // 8, rate, 0, "NONE", "not compressed"))
        f.writeframes(data)


def tone(
    rate: int,
    bits: int,
    channels: int,
    frames: int,
    edge: bool = False,
    amplitude: float = 0.082,
    base_freq: float = 431.0,
) -> bytes:
    """Deterministic multi-tone with distinct L/R frequencies and nonzero low bits."""
    data = bytearray()
    scale = 1 << (bits - 1)
    primary_gain = amplitude * 0.85
    secondary_gain = amplitude * 0.15
    ramp_len = max(1.0, rate / 50.0)
    byte_width = bits // 8
    for i in range(frames):
        ramp = min(1.0, i / ramp_len, (frames - 1 - i) / ramp_len)
        if edge and (i < rate // 4 or i >= frames - rate // 4):
            ramp = 0.0
        for ch in range(channels):
            signal = primary_gain * math.sin(2 * math.pi * (base_freq + 122.0 * ch) * i / rate)
            signal += secondary_gain * math.sin(2 * math.pi * (137.0 + 38.0 * ch) * i / rate)
            value = round(signal * ramp * scale)
            data.extend(value.to_bytes(byte_width, "little", signed=True))
    return bytes(data)


def write_dsd_pair(rate: int, seconds: int, dsf_name: str, dop_name: str | None = None) -> None:
    """Generate DSF (LSB-first 4096-byte planar blocks) and optional DoP 1.1 WAV carrier."""
    lanes = [bytearray(), bytearray()]
    for ch, lane in enumerate(lanes):
        errors = 0.0
        freq = 431.0 + 122.0 * ch
        for i in range(0, rate * seconds, 8):
            packed = 0
            for bit in range(8):
                errors += 0.06 * math.sin(2 * math.pi * freq * (i + bit) / rate)
                if errors >= 0:
                    packed |= 1 << bit
                    errors -= 1.0
                else:
                    errors += 1.0
            lane.append(packed)

    block = 4096
    planar = b"".join(
        lane[offset:offset + block].ljust(block, b"\0")
        for offset in range(0, len(lanes[0]), block)
        for lane in lanes
    )
    header = struct.pack(
        "<4sQQQ4sQIIIIIIQII4sQ",
        b"DSD ",
        28,
        92 + len(planar),
        0,
        b"fmt ",
        52,
        1,
        0,
        2,
        2,
        rate,
        1,
        rate * seconds,
        block,
        0,
        b"data",
        12 + len(planar),
    )
    assert len(header) == 92
    (ROOT / dsf_name).write_bytes(header + planar)

    if dop_name is not None:
        carrier = bytearray()
        reverse_byte = bytes(int(f"{value:08b}"[::-1], 2) for value in range(256))
        for i in range(0, len(lanes[0]), 2):
            marker = 0x05 if i % 4 == 0 else 0xFA
            for lane in lanes:
                carrier.extend((reverse_byte[lane[i + 1]], reverse_byte[lane[i]], marker))
        carrier_hz = rate // 16
        write_wav(ROOT / dop_name, carrier_hz, 24, 2, bytes(carrier))
        for ch, lane in enumerate(lanes):
            recovered = bytearray()
            for i in range(3 * ch, len(carrier), 6):
                assert carrier[i + 2] == (0x05 if i // 6 % 2 == 0 else 0xFA)
                recovered.extend((reverse_byte[carrier[i + 1]], reverse_byte[carrier[i]]))
            assert recovered == lane


def generate() -> None:
    if ROOT.exists():
        shutil.rmtree(ROOT)
    ROOT.mkdir(parents=True, exist_ok=True)

    encoders = supported_encoders()
    expectations: dict[str, dict] = {}

    with TemporaryDirectory() as scratch:
        source = Path(scratch) / "source.wav"

        def sample(
            name: str,
            rate: int,
            bits: int,
            channels: int,
            frames: int,
            data: bytes | None = None,
            amplitude: float = 0.082,
            base_freq: float = 431.0,
        ) -> None:
            raw = tone(rate, bits, channels, frames, amplitude=amplitude, base_freq=base_freq) if data is None else data
            write_wav(source, rate, bits, channels, raw)
            target = ROOT / name
            suffix = target.suffix.lower()
            if suffix == ".wav":
                shutil.copyfile(source, target)
            else:
                codec_map = {
                    ".flac": "flac",
                    ".m4a": "alac",
                    ".mp3": "libmp3lame",
                    ".aac": "aac",
                    ".wv": "wavpack",
                    ".opus": "libopus",
                }
                codec = codec_map[suffix]
                if codec not in encoders:
                    print(f"[skip] Encoder {codec} not available for {name}")
                    return
                extra = ["-b:a", "192k"] if suffix in {".mp3", ".aac", ".opus"} else []
                if suffix == ".flac" and rate > 192000:
                    extra.extend(["-strict", "-2"])
                ffmpeg(
                    "-y",
                    "-i",
                    source,
                    "-map_metadata",
                    "-1",
                    "-c:a",
                    codec,
                    *extra,
                    "-fflags",
                    "+bitexact",
                    "-flags:a",
                    "+bitexact",
                    target,
                )

            lossless = suffix not in {".mp3", ".aac", ".opus"}
            if lossless:
                pcm_fmt = f"s{bits}le"
                decoded = ffmpeg("-i", target, "-f", pcm_fmt, "-c:a", f"pcm_{pcm_fmt}", "-")
                assert decoded == raw, f"Lossless round-trip failed for {name}"

            expectations[name] = {
                "frames": frames,
                "source_pcm_sha256": digest(raw) if lossless else None,
                "generator_rate_hz": rate,
                "generator_channels": channels,
                "source_valid_bits": bits if lossless else None,
            }

        # 1. PCM FLAC sample-rate ladder (12s for 96k hold/hotplug/interrupt tests, 3s for >=352.8k, 6s otherwise)
        for rate in PCM_LADDER_RATES:
            bits = 16 if rate == 44100 else 24
            if rate == 96000:
                secs = 12
            elif rate >= 352800:
                secs = 3
            else:
                secs = 6
            sample(f"flac{rate}.flac", rate, bits, 2, rate * secs)

        # 2. Multi-format, bit-depth & channel layout coverage
        sample("wav16.wav", 48000, 16, 2, 48000 * 3)
        sample("wav24.wav", 48000, 24, 2, 48000 * 3)
        sample("mono24.wav", 48000, 24, 1, 48000 * 3)
        sample("alac96.m4a", 96000, 24, 2, 96000 * 4)
        sample("wv96.wv", 96000, 24, 2, 96000 * 4)
        sample("opus48.opus", 48000, 16, 2, 48000 * 4)
        sample("lossy.mp3", 44100, 16, 2, 44100 * 4)
        sample("lossy.aac", 48000, 16, 2, 48000 * 4)

        # 3. Anti-pop steady-tone pair (-12 dBFS continuous sine, exposes any hard stop click)
        sample("poptest-a.flac", 48000, 24, 2, 48000 * 6, amplitude=0.25, base_freq=440.0)
        sample("poptest-b.flac", 48000, 24, 2, 48000 * 6, amplitude=0.25, base_freq=659.25)

        # 4. Edge timing & silence boundaries
        sample("short.wav", 48000, 24, 2, 4800)  # 100 ms
        sample("silence-edge.wav", 48000, 24, 2, 48000 * 2, tone(48000, 24, 2, 96000, edge=True))

        # 5. Gapless 44.1 kHz / 16-bit pair (6s total, non-zero cut at frame 132,337)
        r44 = 44100
        sig44 = tone(r44, 16, 2, 6 * r44)
        cut44 = (3 * r44 + 37) * 4
        assert any(sig44[cut44 - 4:cut44]) and any(sig44[cut44:cut44 + 4])
        sample("continuous.wav", r44, 16, 2, 6 * r44, sig44)
        sample("gap-a.wav", r44, 16, 2, cut44 // 4, sig44[:cut44])
        sample("gap-b.wav", r44, 16, 2, (len(sig44) - cut44) // 4, sig44[cut44:])
        with wave.open(str(ROOT / "gap-a.wav"), "rb") as a, wave.open(str(ROOT / "gap-b.wav"), "rb") as b:
            assert a.readframes(a.getnframes()) + b.readframes(b.getnframes()) == sig44

        # 6. Gapless 96 kHz / 24-bit FLAC pair (6s total, non-zero cut at frame 288,073)
        r96 = 96000
        sig96 = tone(r96, 24, 2, 6 * r96)
        cut96 = (3 * r96 + 73) * 6  # 2ch * 3 bytes = 6 bytes/frame
        assert any(sig96[cut96 - 6:cut96]) and any(sig96[cut96:cut96 + 6])
        sample("continuous96.flac", r96, 24, 2, 6 * r96, sig96)
        sample("gap96-a.flac", r96, 24, 2, cut96 // 6, sig96[:cut96])
        sample("gap96-b.flac", r96, 24, 2, (len(sig96) - cut96) // 6, sig96[cut96:])

        # 7. Corrupt / truncated resilience fixtures
        orig_flac = (ROOT / "flac44100.flac").read_bytes()
        (ROOT / "truncated.flac").write_bytes(orig_flac[:len(orig_flac) // 2])
        (ROOT / "invalid.flac").write_bytes(b"Fidelune BASS intentional non-audio fixture 1\n")
        (ROOT / "invalid-2.flac").write_bytes(b"Fidelune BASS intentional non-audio fixture 2\n")

        # 8. DSD64 (6s for comfortable hardware lock/watchdog timing), DSD128 (3s) & pre-packaged DoP64 WAV
        write_dsd_pair(2822400, 6, "dsd64.dsf", "dop64.wav")
        write_dsd_pair(5644800, 3, "dsd128.dsf", None)

    # Probe and index every generated file
    sources: dict[str, dict] = {}
    for path in sorted(ROOT.iterdir()):
        if path.suffix == ".json":
            continue
        probe = subprocess.run(
            [
                "ffprobe",
                "-v",
                "error",
                "-select_streams",
                "a:0",
                "-show_streams",
                "-show_format",
                "-of",
                "json",
                str(path),
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        info = json.loads(probe.stdout) if probe.stdout.strip() else {}
        stream = next(iter(info.get("streams", [])), {})
        fmt = info.get("format", {})
        invalid = path.name.startswith("invalid")
        probed_rate = int(stream.get("sample_rate") or 0)
        assert invalid == (probed_rate == 0), (path, stream)
        if invalid:
            decode = subprocess.run(
                ["ffmpeg", "-v", "error", "-nostdin", "-i", str(path), "-f", "s16le", "-"],
                capture_output=True,
                check=False,
            )
            assert decode.returncode != 0 and not decode.stdout, path

        expected = expectations.get(path.name, {})
        if expected:
            assert int(stream["sample_rate"]) == expected["generator_rate_hz"], (path, stream)
            assert stream["channels"] == expected["generator_channels"], (path, stream)
            raw_bits = stream.get("bits_per_raw_sample")
            if (
                expected.get("source_valid_bits") is not None
                and raw_bits not in (None, "", "N/A", "0")
                and path.suffix.lower() != ".wv"
            ):
                assert int(raw_bits) == expected["source_valid_bits"], (
                    path,
                    raw_bits,
                    expected["source_valid_bits"],
                )

        sources[path.name] = {
            "sha256": digest(path.read_bytes()),
            "bytes": path.stat().st_size,
            "container": fmt.get("format_name"),
            "codec": stream.get("codec_name"),
            "ffprobe_rate_hz": stream.get("sample_rate"),
            "ffprobe_channels": stream.get("channels"),
            "ffprobe_bits_per_sample": stream.get("bits_per_sample"),
            "ffprobe_bits_per_raw_sample": stream.get("bits_per_raw_sample"),
            "ffprobe_duration_seconds": stream.get("duration", fmt.get("duration")),
            "intentional_invalid": invalid,
            **expected,
        }
        if path.name == "dsd64.dsf":
            assert stream["codec_name"] == "dsd_lsbf_planar" and stream["channels"] == 2
            sources[path.name].update(
                dsd_bits_per_second_per_channel=2822400,
                dop_carrier_hz=176400,
                source_valid_bits=1,
            )
        elif path.name == "dsd128.dsf":
            assert stream["codec_name"] == "dsd_lsbf_planar" and stream["channels"] == 2
            sources[path.name].update(
                dsd_bits_per_second_per_channel=5644800,
                dop_carrier_hz=352800,
                source_valid_bits=1,
            )
        elif path.name == "dop64.wav":
            assert stream["sample_rate"] == "176400" and stream["bits_per_sample"] == 24
            sources[path.name].update(
                dop_carrier_hz=176400,
                dsd_bits_per_second_per_channel=2822400,
            )

    record = {
        "ffmpeg": subprocess.check_output(["ffmpeg", "-version"], text=True).splitlines()[0],
        "origin": "Fidelune BASS synthetic multi-spec PCM, gapless, anti-pop, DSD/DoP and invalid fixtures",
        "sources": sources,
    }
    (ROOT / "manifest.json").write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
    print(f"Validated and indexed {len(sources)} fixtures.")


if __name__ == "__main__":
    generate()
