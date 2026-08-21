import json
import http.client
import tempfile
import threading
import unittest
from pathlib import Path

from PIL import Image
from sprite_gen.curate.curation import stamp_curation

from tools.video_sprite_studio.studio_core import StudioError, StudioWorkspace
from tools.video_sprite_studio.studio_export import build_selected_export, install_selected_export
from tools.video_sprite_studio.studio_server import (
    StudioApplication, create_server, prepare_curation_run,
)


class VideoSpriteStudioCoreTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.workspace = StudioWorkspace(self.root / "workspace")

    def tearDown(self) -> None:
        self.temp.cleanup()

    def _base(self, name: str = "base.png") -> Path:
        path = self.root / name
        image = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
        for y in range(4, 14):
            for x in range(3, 13):
                image.putpixel((x, y), (220, 80 + x, 50 + y, 255))
        image.save(path)
        return path

    def _project(self) -> Path:
        project = self.root / "game"
        project.mkdir()
        (project / "project.godot").write_text(
            '[application]\nconfig/name="Fixture"\n[application/config]\nfeatures=PackedStringArray("4.7")\n',
            encoding="utf-8",
        )
        target = project / "assets" / "hero.tres"
        target.parent.mkdir()
        target.write_text('[gd_resource type="SpriteFrames" format=3]\n', encoding="utf-8")
        return project

    def test_profile_keeps_identity_assets_outside_project_and_uses_presets(self) -> None:
        profile = self.workspace.create_profile(
            display_name="尼可",
            subject_id="Niko Hero",
            subject_type="character",
            base_image=self._base(),
        )

        self.assertEqual(profile["subject_id"], "niko_hero")
        self.assertEqual(profile["cell"], [256, 256])
        self.assertEqual(profile["logical_size"], 64)
        self.assertEqual(profile["anchor"], [128, 232])
        self.assertEqual(profile["align_y"], "bottom")
        palette = json.loads(Path(profile["palette_lock"]).read_text(encoding="utf-8"))
        self.assertEqual(palette["kind"], "sprite-gen-palette-lock")
        self.assertEqual(len(palette["colors"]), 32)
        self.assertTrue(Path(profile["base_image"]).is_relative_to(self.workspace.root))
        config = json.loads(Path(profile["pixelmotion_config"]).read_text(encoding="utf-8"))
        self.assertEqual(config["cutout"]["connectivity"], 8)
        self.assertEqual(config["sprite"]["rootAnchor"], [128, 232])

        object_profile = self.workspace.create_profile(
            display_name="火球",
            subject_id="fireball",
            subject_type="object",
            base_image=self._base("object.png"),
        )
        self.assertEqual(object_profile["logical_size"], 128)
        self.assertEqual(object_profile["anchor"], [128, 128])
        self.assertEqual(object_profile["align_y"], "alpha-centroid")

    def test_project_validation_discovers_spriteframes_and_rejects_non_godot4(self) -> None:
        project = self._project()
        result = self.workspace.validate_project(project)
        self.assertEqual(result["godot_major"], 4)
        self.assertEqual(result["sprite_frames"], ["res://assets/hero.tres"])

        (project / "project.godot").write_text(
            '[application/config]\nfeatures=PackedStringArray("3.5")\n', encoding="utf-8"
        )
        with self.assertRaisesRegex(StudioError, "Godot 4"):
            self.workspace.validate_project(project)

    def test_export_confirmation_is_bound_to_selection_fps_loop_and_target(self) -> None:
        project = self._project()
        request = {
            "project_root": str(project),
            "subject_id": "niko",
            "animation": "walk_down",
            "target_resource": "res://assets/hero.tres",
            "selection": [17, 3, 17],
            "fps": 10.0,
            "loop": True,
        }
        first = self.workspace.preview_export(request)
        self.assertEqual(first["frame_count"], 3)
        self.assertTrue(first["confirmation_token"])
        changed = dict(request, fps=12.0)
        self.assertNotEqual(
            first["confirmation_token"],
            self.workspace.preview_export(changed)["confirmation_token"],
        )
        self.workspace.verify_confirmation(request, first["confirmation_token"])
        with self.assertRaisesRegex(StudioError, "stale"):
            self.workspace.verify_confirmation(changed, first["confirmation_token"])

    def test_job_upload_accepts_supported_video_and_persists_full_frame_intent(self) -> None:
        profile = self.workspace.create_profile(
            display_name="Niko",
            subject_id="niko",
            subject_type="character",
            base_image=self._base(),
        )
        video = self.root / "happy.mp4"
        video.write_bytes(b"fixture-video")
        job = self.workspace.create_video_job(
            profile_id=profile["subject_id"],
            animation="walk_down",
            video_path=video,
        )
        self.assertEqual(job["state"], "uploaded")
        self.assertEqual(job["sampling"], "all_frames")
        self.assertTrue(Path(job["video_path"]).is_relative_to(self.workspace.root))
        self.assertEqual(len(job["video_sha256"]), 64)

        bad = self.root / "bad.txt"
        bad.write_text("no", encoding="utf-8")
        with self.assertRaisesRegex(StudioError, "video extension"):
            self.workspace.create_video_job("niko", "idle_down", bad)

    def test_selected_export_normalizes_legacy_cells_and_preserves_duplicate_order(self) -> None:
        run = self.root / "legacy-run"
        frames = run / "frames" / "walk_down"
        frames.mkdir(parents=True)
        for index, colour in enumerate(((255, 0, 0, 255), (0, 255, 0, 255), (0, 0, 255, 255))):
            image = Image.new("RGBA", (640, 640), (0, 0, 0, 0))
            for y in range(160, 480):
                for x in range(160, 480):
                    image.putpixel((x, y), colour)
            image.save(frames / f"frame-{index}.png")
        (run / "sprite-request.json").write_text(
            json.dumps({
                "version": 1,
                "kind": "sprite-gen-request",
                "engine": "component-row",
                "character": {"id": "legacy"},
                "cell": {"width": 640, "height": 640, "size": 640, "safe_margin": 0},
                "chroma_key": {"name": "magenta", "hex": "#FF00FF", "rgb": [255, 0, 255]},
                "states": {"walk_down": {"frames": 3, "fps": 10, "loop": True, "action": "walk"}},
            }), encoding="utf-8"
        )
        (run / "frames" / "frames-manifest.json").write_text(
            json.dumps({
                "ok": True,
                "engine": "component-row",
                "cell": {"width": 640, "height": 640, "size": 640, "safe_margin": 0},
                "rows": [{
                    "state": "walk_down", "frames": 3, "method": "fixture",
                    "files": [f"frames/walk_down/frame-{i}.png" for i in range(3)],
                    "labels": ["F001", "F002", "F003"], "ok": True,
                }],
                "errors": [], "warnings": [],
            }), encoding="utf-8"
        )
        (run / "curation.json").write_text(
            json.dumps(stamp_curation(run, {
                "version": 1, "kind": "sprite-gen-curation",
                "states": {"walk_down": {"selected": [2, 0, 2], "order": [2, 0, 2, 1], "transforms": {}}},
            })), encoding="utf-8"
        )
        output = self.root / "selected"

        result = build_selected_export(
            run_dir=run,
            state="walk_down",
            output_dir=output,
            subject_id="niko",
            animation="walk_down",
            fps=12.0,
            loop=True,
            video_sha256="a" * 64,
        )

        manifest = json.loads((output / "manifest.json").read_text(encoding="utf-8"))
        provenance = json.loads((output / "provenance.json").read_text(encoding="utf-8"))
        with Image.open(output / "atlas.png") as atlas:
            self.assertEqual(atlas.size, (768, 256))
            self.assertEqual(atlas.getpixel((128, 128)), (0, 0, 255, 255))
            self.assertEqual(atlas.getpixel((384, 128)), (255, 0, 0, 255))
            self.assertEqual(atlas.getpixel((640, 128)), (0, 0, 255, 255))
        self.assertEqual(result["frame_count"], 3)
        self.assertEqual(manifest["animation"]["rows"]["walk_down"]["fps"], 12.0)
        self.assertEqual(provenance["ordered_source_indices"], [2, 0, 2])

    def test_godot_install_atomically_replaces_target_and_cleans_bridge_files(self) -> None:
        project = self._project()
        selected = self.root / "selected-artifacts"
        selected.mkdir()
        Image.new("RGBA", (256, 256), (20, 30, 40, 255)).save(selected / "atlas.png")
        (selected / "manifest.json").write_text(json.dumps({
            "cell": {"width": 256, "height": 256},
            "animation": {"rows": {"walk_down": {
                "frames": 1, "fps": 10.0, "loop": True, "durations_ms": [100.0],
            }}},
            "frame_layout": {"sheetWidth": 256, "sheetHeight": 256,
                             "rows": {"walk_down": [{"x": 0, "y": 0, "w": 256, "h": 256}]}},
        }), encoding="utf-8")
        (selected / "provenance.json").write_text("{}", encoding="utf-8")
        target = project / "assets" / "hero.tres"
        original = target.read_bytes()
        calls = []

        def successful_runner(command, request):
            calls.append(command)
            Path(request["temp_absolute"]).write_text(
                '[gd_resource type="SpriteFrames" format=3]\n[resource]\nanimations = []\n',
                encoding="utf-8",
            )
            return 0, '{"ok":true}', ""

        receipt = install_selected_export(
            project_root=project,
            selected_dir=selected,
            subject_id="niko",
            animation="walk_down",
            target_resource="res://assets/hero.tres",
            godot_binary=Path("C:/Godot/Godot.exe"),
            bridge_source=Path(__file__).parents[2] / "tools" / "video_sprite_studio",
            runner=successful_runner,
        )

        self.assertTrue(calls)
        self.assertNotEqual(target.read_bytes(), original)
        self.assertEqual(receipt["target_resource"], "res://assets/hero.tres")
        self.assertTrue(receipt["replaced"])
        revision = project / receipt["revision_resource"].removeprefix("res://")
        self.assertEqual(sorted(path.name for path in revision.iterdir()), [
            "atlas.png", "manifest.json", "provenance.json",
        ])
        self.assertFalse(any(project.rglob(".video_sprite_studio_bridge*")))

    def test_godot_install_failure_keeps_target_and_removes_new_revision(self) -> None:
        project = self._project()
        selected = self.root / "selected-failure"
        selected.mkdir()
        Image.new("RGBA", (256, 256), (20, 30, 40, 255)).save(selected / "atlas.png")
        (selected / "manifest.json").write_text("{}", encoding="utf-8")
        (selected / "provenance.json").write_text("{}", encoding="utf-8")
        target = project / "assets" / "hero.tres"
        original = target.read_bytes()

        with self.assertRaisesRegex(StudioError, "Godot import failed"):
            install_selected_export(
                project_root=project,
                selected_dir=selected,
                subject_id="niko",
                animation="walk_down",
                target_resource="res://assets/hero.tres",
                godot_binary=Path("C:/Godot/Godot.exe"),
                bridge_source=Path(__file__).parents[2] / "tools" / "video_sprite_studio",
                runner=lambda _command, _request: (3, "", "broken"),
            )
        self.assertEqual(target.read_bytes(), original)
        generated = project / "assets" / "generated" / "video_sprites" / "niko" / "walk_down"
        self.assertFalse(generated.exists())

    def test_processed_clip_becomes_a_full_frame_curation_run_without_losing_018(self) -> None:
        profile = self.workspace.create_profile(
            display_name="Niko", subject_id="niko", subject_type="character", base_image=self._base()
        )
        clip = self.root / "processed" / "clip"
        frame_root = clip / "frames"
        frame_root.mkdir(parents=True)
        source_frames = []
        rects = []
        for index in range(19):
            frame = frame_root / f"frame_{index + 1:03d}.png"
            Image.new("RGBA", (256, 256), (index, 20, 30, 255)).save(frame)
            rect = {"x": (index % 16) * 256, "y": (index // 16) * 256, "w": 256, "h": 256}
            rects.append(rect)
            source_frames.append({
                "index": index, "source_frame": index + 1,
                "timestamp_seconds": index / 24.0, "duration_ms": 1000.0 / 24.0,
                "png": f"frames/{frame.name}", "sha256": "f" * 64, "rect": rect,
            })
        manifest = {
            "source": {"sha256": "a" * 64, "frame_count": 19,
                       "fps": {"numerator": 24, "denominator": 1, "value": 24.0}},
            "cell": {"width": 256, "height": 256},
            "source_frames": source_frames,
        }
        (clip / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
        run = self.root / "run"

        result = prepare_curation_run(
            manifest_path=clip / "manifest.json", run_dir=run,
            profile=profile, animation="walk_down",
        )

        self.assertEqual(result["frame_count"], 19)
        self.assertTrue((run / "frames" / "walk_down" / "frame-17.png").is_file())
        sidecar = json.loads((run / "curation.json").read_text(encoding="utf-8"))
        self.assertEqual(sidecar["states"]["walk_down"]["selected"], [])
        self.assertEqual(sidecar["states"]["walk_down"]["order"], list(range(19)))
        source = json.loads((run / "studio-source.json").read_text(encoding="utf-8"))
        self.assertEqual(source["frames"][17]["source_frame"], 18)

    def test_application_registers_legacy_run_and_exposes_only_cn_en_ui(self) -> None:
        legacy = self.root / "legacy"
        legacy.mkdir()
        (legacy / "sprite-request.json").write_text("{}", encoding="utf-8")
        app = StudioApplication(
            workspace=self.workspace,
            repo_root=Path(__file__).parents[2],
            legacy_run=legacy,
        )
        self.assertEqual(app.active_run, legacy.resolve())
        html = app.dashboard_html("cn")
        self.assertIn("视频精灵工作台", html)
        self.assertIn("上传视频", html)
        self.assertIn("导出到 Godot", html)
        self.assertNotIn("한국", html)

    def test_http_dashboard_and_project_write_api_require_session_token(self) -> None:
        legacy = self.root / "legacy-http"
        legacy.mkdir()
        (legacy / "sprite-request.json").write_text("{}", encoding="utf-8")
        app = StudioApplication(
            workspace=self.workspace,
            repo_root=Path(__file__).parents[2],
            legacy_run=legacy,
        )
        server = create_server(app, "127.0.0.1", 0)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            connection = http.client.HTTPConnection("127.0.0.1", server.server_port, timeout=5)
            connection.request("GET", "/studio/?lang=cn")
            response = connection.getresponse()
            html = response.read().decode("utf-8")
            self.assertEqual(response.status, 200)
            self.assertIn("VIDEO_SPRITE_STUDIO_TOKEN", html)

            body = json.dumps({"project_root": str(self._project())})
            connection.request("POST", "/api/studio/project/validate", body=body,
                               headers={"Content-Type": "application/json"})
            denied = connection.getresponse()
            denied.read()
            self.assertEqual(denied.status, 403)

            connection.request(
                "POST", "/api/studio/project/validate", body=body,
                headers={"Content-Type": "application/json", "X-Studio-Token": app.session_token},
            )
            allowed = connection.getresponse()
            payload = json.loads(allowed.read())
            self.assertEqual(allowed.status, 200)
            self.assertEqual(payload["godot_major"], 4)
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)


if __name__ == "__main__":
    unittest.main()
