# Full Static Assets and Brotato-Style HUD Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Connect all 70 registered non-character assets to real GOGOBRO gameplay and UI consumers, with Niko as the only character and a 1280×720 Brotato-style combat presentation.

**Architecture:** Approved shipping assets remain the immutable base snapshot; debug builds add a validated candidate content pack and candidate texture overlay before a session starts. Focused presenters consume the snapshot for content cards, the 320×180 HUD shell, and deterministic world decoration, while a coverage audit records the exact real consumer for every registry unit.

**Tech Stack:** Godot 4.7, typed GDScript, GdUnit4, JSON manifests, PNG nearest-neighbor textures, headless integration capture scripts.

**Spec:** `docs/superpowers/specs/2026-08-27-full-static-assets-brotato-hud-design.md`

## Global Constraints

- The canonical registry contains exactly 70 non-character units: 12 weapons, 30 items, 6 upgrades, 11 world assets, 10 UI/brand assets, and 1 projectile/hit kit.
- `character.niko:character/niko` remains the only character definition.
- Candidate textures and candidate-only content are enabled only when `OS.is_debug_build()` is true; release snapshots accept only hash-bound approved shipping assets.
- Weapons use at most six sockets on a 72-pixel ring, independently target the nearest valid enemy, and render with nearest-neighbor sampling.
- The reference viewport is 1280×720; `combat_hud_shell` has a 320×180 logical layout rendered at exactly 4×.
- Static candidates remain `preview_ready`; only approved `ready` states count toward release readiness.
- A review gallery is not a runtime consumer and cannot satisfy coverage.

## File structure

| File | Responsibility |
|---|---|
| `game/content/assets/gogobro_static_preview_content_v1.json` | Explicit debug weapon balance and schema version; no runtime filename inference. |
| `game/content/assets/gogobro_static_preview_content_factory.gd` | Build debug weapon/item/upgrade definitions from the explicit balance file and canonical registry. |
| `game/content/assets/gogobro_static_coverage_audit.gd` | Validate and serialize one real consumer record for every registry asset. |
| `game/content/assets/gogobro_static_consumer_registry.gd` | Collect typed consumer observations from screens, HUD, world, and combat feedback. |
| `game/ui/combat_hud_snapshot.gd` | Immutable typed HUD values emitted by `CombatWorld`. |
| `game/ui/brotato_combat_hud.gd` | Build and update the 320×180 logical combat HUD. |
| `game/ui/static_card_presenter.gd` | Build consistent weapon/item/upgrade cards with image and text fallback. |
| `game/gameplay/world/static_world_presenter.gd` | Tile floor/border and place deterministic props, pickups, marker, and turret. |
| `game/gameplay/world/static_pickup_visual.gd` | Render a single collision-free world pickup from a snapshot handle. |
| `game/gameplay/world/static_spawn_marker.gd` | Show a short marker before an enemy is activated. |
| `game/assets/gogobro_static/items/smoke_shell_helmet*.png` | Exact approved candidate-002 icon and rigid appearance payloads. |
| `game/content/packs/items/smoke_shell_helmet/` | Approved helmet appearance metadata and eight-frame anchor evidence. |
| `tests/unit/test_static_preview_content_factory.gd` | Debug/release content counts, IDs, literal stat translation, and invalid metadata tests. |
| `tests/unit/test_brotato_combat_hud.gd` | Snapshot contract, layout hierarchy, icon fallback, weapon/item strips, and hint timeout tests. |
| `tests/unit/test_static_menu_consumers.gd` | Real menu background, wordmark, panel, button, card, zone, and difficulty consumers. |
| `tests/unit/test_static_world_presenter.gd` | Deterministic floor, border, props, pickup, marker, and turret consumers. |
| `tests/unit/test_static_asset_coverage_audit.gd` | Exact 70/70 coverage and debug/release provenance assertions. |
| `tests/integration/full_static_assets_menu_v1_smoke.gd` | Launch and capture the actual menu route at 1280×720. |
| `tests/integration/full_static_assets_combat_v1_smoke.gd` | Launch and capture live six-weapon combat at 1280×720. |

---

### Task 1: Development content catalog and release separation

**Files:**
- Create: `game/content/assets/gogobro_static_preview_content_v1.json`
- Create: `game/content/assets/gogobro_static_preview_content_factory.gd`
- Modify: `game/content/validation_content_factory.gd`
- Modify: `game/app/app_kernel.gd`
- Modify: `game/gameplay/rules/stat_pipeline.gd`
- Modify: `game/gameplay/weapons/weapon_runtime_service.gd`
- Test: `tests/unit/test_static_preview_content_factory.gd`
- Modify: `tests/unit/test_static_candidate_preview_runtime.gd`

**Interfaces:**
- Consumes: canonical `gogobro_static_assets_v1.json` units and explicit weapon records from `gogobro_static_preview_content_v1.json`.
- Produces: `GogoStaticPreviewContentFactory.create_pack() -> GogoContentPackDefinition`, `ValidationContentFactory.create_packs(include_development_preview: bool = false) -> Array[GogoContentPackDefinition]`, and debug counts of 12 weapons, 30 items, 6 upgrades, and one character.

