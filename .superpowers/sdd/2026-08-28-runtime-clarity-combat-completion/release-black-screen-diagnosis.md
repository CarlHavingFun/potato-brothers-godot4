# GOGOBRO exported release black-screen diagnosis

Date: 2026-08-28 (Asia/Shanghai)

Scope began as diagnosis-only. After the parent independently confirmed the root cause, it authorized the minimal TDD repair and release-smoke regression recorded below. Only GOGOBRO release executables and the Godot console executable were launched. Brotato, Steam, and their save data were not opened or touched.

## Verdict

The Task 6 release was not stuck in a renderer-level black screen. It successfully created a responsive 1280x720 window, loaded `res://game/app/app_root.tscn`, and deliberately routed to the dark `启动诊断` screen. The boot failure was `内容包注册失败` for `character.niko`.

There is one causal defect:

`GogoCharacterAttachmentRig._load_data()` validates an imported texture path with `FileAccess.file_exists()`. In a native/editor run, the source PNG physically exists and this returns `true`. In the exported PCK, Godot stores the texture as `.png.import` plus an imported `.ctex`; the logical PNG remains loadable through `ResourceLoader`, but is not a raw `FileAccess` file. The release-only false negative invalidates the Niko rig, then the character definition, then the whole `character.niko` content pack, and boot returns before the static runtime manifest is staged.

The dark diagnostic UI and missing default logging made the failure easy to describe as a pure black screen, but they were observability consequences, not separate root causes.

The authorized repair now uses `ResourceLoader.exists(path, "Texture2D")` for runtime existence while retaining exact raw PNG SHA-256 validation whenever the source file is physically visible. A newly exported release boots to the actual main menu in both an automated mounted-PCK check and a real windowed run, with zero `ERROR:`/`SCRIPT ERROR:` lines.

## Exact artifact identity

The artifact under test was not rebuilt or substituted:

| File | Size | SHA-256 | Timestamp |
| --- | ---: | --- | --- |
| `builds/task6-release-proof/GOGOBRO.exe` | 109,071,360 bytes | `04BAF75CC1D69DD93EB709533ECAB4FD7770BB8A530645717017A06A9D9809FC` | 2026-08-28 06:50:49 |
| `builds/task6-release-proof/GOGOBRO.pck` | 1,839,576 bytes | `BFD6A02ED0EDF113D4BAC36C6276085719105C6562BAA371AD6657D811BDFEBC` | 2026-08-28 06:50:50 |
| `builds/task6-release-proof/export.log` | 79,738 bytes | `8775EAB9C6AD418743F227BA1C2DF3E229CE0E8D5DD2DF137A07DDA217BE4FAD` | 2026-08-28 06:50:50 |

The executable is unsigned x86-64 PE32+ with Windows GUI subsystem (`Subsystem=2`). The release folder has only `GOGOBRO.exe`, `GOGOBRO.pck`, and `export.log`; it has no console-wrapper executable.

## Reproduction evidence

The exact release was launched with isolated `APPDATA`, `LOCALAPPDATA`, and `USERPROFILE`, with stdout, stderr, and `--log-file` captured. After eight seconds:

- PID `22012` was alive, responsive, and owned the uniquely identified `GOGOBRO` window.
- The window was 1282x752 including chrome and the game content was 1280x720.
- The rendered page said `启动诊断`, `内容包注册失败`, and `character.niko`.
- The only runtime error was:

```text
ERROR: Niko attachment rig is invalid: atlas.path must reference an existing file
   at: push_error (core/variant/variant_utility.cpp:1023)
```

The process was stopped after capture and no process for this exact artifact remained.

Primary evidence:

- `reports/release-black-screen-diagnosis/existing-artifact-20260828-080311/window.png` — SHA-256 `B1EF1ACF4299FA5323282E1E3BE794F4726A66E120C0392D303CFE38E58EC6F3`
- `reports/release-black-screen-diagnosis/existing-artifact-20260828-080311/godot-runtime.log` — SHA-256 `69B39D6DFE0118D81C435A424694741F86CC390BC956FE24ACAC367144B118BA`
- `reports/release-black-screen-diagnosis/existing-artifact-20260828-080311/stdout.log` — SHA-256 `8CC089D17EC5B213B4A76924E4EFC603370870E4DD50CDBF300958167E8CFFFE`
- `reports/release-black-screen-diagnosis/existing-artifact-20260828-080311/stderr.log` — SHA-256 `747C2867F524C780EFD07AA4AD7171F297892BBD840679D798B7C9FDF98A5123`

## Causal chain

