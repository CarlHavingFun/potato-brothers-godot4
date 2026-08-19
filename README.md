# LET'S GOOOOO · Godot 4

An independent Godot 4.7.1 project that combines the runnable Godot tutorial
implementation with the broader gameplay systems and assets from the local
Unity/Tuanjie reproduction.

## Core-parity target

- 12 characters
- 24 weapon families with 4 tiers each
- 60 passive items
- 16 stat families with 4 upgrade tiers each
- 20 waves, 5 difficulty levels, 2 elites, and 2 final bosses
- standard and deterministic endless runs with wave checkpoints and per-character records
- shop, inventory, rewards, win/loss settlement, unlocks, and local saves
- save v3 profiles with v1/v2 and legacy namespace migration
- presentation-neutral `core:` gameplay IDs with build-selected `SkinPackDef` manifests
- Simplified Chinese and English UI

The Unity/Tuanjie project, the tutorial source project, and `c-sbro` are
read-only references. The game must not depend on their paths at runtime.

## Engine

- Godot 4.7.1 standard build
- GDScript
- Compatibility renderer

## Development checks

Run the headless GdUnit4 suite from PowerShell:

```powershell
.\tools\run_tests.ps1 -GodotBinary D:\path\to\Godot_v4.7-stable_win64_console.exe
```

Build the restricted content pack, run all acceptance gates, export Windows,
Linux, and macOS, and assemble the internal playtest archives with:

```powershell
.\tools\build_release.ps1 -GodotBinary D:\path\to\Godot_v4.7-stable_win64_console.exe
```

For a Windows playtest build, use the one-command entry point:

```powershell
.\tools\build_windows_release.ps1 `
  -GodotBinary C:\path\to\Godot_v4.7-stable_win64_console.exe
```

On the first run it downloads the matching official Godot template archive,
verifies its pinned SHA-256, and installs only the Windows x86_64 templates.
Later runs reuse the installed templates. The portable directory and zip are
written under `dist/lets-gooooo/`; the exported executable is smoke-tested
from a temporary directory with isolated user data before the build succeeds.

Choose the presentation shell at build time without changing gameplay IDs:

```powershell
.\tools\build_release.ps1 `
  -GodotBinary D:\path\to\Godot_v4.7-stable_win64_console.exe `
  -SkinManifest res://content_packs/skins/lets_gooooo/skin.tres
```

Release output is written to the configured `dist` directory. The build uses a
sanitized staging copy, so MCP, GdUnit4, tests, and the source content directory
cannot enter the core PCK. It also removes every unselected skin before export.
The separately validated gameplay-only `default_content.pck` is then placed
beside the Windows/Linux executable and inside the macOS app bundle. Godot's
matching official export templates must be installed before producing platform
executables; editor and test runs do not require those templates.

The Godot MCP addon exposes its loopback-only HTTP endpoint at
`http://127.0.0.1:9100/mcp` while the editor is open. Generated reports and
screenshots stay under `reports/`, which Godot and Git both ignore.

The complete upstream Godot MCP 0.8.2 Windows AMD64 package is vendored at
`tools/vendor/godot-mcp/0.8.2/`, including its bundled skill and checksum. The
working CLI is extracted to `bin/godot-mcp.exe`; that generated copy is ignored
so Git keeps a single authoritative binary archive. With the editor open,
verify the local setup with:

```powershell
.\bin\godot-mcp.exe doctor --project . --json
.\bin\godot-mcp.exe --format json project info
.\bin\godot-mcp.exe --format json scene tree --max-depth 2
```

`RunState` is the authority for per-run materials, stats, inventory, wave,
difficulty, and phase. `Global` remains a temporary compatibility facade and a
holder for live scene references while tutorial systems are migrated. The
production project contains no Unity legacy cloud endpoints; a regression test
prevents them from being reintroduced. A future Steam integration must be a new
`SaveProvider` implementation.
