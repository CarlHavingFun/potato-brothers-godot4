from __future__ import annotations

import hashlib
import hmac
import json
import os
import re
import secrets
import shutil
import time
from pathlib import Path
from typing import Any, Mapping

from PIL import Image


VIDEO_EXTENSIONS = {".mp4", ".mov", ".mkv", ".webm", ".avi"}
SUBJECT_ID = re.compile(r"^[a-z0-9_]+$")
ANIMATION_ID = re.compile(r"^[a-z0-9_]+$")
PROJECT_FEATURE = re.compile(r"(?:\"|')?(4)(?:\.\d+)?(?:\"|')?")
PRESETS: dict[str, dict[str, Any]] = {
    "character": {
        "cell": [256, 256],
        "logical_size": 64,
        "anchor": [128, 232],
        "align_x": "alpha-centroid",
        "align_y": "bottom",
        "ground_frames": True,
    },
    "object": {
        "cell": [256, 256],
        "logical_size": 128,
        "anchor": [128, 128],
        "align_x": "alpha-centroid",
        "align_y": "alpha-centroid",
        "ground_frames": False,
    },
    "effect": {
        "cell": [256, 256],
        "logical_size": 128,
        "anchor": [128, 128],
        "align_x": "alpha-centroid",
        "align_y": "alpha-centroid",
        "ground_frames": False,
    },
}


class StudioError(ValueError):
    pass