- [ ] **Step 1: Write the failing content and separation tests**

```gdscript
func test_debug_catalog_has_exact_static_content_counts_and_only_niko() -> void:
	var content := GogoContentRegistry.new().build_snapshot(ValidationContentFactory.create_packs(true))
	assert_int(content.all(&"weapon").size()).is_equal(12)
	assert_int(content.all(&"item").size()).is_equal(30)
	assert_int(content.all(&"upgrade").size()).is_equal(6)
	assert_int(content.all(&"character").size()).is_equal(1)
	assert_str(String(content.all(&"character")[0].content_id)).is_equal("character.niko:character/niko")

func test_release_catalog_excludes_candidate_only_definitions() -> void:
	var content := GogoContentRegistry.new().build_snapshot(ValidationContentFactory.create_packs(false))
	assert_int(content.all(&"weapon").size()).is_equal(2)
	assert_bool(content.has_definition(&"gogobro.preview:weapon/community_tapper", &"weapon")).is_false()

func test_literal_percent_effects_are_converted_once() -> void:
	var content := GogoContentRegistry.new().build_snapshot(ValidationContentFactory.create_packs(true))
	var item := content.definition(&"gogobro.preview:item/crosshair_shim", &"item") as GogoItemDefinition
	assert_float(item.stat_modifiers[&"damage_multiplier"]).is_equal_approx(0.05, 0.0001)
```

- [ ] **Step 2: Run the focused test and record RED**

Run:

```powershell
cmd.exe /c "addons\gdUnit4\runtest.cmd --godot_binary E:\01_gobro\.tools\godot-4.7.1\Godot_v4.7.1-stable_win64.exe -a res://tests/unit/test_static_preview_content_factory.gd"
```

Expected: FAIL because `GogoStaticPreviewContentFactory` and the boolean `create_packs` argument do not exist.

- [ ] **Step 3: Add the explicit weapon balance records**

Write all ten candidate rows with these fixed fields and values; the two approved training weapons remain in `ValidationContentFactory`:

```json
{
  "schema_version": "gogobro-static-preview-content-v1",
  "weapons": [
    {"asset_id":"community_tapper","name":"社区连点器","damage":3.0,"cooldown":0.18,"range":420.0,"projectile_speed":650.0,"knockback":10.0,"price":12,"profile":"rapid"},
    {"asset_id":"wood_stock_assault_rifle","name":"木托突击步枪","damage":8.0,"cooldown":0.34,"range":560.0,"projectile_speed":760.0,"knockback":24.0,"price":22,"profile":"rifle"},
    {"asset_id":"heavy_bolt_sniper","name":"重型栓动狙","damage":30.0,"cooldown":1.45,"range":820.0,"projectile_speed":980.0,"knockback":70.0,"price":34,"profile":"heavy"},
    {"asset_id":"suppressed_carbine","name":"消音卡宾枪","damage":7.0,"cooldown":0.38,"range":540.0,"projectile_speed":740.0,"knockback":18.0,"price":23,"profile":"suppressed"},
    {"asset_id":"suppressed_tactical_pistol","name":"消音战术手枪","damage":6.0,"cooldown":0.42,"range":470.0,"projectile_speed":700.0,"knockback":16.0,"price":18,"profile":"suppressed"},
    {"asset_id":"heavy_hand_cannon","name":"重型手炮","damage":18.0,"cooldown":0.82,"range":520.0,"projectile_speed":800.0,"knockback":52.0,"price":28,"profile":"heavy"},
    {"asset_id":"box_submachine_gun","name":"盒式冲锋枪","damage":4.0,"cooldown":0.16,"range":390.0,"projectile_speed":650.0,"knockback":9.0,"price":17,"profile":"rapid"},
    {"asset_id":"compact_submachine_gun","name":"紧凑冲锋枪","damage":4.5,"cooldown":0.15,"range":370.0,"projectile_speed":660.0,"knockback":9.0,"price":18,"profile":"rapid"},
    {"asset_id":"bullpup_pdw","name":"牛头式 PDW","damage":5.0,"cooldown":0.20,"range":430.0,"projectile_speed":690.0,"knockback":12.0,"price":20,"profile":"rapid"},
    {"asset_id":"folding_stock_submachine_gun","name":"折叠托冲锋枪","damage":5.5,"cooldown":0.22,"range":450.0,"projectile_speed":700.0,"knockback":14.0,"price":20,"profile":"rifle"}
  ]
}
```

- [ ] **Step 4: Implement deterministic definition construction**

Use stable IDs `gogobro.preview:<kind>/<asset_id>`. Translate only unconditional top-level numeric registry effects with this exact map; percentage operations divide by 100 and conditional or trigger objects do not become unconditional stats:

