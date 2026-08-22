# Independent character pack template

Copy this directory to `content_packs/characters/<name>/` and rename
`pack.tres.example` to `pack.tres`.

- Pack ID: `character_<name>` using lowercase letters, digits, and underscores.
- Pack kind: `ContentPackDef.PackKind.CHARACTER` (`1`).
- Exactly one `CharacterDef` with local ID `character/<name>`.
- Add a strict dependency on `core` and use fully qualified `core:` weapon IDs.
- Keep the scene, SpriteFrames, atlases, icon, stats, and translations below the
  pack directory. Runtime resources may reference trusted shared `core/`,
  `scenes/`, and `resources/` files, but never `tools/` or another optional pack
  without declaring that pack as a dependency.
- Add the manifest and versioned shipping PCK name to
  `content_packs/builtin_packs.json` when the pack ships with the game.

Build one pack:

```powershell
.\tools\build_content_pack.ps1 `
  -GodotBinary C:\path\to\Godot_v4.7.1-stable_win64.exe `
  -SourceRoot res://content_packs/characters/<name> `
  -ManifestPath res://content_packs/characters/<name>/pack.tres `
  -OutputPath res://builds/content/character_<name>-1.0.0.pck
```

Enable or disable it from **Content Packs** on the main menu. The active run
keeps its current catalog snapshot; mounted updates and removals take effect
after restart.
