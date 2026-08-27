# Brotato-Structured UI Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the border-heavy generic screens with dedicated 1280×720 shop, upgrade, Niko character-selection, weapon-selection, difficulty-selection, and combat-HUD layouts that match Brotato's information hierarchy while retaining original GOGOBRO art.

**Architecture:** `GogoScreenBase` supplies only background, typography, spacing, button states, and one optional principal surface; each gameplay screen owns its dedicated composition. A shared stat-list presenter, loadout strip, and compact card presenter keep data and interaction behavior consistent without nesting ornamental frames.

**Tech Stack:** Godot 4.7 typed GDScript, Control nodes, StyleBoxFlat/StyleBoxTexture, GdUnit4, non-headless Windows/OpenGL screenshot tests.

**Spec:** `docs/superpowers/specs/2026-08-27-full-static-assets-brotato-hud-design.md`

## Global Constraints

- Reference size is native 1280×720; do not scale an entire 320×180 interface.
- No decorative frame around the viewport.
- A card, button, slot, or stats surface gets at most one outline.
- A bordered panel may not contain another bordered panel except the icon's single rarity cue.
- Shop and upgrade reward show exactly four choices.
- Character selection contains exactly one real character: Niko.
- Missing textures retain readable, interactive flat-color fallbacks.
- All runtime data comes from canonical session/content state; screenshot-only fake rows are forbidden.

## File structure

| File | Responsibility |
|---|---|
| `game/ui/screen_base.gd` | Full-screen background, native-size safe region, text hierarchy, and flat fallback styles. |
| `game/ui/static_card_presenter.gd` | One-outline cards with physical icons, localized stats, rarity accent, state, and price. |
| `game/ui/stat_list_presenter.gd` | Shared player-stat rows for shop and upgrade screens. |
| `game/ui/loadout_strip_presenter.gd` | Six weapon slots and compact acquired-item strip with attached sell/combine actions. |
| `game/ui/shop_screen.gd` | Dedicated top/offer/stats/loadout/continue composition. |
| `game/ui/upgrade_screen.gd` | Dedicated four-choice reward composition and reroll. |
| `game/ui/character_select_screen.gd` | One-cell Niko roster and right-side Niko detail. |
| `game/ui/weapon_select_screen.gd` | Low-border weapon grid using CS names and readable icons. |
| `game/ui/difficulty_select_screen.gd` | Low-border difficulty grid and selected-state summary. |
| `game/ui/brotato_combat_hud.gd` | Native 1280×720 timer, wave, health, XP, material, weapon, and item hierarchy. |
| `tests/unit/test_brotato_structured_screens.gd` | Exact node, card-count, border-budget, Niko-only, and fallback assertions. |

---

### Task 1: Replace the generic framed shell with low-border primitives

**Files:**
- Modify: `game/ui/screen_base.gd`
- Modify: `game/ui/static_card_presenter.gd`
- Create: `game/ui/stat_list_presenter.gd`
- Create: `game/ui/loadout_strip_presenter.gd`
- Create: `tests/unit/test_brotato_structured_screens.gd`

**Interfaces:**
- Produces: `build_screen_chrome(title: String, subtitle: String = "") -> Control` without a centered full-height panel.
- Produces: `GogoStatListPresenter.build(player: SessionPlayerState, content: GogoContentSnapshot) -> VBoxContainer`.
- Produces: `GogoLoadoutStripPresenter.build(player, content, snapshot, actions: Dictionary) -> Control`.

- [ ] **Step 1: Write failing border-budget tests**

```gdscript
func test_base_has_no_full_viewport_or_nested_ornamental_frame() -> void:
	var screen := _screen_fixture()
	screen.build_screen_chrome("标题")
	assert_bool(screen.has_node("StaticNineSlicePanel")).is_false()
	assert_int(_count_ornamental_ancestors(screen)).is_equal(0)

func test_card_uses_one_outline_and_one_rarity_accent() -> void:
	var card := GogoStaticCardPresenter.build_card(_item(), "12", _snapshot())
	assert_int(_count_stylebox_borders(card)).is_less_equal(1)
	assert_int(card.find_children("RarityAccent", "ColorRect", true, false).size()).is_equal(1)
```

