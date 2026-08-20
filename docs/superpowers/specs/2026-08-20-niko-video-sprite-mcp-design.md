# Niko Video Sprite MCP and Godot Full-Frame Curation Design

**Date:** 2026-08-20

**Status:** Approved architecture; implementation pending

**Owners:** Niko video pipeline and Potato Brothers Godot project

## 1. Objective

Create a repeatable MCP-driven pipeline that recursively scans the videos below
`E:\01_gobro\MINIMAX_OK\niko`, extracts every source frame, converts each frame
to a Godot-ready Niko pixel sprite, and installs a per-video sprite library into
the Potato Brothers Godot project.

The user must be able to open a generated `selection.tres` in Godot's built-in
`SpriteFrames` editor, view all source frames, delete unwanted frames, reorder
the remainder, and choose the final playback rate and loop mode without using a
separate curation UI.

This is a source-curation workflow. It does not claim that any video is already
a production-ready action, and it does not install incomplete clips into the
formal eight-direction Niko character resources.

## 2. Confirmed Product Decisions

- Preserve Niko's current appearance and identity.
- Match the Potato Brothers player presentation scale, pixel density, and foot
  anchor; do not redraw Niko into a different art style.
- Use all decoded video frames. Do not uniformly sample, synthesize in-between
  frames, mix videos, or silently substitute another take.
- Use Godot's built-in `SpriteFrames` editor for final human frame selection.
- Export both individual transparent PNG frames and a Godot atlas.
- Extend the project's existing `godot_mcp` through project-local commands in
  `res://mcp_commands`; do not fork the addon or create a second MCP server.
- Keep generated source resources separate from editable selection resources so
  a re-import cannot erase human curation.

## 3. Existing Inputs and Measured Baseline

The current source tree contains nine MP4 files:

| Clip ID | Source path relative to the Niko root |
| --- | --- |
| `born_niko_born_00006` | `born/niko_born_00006_.mp4` |
| `die_die` | `die/die.mp4` |
| `die_niko_die` | `die/niko_die.mp4` |
| `happy_jump_minimax_h3_00026` | `happy_jump/MiniMax_H3_00026_.mp4` |
| `hit_niko_born_00015` | `hit/niko_born_00015_.mp4` |
| `idle_minimax_h3_00018` | `idle/MiniMax_H3_00018_.mp4` |
| `walk_happy` | `walk/niko_walk_happy.mp4` |
| `walk_power` | `walk/niko_walk_power.mp4` |
| `walk_strong` | `walk/niko_walk_strong.mp4` |

All nine currently probe as 640 x 640, 24 FPS, 124 decoded frames, and
5.166667 seconds. The pipeline must still trust probe results rather than
hard-coding those values so future videos can differ.

The existing Potato Brothers player textures are 150 x 150, with visible
character heights around 129-140 pixels, and are displayed below a `Visuals`
node scaled to 0.5. Their effective world height is therefore about 65-70
pixels. The existing Niko directional import contract uses 256 x 256 cells,
pivot `(128, 232)`, nearest-neighbour sampling, and an additional presentation
scale. Its effective player height is compatible with that range. The new
library therefore reuses the Niko 256 x 256 contract rather than installing
640 x 640 video cutouts directly.

## 4. Architecture

The system has three layers:

1. **Project-local MCP adapter (Godot/GDScript)**
   Exposes narrowly scoped commands through the already enabled `godot_mcp`
   command router. It validates parameters, starts or polls background jobs,
   refreshes the Godot filesystem after a completed install, and returns
   structured JSON results.

2. **Video sprite worker (Python/PixelMotion)**
   Performs probing, frame decoding, safe background removal, normalization,
   palette application, individual-frame export, atlas composition, manifest
   writing, QA, and job receipt writing. Image work remains in Python so the
   existing PixelMotion algorithms are reused and testable outside Godot.