```gdscript
const EFFECT_MAP := {
	"max_health": [&"max_health", 1.0],
	"move_speed_pct": [&"movement_speed_multiplier", 0.01],
	"damage_pct": [&"damage_multiplier", 0.01],
	"economy": [&"economy", 1.0],
	"armor": [&"armor", 1.0],
	"regeneration": [&"health_regen", 1.0],
	"explosion_damage_pct": [&"explosion_damage_multiplier", 0.01],
	"melee_damage": [&"melee_damage", 1.0],
	"ranged_damage": [&"ranged_damage", 1.0],
	"critical_chance": [&"critical_chance", 0.01],
	"dodge": [&"dodge", 0.01],
	"range": [&"attack_range_bonus", 1.0],
	"attack_speed_pct": [&"attack_speed_multiplier", 0.01],
}
```

The stat pipeline derives final movement speed, damage multiplier, and attack speed from additive multiplier fields after all equipment has been summed. `WeaponRuntimeService` adds `attack_range_bonus`, melee/ranged flat damage, and preserves the existing final minimum clamps.

- [ ] **Step 5: Install the pack only during debug boot and build the overlay against it**

```gdscript
static func create_packs(include_development_preview: bool = false) -> Array[GogoContentPackDefinition]:
	var packs := [_core_pack(), _weapon_pack(MELEE_ID, true), _weapon_pack(RANGED_ID, false), NIKO_CONTENT_FACTORY.create_pack()]
	if include_development_preview:
		packs.append(GogoStaticPreviewContentFactory.create_pack())
	return packs
```

`AppKernel.boot()` passes `OS.is_debug_build()` and keeps the existing release activation path unchanged.

- [ ] **Step 6: Run focused content and existing preview tests GREEN**

Run both test files and expect all assertions to pass, including ten candidate content icon bindings and the unchanged false release readiness.

- [ ] **Step 7: Commit the content slice**

```powershell
git add game/content/assets/gogobro_static_preview_content_v1.json game/content/assets/gogobro_static_preview_content_factory.gd game/content/validation_content_factory.gd game/app/app_kernel.gd game/gameplay/rules/stat_pipeline.gd game/gameplay/weapons/weapon_runtime_service.gd tests/unit/test_static_preview_content_factory.gd tests/unit/test_static_candidate_preview_runtime.gd
git commit -m "feat: add full debug static content catalog"
```

### Task 2: Install the approved smoke-shell helmet exactly

**Files:**
- Create: `game/assets/gogobro_static/items/smoke_shell_helmet.png`
- Create: `game/assets/gogobro_static/items/smoke_shell_helmet_appearance.png`
- Create: `game/content/packs/items/smoke_shell_helmet/anchors_walk_down.json`
- Create: `game/content/packs/items/smoke_shell_helmet/smoke_shell_helmet_factory.gd`
- Modify: `game/content/assets/gogobro_static_assets_v1.json`
- Modify: `game/content/assets/gogobro_static_runtime_bindings_v1.json`
- Modify: `game/content/assets/gogobro_static_preview_content_factory.gd`
- Test: `tests/unit/test_smoke_shell_helmet_install.gd`
- Modify: `tests/integration/item_appearance_v2_smoke.gd`

**Interfaces:**
- Consumes: candidate-002 icon SHA-256 `9D5D9A14D005BE3B08C5CC90F2E11C74EF214BAC8C921452F34DC1DAEF509BEC`, appearance SHA-256 `B3932E02DAF39074CE048E45B6FAE7F221019D87AD7B3A4327FA40714F25874A`, anchor SHA-256 `7055D9A6A12B35C06BA3744A78F8CA7CC4B5C9E7E48CF0BA94BA383898C0978E`.
- Produces: `SmokeShellHelmetFactory.attach_appearance(item: GogoItemDefinition) -> Error` and a shipping `icon` binding for `gogobro.preview:item/smoke_shell_helmet` without regenerating any image.

- [ ] **Step 1: Write failing hash, binding, and runtime appearance tests**

```gdscript
func test_installed_payloads_match_approved_candidate_002() -> void:
	assert_str(FileAccess.get_sha256("res://game/assets/gogobro_static/items/smoke_shell_helmet.png").to_upper()).is_equal("9D5D9A14D005BE3B08C5CC90F2E11C74EF214BAC8C921452F34DC1DAEF509BEC")
	assert_str(FileAccess.get_sha256("res://game/assets/gogobro_static/items/smoke_shell_helmet_appearance.png").to_upper()).is_equal("B3932E02DAF39074CE048E45B6FAE7F221019D87AD7B3A4327FA40714F25874A")

func test_helmet_uses_niko_head_shell_at_depth_40() -> void:
	var item := GogoStaticPreviewContentFactory.item_for_asset(&"smoke_shell_helmet")
	var appearance := item.appearances[0]
	assert_str(String(appearance.socket_id)).is_equal("head_shell")
	assert_int(appearance.depth).is_equal(40)
	assert_int(appearance.mode).is_equal(GogoAppearanceDefinition.Mode.RIGID)
```

