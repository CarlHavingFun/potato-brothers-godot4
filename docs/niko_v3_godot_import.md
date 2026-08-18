# Niko v3 directional sprite import

The 3D-to-sprite pipeline publishes its Godot atlases and manifest below
`res://content_packs/default/assets/sprites/players/niko_v3/`. Atlas images must
be imported by Godot before running the resource generator.

```powershell
godot --headless --editor --path . --import --quit
godot --headless --path . res://tools/sprites/import_niko_v3.tscn -- `
  --manifest res://content_packs/default/assets/sprites/players/niko_v3/sprite_manifest.json
```

The tool does not write anything until all atlases load and the manifest passes
validation. It then creates:

- `niko_v3_sprite_frames.tres`
- `player_niko_v3.tscn`
- `character_niko_v3.tres`

The bootstrap loader discovers `character_niko_v3.tres` on the next project
start. If it does not exist, the default content pack is left unchanged.

## Manifest contract

The root contract is schema version 1, 256 x 256 cells and pivot `(128, 232)`.
Each direction entry points to a horizontal atlas strip. Paths may be `res://`
paths or paths relative to the manifest. Every atlas must be exactly
`frame_count * 256` pixels wide by `256` pixels high; multi-row atlases and a
`row` field are rejected.

```json
{
  "schema_version": 1,
  "frame_size": {"width": 256, "height": 256},
  "pivot": {"x": 128, "y": 232},
  "godot_visual_scale": 0.7,
  "actions": {
    "idle": {
      "frame_count": 6,
      "fps": 6,
      "loop": true,
      "directions": {
        "down": {"atlas": "idle_down.png", "frame_count": 6},
        "down_right": {"atlas": "idle_down_right.png", "frame_count": 6},
        "right": {"atlas": "idle_right.png", "frame_count": 6},
        "up_right": {"atlas": "idle_up_right.png", "frame_count": 6},
        "up": {"atlas": "idle_up.png", "frame_count": 6},
        "up_left": {"atlas": "idle_up_left.png", "frame_count": 6},
        "left": {"atlas": "idle_left.png", "frame_count": 6},
        "down_left": {"atlas": "idle_down_left.png", "frame_count": 6}
      }
    }
  }
}
```

The actual manifest must also contain `walk`, `dash`, `hit`, `death`, and
`victory`. All actions use eight directions except `victory`, which contains
only `down`. Exact frame counts, rates, and loop flags are enforced by
`DirectionalSpriteManifestImporter.ACTION_CONTRACT`.
