from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any, Callable, Mapping, Sequence

from PIL import Image


TOOL_ROOT = Path(__file__).resolve().parent
IDENTITY_ROOT = TOOL_ROOT / "niko_identity"
DEFAULT_BASE_IMAGE = IDENTITY_ROOT / "base-source.png"
DEFAULT_PALETTE_LOCK = IDENTITY_ROOT / "palette.lock.json"
STATE = "source_all"
CELL_SIZE = (256, 256)
SAFE_MARGIN = 24
ROOT_ANCHOR = (128, 232)
PIXEL_SCALE = 4
CHROMA_RGBA = (255, 0, 255, 255)
VIDEO_EXTENSIONS = (".avi", ".mkv", ".mov", ".mp4", ".webm")
IMAGE_EXTENSIONS = (".bmp", ".jpeg", ".jpg", ".png", ".webp")


class WorkerError(RuntimeError):
    """Raised when the reproducible PixelMotion -> sprite-gen contract fails."""


def build_sprite_request(frame_count: int, fps: float, loop: bool) -> dict[str, Any]:
    if frame_count <= 0:
        raise WorkerError("frame_count must be positive")
    if fps <= 0:
        raise WorkerError("fps must be positive")
    rounded_fps = int(round(fps))
    # ffprobe timestamps are serialized to microseconds, so a declared 24 FPS
    # stream can round-trip through one frame duration as 23.999808. Keep real
    # fractional rates loud while accepting that bounded timestamp quantization.
    if abs(fps - rounded_fps) > 0.01:
        raise WorkerError(f"sprite-gen request requires an integral FPS, got {fps}")
    return {
        "cell": {
            "width": CELL_SIZE[0],
            "height": CELL_SIZE[1],
            "safe_margin_x": SAFE_MARGIN,
            "safe_margin_y": SAFE_MARGIN,
        },
        "states": {
            STATE: {
                "frames": frame_count,
                "fps": rounded_fps,
                "loop": bool(loop),
                "action": "all source-video frames in original chronological order",
            }
        },
        "fit": {
            "pixel_unfake": True,
            "logical_height": 64,
            "palette_size": 32,
            "resample": "kcentroid",
            "align_x": "alpha-centroid",
            "align_y": "bottom",
            "ground_frames": True,
            "outline": False,
        },
        "style": (
            "Preserve the locked Niko identity, costume, proportions, outline density, "
            "and shared palette. This run derives frames from source video and does not "
            "invent or interpolate poses."
        ),
    }


def compose_chroma_strip(
    subjects: Sequence[Image.Image],
    destination: Path,
) -> None:
    if not subjects:
        raise WorkerError("cannot compose an empty sprite-gen strip")
    first_size = subjects[0].size
    if first_size[0] <= 0 or first_size[1] <= 0:
        raise WorkerError(f"invalid source frame size: {first_size}")
    for index, subject in enumerate(subjects, start=1):
        if subject.size != first_size:
            raise WorkerError(
                f"source frame {index} size {subject.size} does not match {first_size}"
            )
    strip = Image.new(
        "RGBA",
        (first_size[0] * len(subjects), first_size[1]),
        CHROMA_RGBA,
    )
    try:
        for index, subject in enumerate(subjects):
            rgba = subject.convert("RGBA")
            try:
                strip.alpha_composite(rgba, (index * first_size[0], 0))
            finally:
                rgba.close()
        destination = Path(destination)
        destination.parent.mkdir(parents=True, exist_ok=True)
        strip.save(destination, format="PNG", optimize=False)
    finally:
        strip.close()


