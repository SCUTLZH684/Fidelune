"""Compare a diagnostic PCM WAV capture with its known reference at full precision."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import subprocess

from fixtures import ROOT, digest, ffmpeg


def read_pcm(path: Path) -> tuple[int, int, bytes]:
    probe = subprocess.check_output([
        "ffprobe",
        "-v",
        "error",
        "-select_streams",
        "a:0",
        "-show_entries",
        "stream=codec_name,sample_rate,channels",
        "-of",
        "json",
        str(path),
    ])
    info = json.loads(probe)["streams"][0]
    if info["codec_name"] not in {"pcm_s16le", "pcm_s24le", "pcm_s32le"}:
        raise ValueError(f"{path}: expected signed integer WAV, found {info['codec_name']}")
    pcm = ffmpeg("-i", path, "-f", "s32le", "-c:a", "pcm_s32le", "-")
    return int(info["sample_rate"]), info["channels"], pcm


def aligned_find(data: bytes, pattern: bytes, frame_size: int, start: int = 0) -> int | None:
    index = data.find(pattern, start)
    while index != -1 and index % frame_size:
        index = data.find(pattern, index + 1)
    return None if index == -1 else index // frame_size


def compare_pcm_buffers(
    rate: int,
    channels: int,
    source_s32le: bytes,
    capture_rate: int,
    capture_channels: int,
    capture_s32le: bytes,
    cut_frame: int | None = None,
) -> tuple[bool, dict]:
    """Compare raw s32le PCM buffers directly (usable in pure-Python unit tests)."""
    size = channels * 4
    identical = (capture_rate, capture_channels, capture_s32le) == (rate, channels, source_s32le)
    report: dict[str, object] = {
        "reference_hz": rate,
        "capture_hz": capture_rate,
        "reference_channels": channels,
        "capture_channels": capture_channels,
        "reference_frames": len(source_s32le) // size,
        "capture_frames": len(capture_s32le) // (capture_channels * 4),
        "reference_s32le_sha256": digest(source_s32le),
        "capture_s32le_sha256": digest(capture_s32le),
        "exact_same_frames_and_samples": identical,
    }
    if cut_frame is not None and (rate, channels) == (capture_rate, capture_channels):
        before = aligned_find(
            capture_s32le,
            source_s32le[(cut_frame - 512) * size:(cut_frame - 256) * size],
            size,
        )
        after = None if before is None else aligned_find(
            capture_s32le,
            source_s32le[(cut_frame + 256) * size:(cut_frame + 512) * size],
            size,
            (before + 256) * size,
        )
        report["boundary_anchors_delta_frames"] = None if after is None else after - before - 768
        if before is not None and after is not None and after - before == 768:
            report["boundary_samples_match"] = (
                capture_s32le[before * size:(after + 256) * size]
                == source_s32le[(cut_frame - 512) * size:(cut_frame + 512) * size]
            )
    return identical, report


def compare(kind: str, capture: Path) -> tuple[bool, dict]:
    ref_map = {
        "pcm24": ("wav24.wav", None),
        "gap": ("continuous.wav", 44137),
        "gap96": ("continuous96.flac", 96037),
    }
    ref_name, cut_frame = ref_map[kind]
    ref = ROOT / ref_name
    rate, channels, source = read_pcm(ref)
    capture_rate, capture_channels, result = read_pcm(capture)
    return compare_pcm_buffers(rate, channels, source, capture_rate, capture_channels, result, cut_frame)


if __name__ == "__main__":
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("kind", choices=["pcm24", "gap", "gap96"])
    cli.add_argument("capture", type=Path)
    args = cli.parse_args()
    passed, evidence = compare(args.kind, args.capture)
    print(json.dumps(evidence, indent=2))
    raise SystemExit(0 if passed else 1)
