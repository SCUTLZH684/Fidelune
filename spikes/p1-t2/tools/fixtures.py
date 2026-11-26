"""Build original test signals and verify lossless decoder output."""

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
RATES = [44100, 48000, 88200, 96000, 176400, 192000]


def ffmpeg(*args):
    return subprocess.check_output(["ffmpeg", "-v", "error", "-nostdin", *map(str, args)])


def digest(data):
    return hashlib.sha256(data).hexdigest()


def write_wav(path, rate, bits, channels, data):
    with wave.open(str(path), "wb") as f:
        f.setparams((channels, bits // 8, rate, 0, "NONE", "not compressed"))
        f.writeframes(data)


def tone(rate, bits, channels, frames, edge=False):
    # Distinct channels and nonzero low bits expose swaps and loss of precision.
    data = bytearray()
    for i in range(frames):
        ramp = min(1, i / (rate / 50), (frames - 1 - i) / (rate / 50))
        if edge and (i < rate // 4 or i >= frames - rate // 4):
            ramp = 0
        for ch in range(channels):
            signal = 0.07 * math.sin(2 * math.pi * (431 + 122 * ch) * i / rate)
            signal += 0.012 * math.sin(2 * math.pi * (137 + 38 * ch) * i / rate)
            value = round(signal * ramp * (1 << (bits - 1)))
            data.extend(value.to_bytes(bits // 8, "little", signed=True))
    return bytes(data)


def write_dsd():
    # DSF is one-bit LSB-first with 4096-byte planar blocks. The same DSD64
    # payload is packed into the low 16 bits of a separate DoP carrier.
    rate = 2822400
    lanes = [bytearray(), bytearray()]
    for ch, lane in enumerate(lanes):
        errors = 0.0
        for i in range(0, rate * 3, 8):
            packed = 0
            for bit in range(8):
                errors += 0.07 * math.sin(2 * math.pi * (431 + 122 * ch) * (i + bit) / rate)
                if errors >= 0:
                    packed |= 1 << bit
                    errors -= 1
                else:
                    errors += 1
            lane.append(packed)
    block = 4096
    planar = b"".join(lane[offset:offset + block].ljust(block, b"\0")
                      for offset in range(0, len(lanes[0]), block) for lane in lanes)
    header = struct.pack("<4sQQQ4sQIIIIIIQII4sQ",
                         b"DSD ", 28, 92 + len(planar), 0, b"fmt ", 52,
                         1, 0, 2, 2, rate, 1, rate * 3, block, 0, b"data", 12 + len(planar))
    assert len(header) == 92
    (ROOT / "dsd64.dsf").write_bytes(header + planar)
    carrier = bytearray()
    reverse_byte = bytes(int(f"{value:08b}"[::-1], 2) for value in range(256))
    for i in range(0, len(lanes[0]), 2):
        marker = 0x05 if i % 4 == 0 else 0xFA
        for lane in lanes:
            carrier.extend((reverse_byte[lane[i + 1]], reverse_byte[lane[i]], marker))
    write_wav(ROOT / "dop64.wav", 176400, 24, 2, carrier)
    for ch, lane in enumerate(lanes):
        recovered = bytearray()
        for i in range(3 * ch, len(carrier), 6):
            assert carrier[i + 2] == (0x05 if i // 6 % 2 == 0 else 0xFA)
            recovered.extend((reverse_byte[carrier[i + 1]], reverse_byte[carrier[i]]))
        assert recovered == lane


def generate():
    ROOT.mkdir(exist_ok=True)
    expectations = {}
    with TemporaryDirectory() as scratch:
        source = Path(scratch) / "source.wav"

        def sample(name, rate, bits, channels, frames, data=None):
            data = tone(rate, bits, channels, frames) if data is None else data
            write_wav(source, rate, bits, channels, data)
            target = ROOT / name
            if target.suffix == ".wav":
                shutil.copyfile(source, target)
            else:
                codec = {".flac": "flac", ".m4a": "alac", ".mp3": "libmp3lame",
                         ".aac": "aac"}[target.suffix]
                ffmpeg("-y", "-i", source, "-map_metadata", "-1", "-c:a", codec,
                       "-fflags", "+bitexact", "-flags:a", "+bitexact", target)
            lossless = target.suffix not in {".mp3", ".aac"}
            if lossless:
                pcm = f"s{bits}le"
                decoded = ffmpeg("-i", target, "-f", pcm, "-c:a", f"pcm_{pcm}", "-")
                assert decoded == data, name
            expectations[name] = {"frames": frames, "source_pcm_sha256": digest(data) if lossless else None,
                                  "generator_rate_hz": rate, "generator_channels": channels,
                                  "source_valid_bits": bits if lossless else None}

        for rate in RATES:
            sample(f"flac{rate}.flac", rate, 16 if rate == 44100 else 24, 2, rate * 9)
        sample("wav16.wav", 48000, 16, 2, 48000 * 4)
        sample("wav24.wav", 48000, 24, 2, 48000 * 4)
        sample("mono24.wav", 48000, 24, 1, 48000 * 4)
        sample("alac96.m4a", 96000, 24, 2, 96000 * 5)
        sample("lossy.mp3", 44100, 16, 2, 44100 * 5)
        sample("lossy.aac", 48000, 16, 2, 48000 * 5)
        sample("short.wav", 48000, 24, 2, 4800)
        sample("silence-edge.wav", 48000, 24, 2, 48000 * 2, tone(48000, 24, 2, 96000, edge=True))
        rate = 44100
        signal = tone(rate, 16, 2, 2 * rate)
        cut = (rate + 37) * 4
        assert any(signal[cut - 4:cut]) and any(signal[cut:cut + 4])
        sample("continuous.wav", rate, 16, 2, 2 * rate, signal)
        sample("gap-a.wav", rate, 16, 2, cut // 4, signal[:cut])
        sample("gap-b.wav", rate, 16, 2, (len(signal) - cut) // 4, signal[cut:])
        with wave.open(str(ROOT / "gap-a.wav"), "rb") as a, wave.open(str(ROOT / "gap-b.wav"), "rb") as b:
            assert a.readframes(a.getnframes()) + b.readframes(b.getnframes()) == signal
        original = (ROOT / "flac44100.flac").read_bytes()
        (ROOT / "truncated.flac").write_bytes(original[:len(original) // 2])
        (ROOT / "invalid.flac").write_bytes(b"Fidelune P1-T2 intentional non-audio fixture\n")
        (ROOT / "invalid-2.flac").write_bytes(b"Fidelune P1-T2 second non-audio fixture\n")
        write_dsd()

    sources = {}
    for path in sorted(ROOT.iterdir()):
        if path.suffix == ".json":
            continue
        probe = subprocess.run(
            ["ffprobe", "-v", "error", "-select_streams", "a:0", "-show_streams",
             "-show_format", "-of", "json", str(path)], capture_output=True, text=True, check=False)
        info = json.loads(probe.stdout)
        stream = next(iter(info.get("streams", [])), {})
        fmt = info.get("format", {})
        invalid = path.name.startswith("invalid")
        assert invalid == (int(stream.get("sample_rate", 0)) == 0), path
        if invalid:
            decode = subprocess.run(
                ["ffmpeg", "-v", "error", "-nostdin", "-i", str(path), "-f", "s16le", "-"],
                capture_output=True, check=False)
            assert decode.returncode != 0 and not decode.stdout, path
        expected = expectations.get(path.name, {})
        if expected:
            assert int(stream["sample_rate"]) == expected["generator_rate_hz"], path
            assert stream["channels"] == expected["generator_channels"], path
            if stream.get("bits_per_raw_sample", "N/A") != "N/A":
                assert int(stream["bits_per_raw_sample"]) == expected["source_valid_bits"], path
        sources[path.name] = {
            "sha256": digest(path.read_bytes()), "bytes": path.stat().st_size,
            "container": fmt.get("format_name"), "codec": stream.get("codec_name"),
            "ffprobe_rate_hz": stream.get("sample_rate"), "ffprobe_channels": stream.get("channels"),
            "ffprobe_bits_per_sample": stream.get("bits_per_sample"),
            "ffprobe_bits_per_raw_sample": stream.get("bits_per_raw_sample"),
            "ffprobe_duration_seconds": stream.get("duration", fmt.get("duration")),
            "intentional_invalid": invalid,
            **expected,
        }
        if path.name == "dsd64.dsf":
            assert stream["codec_name"] == "dsd_lsbf_planar" and stream["channels"] == 2
            sources[path.name].update(dsd_bits_per_second_per_channel=2822400, source_valid_bits=1)
        if path.name == "dop64.wav":
            assert stream["sample_rate"] == "176400" and stream["bits_per_sample"] == 24
            sources[path.name].update(dop_carrier_hz=176400, dsd_bits_per_second_per_channel=2822400)
    record = {"ffmpeg": subprocess.check_output(["ffmpeg", "-version"], text=True).splitlines()[0],
              "origin": "Fidelune synthetic stereo/mono test tones and intentional invalid files",
              "sources": sources}
    (ROOT / "manifest.json").write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
    print(f"Validated and indexed {len(sources)} fixtures.")


if __name__ == "__main__":
    generate()
