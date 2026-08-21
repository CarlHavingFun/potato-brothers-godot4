# Niko Video Sprite MCP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an MCP-driven, repeatable pipeline that converts every frame of every video under the Niko source directory into 256 x 256 Godot sprites and editable per-video `SpriteFrames` selections.

**Architecture:** A Python worker in the existing PixelMotion project owns video discovery, probing, cutout, normalization, atlas composition, manifests, QA, and atomic job receipts. Project-local Godot MCP commands launch and monitor that worker; a separate GDScript importer validates explicit manifest rectangles and creates immutable all-frame resources plus preserve-on-reimport selection resources.

**Tech Stack:** Python 3, Pillow, ffmpeg/ffprobe, existing `pixelmotion2d` image utilities, Godot 4.7.1 GDScript, GdUnit4, project-local `godot_mcp` commands.

**Spec:** `docs/superpowers/specs/2026-08-20-niko-video-sprite-mcp-design.md`

## Global Constraints

- Source directory `E:\01_gobro\MINIMAX_OK\niko` is read-only.
- Preserve Niko's current appearance; do not synthesize, interpolate, mix, or restyle frames.
- Every output frame is 256 x 256 with hard alpha, fixed Niko palette, root `(128, 232)`, nearest-neighbour resizing, and no more than 32 opaque RGB colours.
- Export every decoded frame as an individual PNG and into a 16-column atlas with explicit per-frame rectangles.
- Preserve exact source order, one-based frame number, timestamp, and duration.
- `degraded_static_fallback` is always `false`.
- Normal re-imports may regenerate `source_all_frames.tres` but must never overwrite an existing `selection.tres`.
- Godot output paths must remain below `res://tools/sprites`; reject absolute output paths and traversal.
- Do not modify `DirectionalSpriteManifestImporter`, player/content-pack resources, the existing single-state importer, or existing proof scenes.
- Use TDD for every production function: failing test, observed expected failure, minimal implementation, passing test, refactor while green.
- Preserve unrelated dirty-worktree changes in the original checkout.

---

## File Structure

### PixelMotion project (`E:\01_gobro\pixelmotion-2d-niko`)

- Create `pixelmotion2d/video_sprite_library.py`: discovery, ffprobe parsing, frame processing, atlas/manifest creation, QA, hash/receipt utilities, and atomic per-clip installation.
- Create `tools/build_video_sprite_library.py`: thin CLI with `scan`, `import-directory`, `import-video`, and `validate` subcommands.
- Create `tests/test_video_sprite_library.py`: unit and small ffmpeg-backed integration coverage.

### Godot feature worktree

- Create `tools/video_sprites/video_sprite_manifest_importer.gd`: manifest parsing/validation, `SpriteFrames` construction, source/selection save policy, and preview scene writing.
- Create `tools/video_sprites/video_sprite_library_cli.gd`: headless finalizer and validator used by tests and automation.
- Create `tools/video_sprites/video_sprite_preview.gd`: reusable preview behaviour and structural checks.
- Create `mcp_commands/video_sprite_commands.gd`: project-local MCP command group, path validation, worker process launch, job polling, and finalization.
- Create `tests/unit/test_video_sprite_manifest_importer.gd`: manifest and resource-builder tests.
- Create `tests/unit/test_video_sprite_mcp_commands.gd`: MCP parameter, containment, command registration, and receipt-state tests.
- Create `tools/video_sprites/README.md`: user-facing MCP and Godot selection workflow.

---

### Task 1: Python Video Discovery and Probe Contract

**Files:**
- Create: `E:\01_gobro\pixelmotion-2d-niko\pixelmotion2d\video_sprite_library.py`
- Create: `E:\01_gobro\pixelmotion-2d-niko\tests\test_video_sprite_library.py`

**Interfaces:**
- Produces: `scan_video_directory(root: Path, ffprobe: str = "ffprobe") -> list[dict[str, Any]]`
- Produces: `probe_video(path: Path, ffprobe: str = "ffprobe") -> dict[str, Any]`
- Produces: `derive_clip_id(root: Path, video: Path) -> str`
- Produces: `sha256_path(path: Path) -> str`