- [ ] **Step 2: Run the focused test and record RED**

```powershell
tools\run_tests.ps1 -TestPath res://tests/unit/test_brotato_structured_screens.gd -ReportDir reports/brotato-ui-red
```

Expected: the generic `StaticNineSlicePanel` still wraps the complete screen and the new presenters do not exist.

- [ ] **Step 3: Implement flat screen chrome**

Keep `StaticMenuBackground` and `ReadabilityVeil`, then add a 64-pixel title band and an unframed content root with 32-pixel screen margins. `nine_slice_panel` is available only through `add_principal_surface(rect: Rect2)`. Replace rounded antialiased two-pixel default borders with hard one-pixel borders and `anti_aliasing = false`.

- [ ] **Step 4: Rebuild the card hierarchy**

Use a single flat dark card backing, a 64×64 nearest-neighbor icon, a four-pixel left rarity accent, 18-pixel name, two localized stat rows, and right-aligned price/state. Do not modulate an authored rarity frame and do not place a framed button inside a framed card; the card itself is the button.

- [ ] **Step 5: Add localized shared stat and loadout presenters**

The stat list maps canonical keys to Chinese labels and renders value changes by color without row borders. The loadout strip has six 72×72 weapon cells, each with one rarity edge, followed by compact 48×48 item icons and `+N`; sell/combine buttons attach inside the selected weapon cell only.

- [ ] **Step 6: Run focused tests GREEN and commit**

```powershell
tools\run_tests.ps1 -TestPath res://tests/unit/test_brotato_structured_screens.gd -ReportDir reports/brotato-ui-primitives
git add game/ui/screen_base.gd game/ui/static_card_presenter.gd game/ui/stat_list_presenter.gd game/ui/loadout_strip_presenter.gd tests/unit/test_brotato_structured_screens.gd
git commit -m "feat: add low-border Brotato UI primitives"
```

### Task 2: Build the dedicated shop composition

**Files:**
- Modify: `game/ui/shop_screen.gd`
- Modify: `tests/unit/test_brotato_structured_screens.gd`
- Modify: `tests/integration/full_static_assets_menu_v1_smoke.gd`

**Interfaces:**
- Consumes: `ShopRuntimeService`, shared stat presenter, loadout presenter, and card presenter.
- Produces named nodes: `TopBand/Wave`, `TopBand/Materials`, `TopBand/Reroll`, `OfferRow`, `StatsColumn`, `LoadoutBar`, and `ContinueButton`.

- [ ] **Step 1: Write failing exact-layout tests**

```gdscript
func test_shop_has_four_offers_stats_loadout_and_continue() -> void:
	var shop := await _route_shop()
	assert_int(shop.get_node("OfferRow").get_child_count()).is_equal(4)
	assert_bool(shop.has_node("StatsColumn")).is_true()
	assert_int(shop.get_node("LoadoutBar/Weapons").get_child_count()).is_equal(6)
	assert_bool(shop.has_node("ContinueButton")).is_true()
```

- [ ] **Step 2: Run the test and record RED**

Expected: current shop is a vertical generic list and has no dedicated nodes.

- [ ] **Step 3: Build the 1280×720 shop layout**

Place the top band at `Rect2(32, 20, 1216, 64)`, four 220×250 offer cards in `OfferRow` at the left/center, a 250-pixel stats column at the right, and the loadout bar from y=570 to 688. Show reroll cost on the reroll button, lock state on each offer card, and attach buy behavior to the card.

- [ ] **Step 4: Preserve every existing shop action**

Route buy, lock, reroll, sell, combine, and continue through the existing `ShopRuntimeService`. Rebuild from canonical state after each action and restore focus by content ID so controller navigation remains stable.

