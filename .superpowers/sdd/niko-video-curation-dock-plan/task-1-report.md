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

## Fix Round 1

### Coverage added

- `tests/unit/test_video_sprite_job_service.gd`: sibling-prefix containment escape, terminal `worker_complete` PID reuse protection, receipt PID ownership mismatch, exited-worker failure normalization through injected liveness/exit-code callables, launch/receipt race preservation, dependency candidate/source/resolution diagnostics, and default external staging/config compatibility.
- `tests/unit/test_video_sprite_mcp_commands.gd`: typed MCP documentation for external staging, diagnostics, and cancellation.
- `tests/python/test_spritegen_video_worker.py`: worker-owned PID receipt publication.

### RED

```powershell
.\tools\run_tests.ps1 -GodotBinary E:\01_gobro\.tools\godot-4.7.1\Godot_v4.7.1-stable_win64_console.exe -TestPath res://tests/unit/test_video_sprite_job_service.gd -ReportDirectory res://reports/gdunit-task1-fix1-red
py -3 tests\python\test_spritegen_video_worker.py
```

```powershell
.\tools\run_tests.ps1 -GodotBinary E:\01_gobro\.tools\godot-4.7.1\Godot_v4.7.1-stable_win64_console.exe -TestPath res://tests/unit/test_video_sprite_job_service.gd -ReportDirectory res://reports/gdunit-task1-fix1-pid-red
```

The service RED failed at discovery because `poll_job` lacked the liveness/exit-code seam. The subsequent no-PID regression RED returned `queued` with an empty error instead of the required loud `failed` terminal state. The worker RED failed with `AttributeError: module 'spritegen_video_worker' has no attribute 'record_worker_pid'`.

### GREEN

```powershell
git diff --check
.\tools\run_tests.ps1 -GodotBinary E:\01_gobro\.tools\godot-4.7.1\Godot_v4.7.1-stable_win64_console.exe -TestPath res://tests/unit/test_video_sprite_job_service.gd -ReportDirectory res://reports/gdunit-task1-fix1-final-service
.\tools\run_tests.ps1 -GodotBinary E:\01_gobro\.tools\godot-4.7.1\Godot_v4.7.1-stable_win64_console.exe -TestPath res://tests/unit/test_video_sprite_mcp_commands.gd -ReportDirectory res://reports/gdunit-task1-fix1-final-mcp
py -3 tests\python\test_spritegen_video_worker.py
```

Final output: service 12/12, MCP 11/11, Python 13/13; all commands exit `0` and `git diff --check` is clean.

### Review fixes

- Terminal states now neutralize the tracked PID; `worker_complete` normalizes to `complete`, and cancellation reads/validates the receipt job ID before treating terminal jobs as non-cancellable or comparing a live PID.
- Cancellation compares the worker-published receipt PID to the tracked PID before termination. The Python worker records its own PID before it loads PixelMotion, and the Godot service never overwrites receipt state after launch.
- Staging uses a component boundary rather than a raw prefix and rejects existing link/reparse-point components below the staging root.
- Polling owns final state, writes a loud failed terminal receipt for exited or untracked workers, and accepts injected liveness/exit-code callables for safe tests.
- Dependency diagnostics retain candidates plus `source` and `resolution`; legacy workspace/settings/environment defaults and PATH ffprobe lookup are restored. Omitted staging and config select an external job-specific directory and the legacy PixelMotion config path.
- Typed MCP docs now distinguish single-video external staging from legacy `res://` directory output and publish the diagnostics/cancellation schemas.

## Fix Round 2

### Coverage added

- `tests/unit/test_video_sprite_job_service.gd`: cooperative cancellation request/token contract, root reparse-point detector seam, and stateful missing/corrupt receipt recovery with an atomically created failed fallback receipt.
- `tests/python/test_spritegen_video_worker.py`: resolved allowed-root containment, injected root-link detection, and worker cancellation receipt finalization.
- `tests/unit/test_video_sprite_mcp_commands.gd`: complete required/type/default contract for `source_video` and optional auto-created `staging_directory`.

### RED

```powershell
.\tools\run_tests.ps1 -GodotBinary E:\01_gobro\.tools\godot-4.7.1\Godot_v4.7.1-stable_win64_console.exe -TestPath res://tests/unit/test_video_sprite_job_service.gd -ReportDirectory res://reports/gdunit-task1-fix2-red-service
.\tools\run_tests.ps1 -GodotBinary E:\01_gobro\.tools\godot-4.7.1\Godot_v4.7.1-stable_win64_console.exe -TestPath res://tests/unit/test_video_sprite_mcp_commands.gd -ReportDirectory res://reports/gdunit-task1-fix2-red-mcp
py -3 tests\python\test_spritegen_video_worker.py
.\tools\run_tests.ps1 -GodotBinary E:\01_gobro\.tools\godot-4.7.1\Godot_v4.7.1-stable_win64_console.exe -TestPath res://tests/unit/test_video_sprite_job_service.gd -ReportDirectory res://reports/gdunit-task1-fix2-corrupt-red
```

Observed RED: service discovery reported that `validate_staging_directory` lacked the injected root-link detector; the MCP schema had no `staging_directory.default`; Python lacked the staging validator and `WorkerCancelled`; the corrupt-receipt regression did not create a failed fallback receipt.

### GREEN

```powershell
git diff --check
.\tools\run_tests.ps1 -GodotBinary E:\01_gobro\.tools\godot-4.7.1\Godot_v4.7.1-stable_win64_console.exe -TestPath res://tests/unit/test_video_sprite_job_service.gd -ReportDirectory res://reports/gdunit-task1-fix2-green-service
.\tools\run_tests.ps1 -GodotBinary E:\01_gobro\.tools\godot-4.7.1\Godot_v4.7.1-stable_win64_console.exe -TestPath res://tests/unit/test_video_sprite_mcp_commands.gd -ReportDirectory res://reports/gdunit-task1-fix2-green-mcp
py -3 tests\python\test_spritegen_video_worker.py
```

Final output: service 16/16, MCP 11/11, Python 16/16; all commands exited `0` and `git diff --check` was clean.

### Review fixes

- `cancel_job` no longer calls a terminator or `OS.kill`. It atomically creates a request scoped to the job directory, `job_id`, and random job token; the worker validates that request at startup and before/after its main stages, atomically writes `cancelled`, and polling returns the terminal state.
- Single-video worker invocation now receives the allowed staging root and project root. Both Godot and Python reject root/component links (including junction/reparse detectors), resolved containment escapes, and project-root output before processing or rechecking before import writes.
- Polling turns missing/corrupt receipts into a stateful `running` response while the tracked process is live, or a persisted terminal `failed` receipt with cleared PID after exit. Corrupt receipts retain forensic evidence while an atomic `.failed.json` fallback becomes the tracked receipt.
- MCP documentation now publishes `staging_directory` as optional `String` with an explicit unique-job-directory default, and README describes the same cooperative cancellation and optional staging contract.

### Self-review and concerns

- No production path uses PID termination. Cooperative cancellation is intentionally delayed until the worker reaches a checkpoint; it cannot interrupt an opaque PixelMotion call mid-function, but it cannot kill an unrelated reused PID.
- Windows junction behavior is covered through the Godot and Python detector seams; the focused test suite does not create a real privileged junction.
