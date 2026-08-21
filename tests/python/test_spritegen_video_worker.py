from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
WORKER_PATH = ROOT / "tools" / "video_sprites" / "spritegen_video_worker.py"


def load_worker():
    spec = importlib.util.spec_from_file_location("spritegen_video_worker", WORKER_PATH)
    if spec is None or spec.loader is None:
        raise AssertionError(f"could not import {WORKER_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class SpriteRequestTests(unittest.TestCase):
    def test_full_video_request_keeps_every_frame_and_locks_pixel_unfake_contract(self) -> None:
        worker = load_worker()
        request = worker.build_sprite_request(124, 24.0, True)

        self.assertEqual(124, request["states"]["source_all"]["frames"])
        self.assertEqual(24, request["states"]["source_all"]["fps"])
        self.assertTrue(request["states"]["source_all"]["loop"])
        self.assertEqual(
            {
                "pixel_unfake": True,
                "logical_height": 64,
                "palette_size": 32,
                "resample": "kcentroid",
                "align_x": "alpha-centroid",
                "align_y": "bottom",
                "ground_frames": True,
                "outline": False,
            },
            request["fit"],
        )

    def test_ffprobe_duration_rounding_normalizes_back_to_declared_24_fps(self) -> None:
        worker = load_worker()
        request = worker.build_sprite_request(124, 23.999808001535985, True)
        self.assertEqual(24, request["states"]["source_all"]["fps"])


class RawStripTests(unittest.TestCase):
    def test_strip_uses_explicit_native_slots_and_preserves_white_clothing(self) -> None:
        worker = load_worker()
        with tempfile.TemporaryDirectory() as temporary:
            destination = Path(temporary) / "source_all.png"
            first = Image.new("RGBA", (8, 8), (0, 0, 0, 0))
            first.paste((250, 250, 250, 255), (2, 2, 6, 7))
            second = Image.new("RGBA", (8, 8), (0, 0, 0, 0))
            second.paste((40, 70, 68, 255), (1, 1, 7, 7))

            worker.compose_chroma_strip([first, second], destination)

            with Image.open(destination) as strip:
                rgba = strip.convert("RGBA")
                self.assertEqual((16, 8), rgba.size)
                self.assertEqual((255, 0, 255, 255), rgba.getpixel((0, 0)))
                self.assertEqual((250, 250, 250, 255), rgba.getpixel((3, 3)))
                self.assertEqual((40, 70, 68, 255), rgba.getpixel((10, 3)))


class ExtractedFrameTests(unittest.TestCase):
    def test_install_keeps_one_to_one_source_mapping_including_frame_018(self) -> None:
        worker = load_worker()
        palette = [(42, 15, 13), (241, 238, 240)]
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            extracted = root / "extracted"
            extracted.mkdir()
            timing = []
            for index in range(18):
                frame = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
                # sprite-gen treats y=232 as the ground boundary, so the last
                # opaque row is y=231 and PIL reports bbox end 232.
                frame.paste((*palette[index % 2], 255), (100, 100, 156, 232))
                frame.save(extracted / f"frame-{index}.png")
                timing.append(
                    {
                        "source_frame": index + 1,
                        "timestamp_seconds": index / 24.0,
                        "duration_ms": 1000.0 / 24.0,
                    }
                )
            # sprite-gen intentionally keeps this QA twin beside the official frame.
            # It must never be counted as another source-video frame.
            (extracted / "frame-0.plain.png").write_bytes(
                (extracted / "frame-0.png").read_bytes()
            )

            installed = worker.install_extracted_frames(
                extracted, root / "frames", timing, palette
            )

            self.assertEqual(18, len(installed))
            self.assertEqual(18, installed[17]["source_frame"])
            self.assertEqual("frame_018.png", Path(installed[17]["path"]).name)
            self.assertTrue((root / "frames" / "frame_018.png").is_file())

    def test_install_refuses_a_missing_extracted_frame(self) -> None:
        worker = load_worker()
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            extracted = root / "extracted"
            extracted.mkdir()
            timing = [
                {"source_frame": 1, "timestamp_seconds": 0.0, "duration_ms": 41.666667}
            ]
            with self.assertRaisesRegex(worker.WorkerError, "frame-0.png"):
                worker.install_extracted_frames(
                    extracted, root / "frames", timing, [(42, 15, 13)]
                )


class PaletteTests(unittest.TestCase):
    def test_palette_lock_is_the_fixed_32_colour_truth(self) -> None:
        worker = load_worker()
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "palette.lock.json"
            path.write_text(
                json.dumps(
                    {
                        "kind": "sprite-gen-palette-lock",
                        "colors": [[index, index, index] for index in range(32)],
                    }
                ),
                encoding="utf-8",
            )
            self.assertEqual(32, len(worker.load_palette_lock(path)))


class InstalledClipTests(unittest.TestCase):
    def test_validation_uses_sprite_gen_ground_boundary_and_explicit_layout(self) -> None:
        worker = load_worker()
        palette = [(42, 15, 13), (241, 238, 240)]
        with tempfile.TemporaryDirectory() as temporary:
            clip = Path(temporary)
            frames = clip / "frames"
            frames.mkdir()
            frame_path = frames / "frame_001.png"
            frame = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
            frame.paste((*palette[0], 255), (100, 100, 156, 232))
            frame.save(frame_path)
            atlas = Image.new("RGBA", (4096, 256), (0, 0, 0, 0))
            atlas.alpha_composite(frame, (0, 0))
            atlas.save(clip / "atlas.png")
            rect = {"x": 0, "y": 0, "w": 256, "h": 256}
            (clip / "manifest.json").write_text(
                json.dumps(
                    {
                        "clip_id": "walk_test",
                        "degraded_static_fallback": False,
                        "game_input": "atlas.png",
                        "source": {"frame_count": 1},
                        "frame_layout": {
                            "sheetWidth": 4096,
                            "sheetHeight": 256,
                            "rows": {"source_all": [rect]},
                        },
                        "source_frames": [
                            {
                                "index": 0,
                                "source_frame": 1,
                                "duration_ms": 41.666667,
                                "png": "frames/frame_001.png",
                                "sha256": worker._sha256(frame_path),
                                "rect": rect,
                            }
                        ],
                    }
                ),
                encoding="utf-8",
            )

            result = worker.validate_installed_clip(clip, palette)

            self.assertEqual(
                {"clip_id": "walk_test", "frame_count": 1, "valid": True}, result
            )


if __name__ == "__main__":
    unittest.main()