- [ ] **Step 2: Run the focused test and record RED**

Expected: missing installed files and missing `SmokeShellHelmetFactory`.

- [ ] **Step 3: Copy approved payload bytes without image processing**

Copy these exact sources with `Copy-Item -LiteralPath`; verify all three hashes immediately after copying:

```powershell
Copy-Item -LiteralPath 'E:\01_gobro\GOGOBRO_ASSET_INBOX\02_static_assets\items\smoke_shell_helmet\candidate-002\derived\icon-256.png' -Destination 'game\assets\gogobro_static\items\smoke_shell_helmet.png'
Copy-Item -LiteralPath 'E:\01_gobro\GOGOBRO_ASSET_INBOX\02_static_assets\items\smoke_shell_helmet\candidate-002\derived\appearance-128.png' -Destination 'game\assets\gogobro_static\items\smoke_shell_helmet_appearance.png'
Copy-Item -LiteralPath 'E:\01_gobro\GOGOBRO_ASSET_INBOX\02_static_assets\items\smoke_shell_helmet\candidate-002\appearance\anchors-walk-down.json' -Destination 'game\content\packs\items\smoke_shell_helmet\anchors_walk_down.json'
```

- [ ] **Step 4: Build the approved rigid appearance**

The factory loads the 128×128 texture, sets `target_character_id = ValidationContentFactory.CHARACTER_ID`, `slot = &"head"`, `socket_id = &"head_shell"`, `mode = RIGID`, `depth = 40`, `render_scale = Vector2(0.625, 0.625)`, and the approved rendered pivot/local offset needed by the candidate-002 anchor evidence. It rejects any source or anchor hash mismatch with `ERR_FILE_CORRUPT`.

- [ ] **Step 5: Add exact shipping evidence and bind the item icon**

Update registry hashes, active approved candidate evidence, and the runtime manifest entry so the shipping runtime resolves the icon. The appearance remains a separate exact resource owned by the item factory and does not broaden static runtime release approval.

- [ ] **Step 6: Run focused and appearance integration tests GREEN**

Run `test_smoke_shell_helmet_install.gd` and `item_appearance_v2_smoke.gd`; expect the icon to resolve, eight animation frames to keep a visible rigid helmet, and Niko to remain the only character.

- [ ] **Step 7: Commit the approved helmet slice**

```powershell
git add game/assets/gogobro_static/items/smoke_shell_helmet.png game/assets/gogobro_static/items/smoke_shell_helmet_appearance.png game/content/packs/items/smoke_shell_helmet game/content/assets/gogobro_static_assets_v1.json game/content/assets/gogobro_static_runtime_bindings_v1.json game/content/assets/gogobro_static_preview_content_factory.gd tests/unit/test_smoke_shell_helmet_install.gd tests/integration/item_appearance_v2_smoke.gd
git commit -m "feat: install approved smoke shell helmet"
```

### Task 3: Typed combat HUD snapshot and Brotato layout

**Files:**
- Create: `game/ui/combat_hud_snapshot.gd`
- Create: `game/ui/brotato_combat_hud.gd`
- Modify: `game/gameplay/world/combat_world.gd`
- Modify: `game/ui/combat_screen.gd`
- Test: `tests/unit/test_brotato_combat_hud.gd`
- Modify: `tests/unit/test_combat_static_ui_consumers.gd`
- Modify: `tests/unit/test_combat_event_publication.gd`

**Interfaces:**
- Produces: `signal CombatWorld.hud_snapshot_changed(snapshot: GogoCombatHudSnapshot)`, `GogoCombatHudSnapshot.create(player, seconds, wave)`, and `GogoBrotatoCombatHud.apply_snapshot(snapshot)`.
- Preserves: existing `hud_changed(health, max_health, time_left, wave)` signal.

- [ ] **Step 1: Write failing snapshot and 320×180 layout tests**

```gdscript
func test_snapshot_copies_canonical_player_values() -> void:
	var player := SessionPlayerState.new()
	player.level = 3; player.xp = 11; player.xp_to_next_level = 42; player.materials = 77
	player.weapon_ids.assign([&"w1", &"w2"]); player.item_ids.assign([&"i1"])
	var snapshot := GogoCombatHudSnapshot.create(player, 9.25, 4)
	assert_int(snapshot.level).is_equal(3)
	assert_int(snapshot.experience).is_equal(11)
	assert_array(snapshot.weapon_ids).contains_exactly([&"w1", &"w2"])

func test_hud_uses_fixed_reference_hierarchy() -> void:
	var hud := auto_free(GogoBrotatoCombatHud.new())
	hud.configure(_snapshot_fixture(), _content_fixture())
	add_child(hud)
	assert_bool(hud.custom_minimum_size == Vector2(320, 180)).is_true()
	assert_bool(hud.has_node("TopCenter/Timer")).is_true()
	assert_bool(hud.has_node("BottomLeft/HealthBar")).is_true()
	assert_int(hud.get_node("WeaponStrip").get_child_count()).is_equal(6)
```

