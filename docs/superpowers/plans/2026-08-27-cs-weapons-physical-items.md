# CS Weapons and Physical Items Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace all twelve weapon visuals with unmistakable CS archetypes and make every one of the thirty item icons a concrete, consistently styled physical object while preserving stable IDs and item numbers.

**Architecture:** A checked-in redraw contract is the single source of truth for visible archetypes, physical subjects, dimensions, pivots, anchors, and localization. Generated work stays in numbered inbox candidates; only QC-passing files are copied into the development-preview asset tree and hash-bound in the preview manifest. Runtime content consumes the same stable IDs, with melee/ranged behavior matching the visible archetype and the existing `skyline_grenade` trigger providing the canonical explosion source.

**Tech Stack:** Godot 4.7 typed GDScript, GdUnit4, JSON manifests, GPT Image generation through the installed `generate2dsprite` workflow, solid-magenta chroma cleanup, nearest-neighbor PNG postprocessing.

**Spec:** `docs/superpowers/specs/2026-08-27-full-static-assets-brotato-hud-design.md`

## Global Constraints

- Niko remains the only character; this plan creates no character art.
- Preserve all existing weapon/item asset IDs and item gameplay numbers.
- Every raw generation uses a perfectly solid `#FF00FF` background; final runtime PNGs use transparent alpha and transparent RGB zero.
- Firearms are right-facing 96×64 gameplay textures; knives and item icons are 64×64 gameplay textures.
- Weapon silhouettes must be readable at 100% gameplay size and use chunky color masses; no gun may be accepted merely because its name disambiguates it.
- Items depict concrete physical objects. Footprints, arrows, speed streaks, isolated crosshairs, floating numbers, and abstract status glyphs are hard failures.
- Candidates remain development-preview assets and never inherit shipping approval.
- `heavy_hand_cannon` is a Desert Eagle and does not cause explosions. Explosion feedback comes from the existing `skyline_grenade` every-seventh-ranged-attack rule.

## File structure

| File | Responsibility |
|---|---|
| `tools/assets/gogobro_static_redraw_contract_v1.json` | Exact twelve-weapon mapping, thirty physical subjects, dimensions, pivots, and display names. |
| `tools/assets/validate_static_redraws.py` | Mechanical PNG, alpha, palette, size, safe-margin, and contract validation. |
| `tests/unit/test_static_redraw_contract.gd` | Contract completeness, stable IDs, physical-subject, content-mode, and manifest-binding tests. |
| `game/content/assets/gogobro_static_preview_content_v1.json` | Stable debug content IDs, CS display names, weapon modes, and combat profiles. |
| `game/content/assets/gogobro_static_preview_content_factory.gd` | Creates melee/ranged definitions exactly as declared by the content file. |
| `game/content/assets/gogobro_static_candidate_preview_v1.json` | Hash-bound development-preview paths, sizes, pivots, muzzle/contact anchors, and selectors. |
| `game/assets/gogobro_static_preview/weapons/*.png` | QC-passing transparent weapon gameplay textures. |
| `game/assets/gogobro_static_preview/items/*.png` | QC-passing transparent physical-item icons. |
| `game/gameplay/weapons/weapon_trigger_runtime.gd` | Per-weapon item trigger counters, including canonical `skyline_grenade` explosions. |
| `game/gameplay/weapons/weapon_instance.gd` | Dispatches ranged, melee, and item-triggered attacks using authored anchors. |

---

### Task 1: Lock the redraw contract and executable acceptance checks

**Files:**
- Create: `tools/assets/gogobro_static_redraw_contract_v1.json`
- Create: `tools/assets/validate_static_redraws.py`
- Create: `tests/unit/test_static_redraw_contract.gd`

**Interfaces:**
- Produces: `validate_static_redraws.py --contract <json> --assets-root <path>` with exit 0 only when every installed redraw satisfies the contract.
- Produces: one exact record per weapon/item with `asset_id`, `visible_name_zh`, `subject`, `width`, `height`, `mode`, `pivot_px`, and `anchor_px`.

- [ ] **Step 1: Write the failing contract-completeness test**