3. **Godot manifest importer (GDScript)**
   Treats the manifest as the source of truth for atlas rectangles and frame
   durations. It creates or refreshes the immutable `source_all_frames.tres`
   and creates `selection.tres` only when that editable resource does not yet
   exist.

The formal `DirectionalSpriteManifestImporter` remains unchanged because it
requires the complete production action/direction contract. The existing
single-state happy-walk proof importer also remains unchanged.

### 4.1 Planned File Ownership

New pipeline code is isolated to new paths:

```text
potato-brothers-godot4/
  mcp_commands/video_sprite_commands.gd
  tools/video_sprites/
    video_sprite_manifest_importer.gd
    video_sprite_library_cli.gd
    README.md
  tests/unit/
    test_video_sprite_manifest_importer.gd
    test_video_sprite_mcp_commands.gd

pixelmotion-2d-niko/
  tools/build_video_sprite_library.py
  tests/test_video_sprite_library.py
```

Generated Godot assets are isolated below:

```text
res://tools/sprites/niko_video_library/<clip_id>/
```

No existing player scene, content pack, skin, formal Niko importer, or existing
proof scene is modified by this feature.

## 5. MCP Contract

Project-local methods use the `video_sprites` group. The HTTP MCP layer exposes
typed names with dots converted to underscores, consistent with the existing
addon.

### 5.1 `video_sprites.scan_directory`

Inputs:

- `source_directory` (required absolute path)
- `recursive` (optional, default `true`)

Behaviour:

- Accept `.mp4`, `.mov`, `.mkv`, and `.webm`, case-insensitively.
- Never write to the source directory.
- Probe every candidate with ffprobe.
- Derive a stable, lowercase clip ID from the relative parent path and filename.
- Detect and report clip-ID collisions instead of silently renaming them.

Result includes the relative path, absolute source path, SHA-256, dimensions,
rate as numerator/denominator, duration, decoded frame count, and proposed clip
ID for every video.

### 5.2 `video_sprites.import_directory`

Inputs:

- `source_directory` (required absolute path)
- `output_directory` (optional; defaults to the Niko library `res://` path)
- `force_generated` (optional, default `false`)
- `replace_selection` (optional, default `false` and rejected unless explicitly
  true)

Behaviour:

- Resolves `output_directory` to a canonical `res://` path and requires it to
  remain below `res://tools/sprites`; absolute filesystem outputs, `..`
  traversal, and writes outside that subtree are rejected.
- Starts a background worker and returns a job ID immediately so the Godot
  editor is not frozen while up to 1,116 frames are processed.
- Skips clips whose source hash and processing-contract hash match the installed
  manifest unless `force_generated` is true.
- Processes clips independently and reports per-clip success or failure.
- Never overwrites `selection.tres` by default.

### 5.3 `video_sprites.import_video`

Uses the same processing contract for one absolute video path. This supports
incremental additions and retrying a failed clip without rebuilding the full
library.

### 5.4 `video_sprites.job_status`

Returns state (`queued`, `running`, `finalizing`, `complete`, `failed`), current
clip, completed/total clip and frame counts, warnings, per-clip results, and
error details. Once the worker succeeds, finalization refreshes Godot's imported
textures and generates `SpriteFrames` resources from the manifests.

### 5.5 `video_sprites.validate_library`

Performs read-only validation of installed manifests, images, atlases, source
resources, and editable selections. It never repairs or rewrites resources.

## 6. Frame Processing Contract

For every decoded frame:

1. Decode in source presentation order and retain a one-based decoded frame
   number, source timestamp, and source rate.
2. Remove the edge-connected background using the existing PixelMotion subject
   extraction path. Do not use rembg because it can remove Niko's white shirt.
3. Normalize the subject into a 256 x 256 transparent cell with:
   - 24-pixel safe margin;
   - root anchor `(128, 232)`;
   - horizontal alpha-centroid alignment;
   - foot/bottom alignment;
   - nearest-neighbour integer pixel scaling;
   - hard alpha values only (0 or 255).
