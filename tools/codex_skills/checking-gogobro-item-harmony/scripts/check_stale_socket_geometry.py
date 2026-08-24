"""Reject socket geometry copied from a prior rig by cycling or one affine transform.

Run this negative-control gate before updating a trusted binding for a changed
animation. The baseline must be the previously approved rig; the candidate is
the newly authored rig. Exit 2 means stale reuse or an invalid comparison.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import sys
from collections import Counter
from fractions import Fraction
from pathlib import Path
from typing import Any


MIN_AFFINE_REUSE_RATIO = Fraction(4, 5)
MIN_SOCKET_COUNT = 3
MAX_AXIS_HYPOTHESES = 16
SCHEMA_VERSION = "gogobro-character-attachment-rig-v2"


def _load_trust_module() -> Any:
    module_name = "_gogobro_stale_geometry_trusted_bindings"
    module_path = Path(__file__).with_name("trusted_character_bindings.py").resolve()
    spec = importlib.util.spec_from_file_location(module_name, module_path)
    if spec is None or spec.loader is None:
        raise RuntimeError("trusted bindings module cannot be loaded")
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _read_rig(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise ValueError("malformed_rig") from error
    if (
        type(value) is not dict
        or value.get("schema_version") != SCHEMA_VERSION
        or type(value.get("rig_id")) is not str
        or not value["rig_id"]
        or type(value.get("character_id")) is not str
        or not value["character_id"]
    ):
        raise ValueError("malformed_rig")
    return value


def _pair(value: object) -> tuple[int, int]:
    if (
        type(value) is not list
        or len(value) != 2
        or type(value[0]) is not int
        or type(value[1]) is not int
    ):
        raise ValueError("invalid_socket_geometry")
    return value[0], value[1]


def _frames(rig: dict[str, Any], animation_id: str) -> list[dict[str, Any]]:
    animations = rig.get("animations")
    state = animations.get(animation_id) if type(animations) is dict else None
    frames = state.get("frames") if type(state) is dict else None
    frame_count = state.get("frame_count") if type(state) is dict else None
    if (
        type(frames) is not list
        or not frames
        or type(frame_count) is not int
        or frame_count != len(frames)
        or any(type(frame) is not dict for frame in frames)
        or any(
            frame.get("frame_index") != frame_index
            for frame_index, frame in enumerate(frames)
        )
    ):
        raise ValueError("invalid_animation_geometry")
    return frames


def _baseline_socket_ids(frames: list[dict[str, Any]]) -> tuple[str, ...]:
    first = frames[0].get("sockets")
    if type(first) is not dict or not first:
        raise ValueError("invalid_socket_geometry")
    socket_ids = tuple(sorted(first))
    if any(type(socket_id) is not str for socket_id in socket_ids):
        raise ValueError("invalid_socket_geometry")
    if len(socket_ids) < MIN_SOCKET_COUNT:
        raise ValueError("insufficient_geometry_evidence")
    expected = set(socket_ids)
    for frame in frames:
        sockets = frame.get("sockets")
        if type(sockets) is not dict or set(sockets) != expected:
            raise ValueError("baseline_socket_topology_mismatch")
        for socket_id in socket_ids:
            _pair(sockets[socket_id])
    return socket_ids


def _rank_axis_hypotheses(
    pairs: list[tuple[int, int]],
) -> list[tuple[Fraction, Fraction]]:
    frequencies: Counter[tuple[Fraction, Fraction]] = Counter()
    frequencies[(Fraction(1), Fraction(0))] += 1
    for source, target in pairs:
        frequencies[(Fraction(1), Fraction(target - source))] += 1
        frequencies[(Fraction(0), Fraction(target))] += 1
    for first_index, (source1, target1) in enumerate(pairs):
        for source2, target2 in pairs[first_index + 1 :]:
            if source1 == source2:
                continue
            scale = Fraction(target2 - target1, source2 - source1)
            translate = Fraction(target1) - scale * source1
            frequencies[(scale, translate)] += 1
    candidates = {
        transform
        for transform, _ in frequencies.most_common(MAX_AXIS_HYPOTHESES * 2)
    }
    candidates.add((Fraction(1), Fraction(0)))
    return sorted(
        candidates,
        key=lambda transform: (
            -sum(
                transform[0] * source + transform[1] == target
                for source, target in pairs
            ),
            transform,
        ),
    )[:MAX_AXIS_HYPOTHESES]


def _best_axis_aligned_affine(
    correspondences: list[tuple[int, int, int, int, int, str]],
) -> tuple[tuple[Fraction, Fraction, Fraction, Fraction], set[int]]:
    """Return the deterministic axis-aligned affine with the most exact inliers."""
    x_hypotheses = _rank_axis_hypotheses(
        [(value[0], value[2]) for value in correspondences]
    )
    y_hypotheses = _rank_axis_hypotheses(
        [(value[1], value[3]) for value in correspondences]
    )
    best_transform = (
        x_hypotheses[0][0],
        x_hypotheses[0][1],
        y_hypotheses[0][0],
        y_hypotheses[0][1],
    )
    best_inliers: set[int] = set()
    for scale_x, translate_x in x_hypotheses:
        for scale_y, translate_y in y_hypotheses:
            transform = (scale_x, translate_x, scale_y, translate_y)
            inliers = {
                index
                for index, (
                    source_x,
                    source_y,
                    target_x,
                    target_y,
                    _,
                    _,
                ) in enumerate(correspondences)
                if scale_x * source_x + translate_x == target_x
                and scale_y * source_y + translate_y == target_y
            }
            if len(inliers) > len(best_inliers) or (
                len(inliers) == len(best_inliers) and transform < best_transform
            ):
                best_transform = transform
                best_inliers = inliers
    return best_transform, best_inliers


def _correspondences(
    baseline_frames: list[dict[str, Any]],
    candidate_frames: list[dict[str, Any]],
    socket_ids: tuple[str, ...],
    candidate_indexes: list[int],
    phase: int,
) -> list[tuple[int, int, int, int, int, str]]:
    result: list[tuple[int, int, int, int, int, str]] = []
    for candidate_index in candidate_indexes:
        baseline_frame = baseline_frames[
            (candidate_index + phase) % len(baseline_frames)
        ]
        baseline_sockets = baseline_frame["sockets"]
        candidate_sockets = candidate_frames[candidate_index].get("sockets")
        if type(candidate_sockets) is not dict:
            raise ValueError("invalid_socket_geometry")
        if set(socket_ids) - set(candidate_sockets):
            raise ValueError("candidate_socket_topology_mismatch")
        for socket_id in socket_ids:
            baseline_position = _pair(baseline_sockets[socket_id])
            candidate_position = _pair(candidate_sockets[socket_id])
            result.append(
                (
                    baseline_position[0],
                    baseline_position[1],
                    candidate_position[0],
                    candidate_position[1],
                    candidate_index,
                    socket_id,
                )
            )
    return result


def _best_phase_comparison(
    baseline_frames: list[dict[str, Any]],
    candidate_frames: list[dict[str, Any]],
    socket_ids: tuple[str, ...],
    candidate_indexes: list[int],
) -> dict[str, Any]:
    best_phase = 0
    best_correspondences: list[tuple[int, int, int, int, int, str]] = []
    best_transform = (Fraction(1), Fraction(0), Fraction(1), Fraction(0))
    best_inliers: set[int] = set()
    for phase in range(len(baseline_frames)):
        values = _correspondences(
            baseline_frames,
            candidate_frames,
            socket_ids,
            candidate_indexes,
            phase,
        )
        transform, inliers = _best_axis_aligned_affine(values)
        if len(inliers) > len(best_inliers):
            best_phase = phase
            best_correspondences = values
            best_transform = transform
            best_inliers = inliers
    if not best_correspondences:
        best_correspondences = _correspondences(
            baseline_frames,
            candidate_frames,
            socket_ids,
            candidate_indexes,
            0,
        )
    reuse_ratio = Fraction(len(best_inliers), len(best_correspondences))
    complete_socket_tracks = sorted(
        socket_id
        for socket_id in socket_ids
        if all(
            index in best_inliers
            for index, correspondence in enumerate(best_correspondences)
            if correspondence[5] == socket_id
        )
    )
    return {
        "candidate_frame_indexes": candidate_indexes,
        "compared_positions": len(best_correspondences),
        "cycle_phase": best_phase,
        "frame_mapping": "(candidate_index + cycle_phase) modulo baseline_frame_count",
        "affine_reuse": reuse_ratio >= MIN_AFFINE_REUSE_RATIO,
        "minimum_affine_reuse_ratio": float(MIN_AFFINE_REUSE_RATIO),
        "affine_inlier_positions": len(best_inliers),
        "affine_inlier_ratio": float(reuse_ratio),
        "complete_reused_socket_tracks": complete_socket_tracks,
        "transform": {
            "scale_x": _fraction_text(best_transform[0]),
            "translate_x": _fraction_text(best_transform[1]),
            "scale_y": _fraction_text(best_transform[2]),
            "translate_y": _fraction_text(best_transform[3]),
        },
    }


def _fraction_text(value: Fraction | None) -> str | None:
    if value is None:
        return None
    return str(value.numerator) if value.denominator == 1 else str(value)


def _trusted_baseline_sha256(character_id: str, animation_id: str) -> str:
    try:
        trust_module = _load_trust_module()
        catalog = trust_module.load_trusted_bindings()
        _, animation = trust_module.animation_binding(
            catalog, character_id, animation_id
        )
        return animation["rig_sha256"]
    except (KeyError, OSError, RuntimeError, TypeError, ValueError) as error:
        raise ValueError("baseline_not_trusted") from error


def check_stale_geometry(
    baseline_path: Path,
    candidate_path: Path,
    animation_id: str,
    *,
    require_trusted_baseline: bool = True,
) -> dict[str, Any]:
    reasons: set[str] = set()
    before = {
        "baseline_rig": _sha256(baseline_path) if baseline_path.is_file() else None,
        "candidate_rig": _sha256(candidate_path) if candidate_path.is_file() else None,
    }
    report: dict[str, Any] = {
        "verdict": "hard_fail",
        "reason_codes": [],
        "animation_id": animation_id,
        "baseline": {
            "path": str(baseline_path),
            "sha256": before["baseline_rig"],
            "trusted_sha256": None,
        },
        "candidate": {
            "path": str(candidate_path),
            "sha256": before["candidate_rig"],
        },
        "comparison": None,
        "source_integrity": None,
    }
    try:
        baseline = _read_rig(baseline_path)
        candidate = _read_rig(candidate_path)
        if baseline.get("character_id") != candidate.get("character_id"):
            raise ValueError("character_identity_mismatch")
        if require_trusted_baseline:
            trusted_sha256 = _trusted_baseline_sha256(
                baseline["character_id"], animation_id
            )
            report["baseline"]["trusted_sha256"] = trusted_sha256
            if before["baseline_rig"] != trusted_sha256:
                raise ValueError("baseline_not_trusted")
        baseline_frames = _frames(baseline, animation_id)
        candidate_frames = _frames(candidate, animation_id)
        socket_ids = _baseline_socket_ids(baseline_frames)
        full_comparison = _best_phase_comparison(
            baseline_frames,
            candidate_frames,
            socket_ids,
            list(range(len(candidate_frames))),
        )
        tail_comparison = None
        if len(candidate_frames) > len(baseline_frames):
            tail_comparison = _best_phase_comparison(
                baseline_frames,
                candidate_frames,
                socket_ids,
                list(range(len(baseline_frames), len(candidate_frames))),
            )
        comparison = {
            "baseline_frame_count": len(baseline_frames),
            "candidate_frame_count": len(candidate_frames),
            "baseline_socket_count": len(socket_ids),
            "full_sequence": full_comparison,
            "new_tail": tail_comparison,
        }
        if full_comparison["affine_reuse"]:
            reasons.add(
                "stale_geometry_affine_cycle_reuse"
                if len(candidate_frames) > len(baseline_frames)
                else "stale_geometry_affine_reuse"
            )
        elif tail_comparison is not None and tail_comparison["affine_reuse"]:
            reasons.add("stale_geometry_affine_tail_reuse")
        report["comparison"] = comparison
    except ValueError as error:
        reasons.add(str(error))

    after = {
        "baseline_rig": _sha256(baseline_path) if baseline_path.is_file() else None,
        "candidate_rig": _sha256(candidate_path) if candidate_path.is_file() else None,
    }
    changed_keys = sorted(key for key in before if before[key] != after[key])
    if changed_keys:
        reasons.add("source_changed")
    report["source_integrity"] = {
        "before": before,
        "after": after,
        "changed_keys": changed_keys,
    }

    report["reason_codes"] = sorted(reasons)
    report["verdict"] = "hard_fail" if reasons else "stale_geometry_pass"
    return report


def _arguments(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline-rig", required=True, type=Path)
    parser.add_argument("--candidate-rig", required=True, type=Path)
    parser.add_argument("--animation", required=True)
    parser.add_argument("--out", type=Path)
    return parser.parse_args(argv)


def _output_collides(output: Path, sources: tuple[Path, ...]) -> bool:
    try:
        output_resolved = output.resolve()
    except OSError:
        output_resolved = output.absolute()
    for source in sources:
        try:
            source_resolved = source.resolve()
        except OSError:
            source_resolved = source.absolute()
        if output_resolved == source_resolved:
            return True
        if output.exists() and source.exists():
            try:
                if output.samefile(source):
                    return True
            except OSError:
                pass
    return False


def main(argv: list[str] | None = None) -> int:
    args = _arguments(argv)
    output_collision = args.out is not None and _output_collides(
        args.out, (args.baseline_rig, args.candidate_rig)
    )
    if output_collision:
        report = {
            "verdict": "hard_fail",
            "reason_codes": ["output_source_collision"],
            "animation_id": args.animation,
            "baseline": {"path": str(args.baseline_rig)},
            "candidate": {"path": str(args.candidate_rig)},
            "comparison": None,
        }
    else:
        report = check_stale_geometry(
            args.baseline_rig,
            args.candidate_rig,
            args.animation,
            require_trusted_baseline=True,
        )
    rendered = json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    if args.out is not None and not output_collision:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(rendered, encoding="utf-8")
    print(rendered, end="")
    return 2 if report["verdict"] == "hard_fail" else 0


if __name__ == "__main__":
    raise SystemExit(main())