def _atomic_json(path: Path, value: Mapping[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.{secrets.token_hex(6)}.tmp")
    temporary.write_text(
        json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    os.replace(temporary, path)


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _slug(value: str, fallback: str = "subject") -> str:
    slug = re.sub(r"[^a-z0-9]+", "_", value.strip().lower()).strip("_")
    return slug or fallback


def _palette_from_image(path: Path) -> list[list[int]]:
    with Image.open(path) as opened:
        rgba = opened.convert("RGBA")
    try:
        background = Image.new("RGB", rgba.size, (255, 0, 255))
        background.paste(rgba.convert("RGB"), mask=rgba.getchannel("A"))
        quantized = background.quantize(colors=32, method=Image.Quantize.MEDIANCUT)
        counts = sorted(quantized.getcolors() or [], reverse=True)
        raw_palette = quantized.getpalette() or []
        colours: list[list[int]] = []
        for _count, index in counts:
            rgb = raw_palette[index * 3 : index * 3 + 3]
            if len(rgb) == 3 and rgb != [255, 0, 255] and rgb not in colours:
                colours.append([int(channel) for channel in rgb])
        if not colours:
            colours.append([0, 0, 0])
        while len(colours) < 32:
            colours.append(colours[len(colours) % len(colours)].copy())
        return colours[:32]
    finally:
        rgba.close()


class StudioWorkspace:
    def __init__(self, root: Path | str):
        self.root = Path(root).expanduser().resolve()
        self.profiles_root = self.root / "profiles"
        self.jobs_root = self.root / "jobs"
        self.projects_path = self.root / "projects.json"
        self.secret_path = self.root / ".confirmation-secret"
        self.root.mkdir(parents=True, exist_ok=True)

    def create_profile(
        self,
        *,
        display_name: str,
        subject_id: str,
        subject_type: str,
        base_image: Path | str,
        logical_size: int | None = None,
        anchor: list[int] | None = None,
    ) -> dict[str, Any]:
        normalized = _slug(subject_id)
        if not SUBJECT_ID.fullmatch(normalized):
            raise StudioError("subject_id must contain lowercase letters, numbers, or underscores")
        if subject_type not in PRESETS:
            raise StudioError("subject_type must be character, object, or effect")
        source = Path(base_image).expanduser().resolve()
        if not source.is_file():
            raise StudioError("base image does not exist")
        profile_root = self.profiles_root / normalized
        profile_root.mkdir(parents=True, exist_ok=True)
        destination = profile_root / "base-source.png"
        with Image.open(source) as opened:
            opened.convert("RGBA").save(destination, format="PNG")
        palette_path = profile_root / "palette.lock.json"
        palette = {
            "kind": "sprite-gen-palette-lock",
            "source": f"video-sprite-studio:{normalized}",
            "colors": _palette_from_image(destination),
        }
        _atomic_json(palette_path, palette)
        pixelmotion_path = profile_root / "pixelmotion.json"
        profile = dict(PRESETS[subject_type])
        if logical_size is not None:
            if not 8 <= int(logical_size) <= 232:
                raise StudioError("logical_size must be 8..232")
            profile["logical_size"] = int(logical_size)
        if anchor is not None:
            if len(anchor) != 2 or any(not 0 <= int(value) < 256 for value in anchor):
                raise StudioError("anchor must contain two 0..255 values")
            profile["anchor"] = [int(anchor[0]), int(anchor[1])]
        profile.update(
            {
                "schema_version": 1,
                "display_name": display_name.strip() or normalized,
                "subject_id": normalized,
                "subject_type": subject_type,
                "base_image": str(destination),
                "base_sha256": _sha256(destination),
                "palette_lock": str(palette_path),
                "palette_size": 32,
                "pixelmotion_config": str(pixelmotion_path),
                "updated_at_unix": time.time(),
            }
        )
        _atomic_json(pixelmotion_path, {
            "schemaVersion": 1,
            "pipelineId": f"video-sprite-studio-{normalized}",
            "name": profile["display_name"],
            "cutout": {
                "whiteThreshold": 200,
                "borderTolerance": 36,
                "componentAlphaThreshold": 8,
                "connectivity": 8,
            },
            "sprite": {
                "frameSize": [256, 256],
                "rootAnchor": profile["anchor"],
                "subjectBox": [208, 208],
            },
            "studioProfile": {
                "subjectId": normalized,
                "subjectType": subject_type,
                "logicalSize": profile["logical_size"],
                "alignX": profile["align_x"],
                "alignY": profile["align_y"],
                "groundFrames": profile["ground_frames"],
                "anchor": profile["anchor"],
            },
        })
        _atomic_json(profile_root / "profile.json", profile)
        return profile

    def load_profile(self, subject_id: str) -> dict[str, Any]:
        path = self.profiles_root / _slug(subject_id) / "profile.json"
        try:
            value = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            raise StudioError(f"profile not found: {subject_id}") from exc
        if not isinstance(value, dict):
            raise StudioError(f"profile is invalid: {subject_id}")
        return value

    def list_profiles(self) -> list[dict[str, Any]]:
        profiles: list[dict[str, Any]] = []
        if not self.profiles_root.is_dir():
            return profiles
        for path in sorted(self.profiles_root.glob("*/profile.json")):
            try:
                value = json.loads(path.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError):
                continue
            if isinstance(value, dict):
                profiles.append(value)
        return profiles

    def create_video_job(
        self,
        profile_id: str,
        animation: str,
        video_path: Path | str,
    ) -> dict[str, Any]:
        profile = self.load_profile(profile_id)
        animation_id = _slug(animation, "animation")
        if not ANIMATION_ID.fullmatch(animation_id):
            raise StudioError("animation must contain lowercase letters, numbers, or underscores")
        source = Path(video_path).expanduser().resolve()
        if source.suffix.lower() not in VIDEO_EXTENSIONS:
            raise StudioError("unsupported video extension")
        if not source.is_file():
            raise StudioError("video does not exist")
        job_id = f"{int(time.time() * 1000)}-{secrets.token_hex(4)}"
        job_root = self.jobs_root / job_id
        job_root.mkdir(parents=True, exist_ok=False)
        destination = job_root / f"source{source.suffix.lower()}"
        shutil.copy2(source, destination)
        job = {
            "schema_version": 1,
            "job_id": job_id,
            "state": "uploaded",
            "sampling": "all_frames",
            "profile_id": profile["subject_id"],
            "animation": animation_id,
            "video_path": str(destination),
            "video_sha256": _sha256(destination),
            "run_dir": str(job_root / "run"),
            "created_at_unix": time.time(),
        }
        _atomic_json(job_root / "job.json", job)
        return job

    def load_job(self, job_id: str) -> dict[str, Any]:
        if not re.fullmatch(r"[a-zA-Z0-9_-]+", str(job_id)):
            raise StudioError("invalid job id")
        path = self.jobs_root / str(job_id) / "job.json"
        try:
            value = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            raise StudioError(f"job not found: {job_id}") from exc
        if not isinstance(value, dict):
            raise StudioError(f"job is invalid: {job_id}")
        return value

    def save_job(self, job: Mapping[str, Any]) -> dict[str, Any]:
        job_id = str(job.get("job_id", ""))
        existing = self.load_job(job_id)
        updated = dict(existing)
        updated.update(dict(job))
        updated["updated_at_unix"] = time.time()
        _atomic_json(self.jobs_root / job_id / "job.json", updated)
        return updated

    def list_jobs(self) -> list[dict[str, Any]]:
        jobs: list[dict[str, Any]] = []
        if not self.jobs_root.is_dir():
            return jobs
        for path in self.jobs_root.glob("*/job.json"):
            try:
                value = json.loads(path.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError):
                continue
            if isinstance(value, dict):
                jobs.append(value)
        return sorted(jobs, key=lambda value: float(value.get("created_at_unix", 0)), reverse=True)

    def recent_projects(self) -> list[dict[str, Any]]:
        try:
            value = json.loads(self.projects_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            return []
        projects = value.get("projects", []) if isinstance(value, dict) else []
        return [dict(item) for item in projects if isinstance(item, dict)]

    def validate_project(self, project_root: Path | str) -> dict[str, Any]:
        root = Path(project_root).expanduser().resolve()
        marker = root / "project.godot"
        if not marker.is_file():
            raise StudioError("project path must contain project.godot")
        text = marker.read_text(encoding="utf-8", errors="replace")
        if not PROJECT_FEATURE.search(text):
            raise StudioError("project must be Godot 4")
        resources: list[str] = []
        excluded = {".git", ".godot", ".worktrees", "builds"}
        for path in root.rglob("*.tres"):
            try:
                relative = path.relative_to(root)
            except ValueError:
                continue
            if any(part in excluded for part in relative.parts):
                continue
            try:
                head = path.read_text(encoding="utf-8", errors="ignore")[:256]
            except OSError:
                continue
            if re.search(r'\[gd_resource\s+type="SpriteFrames"', head):
                resources.append("res://" + relative.as_posix())
        result = {
            "project_root": str(root),
            "godot_major": 4,
            "sprite_frames": sorted(resources),
        }
        existing = next((value for value in self.recent_projects()
                         if value.get("project_root") == str(root)), None)
        if isinstance(existing, dict) and isinstance(existing.get("bindings"), dict):
            result["bindings"] = dict(existing["bindings"])
        self._remember_project(result)
        return result

    def preview_export(self, request: Mapping[str, Any]) -> dict[str, Any]:
        normalized = self._normalize_export_request(request)
        token = self._confirmation_token(normalized)
        return {
            "project_root": normalized["project_root"],
            "target_resource": normalized["target_resource"],
            "animation": normalized["animation"],
            "frame_count": len(normalized["selection"]),
            "fps": normalized["fps"],
            "loop": normalized["loop"],
            "confirmation_token": token,
        }

    def verify_confirmation(self, request: Mapping[str, Any], token: str) -> None:
        expected = self._confirmation_token(self._normalize_export_request(request))
        if not hmac.compare_digest(expected, str(token)):
            raise StudioError("confirmation is stale")

    def _normalize_export_request(self, request: Mapping[str, Any]) -> dict[str, Any]:
        project = self.validate_project(str(request.get("project_root", "")))
        project_root = Path(project["project_root"])
        try:
            self.root.relative_to(project_root)
            raise StudioError("external workspace must not be inside the Godot project")
        except ValueError:
            pass
        selection = request.get("selection")
        if not isinstance(selection, list) or not selection:
            raise StudioError("selection must contain at least one frame")
        if any(not isinstance(value, int) or value < 0 for value in selection):
            raise StudioError("selection must contain non-negative integer indices")
        animation = _slug(str(request.get("animation", "")), "")
        if not animation or not ANIMATION_ID.fullmatch(animation):
            raise StudioError("animation is required")
        target = str(request.get("target_resource", ""))
        if not target.startswith("res://") or ".." in target or not target.endswith(".tres"):
            raise StudioError("target_resource must be a .tres path inside res://")
        fps = float(request.get("fps", 0.0))
        if not 0.1 <= fps <= 120.0:
            raise StudioError("fps must be 0.1..120")
        return {
            "project_root": str(project_root),
            "subject_id": _slug(str(request.get("subject_id", ""))),
            "animation": animation,
            "target_resource": target,
            "selection": selection,
            "fps": fps,
            "loop": bool(request.get("loop", False)),
        }

    def _confirmation_token(self, normalized: Mapping[str, Any]) -> str:
        payload = json.dumps(normalized, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
        return hmac.new(self._secret(), payload.encode("utf-8"), hashlib.sha256).hexdigest()

    def _secret(self) -> bytes:
        try:
            value = self.secret_path.read_bytes()
        except OSError:
            self.secret_path.parent.mkdir(parents=True, exist_ok=True)
            value = secrets.token_bytes(32)
            self.secret_path.write_bytes(value)
        return value

    def _remember_project(self, project: Mapping[str, Any]) -> None:
        try:
            data = json.loads(self.projects_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            data = {"projects": []}
        existing = next((value for value in data.get("projects", []) if isinstance(value, dict)
                         and value.get("project_root") == project["project_root"]), {})
        projects = [
            value
            for value in data.get("projects", [])
            if isinstance(value, dict) and value.get("project_root") != project["project_root"]
        ]
        merged = dict(existing)
        merged.update(dict(project))
        projects.insert(0, merged)
        _atomic_json(self.projects_path, {"projects": projects[:12]})

    def remember_binding(self, project_root: Path | str, subject_id: str, target_resource: str) -> None:
        project = self.validate_project(project_root)
        projects = self.recent_projects()
        for value in projects:
            if value.get("project_root") == project["project_root"]:
                bindings = dict(value.get("bindings", {})) if isinstance(value.get("bindings"), dict) else {}
                bindings[_slug(subject_id)] = target_resource
                value["bindings"] = bindings
                break
        _atomic_json(self.projects_path, {"projects": projects[:12]})