4. Apply the locked Niko palette from the approved happy-walk proof, with no
   dithering and no more than 32 non-transparent RGB colours. The palette lock
   hash becomes part of the processing-contract hash.
5. Preserve content rather than force a pass: if the subject exceeds the safe
   region, background extraction fails, or no subject is found, mark that clip
   failed with the offending source frame numbers.

There is no motion-quality rejection at this stage because all frames are being
exported specifically for human selection. Motion metrics may be reported as
warnings but must not remove frames.

## 7. Output Contract

Each installed clip has this layout:

```text
<clip_id>/
  frames/
    frame_001.png
    frame_002.png
    ...
  atlas.png
  manifest.json
  qa-report.json
  source_all_frames.tres
  selection.tres
  preview.tscn
```

### 7.1 Individual Frames

- Exactly one 256 x 256 transparent PNG for every decoded source frame.
- Filenames are zero-padded to at least three digits and remain stable across
  re-imports with the same decoded ordering.
- Manifest entries retain source frame number and timestamp, so no frame can
  disappear without validation detecting it.

### 7.2 Atlas

- Fixed 16-column row-major layout.
- Width is `16 * 256 = 4096` pixels.
- Height is `ceil(frame_count / 16) * 256`; 124 frames produce 8 rows and a
  4096 x 2048 atlas with four unused transparent cells.
- The manifest contains an explicit `Rect2`-equivalent rectangle for every
  frame. Consumers must not infer rectangles solely from the grid.
- Godot imports the texture with nearest-neighbour filtering and no filtering
  override that would blur pixels.

### 7.3 Manifest

The manifest is JSON and includes:

- schema and pipeline versions;
- source absolute path, relative path, SHA-256, dimensions, duration, frame
  count, and exact source FPS rational;
- processing-contract hash and palette-lock hash;
- 256 x 256 cell size, safe margin, root anchor, and atlas dimensions;
- `degraded_static_fallback: false`;
- a single source state containing loop default, FPS, and ordered frames;
- per-frame index, source frame number, timestamp, duration in milliseconds,
  individual PNG path, and explicit atlas rectangle;
- QA summary and receipt path.

Durations are derived from the source time base. For the current 24 FPS videos,
each normal frame is represented as approximately 41.666667 milliseconds, not
rounded to 100 milliseconds. A future variable-frame-rate source must preserve
its probed timestamps and per-frame durations.

Godot's `SpriteFrames.add_frame()` duration value is a multiplier relative to
the animation FPS, not an absolute number of milliseconds. The importer sets
the animation's nominal source FPS, then converts each manifest duration with
`duration_multiplier = duration_seconds * animation_fps`. Current constant
24 FPS clips therefore use a multiplier of `1.0` per frame, while future
variable-duration frames retain their actual timing.

### 7.4 Godot Resources

`source_all_frames.tres` contains one looping animation named `source_all` with
all manifest frames in source order. It is regenerated when source or processing
hashes change.

`selection.tres` is initially created with one animation named from the clip ID
and all source frames in order. The user edits this resource with the built-in
`SpriteFrames` editor by deleting and reordering frames, changing FPS/loop, and
optionally renaming the animation to a runtime state such as `walk_down`.

`selection.tres` is never overwritten by a normal re-import. If the source
contract later changes, validation reports it as potentially stale. Explicit
replacement requires `replace_selection: true` and is surfaced as a destructive
operation in the MCP result.

Both resources use one `AtlasTexture` per frame and the exact manifest region.
The preview scene displays `selection.tres` using `AnimatedSprite2D`, nearest
filtering, a checkerboard background, and a visible ground/root guide.

## 8. Job, Staging, and Failure Semantics

- Source videos are always read-only.
- The worker writes each clip into a task-specific staging directory first.
- A clip is installed only after all of its frames, atlas, manifest, and QA
  report pass validation.
