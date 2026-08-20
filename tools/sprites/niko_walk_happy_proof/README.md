# Niko Happy `walk_down` proof

This directory is an isolated Godot sample generated only from
`niko_walk_happy.mp4`. It is not installed into the production Niko character,
the directional importer, or any content pack.

The asset contract is eight 256x256 frames, 10 FPS, looping, with eight explicit
rectangles and eight 100 ms durations in `manifest.json`. Godot consumes
`sprite-sheet-alpha.png` through the generated `sprite_frames.tres`; it must not
consume pre-curation frame directories.

Regenerate the resource from the project root:

```powershell
& $env:GODOT_BIN --headless --path . --script res://tools/sprites/import_sprite_gen_state_cli.gd -- `
  --manifest res://tools/sprites/niko_walk_happy_proof/manifest.json `
  --state walk_down `
  --output res://tools/sprites/niko_walk_happy_proof/sprite_frames.tres
```

Open `niko_walk_happy_proof.tscn` to inspect the loop on a light checkerboard.
The sprite uses nearest-neighbour texture filtering. Its cell-space root is
`(128, 232)`; the preview offsets the centred `AnimatedSprite2D` by `(0, -104)`
so the root lands on the horizontal guide at the node position.

Status: **experimental sample / motion QA failed**. The atlas passes structural
asset validation, but the Happy video keeps the shoes centre-connected and its
horizontal root drift exceeds the production gait threshold. Do not promote it
to formal character art without replacing or correcting the source motion.
