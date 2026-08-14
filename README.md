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