- [ ] **Step 1: Write failing discovery tests**

```python
class DiscoveryTests(unittest.TestCase):
    def test_scan_is_recursive_case_insensitive_and_source_order_is_stable(self):
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "walk").mkdir()
            (root / "walk" / "niko_walk_happy.MP4").write_bytes(b"happy")
            (root / "idle.webm").write_bytes(b"idle")
            (root / "ignore.txt").write_text("no", encoding="utf-8")
            rows = library.discover_video_paths(root)
            self.assertEqual(["idle.webm", "walk/niko_walk_happy.MP4"], [p.relative_to(root).as_posix() for p in rows])

    def test_duplicate_clip_ids_are_rejected(self):
        with self.assertRaisesRegex(library.VideoSpriteError, "clip ID collision"):
            library.ensure_unique_clip_ids([
                {"clip_id": "walk_happy", "relative_path": "a.mp4"},
                {"clip_id": "walk_happy", "relative_path": "b.mp4"},
            ])
```

- [ ] **Step 2: Run and verify RED**

Run:

```powershell
& 'C:\Users\18421\.codex\skills\sprite-gen\.venv\Scripts\python.exe' -m unittest tests.test_video_sprite_library.DiscoveryTests -v
```

Expected: import failure because `pixelmotion2d.video_sprite_library` does not exist.

- [ ] **Step 3: Implement discovery and stable IDs**

Implement extension filtering for `.mp4`, `.mov`, `.mkv`, `.webm`, and `.avi`, natural case-insensitive relative-path sorting, slug normalization, and collision rejection. For the current source tree, assert these exact IDs:

```python
CURRENT_CLIP_IDS = {
    "born/niko_born_00006_.mp4": "born_niko_born_00006",
    "die/die.mp4": "die_die",
    "die/niko_die.mp4": "die_niko_die",
    "happy_jump/MiniMax_H3_00026_.mp4": "happy_jump_minimax_h3_00026",
    "hit/niko_born_00015_.mp4": "hit_niko_born_00015",
    "idle/MiniMax_H3_00018_.mp4": "idle_minimax_h3_00018",
    "walk/niko_walk_happy.mp4": "walk_happy",
    "walk/niko_walk_power.mp4": "walk_power",
    "walk/niko_walk_strong.mp4": "walk_strong",
}
```

Use a general slug as the fallback and a small current-source alias mapping keyed by normalized relative path for the approved human-readable IDs.

- [ ] **Step 4: Add failing ffprobe parsing tests**

Test `_parse_probe_json()` with a 24/1 stream and three frames whose timestamps are `0`, `0.041667`, and `0.083333`; assert the exact rational, width/height, frame count, ordered timestamps, and derived final duration. Test missing video stream and missing timestamps as explicit errors.

- [ ] **Step 5: Implement probe and hash output**

Run ffprobe with JSON output for both stream metadata and frames. Return:

```python
{
    "width": 640,
    "height": 640,
    "fps": {"numerator": 24, "denominator": 1, "value": 24.0},
    "duration_seconds": 5.166667,
    "frame_count": 124,
    "frames": [{"source_frame": 1, "timestamp_seconds": 0.0, "duration_ms": 41.666667}],
}
```

- [ ] **Step 6: Run Python discovery tests GREEN**

Run the Task 1 test class and the existing `tests.test_inputs` suite. Expected: all pass.

- [ ] **Step 7: Commit the Godot plan checkpoint only**

The PixelMotion directory is not a Git repository. Record its absolute changed files in the Godot plan progress notes; do not fabricate a Git commit for it.

---

### Task 2: Python Full-Frame Processing, Atlas, Manifest, and QA

**Files:**
- Modify: `E:\01_gobro\pixelmotion-2d-niko\pixelmotion2d\video_sprite_library.py`
- Modify: `E:\01_gobro\pixelmotion-2d-niko\tests\test_video_sprite_library.py`