```gdscript
func test_redraw_contract_has_exact_weapon_and_item_sets() -> void:
	var contract := JSON.parse_string(FileAccess.get_file_as_string(CONTRACT_PATH)) as Dictionary
	assert_array((contract.weapons as Dictionary).keys()).contains_exactly_in_any_order(EXPECTED_WEAPON_IDS)
	assert_array((contract.items as Dictionary).keys()).contains_exactly_in_any_order(EXPECTED_ITEM_IDS)
	for asset_id: String in EXPECTED_ITEM_IDS:
		var subject := String((contract.items as Dictionary)[asset_id].subject).strip_edges()
		assert_bool(subject.is_empty()).is_false()
		for forbidden: String in ["footprint", "arrow", "speed streak", "floating number", "status glyph"]:
			assert_bool(subject.to_lower().contains(forbidden)).is_false()
```

- [ ] **Step 2: Run the focused test and record RED**

Run:

```powershell
tools\run_tests.ps1 -TestPath res://tests/unit/test_static_redraw_contract.gd -ReportDir reports/redraw-contract-red
```

Expected: FAIL because the contract file does not exist.

- [ ] **Step 3: Add the exact twelve-weapon map**

```json
{
  "warmup_shiv": {"visible_name_zh":"蝴蝶刀","subject":"Butterfly Knife with split handles and exposed pivot","width":64,"height":64,"mode":"melee"},
  "community_tapper": {"visible_name_zh":"爪子刀","subject":"Karambit with finger ring and curved claw blade","width":64,"height":64,"mode":"melee"},
  "wood_stock_assault_rifle": {"visible_name_zh":"AK-47","subject":"AK-47 with wood furniture and curved magazine","width":96,"height":64,"mode":"ranged"},
  "heavy_bolt_sniper": {"visible_name_zh":"AWP","subject":"AWP with large scope and green chassis","width":96,"height":64,"mode":"ranged"},
  "suppressed_carbine": {"visible_name_zh":"M4A1-S","subject":"M4A1-S with straight magazine and long suppressor","width":96,"height":64,"mode":"ranged"},
  "suppressed_tactical_pistol": {"visible_name_zh":"USP-S","subject":"USP-S with angular slide and suppressor","width":96,"height":64,"mode":"ranged"},
  "heavy_hand_cannon": {"visible_name_zh":"Desert Eagle","subject":"Desert Eagle with oversized squared slide","width":96,"height":64,"mode":"ranged"},
  "service_pistol": {"visible_name_zh":"Glock-18","subject":"Glock-18 with compact squared slide","width":96,"height":64,"mode":"ranged"},
  "box_submachine_gun": {"visible_name_zh":"MAC-10","subject":"MAC-10 with boxy receiver and short barrel","width":96,"height":64,"mode":"ranged"},
  "compact_submachine_gun": {"visible_name_zh":"MP9","subject":"MP9 with polymer body and skeleton stock","width":96,"height":64,"mode":"ranged"},
  "bullpup_pdw": {"visible_name_zh":"P90","subject":"P90 with horizontal top magazine","width":96,"height":64,"mode":"ranged"},
  "folding_stock_submachine_gun": {"visible_name_zh":"UMP-45","subject":"UMP-45 with long box magazine and folding stock","width":96,"height":64,"mode":"ranged"}
}
```

Every firearm record sets `pivot_px` near the grip and `anchor_px.muzzle` at the rightmost bore center. Both knife records set `anchor_px.contact` inside the forward third of the blade.

- [ ] **Step 4: Add all thirty concrete item subjects**

Use these exact subject assignments while retaining existing asset IDs: ballistic plate insert, gel tactical insoles, sight-calibration shim plate, handheld supply radar, padded forearm guard, sealed trauma patch pouch, smoke-shell helmet, tactical running shoes, coin pouch, Molotov bottle, entry-fragger dumbbell, claw keychain, scorched defuse pliers, digital save-time watch, taped HE grenade, folding laptop analysis desk, cracked scope lens in a protective case, dangling sniper charm, folding boost stool, broadcast microphone, tactics clipboard, engraved ace coin, balaclava, arena-chant cassette, mouse-lift pad, chalk holder, site-hold bandana, wing-shaped sniper charm, clutch stopwatch, and three-stripe rifle magazine.

