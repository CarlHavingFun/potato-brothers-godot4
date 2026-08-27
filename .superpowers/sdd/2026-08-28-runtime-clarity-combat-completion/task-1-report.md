# Task 1 report — authored enemy sprites

**Status:** DONE_WITH_CONCERNS (implementation and evidence pass; only pre-existing UI anchor warnings remain in the combat smoke)

**Implementation commit:** `4c8e8c1125dceb54335d6324a14e207771cf178c`

## Outcome and architecture

- Added original 64×64 authored textures for drifter, spark, and rammer.
- Added `visual_texture: Texture2D` to `GogoEnemyDefinition` and bound the three textures in `ValidationContentFactory`.
- `GogoEnemyActor` now creates a centered, unscaled `Sprite2D` with nearest filtering for authored art. The legacy role-colored circle is drawn only while `fallback_visual_active` is true.
- Enemy art remains content-owned actor art. No enemy texture was added to or counted by the fixed 70-unit static registry.
- Preserved the three enemy content IDs, roles, names, health (`7/10/16`), speed (`82/65/110`), default touch damage/rewards, 14-pixel collision radius, movement, attacks, and reward/death behavior.
- The combat smoke deliberately cycles all three enemy IDs through its deterministic ten-enemy layout, asserts matching authored textures and nearest filtering, and asserts zero fallback circles before capture.

## Style references

All four local references were opened and visually inspected before generation, then supplied to each built-in image-generation call:

- `game/assets/gogobro_static_preview/weapons/wood_stock_assault_rifle.png` — graphite outline, restrained metal, orange accent language.
- `game/assets/gogobro_static_preview/items/skyline_grenade.png` — compact inventory-object readability and material treatment.
- `game/assets/gogobro_static_preview/ui/combat_hud_shell.png` — graphite/amber project-native palette.
- `reports/runtime-data/final-primary-6fbec8a/Roaming/GOGOBRO/full-static-assets-combat-v1/combat-1280x720.png` — actual arena value, contrast, and 1:1 runtime-size reference.

The references were style/runtime evidence only. Every enemy was generated as an original design.

## Generation prompts and paths

The built-in `image_gen` tool was called exactly once per enemy. The exact prompts also ship in each asset's `prompt-used.txt`.

### Drifter

- Raw: `C:\Users\18421\.codex\generated_images\01a04548-a57b-7451-8277-3cae36b51026\exec-b7b43308-d0a1-4d8d-bbf2-ec844b7a93ac.png`
- Raw SHA-256: `EF371E5475B9793DB7F2AA60C9A45CEFFD66C7F60C20EA19843B68A4D49AD68F`
- Output: `game/assets/enemies/drifter.png`
- Output SHA-256: `E0ADA9D1831D5DF9B27AEEE8540E1A1EDF2C2882CE47A31840D23930ADF760E6`

```text
Use case: stylized-concept
Asset type: original static 2D enemy sprite for the GOGOBRO top-down survival game
Input images: Images 1-3 are project-native style and material references only; Image 4 is the actual 1280x720 runtime contrast and scale reference. Do not copy any existing object or character.
Primary request: create one original rust-red compact drifter/chaser scavenger bot-creature, role-readable at 1:1 game scale.
Scene/backdrop: 100% solid perfectly flat #FF00FF magenta across the entire background, with no gradient, texture, floor, or shadow.
Subject: one centered full-body compact scavenger enemy, rounded armored torso but clearly not a circle; low forward-facing prow/face with two small dark sensor eyes; two distinct short feet or drive pods; a slightly ragged rear shell and asymmetrical antenna nub that make its chasing direction obvious. Silhouette must read in greyscale as compact, forward-leaning, and mobile.
Style/medium: project-native clean modern pixel-inspired 2D game sprite, crisp dark graphite outline, restrained CS-like metal materials, controlled highlights, fine detail only where readable; clarity over chunky pixel blocks; original design.
Composition/framing: isolated single asset, centered 3/4 top-down view from slightly above, facing down-right, full silhouette contained, generous magenta margin on all four sides, subject occupies roughly 65-72% of the square height and width.
Color palette: rust red and muted terracotta armor, charcoal joints and outline, tiny warm amber wear accents; silhouette and value contrast must distinguish it without hue.
Constraints: exactly one subject; no text, letters, numbers, labels, logo, watermark, border, frame, separator, UI, health bar, shadow plate, cast shadow, ground ellipse, detached particles, glow cloud, or extra props; no body part touches the image edge; all non-subject pixels must be exact #FF00FF.
```

### Spark

- Raw: `C:\Users\18421\.codex\generated_images\01a04548-a57b-7451-8277-3cae36b51026\exec-de12a5e8-a7b1-42b4-ad34-83780e01c944.png`
- Raw SHA-256: `F395C776C79AD23A0D183765101E867E40004CE9AE45C85CF1B49E0E29943BA9`
- Output: `game/assets/enemies/spark.png`
- Output SHA-256: `696A27F9FA2573B09ECCF734C5CE17EDBB1187CCAC2FA6584DFC837FD8BC6FC1`