**Interfaces:**
- Consumes: `probe_video`, existing `materialize_frames`, `extract_subject`, `normalize_subject_frames`, and `assert_sprite_frame`.
- Produces: `process_clip(source: Path, clip_id: str, staging_dir: Path, config: dict[str, Any], probe: dict[str, Any]) -> dict[str, Any]`
- Produces: `compose_atlas(frames: Sequence[Path], output: Path, columns: int = 16) -> list[dict[str, int]]`
- Produces: `validate_clip_directory(path: Path) -> dict[str, Any]`

- [ ] **Step 1: Write failing 20-frame atlas test**

Generate twenty tiny synthetic 256 x 256 RGBA frames and assert:

```python
rects = library.compose_atlas(frames, atlas)
self.assertEqual((4096, 512), Image.open(atlas).size)
self.assertEqual({"x": 0, "y": 0, "w": 256, "h": 256}, rects[0])
self.assertEqual({"x": 768, "y": 256, "w": 256, "h": 256}, rects[19])
self.assertEqual((0, 0, 0, 0), Image.open(atlas).getpixel((4095, 511)))
```

- [ ] **Step 2: Run atlas test RED, then implement `compose_atlas`**

Use one transparent RGBA canvas, row-major paste, and explicit rectangles. Do not infer rectangles later from the grid.

- [ ] **Step 3: Write failing processing-contract tests**

Use two small white-shirt fixtures on an edge-connected grey background. Assert output count equals input count, each alpha is `{0,255}`, opaque colours are a subset of the fixed Niko palette, alpha bbox bottom is 232, foot-band median is within one pixel of x=128, and bbox remains within the 24-pixel safety boundary. Assert that an empty subject and a subject exceeding safety bounds fail with source-frame numbers.

- [ ] **Step 4: Implement `process_clip` with the approved PixelMotion path**

Load cutout and sprite settings from `characters/niko-walk.json`, but treat these values as locked invariants:

```python
assert sprite["frameSize"] == [256, 256]
assert sprite["rootAnchor"] == [128, 232]
assert len(sprite["palette"]) == 32
```

Decode every frame, extract the edge-connected subject, normalize the entire clip with one shared scale, run `assert_sprite_frame`, enforce the safety bbox, and retain a per-frame cutout/normalization receipt.

- [ ] **Step 5: Write failing manifest test**

Assert schema, source SHA-256, exact FPS rational, `degraded_static_fallback: false`, 256 x 256 cell, root, atlas dimensions, explicit rectangle count, and ordered source frame/timestamp/duration mappings. For 24 FPS, assert duration is approximately `41.666667` ms.

- [ ] **Step 6: Implement manifest and QA report**

Use this stable frame entry shape:

```python
{
    "index": 0,
    "source_frame": 1,
    "timestamp_seconds": 0.0,
    "duration_ms": 41.666667,
    "png": "frames/frame_001.png",
    "rect": {"x": 0, "y": 0, "w": 256, "h": 256},
}
```

Manifest state is `source_all`, has source nominal FPS and loop `true`, and carries the palette and processing-contract hashes. QA reports every frame; motion warnings never remove frames.

- [ ] **Step 7: Run Task 2 tests GREEN**

Run `tests.test_video_sprite_library` plus `tests.test_config_images`. Expected: all pass.

---

### Task 3: Python Batch CLI, Atomic Installation, and Job Receipts

**Files:**
- Create: `E:\01_gobro\pixelmotion-2d-niko\tools\build_video_sprite_library.py`
- Modify: `E:\01_gobro\pixelmotion-2d-niko\pixelmotion2d\video_sprite_library.py`
- Modify: `E:\01_gobro\pixelmotion-2d-niko\tests\test_video_sprite_library.py`

**Interfaces:**
- Produces CLI subcommands: `scan`, `import-directory`, `import-video`, `validate`.
- Produces: `run_import_directory(source_root, output_root, job_receipt, force=False) -> int`.
- Receipt states: `queued`, `running`, `worker_complete`, `complete_with_errors`, `failed`.

- [ ] **Step 1: Write failing CLI scan test**

Invoke `main(["scan", "--source-directory", ...])` with an injected probe callable and assert one JSON document on stdout with `videos` and collision-free IDs.

- [ ] **Step 2: Implement argparse subcommands and JSON-only stdout**

