# Niko Skeleton2D idle proof

This is an isolated, local-only authoring proof. It does not change the game main scene,
the Niko v3 manifest importer, or any content pack.

The scene loads the canonical 300×300 front mother frame and deterministically divides it
into three rigid layers: head, torso and feet. Small joint-overlap bands keep the rest pose
visually identical and prevent gaps; `Skeleton2D`, named `Bone2D` nodes and `AnimationPlayer` own the motion. Feet remain
fixed while torso/head use discrete integer-pixel keys. No AI model, cloud API or paid runtime
is involved.

`actions/idle_front.json` is the editable action contract. A new custom clip copies that
shape and changes its name, fps, loop flag and Bone2D property tracks. `Vector2` and `float`
tracks cover bone position, scale and rotation without embedding motion values in the scene.
Select the scene root and point its exported `action_file` property at another JSON clip.

Run visually:

```powershell
Godot_v4.7-stable_win64.exe --path E:\01_gobro\potato-brothers-godot4 \
  res://tools/sprites/niko_skeleton_idle_proof/niko_skeleton_idle_proof.tscn
```

Capture eight proof frames:

```powershell
Godot_v4.7-stable_win64.exe --headless --resolution 640x640 \
  --path E:\01_gobro\potato-brothers-godot4 \
  res://tools/sprites/niko_skeleton_idle_proof/niko_skeleton_idle_proof.tscn \
  -- --capture-proof
```

The current mask is deliberately conservative. Larger actions such as a wave or attack need
proper arm pieces with the hidden shoulder pixels completed. Other facings need their own
accepted direction mother frames; bones cannot invent a side or back view from the front image.