- [ ] **Step 5: Run unit and real-route capture tests GREEN and commit**

```powershell
tools\run_tests.ps1 -TestPath res://tests/unit/test_brotato_structured_screens.gd -ReportDir reports/shop-layout
cmd.exe /c "addons\gdUnit4\runtest.cmd --godot_binary E:\01_gobro\.tools\godot-4.7.1\Godot_v4.7.1-stable_win64.exe -c -a res://tests/integration/full_static_assets_menu_v1_smoke.gd"
git add game/ui/shop_screen.gd tests/unit/test_brotato_structured_screens.gd tests/integration/full_static_assets_menu_v1_smoke.gd
git commit -m "feat: rebuild shop with Brotato information hierarchy"
```

### Task 3: Build the four-choice upgrade reward screen

**Files:**
- Modify: `game/ui/upgrade_screen.gd`
- Modify: `game/gameplay/rules/player_build_service.gd`
- Modify: `tests/unit/test_brotato_structured_screens.gd`
- Modify: `tests/integration/full_static_assets_menu_v1_smoke.gd`

**Interfaces:**
- Produces named nodes: `RewardStatus`, `StatsColumn`, `UpgradeChoiceRow`, and `RerollButton`.
- Preserves: choosing a card decrements `pending_upgrade_count`, presents the next reward when nonzero, and routes to shop at zero.

- [ ] **Step 1: Write failing four-choice and route tests**

```gdscript
func test_upgrade_reward_has_exactly_four_real_choices() -> void:
	var screen := await _route_upgrade()
	assert_int(screen.get_node("UpgradeChoiceRow").get_child_count()).is_equal(4)
	assert_bool(screen.has_node("StatsColumn")).is_true()
	assert_bool(screen.has_node("RerollButton")).is_true()
```

- [ ] **Step 2: Run the test and record RED**

Expected: the current screen shows at most three choices in one column and has no reroll.

- [ ] **Step 3: Implement deterministic four-card rewards and reroll**

Show the stat column on the left and four 210×280 upgrade cards across the center/right. Seed selection from session state, charge the displayed material reroll cost through canonical state, and never duplicate a choice within one offer set.

- [ ] **Step 4: Verify state flow and commit**

```powershell
tools\run_tests.ps1 -TestPath res://tests/unit/test_brotato_structured_screens.gd -ReportDir reports/upgrade-layout
git add game/ui/upgrade_screen.gd game/gameplay/rules/player_build_service.gd tests/unit/test_brotato_structured_screens.gd tests/integration/full_static_assets_menu_v1_smoke.gd
git commit -m "feat: add four-choice upgrade reward screen"
```

### Task 4: Build Niko-only character selection and unify setup screens

**Files:**
- Modify: `game/ui/character_select_screen.gd`
- Modify: `game/ui/weapon_select_screen.gd`
- Modify: `game/ui/difficulty_select_screen.gd`
- Modify: `tests/unit/test_brotato_structured_screens.gd`
- Modify: `tests/integration/full_static_assets_menu_v1_smoke.gd`

**Interfaces:**
- Character nodes: `BackButton`, `RosterGrid`, `NikoCell`, `NikoDetail/Preview`, `NikoDetail/Name`, `NikoDetail/Traits`, and `ConfirmButton`.
- Setup screens consume the same card/button/selected-state language and never create fake entries.

- [ ] **Step 1: Write failing Niko-only detail tests**

```gdscript
func test_character_screen_has_one_niko_cell_and_real_detail() -> void:
	var screen := await _route_character_select()
	assert_int(screen.get_node("RosterGrid").get_child_count()).is_equal(1)
	assert_str(String(screen.get_node("NikoCell").get_meta("content_id"))).is_equal("character.niko:character/niko")
	assert_object(screen.get_node("NikoDetail/Preview").texture).is_not_null()
	assert_bool(screen.get_node("NikoDetail/Traits").text.is_empty()).is_false()
```

- [ ] **Step 2: Run the test and record RED**