Diagnostic progress goes to stderr. Successful scan/import/validate output is machine-readable JSON.

- [ ] **Step 3: Write failing hash-skip and selection-preservation tests**

Create an installed manifest with matching source and contract hashes; assert the clip is skipped. Create `selection.tres` and `preview.tscn` sentinel files in a clip directory, replace generated frames/atlas/manifest, and assert both sentinels remain byte-for-byte unchanged.

- [ ] **Step 4: Implement staged clip swap**

Build outside the Godot project, fully validate, then replace only generated artifacts: `frames/`, `atlas.png`, `manifest.json`, and `qa-report.json`. Never write or delete `.tres`, `.tscn`, or user files. On failure, leave the prior installed clip intact.

- [ ] **Step 5: Write failing receipt tests**

Assert atomic JSON updates, per-clip success/failure, frame progress, and `complete_with_errors` when one clip succeeds and another fails.

- [ ] **Step 6: Implement receipts and independent clip failures**

Write receipts through a same-directory temporary file followed by `os.replace`. Include process ID, job ID, source/output roots, current clip, completed/total counts, and structured errors.

- [ ] **Step 7: Run the complete PixelMotion test suite**

```powershell
& 'C:\Users\18421\.codex\skills\sprite-gen\.venv\Scripts\python.exe' -m unittest discover -s tests -v
```

Expected: all tests pass.

---

### Task 4: Godot General Full-Frame Manifest Importer

**Files:**
- Create: `tools/video_sprites/video_sprite_manifest_importer.gd`
- Create: `tests/unit/test_video_sprite_manifest_importer.gd`

**Interfaces:**
- Produces: `parse_manifest_file(path: String) -> Dictionary`.
- Produces: `validate_manifest(manifest: Dictionary, manifest_path := "") -> PackedStringArray`.
- Produces: `build_sprite_frames(manifest: Dictionary, texture_loader := Callable()) -> Dictionary`.
- Produces: `install_clip(manifest_path: String, replace_selection := false) -> Dictionary`.

- [ ] **Step 1: Read `superpowers:test-driven-development/writing-good-tests.md` before editing tests**

- [ ] **Step 2: Write a failing valid-manifest GdUnit test**

Create a 20-frame fixture in memory with a 4096 x 512 fake texture. Assert `source_all`, 20 exact explicit regions, nominal 24 FPS, loop true, and duration multiplier `duration_ms / 1000.0 * 24.0`.

- [ ] **Step 3: Run the new suite RED**

```powershell
.\tools\run_tests.ps1 -GodotBinary 'E:\01_gobro\.codex-temp\godot-4.7.1-niko-proof\Godot_v4.7.1-stable_win64_console.exe' -TestPath res://tests/unit/test_video_sprite_manifest_importer.gd
```

Expected: preload failure because importer does not exist.

- [ ] **Step 4: Implement strict validation and build**

Reject missing/wrong atlas, missing state, empty frames, non-256 cell, bad root, missing or non-positive duration, duplicate/non-contiguous indices, out-of-bounds rectangles, missing individual PNGs, count mismatch, and `degraded_static_fallback: true`. Load only the declared atlas and create one `AtlasTexture` per declared rectangle.

- [ ] **Step 5: Add failing install-policy tests**

Use `res://reports/video_sprite_importer/preserve_selection` output paths. Assert source resource is overwritten, selection is created once, a sentinel edit survives normal re-import, and replacement occurs only with `replace_selection=true`.

- [ ] **Step 6: Implement `install_clip`**

Save `source_all_frames.tres` every time. Create selection animation named from `clip_id`, copying all source frames and timing. Preserve existing selection by default. Return explicit `created`, `updated`, `preserved`, and error arrays.

- [ ] **Step 7: Run importer suite GREEN and existing single-state importer regression**

Expected: both suites pass with zero errors/failures.

- [ ] **Step 8: Commit**

```powershell
git add tools/video_sprites/video_sprite_manifest_importer.gd tests/unit/test_video_sprite_manifest_importer.gd
git commit -m "feat: import full-frame video sprite manifests"
```

---

### Task 5: Preview and Headless Finalizer