1. `project.godot:14` sets `run/main_scene="res://game/app/app_root.tscn"`. The release log confirms that its remapped exported scene and compiled `app_root.gdc` load successfully. The main scene is not the fault.
2. `game/app/app_root.gd:24-28` calls `boot()` and routes either to main menu or diagnostic. The captured diagnostic page proves the latter path is executing intentionally.
3. `game/app/app_kernel.gd:43-50` calls `ValidationContentFactory.create_packs(OS.is_debug_build())`, installs each pack, and returns `内容包注册失败` with the pack ID on the first invalid pack.
4. `game/content/validation_content_factory.gd:18-27` includes the Niko pack in both debug and release. The boolean only controls the development-preview tag/overlay; it does not remove Niko from release.
5. `game/content/packs/characters/niko/niko_content_factory.gd:31-34` loads the rig JSON and emits the exact observed error when the rig is invalid.
6. The rig JSON declares `res://game/content/packs/characters/niko/animations/walk_down/sprite-sheet-alpha.png`, whose source bytes have the expected SHA-256 `FBC10108D9A665B14DCC376DA54BBBF66D89B931AE1189E69FE1C45B31FE579D`.
7. `game/content/character_attachment_rig.gd:213-219` requires `FileAccess.file_exists(character_atlas_path)` and hashes raw PNG bytes when present. That assumption is valid in the source tree but not for an imported texture in an exported PCK.
8. `CharacterDefinition.is_valid()` rejects the invalid rig, and `ContentPackCatalog.install()` returns `ERR_INVALID_DATA`. `AppKernel.boot()` therefore returns at line 50.
9. Static runtime staging is at `game/app/app_kernel.gd:62-63`; it is never reached. The shipping static manifest is not the cause of this startup failure.

## Native versus exported resource semantics

An isolated Godot probe mounted the exact Task 6 PCK and tested the declared atlas path without modifying the PCK:

```text
PCK_MOUNTED=true
PATH=res://game/content/packs/characters/niko/animations/walk_down/sprite-sheet-alpha.png FILE=false RESOURCE=true
PATH=res://game/content/packs/characters/niko/animations/walk_down/sprite-sheet-alpha.png.import FILE=true RESOURCE=false
PATH=res://.godot/imported/sprite-sheet-alpha.png-d6ba65310c663a382a8d2fc29dd4fd04.ctex FILE=true RESOURCE=true
PATH=res://game/content/packs/characters/niko/rig/niko_attachment_rig_v2.json FILE=true RESOURCE=true
PATH=res://game/content/packs/characters/niko/niko_animations.tres FILE=false RESOURCE=true
ATLAS_FILE_SHA256=
ATLAS_RESOURCE_LOADED=true
ATLAS_RESOURCE_SIZE=(1024.0, 128.0)
```

The equivalent native/editor probe produced:

```text
DEBUG_BUILD=true
FEATURE_EDITOR=true
FEATURE_GOGOBRO_V2=false
PATH=res://game/content/packs/characters/niko/animations/walk_down/sprite-sheet-alpha.png FILE=true RESOURCE=true
ATLAS_FILE_SHA256=fbc10108d9a665b14dcc376da54bbbf66d89b931ae1189e69fe1c45b31fe579d
ATLAS_RESOURCE_LOADED=true
ATLAS_RESOURCE_SIZE=(1024.0, 128.0)
```

A native headless main-scene run then loaded the main menu and exited 0 with no Niko/content error. This isolates the difference to raw-file versus imported-resource visibility, not the texture data, geometry, renderer, route table, or main scene.

Probe sources and logs:

- `reports/release-black-screen-diagnosis/probe/probe.gd`
- `reports/release-black-screen-diagnosis/probe/project.godot`
- `reports/release-black-screen-diagnosis/native_probe.gd`
- `reports/release-black-screen-diagnosis/native-comparison/native-probe.log`
- `reports/release-black-screen-diagnosis/native-comparison/native-main.log`
- `reports/release-black-screen-diagnosis/native-comparison/native-main-console.log`

## Export and feature-gate findings

- `export_presets.cfg` uses the `Windows Desktop` release preset, `export_filter="all_resources"`, custom feature `gogobro_v2`, external PCK, and `script_export_mode=2`.
- `export.log` shows successful release bytecode/resource packing and no export error. Its only warnings concern missing `.uid` files for unrelated scripts.
- The required atlas is included correctly as an imported Godot resource. The PCK contains the `.png.import`, imported `.ctex`, rig JSON, compiled factory, and remapped `SpriteFrames` resource. Requiring the raw source PNG through `FileAccess` is the incompatible part.
- `OS.is_debug_build()` changes only development-preview behavior in `AppKernel`; the Niko pack and rig validation run in both modes. `gogobro_v2` is not consulted in this failure path.

## Why normal release logs appeared silent

- The executable uses the Windows GUI subsystem, so a normal double-click has no attached console for stdout/stderr.
- The release directory contains no console wrapper.
- `project.godot` sets `debug/file_logging/enable_file_logging.pc=false`.
- `GogoLogService` creates its directory but has no callers or boot/error signal connection, so no `game.log` was produced for this failure.
- Passing `--log-file` or redirecting the process streams exposes the error immediately; it was not absent, only normally invisible.

## Applied minimal repair

At `game/content/character_attachment_rig.gd:213`, imported-resource existence now defines the runtime texture contract:

```gdscript
if character_atlas_path.is_empty() or not ResourceLoader.exists(character_atlas_path, "Texture2D"):
	_validation_errors.append("atlas.path must reference an existing texture resource")
```

