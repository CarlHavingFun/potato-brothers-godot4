from __future__ import annotations

import hashlib
import json
import math
import struct
import subprocess
import sys
import tempfile
import unittest
import wave
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[2]
BUILDER = PROJECT_ROOT / "tools" / "assets" / "build_combat_sfx_v1.py"
EXPECTED_CLIPS = (
    "enemy_down.wav",
    "heavy_shot.wav",
    "impact_critical.wav",
    "impact_explosion.wav",
    "impact_normal.wav",
    "pickup.wav",
    "player_hit.wav",
    "rapid_shot.wav",
    "rifle_shot.wav",
    "suppressed_shot.wav",
)


def _run_builder(output_dir: Path, report_path: Path) -> dict:
    completed = subprocess.run(
        [
            sys.executable,
            str(BUILDER),
            "--output-dir",
            str(output_dir),
            "--report",
            str(report_path),
        ],
        cwd=PROJECT_ROOT,
        check=False,
        capture_output=True,
        text=True,
    )
    assert completed.returncode == 0, completed.stderr
    return json.loads(report_path.read_text(encoding="utf-8"))


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _rms(path: Path) -> float:
    with wave.open(str(path), "rb") as reader:
        frame_count = reader.getnframes()
        samples = struct.unpack(f"<{frame_count}h", reader.readframes(frame_count))
    return math.sqrt(sum(sample * sample for sample in samples) / len(samples))


class CombatSfxBuilderTest(unittest.TestCase):
    def test_builder_writes_deterministic_original_pcm16_combat_set(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            tmp_path = Path(temporary_directory)
            first_dir = tmp_path / "first"
            second_dir = tmp_path / "second"
            first_report_path = tmp_path / "first.json"
            second_report_path = tmp_path / "second.json"

            first_report = _run_builder(first_dir, first_report_path)
            second_report = _run_builder(second_dir, second_report_path)

            self.assertEqual(
                sorted(path.name for path in first_dir.glob("*.wav")),
                list(EXPECTED_CLIPS),
            )
            self.assertEqual(first_report, second_report)
            self.assertEqual(first_report["schema"], "gogobro-combat-sfx-v1")
            self.assertEqual(first_report["sample_rate_hz"], 44_100)
            self.assertEqual(first_report["channels"], 1)
            self.assertEqual(first_report["sample_width_bits"], 16)
            self.assertEqual(
                [clip["file"] for clip in first_report["clips"]],
                list(EXPECTED_CLIPS),
            )

            for clip in first_report["clips"]:
                first_path = first_dir / clip["file"]
                second_path = second_dir / clip["file"]
                self.assertEqual(first_path.read_bytes(), second_path.read_bytes())
                self.assertEqual(clip["sha256"], _sha256(first_path))

    def test_every_clip_has_safe_short_near_zero_waveform(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            tmp_path = Path(temporary_directory)
            output_dir = tmp_path / "audio"
            report = _run_builder(output_dir, tmp_path / "report.json")

            for clip in report["clips"]:
                path = output_dir / clip["file"]
                with wave.open(str(path), "rb") as reader:
                    self.assertEqual(reader.getnchannels(), 1)
                    self.assertEqual(reader.getsampwidth(), 2)
                    self.assertEqual(reader.getframerate(), 44_100)
                    self.assertEqual(reader.getcomptype(), "NONE")
                    frame_count = reader.getnframes()
                    self.assertGreater(frame_count, 0)
                    self.assertLess(frame_count, int(0.350 * 44_100))
                    frames = reader.readframes(frame_count)

                samples = struct.unpack(f"<{frame_count}h", frames)
                peak = max(abs(sample) for sample in samples)
                self.assertLessEqual(peak, int(0.95 * 32_767))
                self.assertEqual(samples[0], 0)
                self.assertEqual(samples[-1], 0)
                self.assertLessEqual(max(abs(sample) for sample in samples[:32]), int(0.03 * 32_767))
                self.assertLessEqual(max(abs(sample) for sample in samples[-32:]), int(0.03 * 32_767))
                self.assertEqual(clip["frames"], frame_count)
                self.assertEqual(clip["duration_ms"], round(frame_count * 1000 / 44_100, 3))
                self.assertEqual(clip["peak"], round(peak / 32_767, 6))

    def test_suppressed_shot_is_shorter_and_at_least_eight_db_quieter_than_rifle(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            tmp_path = Path(temporary_directory)
            output_dir = tmp_path / "audio"
            report = _run_builder(output_dir, tmp_path / "report.json")
            clips = {clip["file"]: clip for clip in report["clips"]}
            suppressed = clips["suppressed_shot.wav"]
            rifle = clips["rifle_shot.wav"]

            self.assertLess(suppressed["duration_ms"], rifle["duration_ms"])
            relative_peak_db = 20.0 * math.log10(suppressed["peak"] / rifle["peak"])
            self.assertLessEqual(relative_peak_db, -8.0)
            relative_rms_db = 20.0 * math.log10(
                _rms(output_dir / "suppressed_shot.wav")
                / _rms(output_dir / "rifle_shot.wav")
            )
            self.assertLessEqual(relative_rms_db, -8.0)
            self.assertGreaterEqual(relative_rms_db, -14.0)


if __name__ == "__main__":
    unittest.main()