- [ ] **Step 2: Run focused HUD tests and record RED**

Expected: the snapshot and HUD types are not defined.

- [ ] **Step 3: Implement the immutable snapshot**

Define typed fields `health`, `maximum_health`, `seconds`, `wave`, `level`, `experience`, `next_level_requirement`, `materials`, `weapon_ids`, and `item_ids`. Duplicate both arrays in `create` so later player mutations cannot change an emitted snapshot.

- [ ] **Step 4: Emit both signals from one canonical helper**

```gdscript
func _emit_hud_snapshot(remaining: float) -> void:
	var player := session.run_state.player()
	var snapshot := GogoCombatHudSnapshot.create(player, remaining, session.run_state.current_wave)
	hud_snapshot_changed.emit(snapshot)
	hud_changed.emit(snapshot.health, snapshot.maximum_health, snapshot.seconds, snapshot.wave)
```

Call the helper from `_physics_process` and `_on_player_health_changed`; do not read world-private fields from `CombatScreen`.

- [ ] **Step 5: Build the fixed 320×180 control tree**

Use the `combat_hud_shell` global texture as a full-rect `TextureRect`, labels at top center, health at bottom left, XP at bottom center, materials at bottom right, six 20×20 weapon cells along the lower edge, and up to eight 16×16 item cells on the right. Every texture control uses `TEXTURE_FILTER_NEAREST`; missing textures leave the label/card visible.

- [ ] **Step 6: Implement permanent control-hint dismissal**

`GogoBrotatoCombatHud.note_movement(direction)` hides the hint on the first non-zero vector. `apply_snapshot` also hides it when wave one elapsed time reaches four seconds. Once hidden, later snapshots cannot reveal it.

- [ ] **Step 7: Replace the old combat screen labels with the new HUD**

Scale the 320×180 HUD root to `Vector2(4, 4)` inside `HUDCanvas`, connect `hud_snapshot_changed`, and keep `static_asset_snapshot_override` injection for unit tests.

- [ ] **Step 8: Run HUD and event publication tests GREEN**

Expect the old compatibility signal assertions plus the new immutable snapshot, hierarchy, six slots, item cap, fallbacks, and hint lifecycle assertions to pass.

- [ ] **Step 9: Commit the HUD slice**

```powershell
git add game/ui/combat_hud_snapshot.gd game/ui/brotato_combat_hud.gd game/gameplay/world/combat_world.gd game/ui/combat_screen.gd tests/unit/test_brotato_combat_hud.gd tests/unit/test_combat_static_ui_consumers.gd tests/unit/test_combat_event_publication.gd
git commit -m "feat: add fixed scale Brotato combat HUD"
```

### Task 4: Shared menu, button, panel, and content cards

**Files:**
- Create: `game/ui/static_card_presenter.gd`
- Modify: `game/ui/screen_base.gd`
- Modify: `game/ui/main_menu_screen.gd`
- Modify: `game/ui/character_select_screen.gd`
- Modify: `game/ui/weapon_select_screen.gd`
- Modify: `game/ui/difficulty_select_screen.gd`
- Modify: `game/ui/shop_screen.gd`
- Modify: `game/ui/upgrade_screen.gd`
- Test: `tests/unit/test_static_menu_consumers.gd`

**Interfaces:**
- Consumes: `GogoStaticAssetSnapshot.resolve_global` and `resolve_asset`.
- Produces: `GogoStaticCardPresenter.build_card(definition, price_text, snapshot) -> Control` and shared screen nodes `StaticMenuBackground`, `ReadabilityVeil`, and `StaticNineSlicePanel`.

- [ ] **Step 1: Write failing real-screen consumer tests**

```gdscript
func test_main_menu_consumes_background_wordmark_panel_and_button() -> void:
	var screen := _instantiate_main_menu_with_fixture()
	assert_object(screen.get_node("StaticMenuBackground").texture).is_not_null()
	assert_object(screen.get_node("Center/StaticNineSlicePanel").texture).is_not_null()
	assert_object(screen.get_node("Center/StaticNineSlicePanel/Body/Wordmark").texture).is_not_null()
	assert_object(screen.get_node("Center/StaticNineSlicePanel/Body/StartButton").get_meta("static_four_state_texture")).is_not_null()

func test_missing_icon_keeps_text_card_selectable() -> void:
	var card := GogoStaticCardPresenter.build_card(_definition_without_texture(), "12 材料", _empty_snapshot())
	assert_bool(card.has_node("Name")).is_true()
	assert_bool(card.mouse_filter != Control.MOUSE_FILTER_IGNORE).is_true()
```

- [ ] **Step 2: Run menu consumer tests and record RED**

Expected: the named background, panel, wordmark, and card nodes do not exist.

- [ ] **Step 3: Upgrade `GogoScreenBase` with static background and panel fallbacks**