Expected: current screen is a zone thumbnail plus a generic Niko button.

- [ ] **Step 3: Implement the roster/detail composition**

Place back/title at the top, a compact roster surface on the left, and a large Niko preview plus canonical traits/starting summary on the right. Use the real Niko content definition and existing Niko texture; do not duplicate the tile to fill space.

- [ ] **Step 4: Apply the same low-border language to weapon and difficulty selection**

Weapon cards show the new CS name, icon, melee/ranged label, damage, cooldown, and selected fill. Difficulty cards show the canonical badge, concise modifiers, and selected fill. Preserve existing route order and selection draft keys.

- [ ] **Step 5: Run setup-flow tests and commit**

```powershell
tools\run_tests.ps1 -TestPath res://tests/unit/test_brotato_structured_screens.gd -ReportDir reports/setup-layout
cmd.exe /c "addons\gdUnit4\runtest.cmd --godot_binary E:\01_gobro\.tools\godot-4.7.1\Godot_v4.7.1-stable_win64.exe -c -a res://tests/integration/full_static_assets_menu_v1_smoke.gd"
git add game/ui/character_select_screen.gd game/ui/weapon_select_screen.gd game/ui/difficulty_select_screen.gd tests/unit/test_brotato_structured_screens.gd tests/integration/full_static_assets_menu_v1_smoke.gd
git commit -m "feat: rebuild Niko and setup selection screens"
```

### Task 5: Finish the native 1280 combat HUD and border audit

**Files:**
- Modify: `game/ui/brotato_combat_hud.gd`
- Modify: `game/ui/combat_screen.gd`
- Modify: `tests/unit/test_brotato_combat_hud.gd`
- Modify: `tests/unit/test_combat_static_ui_consumers.gd`

**Interfaces:**
- Consumes: `GogoCombatHudSnapshot` only.
- Produces: timer/wave top center, health bottom left, XP bottom center, materials bottom right, six weapon cells along the lower edge, and compact item icons on the right.

- [ ] **Step 1: Add failing native-size and border-budget assertions**

```gdscript
func test_hud_uses_native_1280_layout_without_full_screen_frame() -> void:
	var hud := _configured_hud()
	assert_vec2(hud.size).is_equal(Vector2(1280, 720))
	assert_bool(hud.has_node("FullScreenOrnamentalFrame")).is_false()
	assert_int(hud.get_node("WeaponStrip").get_child_count()).is_equal(6)
	assert_bool(hud.get_node("TopCenter/Timer").position.y < hud.get_node("TopCenter/Wave").position.y).is_true()
```

- [ ] **Step 2: Run focused tests and record RED**

Expected: any remaining logical-canvas scaling or nested HUD frames violate the new assertions.

- [ ] **Step 3: Apply native coordinates and one-backing-per-metric rule**

Keep pixel icons at integer scales, but place labels and controls directly in 1280×720 space. A metric group may have one dark backing or one outline, never both. Keep world visibility between groups and collapse item overflow to `+N`.

- [ ] **Step 4: Run HUD tests GREEN and commit**

```powershell
tools\run_tests.ps1 -TestPath res://tests/unit/test_brotato_combat_hud.gd -ReportDir reports/native-hud
tools\run_tests.ps1 -TestPath res://tests/unit/test_combat_static_ui_consumers.gd -ReportDir reports/hud-consumers
git add game/ui/brotato_combat_hud.gd game/ui/combat_screen.gd tests/unit/test_brotato_combat_hud.gd tests/unit/test_combat_static_ui_consumers.gd
git commit -m "feat: finish native low-border combat HUD"
```

## Self-review result

- Spec coverage: dedicated shop, four-choice upgrades, Niko-only character selection, unified setup flow, native combat HUD, fallbacks, and all border-budget rules are assigned to Tasks 1-5.
- Placeholder scan: every layout has exact named regions, counts, data sources, tests, commands, and state transitions.
- Type consistency: shared presenters consume the same session/content/static-snapshot types used by every screen.