`one_missed_shot` changes visible localization to `裂镜纪念盒` / `Cracked-Scope Keepsake`; its internal ID and all effects stay unchanged.

- [ ] **Step 5: Implement mechanical PNG validation**

The validator loads every installed path and rejects any mismatch with these rules:

```python
assert image.size == (record["width"], record["height"])
assert alpha_values <= {0, 255}
assert transparent_rgb_is_zero(image)
assert nontransparent_bbox_has_margin(image, minimum=2)
assert unique_opaque_colors(image) <= 24
assert largest_connected_component_ratio(image) >= 0.82
```

For firearms it also requires an opaque run at least 70 pixels wide; for knives it requires at least 42 pixels of occupied width or height. Emit one JSON result row per asset so a reviewer can distinguish mechanical pass from visual approval.

- [ ] **Step 6: Run the contract test GREEN and commit**

```powershell
tools\run_tests.ps1 -TestPath res://tests/unit/test_static_redraw_contract.gd -ReportDir reports/redraw-contract-green
git add tools/assets/gogobro_static_redraw_contract_v1.json tools/assets/validate_static_redraws.py tests/unit/test_static_redraw_contract.gd
git commit -m "test: lock CS weapon and physical item redraw contract"
```

### Task 2: Generate and curate all twelve CS weapon textures

**Files:**
- Create: numbered candidates under `E:/01_gobro/GOGOBRO_ASSET_INBOX/02_static_assets/weapons/<asset_id>/candidate-003/`
- Replace: `game/assets/gogobro_static_preview/weapons/*.png`
- Replace: `game/assets/gogobro_static/weapons/warmup_shiv.png`
- Replace: `game/assets/gogobro_static/weapons/service_pistol.png`
- Modify: `game/content/assets/gogobro_static_candidate_preview_v1.json`

**Interfaces:**
- Consumes: the Task 1 contract and Niko mother-art palette reference.
- Produces: twelve mechanically valid transparent PNGs plus per-candidate `prompt.txt`, `provenance.json`, `qa/qa-report.json`, pivot, and muzzle/contact anchor metadata.

- [ ] **Step 1: Prepare one locked prompt prefix**

Use this exact invariant prefix for every weapon, changing only the contract subject and silhouette cues:

```text
Original GOGOBRO chunky pixel-art game weapon, visual hierarchy inspired by Brotato but no copied art. Strictly recognizable as {SUBJECT}. Right-facing gameplay silhouette, very large readable color masses, thick barrel and controls, charcoal metal, warm orange accents, muted utility green, off-white highlights, one tiny original CS-community joke sticker. Hard square pixel clusters, no antialiasing, no photorealism, no micro-detail, no text, no logo. Centered with safe margin on a perfectly flat solid #FF00FF background; no shadow, glow, texture, gradient, or magenta spill.
```

- [ ] **Step 2: Generate four independently reviewable batches**

Batch A contains Butterfly Knife and Karambit; Batch B contains AK-47, AWP, and M4A1-S; Batch C contains USP-S, Desert Eagle, and Glock-18; Batch D contains MAC-10, MP9, P90, and UMP-45. Preserve the same prompt prefix and palette reference across all calls.

- [ ] **Step 3: Chroma-key, downsample, and validate every candidate**

Use nearest-neighbor only, remove exactly the connected `#FF00FF` background, zero RGB where alpha is zero, and run:

```powershell
python tools/assets/validate_static_redraws.py --contract tools/assets/gogobro_static_redraw_contract_v1.json --assets-root game/assets/gogobro_static_preview --category weapons --json-out reports/weapons-redraw-qc.json
```

Expected: twelve passing records; no edge touch, soft alpha, color-count overflow, or thin/undersized firearm.

- [ ] **Step 4: Perform actual-size silhouette review before installation**

At 100% size, each reviewer must identify the archetype without seeing its filename. Reject a candidate when any required cue in the spec is absent. Generate the next numbered candidate for only the rejected asset; do not hold back already passing assets.

- [ ] **Step 5: Install passing files and hash-bind metadata**