Resolve `menu_background`, place a dark `ColorRect` veil above it, resolve `nine_slice_panel` for the centered panel, and preserve the current flat `ColorRect` and `PanelContainer` when either handle is absent.

- [ ] **Step 4: Implement the shared 64-pixel card hierarchy**

The card has `Icon` (64×64), `Name`, `Tier`, `StatLine`, and `PriceOrState`. It resolves `card_and_rarity_frame_kit` behind the icon, uses the definition icon when present, and retains all text when absent.

- [ ] **Step 5: Consume brand and selection assets in actual routes**

Main menu adds `gogobro_wordmark`; character/difficulty screens show `zone_thumbnail`; difficulty entries use `difficulty_badge_kit`; weapon selection, shop, and upgrade screens use the shared cards; every normal/hover/pressed/disabled button receives the `four_state_button` texture metadata while the existing stable theme remains its fallback.

- [ ] **Step 6: Run menu consumer and button stability tests GREEN**

Run the focused test plus `button_stability_v2_smoke.gd`; expect all actual routes to instantiate and fallbacks to remain clickable.

- [ ] **Step 7: Commit the menu slice**

```powershell
git add game/ui/static_card_presenter.gd game/ui/screen_base.gd game/ui/main_menu_screen.gd game/ui/character_select_screen.gd game/ui/weapon_select_screen.gd game/ui/difficulty_select_screen.gd game/ui/shop_screen.gd game/ui/upgrade_screen.gd tests/unit/test_static_menu_consumers.gd
git commit -m "feat: connect static assets to menu and cards"
```

### Task 5: Deterministic world presentation, pickups, marker, and turret

**Files:**
- Create: `game/gameplay/world/static_world_presenter.gd`
- Create: `game/gameplay/world/static_pickup_visual.gd`
- Create: `game/gameplay/world/static_spawn_marker.gd`
- Modify: `game/gameplay/actors/structure_actor.gd`
- Modify: `game/gameplay/world/combat_world.gd`
- Test: `tests/unit/test_static_world_presenter.gd`
- Modify: `tests/unit/test_combat_runtime_correctness.gd`

**Interfaces:**
- Produces: `GogoStaticWorldPresenter.configure(snapshot, arena_rect, run_seed, development_preview) -> Array[Dictionary]`, `GogoStaticSpawnMarker.play(position, callback)`, and texture-aware `GogoStructureActor.configure_visual(handle)`.
- Preserves: decorative nodes are collision-free and never modify enemy navigation or damage.

- [ ] **Step 1: Write failing deterministic consumer tests**

```gdscript
func test_world_consumes_all_eleven_assets_at_deterministic_nodes() -> void:
	var first := _build_presenter(9137)
	var second := _build_presenter(9137)
	assert_array(first.consumer_records()).is_equal(second.consumer_records())
	assert_object(first.get_node("Floor/community_server_floor")).is_not_null()
	assert_object(first.get_node("Boundary/arena_boundary_border_top")).is_not_null()
	for name in ["experience_pickup", "supply_pickup", "medical_pickup", "hazard_beacon", "supply_crate", "weapon_rack"]:
		assert_bool(first.has_node("Props/%s" % name)).is_true()

func test_release_world_does_not_place_neutral_preview_turret() -> void:
	assert_bool(_build_presenter(9137, false).has_node("Props/site_hold_turret")).is_false()
```

- [ ] **Step 2: Run focused world tests and record RED**

Expected: the presenter and named nodes do not exist.

- [ ] **Step 3: Implement floor and repeated arena boundary**

Tile `community_server_floor` in native 64-pixel cells under actors. Repeat `arena_boundary_border` on all four edges using nearest filtering and 90-degree integer rotations; a missing floor records a QA issue while the current flat `_draw` fallback remains visible.

- [ ] **Step 4: Place deterministic collision-free props and pickup visuals**

Seed a local `RandomNumberGenerator` with `run_seed`, reserve a 240-pixel player clear radius, and place decor, hazard, crate, rack, and the three pickups at stable snapped 64-pixel sockets. Missing optional handles skip only that node and append one issue.

- [ ] **Step 5: Gate the preview turret and give structures a real texture**

When `development_preview` is true, place a neutral `GogoStructureActor` at the snapped upper-right socket, remove its collision shape, and set the `site_hold_turret` texture. Release mode creates no turret unless a future owned structure definition explicitly calls the same presenter API.

- [ ] **Step 6: Delay enemy activation behind a spawn marker**

`CombatWorld._spawn_enemy` allocates the position first, creates `GogoStaticSpawnMarker`, and activates/registers the enemy only after the marker's fixed 0.35-second timer. Tests may call `complete_now()` to avoid wall-clock waiting. Missing marker texture activates immediately.

- [ ] **Step 7: Run world and combat correctness tests GREEN**

Expect exact deterministic records, eleven world consumers, no decorative collisions, marker-before-activation ordering, and unchanged nearest-target/reward behavior.