```text
Use case: stylized-concept
Asset type: original static 2D enemy sprite for the GOGOBRO top-down survival game
Input images: Images 1-3 are project-native style and material references only; Image 4 is the actual 1280x720 runtime contrast and scale reference. Do not copy any existing object or character.
Primary request: create one original olive-lime flash-core spark/shooter drone-creature, instantly readable as the ranged enemy at 1:1 game scale.
Scene/backdrop: 100% solid perfectly flat #FF00FF magenta across the entire background, with no gradient, texture, floor, or shadow.
Subject: one centered full-body ranged drone enemy with a narrow diamond/triangular body, a bright compact lime flash-core in the center, and one unmistakable forward emitter barrel or pronged muzzle; two small lateral stabilizer fins make a wider horizontal silhouette, but no legs. Silhouette must read in greyscale as light, angular, hovering, and ranged, distinctly unlike a round chaser or broad wedge charger.
Style/medium: project-native clean modern pixel-inspired 2D game sprite, crisp dark graphite outline, restrained CS-like metal materials, controlled highlights, fine detail only where readable; clarity over chunky pixel blocks; original design.
Composition/framing: isolated single asset, centered 3/4 top-down view from slightly above, facing down-right, full silhouette contained, generous magenta margin on all four sides, subject occupies roughly 60-68% of the square height and width.
Color palette: olive drab shell, charcoal outline and joints, high-value lime-yellow flash-core and emitter tip; silhouette and value contrast must distinguish it without hue.
Constraints: exactly one subject; no text, letters, numbers, labels, logo, watermark, border, frame, separator, UI, health bar, shadow plate, cast shadow, ground ellipse, detached projectile, detached sparks, glow cloud, or extra props; no body part touches the image edge; all non-subject pixels must be exact #FF00FF.
```

### Rammer

- Raw: `C:\Users\18421\.codex\generated_images\01a04548-a57b-7451-8277-3cae36b51026\exec-1342df37-f8e3-47ed-85e8-5d6f02701bed.png`
- Raw SHA-256: `E510C81C6598CACF3538B9D85B8F4AF0CE3B85E4BE78F5003D347AFAED3CBE08`
- Output: `game/assets/enemies/rammer.png`
- Output SHA-256: `5C09FA52355A148580D8CBC03E515CAE4B9E99262A6E18881AB30DB90A30BF72`

```text
Use case: stylized-concept
Asset type: original static 2D enemy sprite for the GOGOBRO top-down survival game
Input images: Images 1-3 are project-native style and material references only; Image 4 is the actual 1280x720 runtime contrast and scale reference. Do not copy any existing object or character.
Primary request: create one original orange reinforced wedge rammer/charger bot-creature, instantly readable as the charging enemy at 1:1 game scale.
Scene/backdrop: 100% solid perfectly flat #FF00FF magenta across the entire background, with no gradient, texture, floor, or shadow.
Subject: one centered full-body heavy charger with a broad low wedge-shaped armored front, two short blunt horn/battering projections integrated into the prow, a compact raised rear engine housing, and two thick rear drive pods; no ranged barrel. Silhouette must read in greyscale as wide, heavy, reinforced, and forward-driving, distinctly unlike a rounded chaser or narrow winged shooter.
Style/medium: project-native clean modern pixel-inspired 2D game sprite, crisp dark graphite outline, restrained CS-like metal materials, controlled highlights, fine detail only where readable; clarity over chunky pixel blocks; original design.
Composition/framing: isolated single asset, centered 3/4 top-down view from slightly above, facing down-right, full silhouette contained, generous magenta margin on all four sides, subject occupies roughly 66-73% of the square height and width.
Color palette: safety orange and burnt amber armor, dark graphite reinforced front and joints, sparse pale metal edge accents; silhouette and value contrast must distinguish it without hue.
Constraints: exactly one subject; no text, letters, numbers, labels, logo, watermark, border, frame, separator, UI, health bar, shadow plate, cast shadow, ground ellipse, detached particles, glow cloud, or extra props; no body part touches the image edge; all non-subject pixels must be exact #FF00FF.
```

## Deterministic processing and QC

Each raw image was processed with the installed `generate2dsprite.py process` primitive as a `1×1` static creature asset using:

```text
--rows 1 --cols 1 --cell-size 64 --fit-scale 0.82
--align center --shared-scale --scale-strategy fit
--component-mode largest --component-padding 2
--reject-edge-touch --strict-qc
```

The first 0.78-fit QC pass was safe but left the rammer 40px high. It was deliberately reprocessed at 0.82 so every final bounding-box dimension falls inside the stronger 42–52px interpretation.

