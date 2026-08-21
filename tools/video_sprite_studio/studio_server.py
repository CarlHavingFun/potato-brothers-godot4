from __future__ import annotations

import argparse
import email
import hashlib
import json
import os
import secrets
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import webbrowser
from email import policy
from email.parser import BytesParser
from http.server import ThreadingHTTPServer
from pathlib import Path
from typing import Any, Mapping
from urllib.parse import parse_qs, urlparse

import sprite_gen
from sprite_gen.curate.curation import load_curation, source_frame_index, stamp_curation
from sprite_gen.frames.extract import engine_revision
from sprite_gen.serve.serve_curation import CURATOR_DIR, CurationHandler

from .studio_core import StudioError, StudioWorkspace, _atomic_json
from .studio_export import build_selected_export, install_selected_export


def _link_or_copy(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    try:
        os.link(source, destination)
    except OSError:
        shutil.copy2(source, destination)


def prepare_curation_run(
    *,
    manifest_path: Path | str,
    run_dir: Path | str,
    profile: Mapping[str, Any],
    animation: str,
) -> dict[str, Any]:
    manifest_file = Path(manifest_path).expanduser().resolve()
    try:
        manifest = json.loads(manifest_file.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise StudioError(f"processed manifest is invalid: {manifest_file}") from exc
    source_frames = manifest.get("source_frames")
    if not isinstance(source_frames, list) or not source_frames:
        raise StudioError("processed manifest must contain source_frames")
    run = Path(run_dir).expanduser().resolve()
    if run.exists() and any(run.iterdir()):
        raise StudioError(f"curation run directory is not empty: {run}")
    state_root = run / "frames" / animation
    state_root.mkdir(parents=True, exist_ok=True)
    files: list[str] = []
    labels: list[str] = []
    source_map: list[dict[str, Any]] = []
    for index, value in enumerate(source_frames):
        if not isinstance(value, dict):
            raise StudioError(f"source frame {index} must be an object")
        source = manifest_file.parent / str(value.get("png", ""))
        if not source.is_file():
            raise StudioError(f"processed source frame is missing: {source}")
        destination = state_root / f"frame-{index}.png"
        _link_or_copy(source, destination)
        relative = destination.relative_to(run).as_posix()
        files.append(relative)
        source_frame = int(value.get("source_frame", index + 1))
        labels.append(f"F{source_frame:03d}")
        source_map.append({
            "index": index,
            "source_frame": source_frame,
            "timestamp_seconds": float(value.get("timestamp_seconds", 0.0)),
            "duration_ms": float(value.get("duration_ms", 0.0)),
            "sha256": str(value.get("sha256", "")),
            "png": relative,
        })
    source = manifest.get("source", {}) if isinstance(manifest.get("source"), dict) else {}
    fps_value = source.get("fps", {}) if isinstance(source.get("fps"), dict) else {}
    fps = float(fps_value.get("value", 24.0))
    request = {
        "version": 1,
        "kind": "sprite-gen-request",
        "engine": "component-row",
        "character": {
            "id": str(profile.get("subject_id", "subject")),
            "description": "all source-video frames imported by Video Sprite Studio",
        },
        "cell": {"shape": "square", "width": 256, "height": 256, "size": 256, "safe_margin": 24},
        "chroma_key": {"name": "magenta", "hex": "#FF00FF", "rgb": [255, 0, 255]},
        "states": {animation: {
            "frames": len(source_frames),
            "fps": max(1, min(30, int(round(fps)))),
            "loop": True,
            "action": "all source-video frames in original chronological order",
        }},
    }
    _atomic_json(run / "sprite-request.json", request)
    _atomic_json(run / "frames" / "frames-manifest.json", {
        "ok": True,
        "engine": "component-row",
        "run_dir": str(run),
        "cell": request["cell"],
        "rows": [{
            "state": animation,
            "frames": len(files),
            "method": "video-sprite-studio-all-frames",
            "files": files,
            "labels": labels,
            "engine_revision": engine_revision(),
            "ok": True,
        }],
        "errors": [],
        "warnings": [],
    })
    curation = stamp_curation(run, {
        "version": 1,
        "kind": "sprite-gen-curation",
        "states": {animation: {
            "selected": [],
            "order": list(range(len(files))),
            "transforms": {},
        }},
    })
    _atomic_json(run / "curation.json", curation)
    base_image = Path(str(profile.get("base_image", "")))
    if base_image.is_file():
        shutil.copy2(base_image, run / "base-source.png")
    _atomic_json(run / "studio-source.json", {
        "schema_version": 1,
        "source_manifest": str(manifest_file),
        "video_sha256": str(source.get("sha256", "")),
        "frame_count": len(files),
        "fps": fps,
        "frames": source_map,
    })
    return {"run_dir": str(run), "frame_count": len(files), "state": animation}


class StudioApplication:
    def __init__(
        self,
        *,
        workspace: StudioWorkspace,
        repo_root: Path | str,
        legacy_run: Path | str | None = None,
    ) -> None:
        self.workspace = workspace
        self.repo_root = Path(repo_root).expanduser().resolve()
        self.session_token = secrets.token_urlsafe(32)
        self.active_run: Path | None = None
        self.active_job_id = ""
        self._processes: dict[str, subprocess.Popen[str]] = {}
        self._lock = threading.RLock()
        if legacy_run is not None:
            candidate = Path(legacy_run).expanduser().resolve()
            if (candidate / "sprite-request.json").is_file():
                self.active_run = candidate
                self._register_legacy_run(candidate)

    def _register_legacy_run(self, run: Path) -> None:
        try:
            request = json.loads((run / "sprite-request.json").read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            return
        states = request.get("states", {}) if isinstance(request, dict) else {}
        if not isinstance(states, dict) or not states:
            return
        animation = str(next(iter(states)))
        subject_id = "niko" if "niko" in run.name.lower() else str((request.get("character") or {}).get("id", "subject"))
        try:
            self.workspace.load_profile(subject_id)
        except StudioError:
            bases = [run / "base-source.png", run / "base.png"]
            base = next((path for path in bases if path.is_file()), None)
            if base is None:
                return
            profile = self.workspace.create_profile(
                display_name="Niko" if subject_id == "niko" else subject_id,
                subject_id=subject_id, subject_type="character", base_image=base,
            )
            subject_id = str(profile["subject_id"])
        fingerprint = hashlib.sha256(str(run).encode("utf-8")).hexdigest()[:12]
        job_id = f"legacy-{fingerprint}"
        job_root = self.workspace.jobs_root / job_id
        job_root.mkdir(parents=True, exist_ok=True)
        source_sidecar = run / "studio-source.json"
        video_hash = "0" * 64
        if source_sidecar.is_file():
            try:
                video_hash = str(json.loads(source_sidecar.read_text(encoding="utf-8")).get("video_sha256", video_hash))
            except (OSError, json.JSONDecodeError):
                pass
        _atomic_json(job_root / "job.json", {
            "schema_version": 1, "job_id": job_id, "state": "ready", "sampling": "all_frames",
            "profile_id": subject_id, "animation": animation, "video_sha256": video_hash,
            "run_dir": str(run), "legacy": True, "created_at_unix": run.stat().st_mtime,
            "frame_count": int(states[animation].get("frames", 0)),
        })
        self.active_job_id = job_id

    def dependencies(self) -> dict[str, str]:
        sprite_root = Path(sprite_gen.__file__).resolve().parents[1]
        search_roots = [self.repo_root.parent, *self.repo_root.parents]
        configured_pixelmotion = os.environ.get("VIDEO_SPRITE_PIXELMOTION", "")
        pixel_candidates = ([Path(configured_pixelmotion)] if configured_pixelmotion else []) + [
            root / "pixelmotion-2d-niko" for root in search_roots
        ]
        pixelmotion = next(
            (path.resolve() for path in pixel_candidates if (path / "pixelmotion2d" / "video_sprite_library.py").is_file()),
            None,
        )
        ffprobe = shutil.which("ffprobe") or ""
        configured_godot = os.environ.get("VIDEO_SPRITE_GODOT", "")
        candidates = ([Path(configured_godot)] if configured_godot else []) + [
            root / ".tools" / version / binary
            for root in search_roots
            for version, binary in (
                ("godot-4.7.1", "Godot_v4.7.1-stable_win64_console.exe"),
                ("godot-4.6.1", "Godot_v4.6.1-stable_win64_console.exe"),
            )
        ]
        godot = next((str(path) for path in candidates if path.is_file()), shutil.which("godot") or "")
        return {
            "python": sys.executable,
            "sprite_gen": str(sprite_root),
            "pixelmotion": str(pixelmotion) if pixelmotion is not None else "",
            "ffprobe": ffprobe,
            "godot": godot,
        }

    def state(self) -> dict[str, Any]:
        self.poll_jobs()
        jobs = self.workspace.list_jobs()
        for job in jobs:
            request_path = Path(str(job.get("run_dir", ""))) / "sprite-request.json"
            if request_path.is_file():
                try:
                    request = json.loads(request_path.read_text(encoding="utf-8"))
                    state = (request.get("states") or {}).get(str(job.get("animation", ""))) or {}
                    job["curation_fps"] = float(job.get("export_fps", state.get("fps", 10.0)))
                    job["curation_loop"] = bool(job.get("export_loop", state.get("loop", True)))
                except (OSError, json.JSONDecodeError, TypeError, ValueError):
                    pass
        return {
            "profiles": self.workspace.list_profiles(),
            "jobs": jobs,
            "projects": self.workspace.recent_projects(),
            "active_run": str(self.active_run or ""),
            "active_job_id": self.active_job_id,
            "dependencies": self.dependencies(),
            "workspace": str(self.workspace.root),
        }

    def start_job(self, job_id: str) -> dict[str, Any]:
        with self._lock:
            job = self.workspace.load_job(job_id)
            profile = self.workspace.load_profile(str(job["profile_id"]))
            dependencies = self.dependencies()
            missing = [name for name in ("sprite_gen", "pixelmotion", "ffprobe") if not dependencies[name]]
            if missing:
                raise StudioError("missing dependencies: " + ", ".join(missing))
            job_root = self.workspace.jobs_root / job_id
            output = job_root / "processed"
            receipt = job_root / "receipt.json"
            cancel = job_root / "cancel.json"
            token = secrets.token_urlsafe(24)
            command = [
                dependencies["python"], str(self.repo_root / "tools" / "video_sprites" / "spritegen_video_worker.py"),
                "import-video", "--source-video", str(job["video_path"]),
                "--output-directory", str(output), "--job-receipt", str(receipt),
                "--config", str(profile["pixelmotion_config"]), "--clip-id", str(job["animation"]),
                "--job-id", job_id, "--job-token", token, "--cancel-request", str(cancel),
                "--allowed-staging-root", str(self.workspace.root), "--project-root", str(self.repo_root),
                "--pixelmotion-root", dependencies["pixelmotion"], "--sprite-gen-root", dependencies["sprite_gen"],
                "--base-image", str(profile["base_image"]), "--palette-lock", str(profile["palette_lock"]),
                "--ffprobe", dependencies["ffprobe"], "--force-generated", "--replace-selection",
            ]
            _atomic_json(receipt, {"job_id": job_id, "job_token": token, "state": "queued"})
            stdout = (job_root / "worker.stdout.log").open("w", encoding="utf-8")
            stderr = (job_root / "worker.stderr.log").open("w", encoding="utf-8")
            try:
                process = subprocess.Popen(command, cwd=self.repo_root, stdout=stdout, stderr=stderr, text=True)
            finally:
                stdout.close()
                stderr.close()
            self._processes[job_id] = process
            job.update({"state": "running", "pid": process.pid, "receipt_path": str(receipt),
                        "cancel_path": str(cancel), "output_directory": str(output), "job_token": token})
            return self.workspace.save_job(job)

    def poll_jobs(self) -> None:
        with self._lock:
            for job in self.workspace.list_jobs():
                if job.get("state") not in {"running", "queued", "cancelling"}:
                    continue
                job_id = str(job["job_id"])
                receipt_path = Path(str(job.get("receipt_path", "")))
                receipt: dict[str, Any] = {}
                try:
                    parsed = json.loads(receipt_path.read_text(encoding="utf-8"))
                    if isinstance(parsed, dict):
                        receipt = parsed
                except (OSError, json.JSONDecodeError):
                    pass
                receipt_state = str(receipt.get("state", ""))
                if receipt_state == "cancelled":
                    job.update({"state": "cancelled", "progress": receipt})
                    self.workspace.save_job(job)
                    continue
                if receipt_state in {"worker_complete", "complete"}:
                    manifests = sorted(Path(str(job["output_directory"])).rglob("manifest.json"))
                    manifests = [path for path in manifests if "run" not in path.parts]
                    if len(manifests) != 1:
                        job.update({"state": "failed", "error": f"expected one processed manifest, found {len(manifests)}"})
                    else:
                        try:
                            profile = self.workspace.load_profile(str(job["profile_id"]))
                            run = Path(str(job["run_dir"]))
                            if not (run / "sprite-request.json").is_file():
                                prepare_curation_run(manifest_path=manifests[0], run_dir=run,
                                                     profile=profile, animation=str(job["animation"]))
                            job.update({"state": "ready", "manifest_path": str(manifests[0]),
                                        "frame_count": json.loads(manifests[0].read_text(encoding="utf-8"))["source"]["frame_count"],
                                        "progress": receipt})
                        except Exception as exc:
                            job.update({"state": "failed", "error": str(exc)})
                    self.workspace.save_job(job)
                    continue
                process = self._processes.get(job_id)
                if process is not None and process.poll() is not None:
                    error_path = self.workspace.jobs_root / job_id / "worker.stderr.log"
                    detail = error_path.read_text(encoding="utf-8", errors="replace")[-1000:] if error_path.is_file() else ""
                    job.update({"state": "failed", "error": detail or f"worker exited {process.returncode}"})
                    self.workspace.save_job(job)
                elif receipt:
                    job["progress"] = receipt
                    self.workspace.save_job(job)

    def cancel_job(self, job_id: str) -> dict[str, Any]:
        job = self.workspace.load_job(job_id)
        if job.get("state") not in {"running", "queued", "cancelling"}:
            raise StudioError("job is not active")
        _atomic_json(Path(str(job["cancel_path"])), {
            "job_id": job_id, "job_token": str(job["job_token"]), "requested_at_unix": time.time(),
        })
        job["state"] = "cancelling"
        return self.workspace.save_job(job)

    def open_job(self, job_id: str) -> dict[str, Any]:
        job = self.workspace.load_job(job_id)
        run = Path(str(job["run_dir"])).resolve()
        if job.get("state") != "ready" or not (run / "sprite-request.json").is_file():
            raise StudioError("job is not ready for curation")
        self.active_run = run
        self.active_job_id = job_id
        return {"job_id": job_id, "curation_url": "/?lang=cn", "run_dir": str(run)}

    def _export_request(self, payload: Mapping[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
        job_id = str(payload.get("job_id") or self.active_job_id)
        job = self.workspace.load_job(job_id)
        run = Path(str(job["run_dir"]))
        curation = load_curation(run)
        state = str(job["animation"])
        entry = (curation.get("states") or {}).get(state) or {}
        selected = entry.get("selected")
        if not isinstance(selected, list) or not selected:
            raise StudioError("请先在挑帧页至少添加一帧 / select at least one frame")
        profile = self.workspace.load_profile(str(job["profile_id"]))
        target = str(payload.get("target_resource", "")).strip()
        if not target:
            target = ("res://tools/sprites/niko_character_library/authoring/niko_all_actions.tres"
                      if profile["subject_id"] == "niko" else
                      f"res://assets/generated/video_sprites/{profile['subject_id']}/{profile['subject_id']}_animations.tres")
        request = {
            "project_root": str(payload.get("project_root", "")), "subject_id": profile["subject_id"],
            "animation": str(payload.get("animation") or state), "target_resource": target,
            "selection": selected, "fps": float(payload.get("fps", 10.0)),
            "loop": bool(payload.get("loop", True)),
        }
        return request, {"job": job, "profile": profile, "run": run, "state": state}

    def preview_export(self, payload: Mapping[str, Any]) -> dict[str, Any]:
        request, context = self._export_request(payload)
        preview = self.workspace.preview_export(request)
        job = dict(context["job"])
        job["export_fps"] = request["fps"]
        job["export_loop"] = request["loop"]
        self.workspace.save_job(job)
        target_path = Path(request["project_root"]) / request["target_resource"].removeprefix("res://")
        preview.update({"job_id": context["job"]["job_id"], "exists": target_path.is_file(),
                        "message": "同名动画将被替换；其他动画保持不变" if target_path.is_file() else "将创建总 SpriteFrames"})
        return preview

    def export_to_godot(self, payload: Mapping[str, Any]) -> dict[str, Any]:
        request, context = self._export_request(payload)
        self.workspace.verify_confirmation(request, str(payload.get("confirmation_token", "")))
        profile = context["profile"]
        job = context["job"]
        export_root = self.workspace.jobs_root / str(job["job_id"]) / "exports" / secrets.token_hex(8)
        try:
            built = build_selected_export(
                run_dir=context["run"], state=context["state"], output_dir=export_root,
                subject_id=profile["subject_id"], animation=request["animation"], fps=request["fps"],
                loop=request["loop"], video_sha256=str(job["video_sha256"]), anchor=tuple(profile["anchor"]),
            )
            dependencies = self.dependencies()
            if not dependencies["godot"]:
                raise StudioError("Godot executable was not found")
            receipt = install_selected_export(
                project_root=request["project_root"], selected_dir=built["output_dir"],
                subject_id=profile["subject_id"], animation=request["animation"],
                target_resource=request["target_resource"], godot_binary=dependencies["godot"],
                bridge_source=Path(__file__).parent,
            )
            self.workspace.remember_binding(
                request["project_root"], profile["subject_id"], request["target_resource"]
            )
            receipt["frame_count"] = built["frame_count"]
            return receipt
        finally:
            if export_root.exists():
                shutil.rmtree(export_root, ignore_errors=True)

    def dashboard_html(self, lang: str = "cn") -> str:
        language = "en" if lang == "en" else "cn"
        path = Path(__file__).with_name("static") / "studio.html"
        text = path.read_text(encoding="utf-8")
        return text.replace("{{LANG}}", language)

    def change_workspace(self, value: Path | str) -> dict[str, Any]:
        candidate = Path(value).expanduser().resolve()
        try:
            candidate.relative_to(self.repo_root)
            raise StudioError("workspace must remain outside the Godot project")
        except ValueError:
            pass
        self.workspace = StudioWorkspace(candidate)
        self.active_run = None
        self.active_job_id = ""
        return {"workspace": str(candidate)}


class StudioHandler(CurationHandler):
    application: StudioApplication

    def _send_bytes(self, data: bytes, content_type: str, status: int = 200) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def _authorized(self) -> bool:
        return secrets.compare_digest(
            self.headers.get("X-Studio-Token", ""), self.application.session_token
        )

    def _studio_payload(self) -> tuple[dict[str, Any], dict[str, tuple[str, bytes]]]:
        content_type = self.headers.get("Content-Type", "")
        length = int(self.headers.get("Content-Length", 0))
        if length < 0 or length > 1024 * 1024 * 1024:
            raise StudioError("request is too large")
        raw = self.rfile.read(length) if length else b"{}"
        if not content_type.lower().startswith("multipart/form-data"):
            value = json.loads(raw.decode("utf-8"))
            if not isinstance(value, dict):
                raise StudioError("request body must be an object")
            return value, {}
        message = BytesParser(policy=policy.default).parsebytes(
            b"Content-Type: " + content_type.encode("ascii", errors="ignore") + b"\r\nMIME-Version: 1.0\r\n\r\n" + raw
        )
        fields: dict[str, Any] = {}
        files: dict[str, tuple[str, bytes]] = {}
        for part in message.iter_parts():
            name = part.get_param("name", header="content-disposition")
            if not name:
                continue
            data = part.get_payload(decode=True) or b""
            filename = part.get_filename()
            if filename:
                files[str(name)] = (Path(filename).name, data)
            else:
                fields[str(name)] = data.decode(part.get_content_charset() or "utf-8")
        return fields, files

    def _temporary_upload(self, filename: str, data: bytes) -> Path:
        suffix = Path(filename).suffix.lower()
        fd, raw_path = tempfile.mkstemp(prefix="video-sprite-studio-upload-", suffix=suffix)
        os.close(fd)
        path = Path(raw_path)
        path.write_bytes(data)
        return path

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        path = parsed.path
        if path in {"/studio", "/studio/"}:
            lang = (parse_qs(parsed.query).get("lang") or ["cn"])[0]
            html = self.application.dashboard_html(lang)
            token = json.dumps(self.application.session_token)
            html = html.replace(
                "</head>", f"<script>window.VIDEO_SPRITE_STUDIO_TOKEN={token};</script></head>"
            )
            self._send_bytes(html.encode("utf-8"), "text/html; charset=utf-8")
            return
        if path == "/api/studio/state":
            self._send_json(self.application.state())
            return
        if path == "/api/studio/browse":
            query = parse_qs(parsed.query)
            requested = (query.get("path") or [str(Path.home())])[0]
            root = Path(requested).expanduser()
            if not root.is_dir():
                self._send_json({"error": "directory does not exist"}, 400)
                return
            directories = []
            try:
                directories = [str(item.resolve()) for item in sorted(root.iterdir()) if item.is_dir() and not item.name.startswith(".")]
            except OSError as exc:
                self._send_json({"error": str(exc)}, 400)
                return
            self._send_json({"path": str(root.resolve()), "parent": str(root.resolve().parent), "directories": directories[:200]})
            return
        if path in {"/", "/index.html"} and self.application.active_run is None:
            self.send_response(302)
            self.send_header("Location", "/studio/?lang=cn")
            self.end_headers()
            return
        if path in {"/", "/index.html"} and self.application.active_run is not None:
            html = (CURATOR_DIR / "index.html").read_text(encoding="utf-8")
            toolbar = """<style>#compose,.row-dl-wrap [data-fmt=godot]{display:none!important}#vss-toolbar{position:fixed;z-index:99999;right:18px;bottom:18px;display:flex;gap:8px}#vss-toolbar a{background:#1769e0;color:#fff;padding:10px 14px;border-radius:8px;text-decoration:none;box-shadow:0 2px 12px #0004}</style><div id=\"vss-toolbar\"><a href=\"/studio/?lang=cn#export\">导出到 Godot</a><a href=\"/studio/?lang=cn\">工作台</a></div>"""
            html = html.replace("</body>", toolbar + "</body>")
            self._send_bytes(html.encode("utf-8"), "text/html; charset=utf-8")
            return
        if self.application.active_run is not None:
            self.run_dir = self.application.active_run
        super().do_GET()

    def do_POST(self) -> None:
        path = urlparse(self.path).path
        if path.startswith("/api/studio/"):
            if not self._authorized():
                self._send_json({"error": "invalid studio session token"}, 403)
                return
            try:
                payload, files = self._studio_payload()
                if path == "/api/studio/project/validate":
                    self._send_json(
                        self.application.workspace.validate_project(str(payload.get("project_root", "")))
                    )
                    return
                if path == "/api/studio/workspace/change":
                    self._send_json(self.application.change_workspace(str(payload.get("workspace", ""))))
                    return
                if path == "/api/studio/profile/create":
                    if "base_image" not in files:
                        raise StudioError("base_image is required")
                    filename, data = files["base_image"]
                    upload = self._temporary_upload(filename, data)
                    try:
                        anchor = None
                        if payload.get("anchor_x") not in (None, "") and payload.get("anchor_y") not in (None, ""):
                            anchor = [int(payload["anchor_x"]), int(payload["anchor_y"])]
                        profile = self.application.workspace.create_profile(
                            display_name=str(payload.get("display_name", "")),
                            subject_id=str(payload.get("subject_id", "")),
                            subject_type=str(payload.get("subject_type", "character")),
                            base_image=upload,
                            logical_size=int(payload["logical_size"]) if payload.get("logical_size") not in (None, "") else None,
                            anchor=anchor,
                        )
                    finally:
                        upload.unlink(missing_ok=True)
                    self._send_json(profile)
                    return
                if path == "/api/studio/video/upload":
                    if "video" not in files:
                        raise StudioError("video is required")
                    filename, data = files["video"]
                    upload = self._temporary_upload(filename, data)
                    try:
                        job = self.application.workspace.create_video_job(
                            str(payload.get("profile_id", "")), str(payload.get("animation", "animation")), upload
                        )
                    finally:
                        upload.unlink(missing_ok=True)
                    self._send_json(self.application.start_job(str(job["job_id"])))
                    return
                if path == "/api/studio/job/open":
                    self._send_json(self.application.open_job(str(payload.get("job_id", ""))))
                    return
                if path == "/api/studio/job/cancel":
                    self._send_json(self.application.cancel_job(str(payload.get("job_id", ""))))
                    return
                if path == "/api/studio/export/preview":
                    self._send_json(self.application.preview_export(payload))
                    return
                if path == "/api/studio/export/confirm":
                    self._send_json(self.application.export_to_godot(payload))
                    return
            except (StudioError, OSError, ValueError, json.JSONDecodeError) as exc:
                self._send_json({"error": str(exc)}, 400)
                return
            self._send_json({"error": "not found", "path": path}, 404)
            return
        if self.application.active_run is not None:
            self.run_dir = self.application.active_run
        super().do_POST()


def create_server(
    application: StudioApplication,
    host: str = "127.0.0.1",
    port: int = 8766,
) -> ThreadingHTTPServer:
    handler = type("BoundStudioHandler", (StudioHandler,), {"application": application})
    handler.run_dir = application.active_run or Path(".")
    handler.lang = "cn"
    CurationHandler.lang = "cn"
    return ThreadingHTTPServer((host, port), handler)


def default_workspace() -> Path:
    local = os.environ.get("LOCALAPPDATA")
    if local:
        return Path(local) / "VideoSpriteStudio" / "workspace"
    return Path.home() / ".video-sprite-studio" / "workspace"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Video Sprite Studio")
    parser.add_argument("--workspace", type=Path, default=default_workspace())
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8766)
    parser.add_argument("--legacy-run", type=Path)
    parser.add_argument("--no-open", action="store_true")
    args = parser.parse_args(argv)
    application = StudioApplication(
        workspace=StudioWorkspace(args.workspace),
        repo_root=Path(__file__).parents[2],
        legacy_run=args.legacy_run,
    )
    server = create_server(application, args.host, args.port)
    host, port = server.server_address
    url = f"http://{host}:{port}/studio/?lang=cn"
    print(f"Video Sprite Studio: {url}")
    print(f"  workspace: {application.workspace.root}")
    if not args.no_open:
        webbrowser.open(url)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