- [ ] **Step 8: Commit the world slice**

```powershell
git add game/gameplay/world/static_world_presenter.gd game/gameplay/world/static_pickup_visual.gd game/gameplay/world/static_spawn_marker.gd game/gameplay/actors/structure_actor.gd game/gameplay/world/combat_world.gd tests/unit/test_static_world_presenter.gd tests/unit/test_combat_runtime_correctness.gd
git commit -m "feat: add deterministic static world presentation"
```

### Task 6: Real-consumer registry and exact 70/70 audit

**Files:**
- Create: `game/content/assets/gogobro_static_consumer_registry.gd`
- Create: `game/content/assets/gogobro_static_coverage_audit.gd`
- Modify: `game/content/assets/gogobro_static_asset_handle.gd`
- Modify: `game/ui/static_card_presenter.gd`
- Modify: `game/ui/brotato_combat_hud.gd`
- Modify: `game/ui/screen_base.gd`
- Modify: `game/gameplay/world/static_world_presenter.gd`
- Modify: `game/gameplay/feedback/combat_feedback_presenter.gd`
- Modify: `game/gameplay/weapons/weapon_instance.gd`
- Test: `tests/unit/test_static_asset_coverage_audit.gd`

**Interfaces:**
- Produces: `GogoStaticConsumerRegistry.observe(handle, scene_path, node_path, integer_display_scale, source_kind)`, `records() -> Array[Dictionary]`, and `GogoStaticCoverageAudit.build(registry_path, snapshot, observations) -> Dictionary`.
- Report row fields: `asset_id`, `role`, `selector`, `scene`, `node`, `texture_size`, `integer_display_scale`, and `source_kind` (`approved_shipping` or `development_preview`).

- [ ] **Step 1: Write failing audit completeness tests**

```gdscript
func test_actual_consumers_cover_every_canonical_unit_once_or_more() -> void:
	var report := GogoStaticCoverageAudit.build(REGISTRY_PATH, _debug_snapshot(), _actual_consumer_fixture())
	assert_int(report["expected_units"]).is_equal(70)
	assert_int(report["covered_units"]).is_equal(70)
	assert_array(report["unresolved_asset_ids"]).is_empty()
	assert_bool(report["complete"]).is_true()

func test_gallery_node_cannot_satisfy_coverage() -> void:
	var records := _actual_consumer_fixture()
	records.append(_record(&"menu_background", "res://tools/gallery.tscn", "/Gallery/Image"))
	assert_bool(GogoStaticCoverageAudit.build(REGISTRY_PATH, _debug_snapshot(), records)["complete"]).is_true()
	assert_bool(GogoStaticCoverageAudit.is_allowed_consumer_scene("res://tools/gallery.tscn")).is_false()
```

- [ ] **Step 2: Run audit tests and record RED**

Expected: consumer registry and audit types do not exist.

- [ ] **Step 3: Add observation at the point of real texture assignment**

Weapon instances observe world sprites; card presenter observes weapon/item/upgrade icons and frames; menu/HUD controls observe global UI textures; world presenter observes eleven world assets; feedback presenter observes `projectile_hit_kit`. The registry rejects empty scene/node names and any scene under `tools/` or containing `gallery`/`preview_sheet`.

- [ ] **Step 4: Implement exact registry join and hard failures**

The audit loads the 70 canonical unit IDs, groups allowed observations by asset ID, reports missing floor/HUD shell separately as `required_visual_failures`, validates positive integer scale and texture size, and sets `complete` only when all 70 IDs have at least one valid real consumer.

- [ ] **Step 5: Serialize the machine report from integration runs**

```gdscript
var report := GogoStaticCoverageAudit.build(REGISTRY_PATH, session.static_asset_snapshot, consumer_registry.records())
var file := FileAccess.open("user://gogobro-static-coverage-v1.json", FileAccess.WRITE)
file.store_string(JSON.stringify(report, "  ", true))
```

- [ ] **Step 6: Run audit plus registry/runtime tests GREEN**

Expect 70/70 debug coverage, eight approved shipping sources plus the approved helmet source, candidate sources marked only as development preview, and release readiness still false while candidates remain unapproved.

- [ ] **Step 7: Commit the audit slice**

```powershell
git add game/content/assets/gogobro_static_consumer_registry.gd game/content/assets/gogobro_static_coverage_audit.gd game/content/assets/gogobro_static_asset_handle.gd game/ui/static_card_presenter.gd game/ui/brotato_combat_hud.gd game/ui/screen_base.gd game/gameplay/world/static_world_presenter.gd game/gameplay/feedback/combat_feedback_presenter.gd game/gameplay/weapons/weapon_instance.gd tests/unit/test_static_asset_coverage_audit.gd
git commit -m "test: enforce real consumer coverage for all static assets"
```

### Task 7: 1280×720 menu and combat evidence

