"""Unit tests for Fidelune BASS tooling (runs on Windows without ffmpeg/Xcode)."""

from __future__ import annotations

import pathlib
import sys
import unittest

TOOLS_DIR = pathlib.Path(__file__).resolve().parent
if str(TOOLS_DIR) not in sys.path:
    sys.path.insert(0, str(TOOLS_DIR))

import compare_pcm  # noqa: E402
import fetch_bass  # noqa: E402
import fixtures  # noqa: E402


class BassToolsTests(unittest.TestCase):
    def test_bass_deps_manifest_complete_and_valid_sha256(self) -> None:
        manifest = fetch_bass.load_manifest()
        pkgs = {pkg["name"]: pkg for pkg in manifest["packages"]}
        expected = {"bass", "bassmix", "bassdsd", "bassflac", "basswv", "bassape", "bassopus"}
        self.assertEqual(set(pkgs.keys()), expected)
        for name, pkg in pkgs.items():
            self.assertEqual(len(pkg["sha256"]), 64, name)
            self.assertTrue(pkg["url"].startswith("https://www.un4seen.com/files/"))
            self.assertTrue(pkg["xcframework"].endswith(".xcframework"))
            self.assertTrue(pkg["header"].endswith(".h"))

    def test_tone_and_compare_pcm_controls(self) -> None:
        rate = 44100
        chans = 2
        frames = rate * 2
        # Build 16-bit tone promoted to s32le for pure-Python buffer comparison
        raw16 = fixtures.tone(rate, 16, chans, frames)
        s32 = bytearray()
        for i in range(0, len(raw16), 2):
            sample = int.from_bytes(raw16[i:i + 2], "little", signed=True) << 16
            s32.extend(sample.to_bytes(4, "little", signed=True))
        buf = bytes(s32)

        # Positive control: identical buffers pass and boundary matches
        ok, report = compare_pcm.compare_pcm_buffers(rate, chans, buf, rate, chans, buf, cut_frame=44137)
        self.assertTrue(ok)
        self.assertEqual(report["boundary_anchors_delta_frames"], 0)
        self.assertTrue(report["boundary_samples_match"])

        # Negative control 1: LSB mutation detected
        mutated = bytearray(buf)
        mutated[4000] ^= 0x01
        ok_mut, _ = compare_pcm.compare_pcm_buffers(rate, chans, buf, rate, chans, bytes(mutated))
        self.assertFalse(ok_mut)

        # Negative control 2: 5 inserted zero frames at cut boundary detected
        cut_byte = 44137 * chans * 4
        gapped = buf[:cut_byte] + (b"\x00" * (5 * chans * 4)) + buf[cut_byte:]
        ok_gap, gap_report = compare_pcm.compare_pcm_buffers(
            rate, chans, buf, rate, chans, gapped, cut_frame=44137
        )
        self.assertFalse(ok_gap)
        self.assertEqual(gap_report["boundary_anchors_delta_frames"], 5)


if __name__ == "__main__":
    unittest.main()