**Files:**
- Create: `tools/video_sprites/video_sprite_preview.gd`
- Create: `tools/video_sprites/video_sprite_library_cli.gd`
- Modify: `tools/video_sprites/video_sprite_manifest_importer.gd`
- Modify: `tests/unit/test_video_sprite_manifest_importer.gd`

**Interfaces:**
- CLI example: `--manifest res://reports/video-sprite-fixture/manifest.json [--replace-selection] [--validate-only]`.
- Preview scene consumes sibling `selection.tres` and manifest root anchor.

- [ ] **Step 1: Write failing preview-source and CLI-argument tests**

Assert the generated scene has an `AnimatedSprite2D`, `texture_filter = 1`, checkerboard background, root guide, and references `selection.tres`. Assert missing/unknown CLI flags exit with non-zero status.

- [ ] **Step 2: Implement preview scene writer and reusable preview script**

Preview must show current selected animation, frame number, total frames, FPS, source clip ID, and the root baseline. It must run even after the user deletes/reorders frames.

- [ ] **Step 3: Implement CLI finalizer**

Parse arguments, call importer validation/install, print one JSON result, and use exit code 2 for arguments, 3 for validation/import, and 0 for success.

- [ ] **Step 4: Run headless finalizer fixture and scene load**

Use a temporary fixture below `res://reports/video-sprite-fixture`, import its atlas, generate resources, and launch its preview with `--quit-after 3`. Expected: exit 0 and no parser/resource errors.

- [ ] **Step 5: Commit**

```powershell
git add tools/video_sprites tests/unit/test_video_sprite_manifest_importer.gd
git commit -m "feat: add video sprite selection preview"
```

---

### Task 6: Project-Local MCP Command Group

**Files:**
- Create: `mcp_commands/video_sprite_commands.gd`
- Create: `tests/unit/test_video_sprite_mcp_commands.gd`

**Interfaces:**
- Produces commands: `video_sprites.scan_directory`, `video_sprites.import_directory`, `video_sprites.import_video`, `video_sprites.job_status`, `video_sprites.validate_library`.
- Import commands return `{job_id, pid, receipt_path, state}` immediately.

- [ ] **Step 1: Write failing command-registration and containment tests**

Assert `get_commands()` has exactly the five approved names. Assert output `res://tools/sprites/niko_video_library` is accepted while `res://content_packs`, `res://tools/sprites/../content_packs`, and absolute paths are rejected.

- [ ] **Step 2: Run MCP suite RED**

Expected: preload failure because the command file does not exist.

- [ ] **Step 3: Implement command docs, parameter validation, and executable resolution**

Resolve Python in this order: explicit `python_executable`, `PIXELMOTION2D_PYTHON`, the `.venv/Scripts/python.exe` below the resolved pipeline root, then PATH `python`. Resolve pipeline root from explicit parameter or `PIXELMOTION2D_ROOT`; for the current machine the invocation supplies `E:\01_gobro\pixelmotion-2d-niko` explicitly.

- [ ] **Step 4: Write failing launch/status tests with injected process and receipt readers**

Do not launch a real worker in unit tests. Inject callables and assert exact argument arrays, immediate job response, malformed/missing receipt errors, running progress, worker-complete finalization, and failed state passthrough.

- [ ] **Step 5: Implement asynchronous launch and polling**

Use `OS.create_process` for import commands. Store no global mutable job truth beyond job ID to receipt path mapping; the atomic receipt is authoritative. On first `worker_complete` poll, refresh the editor filesystem, finalize every successful clip with the GDScript importer, update the receipt to `complete` or `complete_with_errors`, and preserve selections.

- [ ] **Step 6: Test project command loading**

Run a Godot editor import and assert log output reports five project commands registered from `res://mcp_commands` without collisions.

- [ ] **Step 7: Commit**

```powershell
git add mcp_commands/video_sprite_commands.gd tests/unit/test_video_sprite_mcp_commands.gd
git commit -m "feat: expose video sprite pipeline through Godot MCP"
```

---

### Task 7: Documentation and Small End-to-End Fixture

**Files:**
- Create: `tools/video_sprites/README.md`
- Modify: `tests/unit/test_video_sprite_mcp_commands.gd`