- Generated files are replaced clip-by-clip; a failed clip leaves its previous
  valid installation intact.
- Job receipts are JSON and updated atomically so `job_status` never reads a
  partially written document.
- Individual clip errors do not cancel unrelated clips. The overall job result
  is `complete_with_errors` when at least one clip succeeds and at least one
  fails.
- Missing Python, ffmpeg, ffprobe, Pillow, PixelMotion modules, or Godot import
  failures produce explicit actionable errors; there is no silent fallback.

## 9. Godot Selection Workflow

1. Invoke `video_sprites.import_directory` for the Niko source root.
2. Poll `video_sprites.job_status` until completion.
3. In Godot, open a clip's `selection.tres`.
4. Select and delete unwanted frames in the `SpriteFrames` editor.
5. Drag frames into the desired order.
6. Set playback speed and loop mode; for example, a curated walk may use 10 FPS
   even though its candidate pool was decoded at 24 FPS.
7. Rename the animation when ready for an isolated proof scene or a later formal
   action import.

The full source resource and individual PNGs remain available for recovery or a
different selection.

## 10. Validation and Test Strategy

### 10.1 Python Unit and Integration Tests

- Recursive extension filtering and stable clip-ID generation.
- Collision rejection.
- ffprobe rational-rate and timestamp parsing.
- Exact decoded frame count and stable source mapping.
- Edge-connected cutout preservation for white clothing.
- Hard-alpha, 256 x 256 size, safe bounds, root baseline, fixed palette, and
  colour-count checks.
- 16-column atlas dimensions, transparent unused cells, explicit rectangles,
  and rectangle bounds.
- Hash-based skip and changed-source rebuild.
- Atomic receipts and partial-job error reporting.

### 10.2 GdUnit Tests

- Valid manifest creates every `AtlasTexture` with the declared region and
  duration.
- Missing atlas, missing frame paths, missing state, empty frame list, wrong
  cell size, rectangle overflow, missing duration, duplicate indices, and
  `degraded_static_fallback: true` are rejected.
- Source resource regeneration works.
- Existing `selection.tres` is preserved by default.
- Explicit selection replacement works only with the destructive flag.
- MCP input paths and output containment are validated.

### 10.3 End-to-End Verification

- Probe the nine current videos and confirm 1,116 source frames in total.
- Import all generated PNGs in headless Godot.
- Load every generated manifest, `source_all_frames.tres`, `selection.tres`, and
  preview scene without parser or resource errors.
- Confirm 124 ordered frames for each current `source_all` animation.
- Confirm nearest-neighbour rendering and root placement in the preview.
- Re-run the import and prove that manually modified selections are unchanged.
- Review repository diffs and ensure all unrelated dirty-worktree changes remain
  untouched.

## 11. Non-Goals

- Automatic selection of the best walk cycle.
- Automatic promotion into the formal eight-direction player character.
- Fabricating missing directions or action poses.
- Retargeting, skeletal animation, or mixing `happy`, `power`, and `strong`.
- Lowering existing gait or production QA thresholds.
- Replacing the existing browser curation tool; both workflows may coexist.

## 12. Acceptance Criteria

The feature is accepted when:

- all nine current videos can be discovered and processed through the project
  MCP without modifying the source directory;
- every current clip exports exactly 124 single frames and an explicit-rectangle
  4096 x 2048 atlas;
- every processed frame is 256 x 256, hard-alpha, palette-locked, bottom-aligned
  to `(128, 232)`, and visually sized for the Potato Brothers player scale;
- Godot can load each all-frame and selection resource with 124 correctly timed
  atlas frames;
- the user can delete and reorder frames in the built-in `SpriteFrames` editor;
- a re-import refreshes generated source artifacts without overwriting an edited
  selection;
- all targeted Python, GdUnit, headless import, and library validation checks
  pass; and
- no formal Niko character resources or unrelated user changes are overwritten.