| Enemy | Canvas | Opaque bbox | Subject size | Source edge | Output edge | Clamp/empty | Magenta residue |
|---|---:|---:|---:|---:|---:|---:|---:|
| drifter | 64×64 | `[6,7,58,57]` | 52×50 | 0 | 0 | 0/0 | 0 |
| spark | 64×64 | `[6,6,58,57]` | 52×51 | 0 | 0 | 0/0 | 0 |
| rammer | 64×64 | `[6,11,58,53]` | 52×42 | 0 | 0 | 0/0 | 0 |

All three final PNGs were inspected individually at original 64×64 resolution. A deterministic 1:1 composite was also inspected with an arena-value background: color row above greyscale row, no scaling. It confirmed role separation independent of hue:

- drifter: compact legged oval/front-face mass;
- spark: narrow angular wing/emitter silhouette with high-value core;
- rammer: wide reinforced wedge with heavy rear pods.

The real OpenGL smoke capture was inspected at 1280×720. It showed all three role silhouettes in view among the six weapons and combat effects. Capture SHA-256: `B630B18D196724A64638C30A0A3AB715AC1B1DE60F37B3CE2BF6F62F093C2D9D`.

The capture coverage record reports:

```json
{
  "authored_enemy_ids": [
    "gogobro.core:enemy/drifter",
    "gogobro.core:enemy/spark",
    "gogobro.core:enemy/rammer"
  ],
  "authored_role_count": 3,
  "fallback_circle_count": 0,
  "count": 10,
  "capture_safe": true
}
```

## TDD and test evidence

Godot binary: `E:\01_gobro\.tools\godot-4.7.1\Godot_v4.7.1-stable_win64.exe` (4.7.1 stable).

1. RED — focused unit before source integration:

   ```powershell
   .\tools\run_tests.ps1 -GodotBinary $godot -TestPath 'res://tests/unit/test_enemy_actor_visual.gd'
   ```

   Meaningful RED result: 2 cases, 0 errors, 2 expected failures — missing `visual_texture` and missing fallback-state contract. Before this meaningful RED, the harness needed an explicit Godot path and one test-only `find_children` syntax correction; neither involved production code.

2. GREEN — focused unit after minimal source integration:

   ```text
   2 cases, 0 errors, 0 failures
   ```

   Proves authored texture assignment, `VisualSprite` creation, texture identity, nearest filtering, centered position/offset, 1:1 scale, authored/fallback state, and unchanged 14px collision radius.

3. Headless 1280×720 combat smoke:

   ```powershell
   .\tools\run_tests.ps1 -GodotBinary $godot -TestPath 'res://tests/integration/full_static_assets_combat_v1_smoke.gd'
   ```

   Result: 2 cases, 0 errors, 0 failures; all three content-owned textures and zero fallback circles asserted. The headless display correctly reports raster capture unavailable.

4. Real OpenGL 1280×720 combat visual smoke against an isolated workspace-local profile:

   ```text
   OpenGL 3.3 Compatibility / NVIDIA GeForce RTX 5090 D v2
   2 cases, 0 errors, 0 failures
   capture=combat-1280x720.png
   shots=29, contacts=24
   ```

5. Final combined verification immediately before the implementation commit:

   ```text
   enemy actor visual: 2/2 pass
   full static assets combat: 2/2 pass
   asset QC: 3/3 pass at 64×64, 42–52px bbox dimensions, zero magenta, strict QC
   ```

## Self-review

- Requirements scan: all requested files exist; the generated PNGs, exact prompts, processor metadata, source integration, new unit, and combat smoke changes are present.
- Architecture scan: no static registry/manifest edits; the 70-unit registry remains unchanged.
- Runtime scan: the texture is content-owned and copied directly to a child `Sprite2D`; no image scaling or filtering fallback is applied.
- Fallback scan: missing texture creates no `VisualSprite`, leaves `fallback_visual_active == true`, and retains the legacy circle draw path. Authored texture sets it false and `_draw()` returns before any fallback circle.
- Mutation scan: removing the definition property, texture assignment, sprite creation, nearest filter, centered state, fallback state, or 14px radius breaks the focused unit; omitting any role texture or enabling fallback breaks the integration smoke.
- Content scan: IDs/stats/collision/combat behavior are preserved; only visual ownership/presentation changed.
- Artifact scan: final alpha bboxes have safe margins, all strict processor edge/clamp/empty gates pass, and no magenta-like opaque pixels remain.

## Concerns

- No task-blocking concern remains.
- The combat smoke emits existing `screen_base.gd` Control-anchor warnings while routing through menu/difficulty/diagnostic screens. They predate this enemy change, do not touch the modified files, and appear in both the prior route and current passing runs.
- Raw built-in generations remain under `$CODEX_HOME/generated_images`; only the final 64×64 assets plus prompts, hashes, and deterministic pipeline metadata are committed. `.codex-temp` intermediates and unrelated import/UID noise are intentionally excluded.
- The report is committed separately after the implementation commit so it can record the immutable implementation hash; a Git commit cannot include its own final hash self-referentially.
