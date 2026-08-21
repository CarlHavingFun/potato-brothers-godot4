# Task 1 — Shared external staging service report

## Result

Added `VideoSpriteJobService`, a reusable non-MCP Godot service for a single-video external-staging job. It confines output to `user://video_sprite_workspace`, records the owned PID in the receipt, exposes UI-ready dependency diagnostics, supports polling and safe cancellation, and is used by the existing MCP command wrapper without changing its `{ "result": ... }` response envelope. Directory import and installed-library finalization remain on their existing path.

## TDD evidence

### RED

```powershell
.\tools\run_tests.ps1 -GodotBinary E:\01_gobro\.tools\godot-4.7.1\Godot_v4.7.1-stable_win64_console.exe -TestPath res://tests/unit/test_video_sprite_job_service.gd -ReportDirectory res://reports/gdunit-task1-red
```

Observed expected RED: GdUnit discovery failed because `res://tools/video_sprites/video_sprite_job_service.gd` did not exist.

```powershell
.\tools\run_tests.ps1 -GodotBinary E:\01_gobro\.tools\godot-4.7.1\Godot_v4.7.1-stable_win64_console.exe -TestPath res://tests/unit/test_video_sprite_mcp_commands.gd -ReportDirectory res://reports/gdunit-task1-delegation-red
```

Observed expected RED: assigning the test service to `commands.video_service` failed because the command class did not expose an injectable delegated service.

### GREEN

```powershell
git diff --check
.\tools\run_tests.ps1 -GodotBinary E:\01_gobro\.tools\godot-4.7.1\Godot_v4.7.1-stable_win64_console.exe -TestPath res://tests/unit/test_video_sprite_job_service.gd -ReportDirectory res://reports/gdunit-task1-final-service
.\tools\run_tests.ps1 -GodotBinary E:\01_gobro\.tools\godot-4.7.1\Godot_v4.7.1-stable_win64_console.exe -TestPath res://tests/unit/test_video_sprite_mcp_commands.gd -ReportDirectory res://reports/gdunit-task1-final-mcp
py -3 tests\python\test_spritegen_video_worker.py
```

All commands exited `0`: 4/4 external-staging service GdUnit tests, 10/10 MCP compatibility GdUnit tests, and 12/12 Python worker tests. `git diff --check` reported no whitespace errors.

## Files changed

- `tools/video_sprites/video_sprite_job_service.gd` — reusable service, external containment, diagnostics, receipt tracking/polling, cancellation.
- `mcp_commands/video_sprite_commands.gd` — delegates single-video operations, polling, diagnostics, and cancellation to the service while retaining command response compatibility.
- `tests/unit/test_video_sprite_job_service.gd` — real service behavior coverage for containment, no `res://` output, diagnostics, polling, and PID-scoped cancellation.
- `tests/unit/test_video_sprite_mcp_commands.gd` — MCP delegation and response-shape coverage.
- `tests/python/test_spritegen_video_worker.py` — arbitrary positive frame-count compatibility coverage.
- `tools/video_sprites/README.md` — documents external staging and the added diagnostics/cancellation commands.

## Commit

`c3fbc44f779bc6bbbaf0f78a587b8b5fa7eb0398` — `feat: stage single-video imports outside project`

## Self-review

- Single-video jobs require an absolute staging directory under `user://video_sprite_workspace`; both project paths and arbitrary external paths are rejected before a worker launches.
- The worker receives that absolute staging output path and no single-video code invokes the legacy Godot importer/finalizer that writes SpriteFrames or previews under `res://`.
- Dependency status names and reports paths for Python, PixelMotion, sprite-gen, worker script, and ffprobe.
- Cancellation calls only the PID recorded for that job and writes a terminal `cancelled` receipt state only after termination succeeds.
- Existing directory import uses the legacy library path unchanged; existing checked-in library assets were not edited.

## Concerns

- Focused tests use injected launcher/terminator callables, as intended to avoid exercising real OS process creation/termination. A live PixelMotion/sprite-gen run is environment-dependent and was not run in this task.