Copy only curated outputs, calculate SHA-256 from installed bytes, set exact `pixel_size`, integer `pivot_px`, and `anchors_px`, remove legacy aliases, and retain `preview_ready` rather than shipping approval. For the two currently approved shipping assets, install the new artwork in the debug overlay first; do not rewrite approval evidence.

- [ ] **Step 6: Import, test, and commit the full weapon set**

```powershell
E:\01_gobro\.tools\godot-4.7.1\Godot_v4.7.1-stable_win64_console.exe --editor --headless --path . --import
tools\run_tests.ps1 -TestPath res://tests/unit/test_static_candidate_preview_manifest.gd -ReportDir reports/weapon-manifest
tools\run_tests.ps1 -TestPath res://tests/unit/test_static_candidate_preview_runtime.gd -ReportDir reports/weapon-runtime
git add game/assets/gogobro_static_preview/weapons game/content/assets/gogobro_static_candidate_preview_v1.json
git commit -m "art: redraw all weapons as readable CS archetypes"
```

### Task 3: Audit all items and replace every non-physical or off-style icon

**Files:**
- Create: numbered replacement candidates under `E:/01_gobro/GOGOBRO_ASSET_INBOX/02_static_assets/items/<asset_id>/`
- Replace as required: `game/assets/gogobro_static_preview/items/*.png`
- Modify: `game/content/assets/gogobro_static_candidate_preview_v1.json`
- Modify: `game/content/assets/gogobro_static_assets_v1.json`
- Test: `tests/unit/test_static_redraw_contract.gd`

**Interfaces:**
- Consumes: the thirty Task 1 physical subjects and the same locked prompt prefix/palette.
- Produces: a thirty-row review record with `physical_subject_pass`, `style_match_pass`, `actual_size_pass`, and `installed_candidate`.

- [ ] **Step 1: Build a 64-pixel actual-size contact sheet and score all thirty current icons**

Hard-reject any icon that depicts an abstract event, reads only because of its name, uses a different rendering style, or loses its subject at 64×64. `one_missed_shot` is a mandatory redraw. Install the already mechanically approved `rebound_fire_bottle/candidate-002` before reviewing the remainder.

- [ ] **Step 2: Generate replacement candidates with the locked physical-item prompt**

```text
Original GOGOBRO chunky pixel-art inventory item, visual hierarchy inspired by Brotato but no copied art. One concrete {SUBJECT}, centered three-quarter view, immediately readable at 64x64, oversized silhouette, hard square pixel clusters, restrained charcoal/orange/off-white/utility-color palette, one subtle original CS-community joke detail, no text, no logo, no floating symbols, no arrows, no footprints. Perfectly flat solid #FF00FF background, no shadow, glow, texture, gradient, or magenta spill.
```

Generate the next numbered candidate for every rejected row and rescore it. A row is installable only when all three review booleans are true.

- [ ] **Step 3: Update concrete localization without changing mechanics**

Only display names and prose may change. Assert before and after that each item keeps the exact `asset_id`, effects JSON, rarity, max count, and appearance socket. Replace generic `“X 的静态视觉资产”` text with one concise physical-object description.

- [ ] **Step 4: Install, validate, import, and commit replacements**

```powershell
python tools/assets/validate_static_redraws.py --contract tools/assets/gogobro_static_redraw_contract_v1.json --assets-root game/assets/gogobro_static_preview --category items --json-out reports/items-redraw-qc.json
E:\01_gobro\.tools\godot-4.7.1\Godot_v4.7.1-stable_win64_console.exe --editor --headless --path . --import
tools\run_tests.ps1 -TestPath res://tests/unit/test_static_redraw_contract.gd -ReportDir reports/item-redraw-green
git add game/assets/gogobro_static_preview/items game/content/assets/gogobro_static_candidate_preview_v1.json game/content/assets/gogobro_static_assets_v1.json
git commit -m "art: replace abstract items with physical CS props"
```

### Task 4: Match runtime behavior to the new weapon archetypes and canonical grenade

