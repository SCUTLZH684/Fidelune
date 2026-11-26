"""Compare a diagnostic PCM file with its known reference at full precision."""

import argparse
import json
from pathlib import Path
import subprocess

from fixtures import ROOT, digest, ffmpeg


def read_pcm(path):
    probe = subprocess.check_output([
        "ffprobe", "-v", "error", "-select_streams", "a:0",
        "-show_entries", "stream=codec_name,sample_rate,channels", "-of", "json", str(path),
    ])
    info = json.loads(probe)["streams"][0]
    if info["codec_name"] not in {"pcm_s16le", "pcm_s24le", "pcm_s32le"}:
        raise ValueError(f"{path}: expected signed integer WAV, found {info['codec_name']}")
    pcm = ffmpeg("-i", path, "-f", "s32le", "-c:a", "pcm_s32le", "-")
    return int(info["sample_rate"]), info["channels"], pcm


def aligned_find(data, pattern, frame_size, start=0):
    index = data.find(pattern, start)
    while index != -1 and index % frame_size:
        index = data.find(pattern, index + 1)
    return None if index == -1 else index // frame_size


def compare(kind, capture):
    ref = ROOT / ("wav24.wav" if kind == "pcm24" else "continuous.wav")
    rate, channels, source = read_pcm(ref)
    capture_rate, capture_channels, result = read_pcm(capture)
    size = channels * 4
    identical = (capture_rate, capture_channels, result) == (rate, channels, source)
    report = {
        "reference_hz": rate, "capture_hz": capture_rate,
        "reference_channels": channels, "capture_channels": capture_channels,
        "reference_frames": len(source) // size,
        "capture_frames": len(result) // (capture_channels * 4),
        "reference_s32le_sha256": digest(source), "capture_s32le_sha256": digest(result),
        "exact_same_frames_and_samples": identical,
    }
    if kind == "gap" and (rate, channels) == (capture_rate, capture_channels):
        cut = 44137
        # Find short anchors immediately before and after the source split.
        before = aligned_find(result, source[(cut - 512) * size:(cut - 256) * size], size)
        after = None if before is None else aligned_find(
            result, source[(cut + 256) * size:(cut + 512) * size], size, (before + 256) * size)
        report["boundary_anchors_delta_frames"] = None if after is None else after - before - 768
        if before is not None and after is not None and after - before == 768:
            report["boundary_samples_match"] = (
                result[before * size:(after + 256) * size]
                == source[(cut - 512) * size:(cut + 512) * size]
            )
    return identical, report


if __name__ == "__main__":
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("kind", choices=["pcm24", "gap"])
    cli.add_argument("capture", type=Path)
    args = cli.parse_args()
    passed, evidence = compare(args.kind, args.capture)
    print(json.dumps(evidence, indent=2))
    raise SystemExit(0 if passed else 1)