The existing raw-byte SHA-256 check at lines 217-219 remains conditional on `FileAccess.file_exists()`. In editor/source validation it continues to verify the exact PNG bytes. In export, the existing `_validate_atlas_geometry()` path at lines 478-486 uses `ResourceLoader`, loads the imported texture, and verifies its 1024x128 dimensions. If release-time pixel integrity must become equivalent to source-byte integrity, a future change should add a declared decoded RGBA8 hash and verify `Texture2D.get_image()` as the static-asset service already does; the shipping PCK should not carry an otherwise unnecessary raw source PNG.

The regression implementation is:

1. `tools/release_smoke/inspect_gogobro_pck.gd` mounts a real exported PCK and asserts the exact export semantics: logical atlas `FileAccess=false`, `ResourceLoader=true`, 1024x128 texture load, valid rig, valid Niko pack, actual AppRoot route `main_menu`, and `MainMenuScreen` rather than `Diagnostic`.
2. `tools/check_exported_release.ps1` isolates `APPDATA`, `LOCALAPPDATA`, and `USERPROFILE`, runs the PCK inspector, launches the real exported EXE headlessly, and fails on nonzero exit, timeout, `ERROR:`, `SCRIPT ERROR:`, or a diagnostic marker.
3. Existing native rig byte-hash, sprite-frame geometry, and attachment-socket tests remain unchanged.

## TDD RED/GREEN record

RED used the original Task 6 PCK before production modification. The new inspector failed exactly as intended:

```text
ERROR: Niko attachment rig is invalid: atlas.path must reference an existing file
GOGOBRO_RELEASE_DIAGNOSTIC: Niko attachment rig is valid in the exported PCK
GOGOBRO_RELEASE_DIAGNOSTIC: Niko content pack is valid in the exported PCK
GOGOBRO_RELEASE_DIAGNOSTIC: exported app boots to main_menu, not diagnostic
GOGOBRO_RELEASE_DIAGNOSTIC: exported app displays MainMenuScreen
```

RED evidence: `reports/release-black-screen-diagnosis/tdd-red/pck-inspector.log`.

After the one-line production repair and a fresh export, GREEN produced:

```text
GOGOBRO_RELEASE_PCK_SMOKE_OK route=main_menu atlas=imported_resource niko_pack=valid
GOGOBRO_EXPORTED_RELEASE_SMOKE_OK pck=valid route=main_menu runtime_errors=0
```

This is a real PCK/compiled-script/AppRoot test, not a mock or source-text assertion.

## Final independent release proof

Fresh artifacts under `reports/release-black-screen-diagnosis/final-proof/`:

| File | Size | SHA-256 |
| --- | ---: | --- |
| `GOGOBRO.exe` | 109,071,360 bytes | `04BAF75CC1D69DD93EB709533ECAB4FD7770BB8A530645717017A06A9D9809FC` |
| `GOGOBRO.pck` | 1,899,820 bytes | `8AD79AEA7DFAF14BF704A3B333318631616713782CD93B3B96B3CC220BB5C10E` |
| `export.log` | 79,642 bytes | `947ACBEDEFFC16F11B0A2D7EACF8B765B7379237972A02FDEE71C71BF5FA264E` |

Export exited 0 and contained zero `ERROR:`/`SCRIPT ERROR:` lines. The automated release smoke passed both mounted-PCK boot inspection and real exported-runtime execution.

The final EXE was then started windowed with an isolated profile. It remained alive and responsive, rendered the true main menu with `开始新游戏` and `退出`, and produced zero runtime error/diagnostic lines. Its stderr was empty. The process was stopped after capture and no matching final-proof process remained.

- Main-menu screenshot: `reports/release-black-screen-diagnosis/final-proof/windowed-proof/main-menu.png`
- Screenshot SHA-256: `4C59F01DA0B724C529850410CF90446560C397346A68C424B724B3CD60E28C79`
- Runtime log SHA-256: `5A2ABD9AC5C20489EC6AB8FF4395C9A7E4F55F35BF6895A7B3925175648CE5F7`
- Stdout SHA-256: `4E204A18A9324951EC912930715326F8E03A3118C34802F20F02A9D03CBA9865`
- Empty stderr SHA-256: `E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855`

## Verification

- Focused `item_attachment_socket_v2_smoke.gd`: `ITEM_ATTACHMENT_SOCKET_V2_SMOKE_OK sockets=24 frames=8`, exit 0.
- Complete GdUnit suite: 39/39 suites, 379/379 cases, 0 errors, 0 failures, 0 flaky, 0 skipped, 0 orphans; exit 0. XML: `reports/release-black-screen-diagnosis/full-gdunit/report_1/results.xml`.
- Final exported-PCK/runtime smoke: both success markers above; runtime error count 0.
- Final windowed release: main menu visible; runtime error count 0; stderr empty.
- `git diff --check`: clean before final staging.

An additional broad `python -m unittest discover -s tests/python -v` was attempted. Twenty-three tests passed, while two test modules could not import because this shell lacks `pytest` and the external `sprite_gen` package. Those are environment/discovery errors unrelated to this GDScript/PowerShell change; the complete Godot suite and release-specific regression are green.
