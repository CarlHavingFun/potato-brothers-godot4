#!/usr/bin/env python3
"""Build GOGOBRO's original deterministic combat sound-effect set."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import struct
import wave
from dataclasses import dataclass
from pathlib import Path
from typing import Callable


SAMPLE_RATE = 44_100
PCM_LIMIT = 32_767
SCHEMA = "gogobro-combat-sfx-v1"
PROJECT_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUTPUT_DIR = PROJECT_ROOT / "game" / "assets" / "audio" / "combat"
DEFAULT_REPORT = DEFAULT_OUTPUT_DIR / "combat_sfx_v1.sha256.json"


@dataclass(frozen=True)
class ClipSpec:
    file: str
    duration_ms: int
    seed: int
    target_peak: float
    synth: Callable[[float, float, float, float], float]


class DeterministicNoise:
    def __init__(self, seed: int) -> None:
        self._state = seed & 0xFFFFFFFF or 0x6D2B79F5

    def sample(self) -> float:
        value = self._state
        value ^= (value << 13) & 0xFFFFFFFF
        value ^= value >> 17
        value ^= (value << 5) & 0xFFFFFFFF
        self._state = value & 0xFFFFFFFF
        return (self._state / 0xFFFFFFFF) * 2.0 - 1.0


def _tone(frequency: float, time_seconds: float, phase: float = 0.0) -> float:
    return math.sin(math.tau * frequency * time_seconds + phase)


def _rapid_shot(t: float, u: float, noise: float, smooth_noise: float) -> float:
    crack = 0.78 * noise * math.exp(-24.0 * t)
    body = 0.45 * _tone(185.0 - 55.0 * u, t) * math.exp(-18.0 * t)
    click = 0.20 * _tone(2_200.0, t) * math.exp(-48.0 * t)
    return crack + body + click + smooth_noise * 0.12


def _rifle_shot(t: float, u: float, noise: float, smooth_noise: float) -> float:
    crack = 0.88 * noise * math.exp(-16.0 * t)
    body = 0.62 * _tone(132.0 - 38.0 * u, t) * math.exp(-10.0 * t)
    ring = 0.18 * _tone(720.0, t) * math.exp(-14.0 * t)
    return crack + body + ring + smooth_noise * 0.18


def _heavy_shot(t: float, u: float, noise: float, smooth_noise: float) -> float:
    boom = 0.78 * _tone(84.0 - 28.0 * u, t) * math.exp(-7.0 * t)
    punch = 0.72 * smooth_noise * math.exp(-11.0 * t)
    metal = 0.18 * _tone(310.0, t) * math.exp(-13.0 * t)
    return boom + punch + metal + noise * 0.18 * math.exp(-24.0 * t)


def _suppressed_shot(t: float, u: float, noise: float, smooth_noise: float) -> float:
    puff = 0.52 * smooth_noise * math.exp(-34.0 * t)
    snap = 0.20 * noise * math.exp(-52.0 * t)
    body = 0.18 * _tone(160.0 - 40.0 * u, t) * math.exp(-28.0 * t)
    return puff + snap + body


def _impact_normal(t: float, _u: float, noise: float, smooth_noise: float) -> float:
    knock = 0.58 * _tone(240.0, t) * math.exp(-28.0 * t)
    grit = (noise * 0.28 + smooth_noise * 0.30) * math.exp(-35.0 * t)
    return knock + grit


def _impact_critical(t: float, u: float, noise: float, _smooth_noise: float) -> float:
    ping = 0.62 * _tone(1_080.0 + 220.0 * u, t) * math.exp(-15.0 * t)
    shine = 0.38 * _tone(1_690.0, t, 0.4) * math.exp(-19.0 * t)
    return ping + shine + noise * 0.20 * math.exp(-32.0 * t)


def _impact_explosion(t: float, u: float, noise: float, smooth_noise: float) -> float:
    blast = smooth_noise * (0.84 - 0.32 * u) * math.exp(-5.0 * t)
    rumble = 0.62 * _tone(66.0 - 20.0 * u, t) * math.exp(-4.2 * t)
    debris = noise * 0.24 * math.exp(-8.0 * t)
    return blast + rumble + debris


def _enemy_down(t: float, u: float, noise: float, smooth_noise: float) -> float:
    fall = 0.66 * _tone(310.0 - 225.0 * u, t) * math.exp(-5.5 * t)
    clatter = (0.28 * noise + 0.20 * smooth_noise) * math.exp(-10.0 * t)
    return fall + clatter


def _player_hit(t: float, u: float, noise: float, smooth_noise: float) -> float:
    thump = 0.72 * _tone(118.0 - 32.0 * u, t) * math.exp(-10.0 * t)
    edge = noise * 0.34 * math.exp(-26.0 * t)
    return thump + edge + smooth_noise * 0.18


def _pickup(t: float, u: float, _noise: float, _smooth_noise: float) -> float:
    first = _tone(720.0, t) * math.exp(-10.0 * t)
    second_time = max(t - 0.070, 0.0)
    second_gate = 1.0 if t >= 0.070 else 0.0
    second = _tone(1_080.0, second_time) * math.exp(-12.0 * second_time) * second_gate
    shimmer = 0.20 * _tone(1_440.0 + 80.0 * u, t) * math.exp(-12.0 * t)
    return first * 0.52 + second * 0.62 + shimmer


CLIPS = (
    ClipSpec("enemy_down.wav", 240, 0xE011D001, 0.82, _enemy_down),
    ClipSpec("heavy_shot.wav", 220, 0x4EA7B001, 0.90, _heavy_shot),
    ClipSpec("impact_critical.wav", 130, 0xC8171CA1, 0.84, _impact_critical),
    ClipSpec("impact_explosion.wav", 300, 0xE7A10510, 0.90, _impact_explosion),
    ClipSpec("impact_normal.wav", 90, 0x10AC7A01, 0.78, _impact_normal),
    ClipSpec("pickup.wav", 180, 0x91C0A001, 0.72, _pickup),
    ClipSpec("player_hit.wav", 160, 0x91A9E417, 0.84, _player_hit),
    ClipSpec("rapid_shot.wav", 90, 0x7A91D001, 0.78, _rapid_shot),
    ClipSpec("rifle_shot.wav", 150, 0x71F1E001, 0.86, _rifle_shot),
    ClipSpec("suppressed_shot.wav", 75, 0x5A99E551, 0.32, _suppressed_shot),
)


def _edge_envelope(index: int, frame_count: int) -> float:
    attack_frames = max(1, round(0.005 * SAMPLE_RATE))
    release_frames = max(1, round(0.018 * SAMPLE_RATE))
    attack = min(index / attack_frames, 1.0)
    release = min((frame_count - 1 - index) / release_frames, 1.0)
    return min(attack * attack, release * release)


def _render(spec: ClipSpec) -> list[int]:
    frame_count = round(spec.duration_ms * SAMPLE_RATE / 1000)
    source = DeterministicNoise(spec.seed)
    smooth_noise = 0.0
    floating_samples: list[float] = []
    for index in range(frame_count):
        time_seconds = index / SAMPLE_RATE
        progress = index / max(frame_count - 1, 1)
        noise = source.sample()
        smooth_noise = smooth_noise * 0.84 + noise * 0.16
        sample = spec.synth(time_seconds, progress, noise, smooth_noise)
        floating_samples.append(sample * _edge_envelope(index, frame_count))

    source_peak = max(abs(sample) for sample in floating_samples) or 1.0
    scale = spec.target_peak / source_peak
    samples = [
        max(-PCM_LIMIT, min(PCM_LIMIT, round(sample * scale * PCM_LIMIT)))
        for sample in floating_samples
    ]
    samples[0] = 0
    samples[-1] = 0
    return samples


def _write_wave(path: Path, samples: list[int]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    pcm = struct.pack(f"<{len(samples)}h", *samples)
    with wave.open(str(path), "wb") as writer:
        writer.setnchannels(1)
        writer.setsampwidth(2)
        writer.setframerate(SAMPLE_RATE)
        writer.setcomptype("NONE", "not compressed")
        writer.writeframes(pcm)


def build(output_dir: Path, report_path: Path) -> dict:
    clip_reports: list[dict] = []
    for spec in CLIPS:
        samples = _render(spec)
        path = output_dir / spec.file
        _write_wave(path, samples)
        peak = max(abs(sample) for sample in samples)
        clip_reports.append(
            {
                "duration_ms": round(len(samples) * 1000 / SAMPLE_RATE, 3),
                "file": spec.file,
                "frames": len(samples),
                "peak": round(peak / PCM_LIMIT, 6),
                "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            }
        )

    report = {
        "channels": 1,
        "clips": clip_reports,
        "sample_rate_hz": SAMPLE_RATE,
        "sample_width_bits": 16,
        "schema": SCHEMA,
    }
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(
        json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
        newline="\n",
    )
    return report


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    return parser.parse_args()


def main() -> int:
    args = _parse_args()
    report = build(args.output_dir.resolve(), args.report.resolve())
    print(json.dumps(report, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