**Files:**
- Create: `tests/integration/full_static_assets_menu_v1_smoke.gd`
- Create: `tests/integration/full_static_assets_combat_v1_smoke.gd`
- Create at runtime: `user://full-static-assets-menu-v1/menu-1280x720.png`
- Create at runtime: `user://full-static-assets-combat-v1/combat-1280x720.png`
- Create at runtime: `user://full-static-assets-combat-v1/gogobro-static-coverage-v1.json`

**Interfaces:**
- Consumes: actual routes, actual debug content, actual candidate overlay, live combat feedback, and consumer observations.
- Produces: two screenshots and one complete machine-readable coverage report.

- [ ] **Step 1: Write the menu smoke capture**

Configure 1280×720 windowed rendering, boot `AppKernel`, instantiate the real main menu and selection route, wait two rendered frames, assert background/wordmark/panel/button/card/zone/difficulty handles are non-null, then save the viewport image.

- [ ] **Step 2: Run the menu smoke and record visual evidence**

```powershell
E:\01_gobro\.tools\godot-4.7.1\Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/integration/full_static_assets_menu_v1_smoke.gd
```

Expected: exit 0 and a 1280×720 PNG containing every required menu consumer at actual size.

- [ ] **Step 3: Write the live six-weapon combat capture**

Create a deterministic debug session, assign six distinct ranged candidate weapon IDs plus visible item IDs, start wave one, let at least twelve shots and four contacts publish, assert the world presenter and fixed HUD nodes are visible, save the viewport, and serialize the consumer audit.

- [ ] **Step 4: Run combat smoke and inspect exact-size readability**

```powershell
E:\01_gobro\.tools\godot-4.7.1\Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/integration/full_static_assets_combat_v1_smoke.gd
```

Expected: exit 0, six distinct readable weapon silhouettes around Niko, visible projectile/contact feedback, tiled floor/border/props, fixed HUD metrics, and `complete: true` with 70 covered units.

- [ ] **Step 5: Repair only concrete capture failures**

When an assertion or actual-size inspection fails, adjust only the consuming layout/scale/anchor that caused the failure, rerun the focused test for that consumer, and regenerate both captures so evidence and code stay synchronized.

- [ ] **Step 6: Commit integration evidence scripts**

```powershell
git add tests/integration/full_static_assets_menu_v1_smoke.gd tests/integration/full_static_assets_combat_v1_smoke.gd
git commit -m "test: capture full static asset menu and combat"
```

### Task 8: Full verification and completion audit

**Files:**
- Modify only if a verified regression identifies a fault in a file from Tasks 1-7.

**Interfaces:**
- Produces: parse-clean project startup, focused and full green test output, exact 70/70 report, and two 1280×720 screenshots.

- [ ] **Step 1: Run editor import and parse verification**

```powershell
E:\01_gobro\.tools\godot-4.7.1\Godot_v4.7.1-stable_win64_console.exe --headless --editor --path . --quit
```

Expected: exit 0 without parse errors.

- [ ] **Step 2: Run the complete unit suite**

```powershell
cmd.exe /c "addons\gdUnit4\runtest.cmd --godot_binary E:\01_gobro\.tools\godot-4.7.1\Godot_v4.7.1-stable_win64.exe -a res://tests/unit"
```

Expected: all unit tests pass; no retired legacy suite is discovered.

- [ ] **Step 3: Run all relevant integration scripts**

Run static pixel sampling, shipping runtime visual, candidate combat, item appearance, button stability, the new menu capture, and the new combat capture. Every process must exit 0.

- [ ] **Step 4: Validate release/debug separation in one final focused run**

Assert release content has two approved weapons and no candidate-only definition, release snapshot is not a development preview, debug content has 12/30/6, debug snapshot state is `preview_ready` for candidates, and neither path adds another character.

- [ ] **Step 5: Inspect artifacts and coverage report**

Verify both images are exactly 1280×720 and inspect them at 100% scale. Parse the JSON report and require `expected_units == 70`, `covered_units == 70`, `unresolved_asset_ids == []`, and `complete == true`.

- [ ] **Step 6: Record final git status without disturbing unrelated user changes**

```powershell
git status --short
git log --oneline -8
```

Report only files and commits from this plan; preserve all unrelated dirty-worktree changes.

## Self-review result

- Spec coverage: Tasks 1-2 cover 12 weapons, 30 items, 6 upgrades, Niko-only scope, debug/release separation, and the approved helmet; Tasks 3-4 cover all combat/menu UI consumers; Task 5 covers all eleven world assets; Task 6 covers projectile feedback and exact 70/70 real-consumer evidence; Tasks 7-8 cover both 1280×720 captures and full verification.
- Placeholder scan: all implementation steps name concrete files, interfaces, data, assertions, commands, and expected outcomes.
- Type consistency: `GogoCombatHudSnapshot`, `GogoBrotatoCombatHud`, `GogoStaticWorldPresenter`, `GogoStaticConsumerRegistry`, and `GogoStaticCoverageAudit` use the same names and signatures in producing and consuming tasks.