**Files:**
- Modify: `game/content/assets/gogobro_static_preview_content_v1.json`
- Modify: `game/content/assets/gogobro_static_preview_content_factory.gd`
- Create: `game/gameplay/weapons/weapon_trigger_runtime.gd`
- Modify: `game/gameplay/weapons/weapon_instance.gd`
- Modify: `game/gameplay/weapons/weapon_runtime_service.gd`
- Modify: `game/gameplay/world/combat_world.gd`
- Modify: `tests/unit/test_projectile_impact_mechanics.gd`
- Create: `tests/unit/test_weapon_archetype_runtime.gd`

**Interfaces:**
- Produces: `GogoWeaponTriggerRuntime.note_ranged_attack(weapon_id: StringName, item_ids: Array[StringName]) -> Array[Dictionary]`.
- Trigger event row: `{impact_kind: &"explosion", damage_scale: 1.0, source_item_id: &"gogobro.preview:item/skyline_grenade"}` on every seventh ranged attack when owned.

- [ ] **Step 1: Write failing archetype and trigger tests**

```gdscript
func test_knives_are_melee_and_firearms_are_ranged() -> void:
	var content := _debug_content()
	assert_int(_weapon(content, "community_tapper").mode).is_equal(GogoWeaponDefinition.Mode.MELEE)
	assert_int(_weapon(content, "heavy_hand_cannon").mode).is_equal(GogoWeaponDefinition.Mode.RANGED)
	assert_str(String(_weapon(content, "heavy_hand_cannon").impact_kind)).is_equal("normal")

func test_skyline_grenade_emits_only_on_seventh_ranged_attack() -> void:
	var runtime := GogoWeaponTriggerRuntime.new()
	for index in 6:
		assert_array(runtime.note_ranged_attack(&"ak", [&"gogobro.preview:item/skyline_grenade"])).is_empty()
	assert_str(String(runtime.note_ranged_attack(&"ak", [&"gogobro.preview:item/skyline_grenade"])[0].impact_kind)).is_equal("explosion")
```

- [ ] **Step 2: Run focused tests and record RED**

Expected: candidate weapons are all ranged, Desert Eagle still has explosion impact, and the trigger runtime does not exist.

- [ ] **Step 3: Declare exact modes and CS names in content JSON**

Add `mode` and visible CS names to all twelve stable slots. The factory accepts only `melee` or `ranged`; invalid values reject the candidate definition. Butterfly Knife and Karambit use contact attacks; all ten firearms use projectiles. Remove `impact_kind: explosion` from Desert Eagle.

- [ ] **Step 4: Implement the skyline-grenade counter at the canonical attack boundary**

Count only attacks that actually publish `weapon_fired`. On count seven, spawn an additional grenade projectile from the weapon muzzle with the attack's base damage, slower visible travel, and `impact_kind = &"explosion"`; reset that weapon's counter to zero. Reset all counters at wave start and session clear.

- [ ] **Step 5: Verify mechanics and commit**

```powershell
tools\run_tests.ps1 -TestPath res://tests/unit/test_weapon_archetype_runtime.gd -ReportDir reports/weapon-archetypes
tools\run_tests.ps1 -TestPath res://tests/unit/test_projectile_impact_mechanics.gd -ReportDir reports/projectile-mechanics
git add game/content/assets/gogobro_static_preview_content_v1.json game/content/assets/gogobro_static_preview_content_factory.gd game/gameplay/weapons/weapon_trigger_runtime.gd game/gameplay/weapons/weapon_instance.gd game/gameplay/weapons/weapon_runtime_service.gd game/gameplay/world/combat_world.gd tests/unit/test_weapon_archetype_runtime.gd tests/unit/test_projectile_impact_mechanics.gd
git commit -m "feat: align combat behavior with CS weapon archetypes"
```

## Self-review result

- Spec coverage: all twelve weapon slots, all thirty item IDs, concrete item rules, magenta pipeline, anchors, stable mechanics, melee/ranged behavior, and CS-grounded explosion source are assigned to Tasks 1-4.
- Placeholder scan: no deferred asset names, subject choices, dimensions, modes, commands, or acceptance thresholds remain.
- Type consistency: the redraw contract, manifest, content factory, and trigger runtime use the same asset IDs, `mode` values, anchor names, and `impact_kind` values.