def load_palette_lock(path: Path) -> list[tuple[int, int, int]]:
    palette_path = Path(path).resolve()
    try:
        payload = json.loads(palette_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise WorkerError(f"could not load sprite-gen palette lock {palette_path}: {exc}") from exc
    if not isinstance(payload, dict) or payload.get("kind") != "sprite-gen-palette-lock":
        raise WorkerError("palette lock must be a sprite-gen-palette-lock object")
    raw_colours = payload.get("colors")
    if not isinstance(raw_colours, list) or len(raw_colours) != 32:
        raise WorkerError("palette lock must contain exactly 32 colours")
    colours: list[tuple[int, int, int]] = []
    for index, value in enumerate(raw_colours):
        if (
            not isinstance(value, list)
            or len(value) != 3
            or any(not isinstance(channel, int) or not 0 <= channel <= 255 for channel in value)
        ):
            raise WorkerError(f"palette lock colour {index} must be three 0..255 integers")
        colours.append((value[0], value[1], value[2]))
    return colours


def install_extracted_frames(
    extracted_directory: Path,
    output_directory: Path,
    timing: Sequence[Mapping[str, Any]],
    palette: Sequence[tuple[int, int, int]],
) -> list[dict[str, Any]]:
    extracted = Path(extracted_directory).resolve()
    output = Path(output_directory).resolve()
    if not timing:
        raise WorkerError("source timing must be non-empty")
    for index in range(len(timing)):
        expected = extracted / f"frame-{index}.png"
        if not expected.is_file():
            raise WorkerError(f"sprite-gen extracted frame is missing: {expected}")
    actual = sorted(
        path
        for path in extracted.glob("frame-*.png")
        if path.name.removeprefix("frame-").removesuffix(".png").isdigit()
    )
    if len(actual) != len(timing):
        raise WorkerError(
            f"sprite-gen extracted frame count mismatch: expected {len(timing)}, found {len(actual)}"
        )
    output.mkdir(parents=True, exist_ok=True)
    allowed = set(palette)
    results: list[dict[str, Any]] = []
    for index, frame_timing in enumerate(timing):
        source = extracted / f"frame-{index}.png"
        destination = output / f"frame_{index + 1:03d}.png"
        alignment = _normalize_registered_frame(source, destination, allowed)
        provenance = {
            "path": str(destination),
            "sha256": _sha256(destination),
            "source_frame": int(frame_timing["source_frame"]),
            "timestamp_seconds": float(frame_timing["timestamp_seconds"]),
            "duration_ms": float(frame_timing["duration_ms"]),
            "processor": "sprite-gen/pixel-unfake",
            "alignment_shift_x": alignment["shift_x"],
        }
        if alignment["safety_margin_intrusion"]:
            provenance["safety_margin_intrusion"] = alignment["safety_margin_intrusion"]
        results.append(
            provenance
        )
    return results


def _normalize_registered_frame(
    source: Path,
    destination: Path,
    allowed_palette: set[tuple[int, int, int]],
) -> dict[str, Any]:
    """Translate a registered sprite-gen cell onto its declared horizontal axis.

    sprite-gen registers a whole row before per-frame alpha-centroid placement.  If
    a frame occupies only an offset portion of that registered logical canvas, its
    placement clamp can retain the empty registration padding and push visible
    pixels into the margin zone.  Re-centering the visible cell after extraction is
    a pixel-grid translation only: no source pose, palette, alpha, scale, or pixel
    count changes.
    """
    try:
        with Image.open(source) as opened:
            rgba = opened.convert("RGBA")
    except OSError as exc:
        raise WorkerError(f"could not open sprite-gen frame {source}: {exc}") from exc
    try:
        _validate_pixel_image(rgba, source, allowed_palette, require_safe_margins=False)
        alpha = rgba.getchannel("A")
        bbox = alpha.getbbox()
        assert bbox is not None
        visible_width = bbox[2] - bbox[0]
        safe_width = CELL_SIZE[0] - SAFE_MARGIN * 2
        if visible_width <= safe_width:
            min_shift = SAFE_MARGIN - bbox[0]
            max_shift = CELL_SIZE[0] - SAFE_MARGIN - bbox[2]
        else:
            # sprite-gen defines native logical content entering the margin zone
            # as informational. Preserve a wide source prop intact and center it
            # within the physical cell; provenance makes the exception explicit.
            min_shift = -bbox[0]
            max_shift = CELL_SIZE[0] - bbox[2]
        lower_grid_shift = math.ceil(min_shift / PIXEL_SCALE) * PIXEL_SCALE
        upper_grid_shift = math.floor(max_shift / PIXEL_SCALE) * PIXEL_SCALE
        if lower_grid_shift > upper_grid_shift:
            raise WorkerError(
                "sprite-gen visible content cannot fit inside the 256px physical cell: "
                f"{source}: {bbox}"
            )

        alpha_pixels = alpha.load()
        alpha_total = 0
        weighted_x = 0.0
        for y in range(bbox[1], bbox[3]):
            for x in range(bbox[0], bbox[2]):
                value = alpha_pixels[x, y]
                if value:
                    alpha_total += value
                    weighted_x += value * (x + 0.5)
        centroid_x = weighted_x / alpha_total
        desired_shift = round((ROOT_ANCHOR[0] - centroid_x) / PIXEL_SCALE) * PIXEL_SCALE
        shift_x = min(max(desired_shift, lower_grid_shift), upper_grid_shift)

        normalized = Image.new("RGBA", CELL_SIZE, (0, 0, 0, 0))
        try:
            visible = rgba.crop(bbox)
            try:
                normalized.alpha_composite(visible, (bbox[0] + shift_x, bbox[1]))
            finally:
                visible.close()
            destination.parent.mkdir(parents=True, exist_ok=True)
            normalized.save(destination, format="PNG", optimize=False)
        finally:
            normalized.close()
    finally:
        rgba.close()
    intrusion = _validate_pixel_frame(
        destination, allowed_palette, allow_margin_intrusion=True
    )
    return {"shift_x": int(shift_x), "safety_margin_intrusion": intrusion}


def _validate_pixel_frame(
    path: Path,
    allowed_palette: set[tuple[int, int, int]],
    *,
    allow_margin_intrusion: bool = False,
) -> dict[str, int]:
    try:
        with Image.open(path) as opened:
            rgba = opened.convert("RGBA")
    except OSError as exc:
        raise WorkerError(f"could not open sprite-gen frame {path}: {exc}") from exc
    try:
        return _validate_pixel_image(
            rgba,
            path,
            allowed_palette,
            require_safe_margins=not allow_margin_intrusion,
        )
    finally:
        rgba.close()


def _validate_pixel_image(
    rgba: Image.Image,
    path: Path,
    allowed_palette: set[tuple[int, int, int]],
    *,
    require_safe_margins: bool,
) -> dict[str, int]:
    if rgba.size != CELL_SIZE:
        raise WorkerError(f"sprite-gen frame must be 256x256: {path} is {rgba.size}")
    alpha_values = set(rgba.getchannel("A").get_flattened_data())
    if not alpha_values.issubset({0, 255}):
        raise WorkerError(f"sprite-gen frame does not have hard alpha: {path}")
    colours = {pixel[:3] for pixel in rgba.get_flattened_data() if pixel[3]}
    if not colours.issubset(allowed_palette):
        unexpected = sorted(colours - allowed_palette)[:5]
        raise WorkerError(f"sprite-gen frame escaped the locked palette: {path}: {unexpected}")
    bbox = rgba.getchannel("A").getbbox()
    if bbox is None:
        raise WorkerError(f"sprite-gen frame has no visible subject: {path}")
    if bbox[3] != ROOT_ANCHOR[1]:
        raise WorkerError(
            f"sprite-gen frame violates 24px safety/root contract: {path}: {bbox}"
        )
    intrusion = _safety_margin_intrusion(bbox)
    if require_safe_margins and intrusion:
        raise WorkerError(
            f"sprite-gen frame violates 24px safety/root contract: {path}: {bbox}"
        )
    return intrusion


def _safety_margin_intrusion(bbox: tuple[int, int, int, int]) -> dict[str, int]:
    values = {
        "left": max(0, SAFE_MARGIN - bbox[0]),
        "top": max(0, SAFE_MARGIN - bbox[1]),
        "right": max(0, bbox[2] - (CELL_SIZE[0] - SAFE_MARGIN)),
    }
    return values if any(values.values()) else {}


def validate_installed_clip(
    path: Path,
    palette: Sequence[tuple[int, int, int]],
) -> dict[str, Any]:
    clip = Path(path).resolve()
    manifest_path = clip / "manifest.json"
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise WorkerError(f"invalid manifest: {manifest_path}: {exc}") from exc
    if manifest.get("degraded_static_fallback") is not False:
        raise WorkerError("degraded_static_fallback must be false")
    source_frames = manifest.get("source_frames")
    layout = manifest.get("frame_layout")
    if not isinstance(source_frames, list) or not isinstance(layout, dict):
        raise WorkerError("manifest source_frames and explicit frame layout are required")
    rows = layout.get("rows")
    rects = rows.get(STATE) if isinstance(rows, dict) else None
    expected_count = int(manifest.get("source", {}).get("frame_count", 0))
    if (
        expected_count <= 0
        or not isinstance(rects, list)
        or len(source_frames) != expected_count
        or len(rects) != expected_count
    ):
        raise WorkerError("manifest frame counts do not match")
    sheet_width = int(layout.get("sheetWidth", 0))
    sheet_height = int(layout.get("sheetHeight", 0))
    atlas_declared = str(manifest.get("game_input", ""))
    atlas_path = (clip / atlas_declared).resolve()
    if not atlas_declared or not atlas_path.is_relative_to(clip) or not atlas_path.is_file():
        raise WorkerError(f"atlas not found inside clip: {atlas_path}")
    with Image.open(atlas_path) as atlas:
        if atlas.size != (sheet_width, sheet_height):
            raise WorkerError("atlas dimensions do not match manifest")
    allowed = set(palette)
    for expected_index, (frame, rect) in enumerate(zip(source_frames, rects)):
        if not isinstance(frame, dict) or not isinstance(rect, dict):
            raise WorkerError(f"frame {expected_index} provenance must be an object")
        if int(frame.get("index", -1)) != expected_index or frame.get("rect") != rect:
            raise WorkerError(f"frame {expected_index} provenance does not match layout")
        if int(frame.get("source_frame", 0)) <= 0 or float(frame.get("duration_ms", 0)) <= 0:
            raise WorkerError(f"frame {expected_index} source timing is invalid")
        values = [int(rect.get(key, -1)) for key in ("x", "y", "w", "h")]
        x, y, width, height = values
        if (
            width != CELL_SIZE[0]
            or height != CELL_SIZE[1]
            or x < 0
            or y < 0
            or x + width > sheet_width
            or y + height > sheet_height
        ):
            raise WorkerError(f"frame {expected_index} rectangle is outside the atlas")
        png_declared = str(frame.get("png", ""))
        frame_path = (clip / png_declared).resolve()
        if not png_declared or not frame_path.is_relative_to(clip) or not frame_path.is_file():
            raise WorkerError(f"frame PNG not found inside clip: {frame_path}")
        if _sha256(frame_path) != str(frame.get("sha256", "")):
            raise WorkerError(f"frame PNG hash mismatch: {frame_path}")
        declared_intrusion = frame.get("safety_margin_intrusion")
        if declared_intrusion is not None and not isinstance(declared_intrusion, dict):
            raise WorkerError(
                f"frame {expected_index} safety_margin_intrusion must be an object"
            )
        actual_intrusion = _validate_pixel_frame(
            frame_path,
            allowed,
            allow_margin_intrusion=declared_intrusion is not None,
        )
        if actual_intrusion != (declared_intrusion or {}):
            raise WorkerError(
                f"frame {expected_index} safety margin provenance does not match pixels"
            )
    return {
        "clip_id": str(manifest.get("clip_id", "")),
        "frame_count": expected_count,
        "valid": True,
    }


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with Path(path).open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _script(sprite_gen_root: Path, name: str) -> Path:
    path = Path(sprite_gen_root).resolve() / "scripts" / name
    if not path.is_file():
        raise WorkerError(f"sprite-gen script not found: {path}")
    return path


def _run_tool(command: Sequence[str], label: str) -> None:
    environment = os.environ.copy()
    environment["PYTHONUTF8"] = "1"
    completed = subprocess.run(
        list(command),
        check=False,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        env=environment,
    )
    if completed.returncode != 0:
        detail = "\n".join(
            part.strip() for part in (completed.stdout, completed.stderr) if part.strip()
        )
        raise WorkerError(f"{label} failed with exit {completed.returncode}: {detail}")


def _prepare_run(
    run_directory: Path,
    sprite_gen_root: Path,
    base_image: Path,
    palette_lock: Path,
    frame_count: int,
    fps: float,
    loop: bool,
) -> None:
    base = Path(base_image).resolve()
    palette = Path(palette_lock).resolve()
    if not base.is_file():
        raise WorkerError(f"locked Niko base image not found: {base}")
    if not palette.is_file():
        raise WorkerError(f"locked Niko palette not found: {palette}")
    request_input = run_directory.parent / "source-request.json"
    request_input.write_text(
        json.dumps(build_sprite_request(frame_count, fps, loop), ensure_ascii=False, indent=2)
        + "\n",
        encoding="utf-8",
    )
    command = [
        sys.executable,
        str(_script(sprite_gen_root, "prepare_sprite_run.py")),
        "--out-dir",
        str(run_directory),
        "--character-id",
        "niko-video-source",
        "--base-image",
        str(base),
        "--description",
        "Niko source-video frame library with locked current appearance",
        "--cell-size",
        "256",
        "--safe-margin",
        "24",
        "--chroma-key",
        "#FF00FF",
        "--fit-resample",
        "kcentroid",
        "--fit-align-x",
        "alpha-centroid",
        "--fit-align-y",
        "bottom",
        "--fit-ground-frames",
        "--fit-pixel-unfake",
        "--fit-logical-height",
        "64",
        "--fit-palette-size",
        "32",
        "--fit-outline",
        "off",
        "--request",
        str(request_input),
    ]
    _run_tool(command, "sprite-gen prepare")
    shutil.copy2(palette, run_directory / "palette.lock.json")


def _extract_run(run_directory: Path, sprite_gen_root: Path) -> Path:
    command = [
        sys.executable,
        str(_script(sprite_gen_root, "extract_sprite_row_frames.py")),
        "--run-dir",
        str(run_directory),
        "--states",
        STATE,
        "--allow-slot-fallback",
    ]
    _run_tool(command, "sprite-gen extract")
    manifest_path = run_directory / "frames" / "frames-manifest.json"
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise WorkerError(f"sprite-gen frames manifest is missing or invalid: {exc}") from exc
    if manifest.get("ok") is not True:
        raise WorkerError(
            "sprite-gen extraction QA failed: "
            + "; ".join(str(value) for value in manifest.get("errors", []))
        )
    rows = manifest.get("rows")
    if not isinstance(rows, list) or len(rows) != 1 or rows[0].get("state") != STATE:
        raise WorkerError("sprite-gen extraction did not produce the source_all row")
    return run_directory / "frames" / STATE


def process_subject_frames(
    subjects: Sequence[Image.Image],
    output_directory: Path,
    timing: Sequence[Mapping[str, Any]],
    *,
    sprite_gen_root: Path,
    base_image: Path,
    palette_lock: Path,
    fps: float,
    loop: bool,
) -> list[dict[str, Any]]:
    if len(subjects) != len(timing) or not subjects:
        raise WorkerError("cutout subjects and timing must be matching and non-empty")
    palette = load_palette_lock(palette_lock)
    with tempfile.TemporaryDirectory(prefix="niko-sprite-gen-") as temporary:
        temporary_root = Path(temporary)
        run_directory = temporary_root / "run"
        _prepare_run(
            run_directory,
            sprite_gen_root,
            base_image,
            palette_lock,
            len(subjects),
            fps,
            loop,
        )
        compose_chroma_strip(subjects, run_directory / "raw" / f"{STATE}.png")
        extracted = _extract_run(run_directory, sprite_gen_root)
        return install_extracted_frames(extracted, output_directory, timing, palette)


def load_worker_config(path: Path, palette_lock: Path, base_image: Path) -> dict[str, Any]:
    config_path = Path(path).resolve()
    try:
        config = json.loads(config_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise WorkerError(f"could not load PixelMotion config {config_path}: {exc}") from exc
    if not isinstance(config, dict) or not isinstance(config.get("sprite"), dict):
        raise WorkerError("PixelMotion config must contain a sprite object")
    palette = load_palette_lock(palette_lock)
    config["sprite"] = dict(config["sprite"])
    config["sprite"]["subjectBox"] = [208, 208]
    config["sprite"]["palette"] = [
        f"#{red:02X}{green:02X}{blue:02X}" for red, green, blue in palette
    ]
    config["sprite"]["pixelUnfake"] = {
        "engine": "sprite-gen/component-row",
        "logicalHeight": 64,
        "paletteSize": 32,
        "alignX": "alpha-centroid",
        "alignY": "bottom",
        "groundFrames": True,
        "baseSha256": _sha256(Path(base_image).resolve()),
        "paletteLockSha256": _sha256(Path(palette_lock).resolve()),
    }
    return config


def _load_pixelmotion(root: Path):
    pipeline_root = Path(root).resolve()
    package = pipeline_root / "pixelmotion2d" / "video_sprite_library.py"
    if not package.is_file():
        raise WorkerError(f"PixelMotion 2D library not found below: {pipeline_root}")
    sys.path.insert(0, str(pipeline_root))
    from pixelmotion2d import images as image_tools  # type: ignore
    from pixelmotion2d import video_sprite_library as library  # type: ignore

    return library, image_tools


def configure_pixelmotion(
    library: Any,
    image_tools: Any,
    *,
    sprite_gen_root: Path,
    base_image: Path,
    palette_lock: Path,
) -> None:
    original_build_manifest = library.build_manifest
    palette = load_palette_lock(palette_lock)
    palette_hash = _sha256(Path(palette_lock).resolve())
    prepare_hash = _sha256(_script(sprite_gen_root, "prepare_sprite_run.py"))
    extract_hash = _sha256(_script(sprite_gen_root, "extract_sprite_row_frames.py"))

    def process_decoded_frames(
        decoded_frames: Sequence[Path],
        output_directory: Path,
        config: Mapping[str, Any],
        timing: Sequence[Mapping[str, Any]],
    ) -> list[dict[str, Any]]:
        if not decoded_frames or len(decoded_frames) != len(timing):
            raise library.VideoSpriteError(
                "decoded frames and timing must be matching and non-empty"
            )
        subjects: list[Image.Image] = []
        try:
            for index, source_path in enumerate(decoded_frames, start=1):
                try:
                    with Image.open(source_path) as image:
                        subject, _receipt = image_tools.extract_subject(
                            image, dict(config["cutout"])
                        )
                except Exception as exc:
                    raise library.VideoSpriteError(
                        f"source frame {index} PixelMotion cutout failed: {exc}"
                    ) from exc
                subjects.append(subject)
            fps = 1000.0 / float(timing[0]["duration_ms"])
            try:
                return process_subject_frames(
                    subjects,
                    output_directory,
                    timing,
                    sprite_gen_root=sprite_gen_root,
                    base_image=base_image,
                    palette_lock=palette_lock,
                    fps=fps,
                    loop=True,
                )
            except WorkerError as exc:
                raise library.VideoSpriteError(str(exc)) from exc
        finally:
            for subject in subjects:
                subject.close()

    def build_manifest(*args: Any, **kwargs: Any) -> dict[str, Any]:
        processed_frames = kwargs.get("processed_frames")
        if processed_frames is None and len(args) >= 3:
            processed_frames = args[2]
        manifest = original_build_manifest(*args, **kwargs)
        manifest["pipeline_version"] = 2
        manifest["engine"] = "pixelmotion2d-cutout+sprite-gen-pixel-unfake"
        processing = manifest["processing"]
        processing.update(
            {
                "pixel_unfake": True,
                "pixel_unfake_engine": "sprite-gen/component-row",
                "logical_height": 64,
                "palette_size": 32,
                "align_x": "alpha-centroid",
                "align_y": "bottom",
                "ground_frames": True,
                "resample": "kcentroid+NEAREST-integer",
                "post_alignment": "4px-grid-alpha-centroid-translation",
                "sprite_gen_palette_lock_sha256": palette_hash,
                "sprite_gen_prepare_sha256": prepare_hash,
                "sprite_gen_extract_sha256": extract_hash,
            }
        )
        manifest_frames = manifest.get("source_frames")
        if isinstance(processed_frames, Sequence) and isinstance(manifest_frames, list):
            for source_frame, processed in zip(manifest_frames, processed_frames):
                if isinstance(source_frame, dict) and isinstance(processed, Mapping):
                    source_frame["alignment_shift_x"] = int(
                        processed.get("alignment_shift_x", 0)
                    )
                    intrusion = processed.get("safety_margin_intrusion")
                    if isinstance(intrusion, Mapping) and intrusion:
                        source_frame["safety_margin_intrusion"] = {
                            str(key): int(value) for key, value in intrusion.items()
                        }
        return manifest

    library.process_decoded_frames = process_decoded_frames
    library.build_manifest = build_manifest
    library.validate_clip_directory = lambda path: validate_installed_clip(path, palette)


def _add_roots(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--pixelmotion-root", required=True, type=Path)
    parser.add_argument("--sprite-gen-root", required=True, type=Path)
    parser.add_argument("--base-image", type=Path, default=DEFAULT_BASE_IMAGE)
    parser.add_argument("--palette-lock", type=Path, default=DEFAULT_PALETTE_LOCK)
    parser.add_argument("--ffprobe", default="ffprobe")


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Build full-frame Godot libraries with PixelMotion cutout and sprite-gen."
    )
    commands = parser.add_subparsers(dest="command", required=True)

    scan = commands.add_parser("scan")
    _add_roots(scan)
    scan.add_argument("--source-directory", required=True, type=Path)

    import_directory = commands.add_parser("import-directory")
    _add_roots(import_directory)
    import_directory.add_argument("--source-directory", required=True, type=Path)
    import_directory.add_argument("--output-directory", required=True, type=Path)
    import_directory.add_argument("--job-receipt", required=True, type=Path)
    import_directory.add_argument("--config", required=True, type=Path)
    import_directory.add_argument("--job-id")
    import_directory.add_argument("--force-generated", action="store_true")
    import_directory.add_argument("--replace-selection", action="store_true")

    import_video = commands.add_parser("import-video")
    _add_roots(import_video)
    import_video.add_argument("--source-video", required=True, type=Path)
    import_video.add_argument("--output-directory", required=True, type=Path)
    import_video.add_argument("--job-receipt", required=True, type=Path)
    import_video.add_argument("--config", required=True, type=Path)
    import_video.add_argument("--clip-id")
    import_video.add_argument("--job-id")
    import_video.add_argument("--force-generated", action="store_true")
    import_video.add_argument("--replace-selection", action="store_true")

    validate = commands.add_parser("validate")
    _add_roots(validate)
    validate.add_argument("--output-directory", required=True, type=Path)
    return parser


def _emit(value: Mapping[str, Any]) -> None:
    print(json.dumps(dict(value), ensure_ascii=False, separators=(",", ":")))


def main(argv: Sequence[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    try:
        library, image_tools = _load_pixelmotion(args.pixelmotion_root)
        if args.command == "scan":
            rows = library.scan_video_directory(args.source_directory, ffprobe=args.ffprobe)
            _emit(
                {
                    "videos": rows,
                    "video_count": len(rows),
                    "frame_count": sum(int(row["probe"]["frame_count"]) for row in rows),
                }
            )
            return 0
        if args.command == "validate":
            configure_pixelmotion(
                library,
                image_tools,
                sprite_gen_root=args.sprite_gen_root,
                base_image=args.base_image,
                palette_lock=args.palette_lock,
            )
            result = library.validate_library(args.output_directory)
            _emit(result)
            return 0 if result["valid"] else 1

        config = load_worker_config(args.config, args.palette_lock, args.base_image)
        configure_pixelmotion(
            library,
            image_tools,
            sprite_gen_root=args.sprite_gen_root,
            base_image=args.base_image,
            palette_lock=args.palette_lock,
        )
        if args.command == "import-directory":
            result = library.run_import_directory(
                args.source_directory,
                args.output_directory,
                args.job_receipt,
                config,
                job_id=args.job_id,
                force=args.force_generated,
                replace_selection=args.replace_selection,
                ffprobe=args.ffprobe,
            )
            _emit(result)
            return 0 if result["state"] in {"worker_complete", "complete_with_errors"} else 1
        result = library.run_import_video(
            args.source_video,
            args.output_directory,
            args.job_receipt,
            config,
            clip_id=args.clip_id,
            job_id=args.job_id,
            force=args.force_generated,
            replace_selection=args.replace_selection,
            ffprobe=args.ffprobe,
        )
        _emit(result)
        return 0 if result["state"] == "worker_complete" else 1
    except (WorkerError, OSError, ValueError) as exc:
        print(str(exc), file=sys.stderr)
        return 1
    except Exception as exc:
        video_error = getattr(locals().get("library"), "VideoSpriteError", None)
        if video_error is not None and isinstance(exc, video_error):
            print(str(exc), file=sys.stderr)
            return 1
        raise


if __name__ == "__main__":
    raise SystemExit(main())