**Interfaces:**
- Documents exact MCP calls, job polling, Godot selection workflow, re-import rules, and generated layout.

- [ ] **Step 1: Write README contract assertions**

Test that README contains all five command names, `selection.tres`, `source_all_frames.tres`, source 24 FPS versus selected FPS, and the non-overwrite warning.

- [ ] **Step 2: Write README with current absolute example paths**

Include a complete `video_sprites.import_directory` example using the current Niko source, PixelMotion root, Python executable, and default `res://tools/sprites/niko_video_library` output.

- [ ] **Step 3: Run a two-frame end-to-end fixture**

Generate a tiny local video with ffmpeg, invoke the Python CLI into a temporary Godot output directory, run the Godot finalizer, load both `.tres` resources, edit selection with a sentinel, re-import, and assert the sentinel remains.

- [ ] **Step 4: Run targeted Python and GdUnit suites GREEN**

Expected: zero failures and no leaked resources.

- [ ] **Step 5: Commit**

```powershell
git add tools/video_sprites/README.md tests/unit/test_video_sprite_mcp_commands.gd
git commit -m "docs: explain Godot video frame selection workflow"
```

---

### Task 8: Process the Nine Niko Videos and Final Verification

**Files:**
- Generate locally: the nine clip directories below `tools/sprites/niko_video_library/`, including `tools/sprites/niko_video_library/walk_happy/`.
- Do not automatically commit the 1,116 generated frame PNGs until size and Git policy are reviewed.

**Interfaces:**
- Consumes all completed commands and both import layers.
- Produces nine validated editable Godot clip libraries.

- [ ] **Step 1: Scan the real source directory**

Run the Python `scan` command and verify nine videos, 124 frames each, 1,116 total frames, 640 x 640, 24 FPS, and the approved clip IDs.

- [ ] **Step 2: Invoke the MCP batch import**

Use `video_sprites.import_directory` with explicit Python and pipeline roots. Poll `video_sprites.job_status` until terminal state, reporting progress at least once per minute.

- [ ] **Step 3: Validate generated visual assets**

Run Python validation and assert for every clip: 124 individual frames, 4096 x 2048 atlas, 124 explicit rectangles, hard alpha, fixed palette, no magenta, safe bounds, and root baseline.

- [ ] **Step 4: Import and validate Godot resources**

Run headless Godot import, `video_sprites.validate_library`, and load all nine source/selection resources and preview scenes. Assert each source animation has 124 frames with 24 FPS and 1.0 duration multipliers for the current CFR videos.

- [ ] **Step 5: Prove selection preservation**

Make a reversible edit to one test selection in the generated library, hash it, re-run import without replacement, and assert the hash is unchanged. Restore the selection using the explicit replacement path only after the preservation assertion is recorded.

- [ ] **Step 6: Run fresh full verification**

Run:

```powershell
& 'C:\Users\18421\.codex\skills\sprite-gen\.venv\Scripts\python.exe' -m unittest discover -s tests -v
.\tools\run_tests.ps1 -GodotBinary 'E:\01_gobro\.codex-temp\godot-4.7.1-niko-proof\Godot_v4.7.1-stable_win64_console.exe' -TestPath res://tests
git diff --check
git status --short
```

Expected: both complete suites pass; diff check is clean; original checkout's unrelated changes remain untouched.

- [ ] **Step 7: Review generated asset size and commit policy**

Commit code, tests, documentation, and small fixtures. If the generated nine-clip library is reasonably sized and intended for repository storage, commit it separately as `assets: add Niko full-frame curation library`; otherwise leave it local and document its absolute path and regeneration command.

- [ ] **Step 8: Final commit and push only with user authorization**

```powershell
git add docs/superpowers/plans/2026-08-20-niko-video-sprite-mcp.md mcp_commands/video_sprite_commands.gd tools/video_sprites tests/unit/test_video_sprite_manifest_importer.gd tests/unit/test_video_sprite_mcp_commands.gd
git commit -m "feat: add Niko full-frame video sprite MCP"
git push -u origin feat/niko-video-sprite-mcp
```
