# Potato Brothers Godot 4

An independent Godot 4.7.1 project that combines the runnable Godot tutorial
implementation with the broader gameplay systems and assets from the local
Unity/Tuanjie reproduction.

## Phase 1 target

- 6 characters
- 11 weapon families with 4 tiers each
- 20 passive items
- 16 stat families with 4 upgrade tiers each
- 10 waves, 5 difficulty levels, and the MouseDog boss
- shop, inventory, rewards, win/loss settlement, unlocks, and local saves
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
.\tools\run_tests.ps1 -GodotBinary D:\path\to\Godot_v4.7.1-stable_win64_console.exe
```

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
