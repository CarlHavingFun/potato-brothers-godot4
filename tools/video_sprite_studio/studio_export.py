from __future__ import annotations

import hashlib
import io
import json
import math
import os
import re
import secrets
import shutil
import subprocess
import time
from pathlib import Path
from typing import Any

from PIL import Image

from sprite_gen.compose.export_pngs import bake_curated_frame_png
from sprite_gen.curate.curation import load_curation, source_frame_index
from sprite_gen.spec.runio import load_request

from .studio_core import StudioError, _atomic_json


def _sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def _normalize_cell(data: bytes) -> Image.Image:
    with Image.open(io.BytesIO(data)) as opened:
        rgba = opened.convert("RGBA")
    if rgba.size != (256, 256):
        resized = rgba.resize((256, 256), Image.Resampling.NEAREST)
        rgba.close()
        rgba = resized
    alpha = rgba.getchannel("A").point(lambda value: 255 if value >= 128 else 0)
    rgba.putalpha(alpha)
    return rgba


def build_selected_export(
    *,
    run_dir: Path | str,
    state: str,
    output_dir: Path | str,
    subject_id: str,
    animation: str,
    fps: float,
    loop: bool,
    video_sha256: str,
    anchor: tuple[int, int] = (128, 232),
) -> dict[str, Any]:
    run = Path(run_dir).expanduser().resolve()
    output = Path(output_dir).expanduser().resolve()
    if not 0.1 <= float(fps) <= 120.0:
        raise StudioError("fps must be 0.1..120")
    request = load_request(run)
    if state not in request.get("states", {}):
        raise StudioError(f"unknown curation state: {state}")
    curation = load_curation(run)
    entry = (curation.get("states") or {}).get(state) or {}
    selected = entry.get("selected")
    if not isinstance(selected, list) or not selected:
        raise StudioError("selection must contain at least one frame")
    if any(not isinstance(value, int) or value < 0 for value in selected):
        raise StudioError("selection contains an invalid frame instance")
    default_count = int(request["states"][state]["frames"])
    source_indices = [source_frame_index(curation, state, value, default_count) for value in selected]
    source_rows: list[dict[str, Any]] = []
    sidecar_path = run / "studio-source.json"
    if sidecar_path.is_file():
        try:
            sidecar = json.loads(sidecar_path.read_text(encoding="utf-8"))
            candidates = sidecar.get("frames", []) if isinstance(sidecar, dict) else []
            if isinstance(candidates, list):
                source_rows = [dict(value) for value in candidates if isinstance(value, dict)]
        except (OSError, json.JSONDecodeError):
            source_rows = []
    ordered_source_frames = [
        int(source_rows[index].get("source_frame", index + 1)) if index < len(source_rows) else index + 1
        for index in source_indices
    ]
    ordered_timestamps = [
        float(source_rows[index].get("timestamp_seconds", 0.0)) if index < len(source_rows) else 0.0
        for index in source_indices
    ]

    if output.exists() and any(output.iterdir()):
        raise StudioError(f"selected export directory is not empty: {output}")
    output.mkdir(parents=True, exist_ok=True)
    frames: list[Image.Image] = []
    frame_hashes: list[str] = []
    labels: list[str] = []
    try:
        for instance in selected:
            data, label = bake_curated_frame_png(run, state, instance)
            normalized = _normalize_cell(data)
            buffer = io.BytesIO()
            normalized.save(buffer, format="PNG", optimize=False)
            frame_hashes.append(_sha256_bytes(buffer.getvalue()))
            labels.append(label)
            frames.append(normalized)
        columns = min(16, len(frames))
        rows = int(math.ceil(len(frames) / columns))
        atlas = Image.new("RGBA", (columns * 256, rows * 256), (0, 0, 0, 0))
        rects: list[dict[str, int]] = []
        try:
            for index, frame in enumerate(frames):
                x = (index % columns) * 256
                y = (index // columns) * 256
                atlas.alpha_composite(frame, (x, y))
                rects.append({"x": x, "y": y, "w": 256, "h": 256})
            atlas.save(output / "atlas.png", format="PNG", optimize=False)
        finally:
            atlas.close()
    finally:
        for frame in frames:
            frame.close()

    duration = 1000.0 / float(fps)
    manifest = {
        "schema_version": 1,
        "kind": "video-sprite-studio-selected",
        "game_input": "atlas.png",
        "degraded_static_fallback": False,
        "subject_id": subject_id,
        "cell": {"width": 256, "height": 256, "safe_margin": 24},
        "root": {"x": int(anchor[0]), "y": int(anchor[1])},
        "animation": {"rows": {animation: {
            "frames": len(selected),
            "fps": float(fps),
            "durations_ms": [duration for _ in selected],
            "loop": bool(loop),
        }}},
        "frame_layout": {
            "sheetWidth": columns * 256,
            "sheetHeight": rows * 256,
            "cellWidth": 256,
            "cellHeight": 256,
            "rows": {animation: rects},
        },
    }
    provenance = {
        "schema_version": 1,
        "run_dir": str(run),
        "video_sha256": video_sha256,
        "subject_id": subject_id,
        "animation": animation,
        "ordered_instances": selected,
        "ordered_source_indices": source_indices,
        "ordered_source_frames": ordered_source_frames,
        "ordered_timestamps_seconds": ordered_timestamps,
        "frame_sha256": frame_hashes,
        "labels": labels,
        "fps": float(fps),
        "loop": bool(loop),
        "exported_at_unix": time.time(),
    }
    _atomic_json(output / "manifest.json", manifest)
    _atomic_json(output / "provenance.json", provenance)
    return {
        "output_dir": str(output),
        "atlas_path": str(output / "atlas.png"),
        "manifest_path": str(output / "manifest.json"),
        "provenance_path": str(output / "provenance.json"),
        "frame_count": len(selected),
        "source_indices": source_indices,
    }


def _inside(root: Path, candidate: Path) -> bool:
    try:
        candidate.resolve().relative_to(root.resolve())
        return True
    except ValueError:
        return False


def _has_link_component(root: Path, candidate: Path) -> bool:
    current = root.resolve()
    try:
        parts = candidate.resolve(strict=False).relative_to(current).parts
    except ValueError:
        return True
    for part in parts:
        current = current / part
        if current.is_symlink() or (hasattr(os.path, "isjunction") and os.path.isjunction(current)):
            return True
    return False


def _default_runner(command: list[str], _request: dict[str, Any]) -> tuple[int, str, str]:
    completed = subprocess.run(command, capture_output=True, text=True, timeout=120)
    return completed.returncode, completed.stdout, completed.stderr


def _remove_empty_parents(path: Path, stop: Path) -> None:
    current = path
    while current != stop and _inside(stop, current):
        try:
            current.rmdir()
        except OSError:
            return
        current = current.parent


def install_selected_export(
    *,
    project_root: Path | str,
    selected_dir: Path | str,
    subject_id: str,
    animation: str,
    target_resource: str,
    godot_binary: Path | str,
    bridge_source: Path | str,
    runner=_default_runner,
) -> dict[str, Any]:
    project = Path(project_root).expanduser().resolve()
    if not (project / "project.godot").is_file():
        raise StudioError("project path must contain project.godot")
    if not target_resource.startswith("res://") or ".." in target_resource or not target_resource.endswith(".tres"):
        raise StudioError("target_resource must be a .tres path inside res://")
    target = project / target_resource.removeprefix("res://")
    if not _inside(project, target) or _has_link_component(project, target):
        raise StudioError("target resource escapes the Godot project")
    selected = Path(selected_dir).expanduser().resolve()
    required = [selected / name for name in ("atlas.png", "manifest.json", "provenance.json")]
    if any(not path.is_file() for path in required):
        raise StudioError("selected export must contain atlas.png, manifest.json, and provenance.json")
    source = Path(bridge_source).expanduser().resolve()
    bridge_files = [source / "godot_import_cli.gd", source / "godot_sprite_frames_importer.gd"]
    if any(not path.is_file() for path in bridge_files):
        raise StudioError("Godot import bridge is incomplete")

    fingerprint = hashlib.sha256(
        (selected / "manifest.json").read_bytes() + (selected / "provenance.json").read_bytes()
    ).hexdigest()[:12]
    revision_root = project / "assets" / "generated" / "video_sprites" / subject_id / animation
    revision = revision_root / fingerprint
    suffix = 2
    while revision.exists():
        revision = revision_root / f"{fingerprint}-{suffix}"
        suffix += 1
    if _has_link_component(project, revision):
        raise StudioError("revision output escapes through a filesystem link")
    bridge_name = f".video_sprite_studio_bridge_{secrets.token_hex(6)}"
    bridge_dir = project / bridge_name
    temp_target = target.with_name(f".{target.stem}.{secrets.token_hex(6)}.next.tres")
    target_existed = target.is_file()
    request_path = bridge_dir / "request.json"
    revision_created = False
    try:
        revision.mkdir(parents=True, exist_ok=False)
        revision_created = True
        for path in required:
            shutil.copy2(path, revision / path.name)
        bridge_dir.mkdir(parents=False, exist_ok=False)
        for path in bridge_files:
            shutil.copy2(path, bridge_dir / path.name)
        target.parent.mkdir(parents=True, exist_ok=True)
        revision_resource = "res://" + revision.relative_to(project).as_posix()
        request = {
            "schema_version": 1,
            "animation": animation,
            "manifest_resource": f"{revision_resource}/manifest.json",
            "atlas_resource": f"{revision_resource}/atlas.png",
            "target_resource": target_resource,
            "temp_resource": "res://" + temp_target.relative_to(project).as_posix(),
            "temp_absolute": str(temp_target),
        }
        _atomic_json(request_path, request)
        import_command = [
            str(godot_binary), "--headless", "--editor", "--path", str(project), "--quit",
        ]
        import_code, import_stdout, import_stderr = runner(import_command, request)
        if import_code != 0:
            detail = (import_stderr or import_stdout or f"exit {import_code}").strip()[-600:]
            raise StudioError(f"Godot import failed during asset scan: {detail}")
        bridge_resource = f"res://{bridge_name}/godot_import_cli.gd"
        command = [
            str(godot_binary), "--headless", "--editor", "--path", str(project),
            "--script", bridge_resource, "--", "--request", str(request_path),
        ]
        code, stdout, stderr = runner(command, request)
        if code != 0 or not temp_target.is_file():
            detail = (stderr or stdout or f"exit {code}").strip()[-600:]
            raise StudioError(f"Godot import failed: {detail}")
        head = temp_target.read_text(encoding="utf-8", errors="ignore")[:256]
        if not re.search(r'\[gd_resource\s+type="SpriteFrames"', head):
            raise StudioError("Godot import failed: temporary resource is not SpriteFrames")
        os.replace(temp_target, target)
        return {
            "project_root": str(project),
            "target_resource": target_resource,
            "revision_resource": revision_resource,
            "atlas_resource": f"{revision_resource}/atlas.png",
            "animation": animation,
            "replaced": target_existed,
        }
    except Exception:
        if revision_created and revision.exists():
            shutil.rmtree(revision, ignore_errors=True)
            _remove_empty_parents(revision.parent, project / "assets")
        raise
    finally:
        if temp_target.exists():
            temp_target.unlink()
        if bridge_dir.exists():
            shutil.rmtree(bridge_dir, ignore_errors=True)
