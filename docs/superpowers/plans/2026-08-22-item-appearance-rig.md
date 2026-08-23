# Item Appearance Rig Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add data-driven, priority-resolved item appearance overlays to every Gogobro character.

**Architecture:** A generic appearance Resource is referenced by character and item definitions. A runtime `CharacterVisualRig` owns the base animation and static overlay sprites; `GogoPlayerActor` supplies owned item definitions and delegates animation state.

**Tech Stack:** Godot 4.7, typed GDScript, SpriteFrames, Sprite2D.

**Spec:** `docs/superpowers/specs/2026-08-22-item-appearance-rig-design.md`

## Global Constraints

- Reimplement recovered-project responsibilities without copying its source, IDs or assets.
- Keep weapons outside the visual rig.
- Do not modify character `.tscn` files per appearance.
- Preserve Niko's 128px authored atlas at runtime scale 1.
- Run one focused appearance test plus the existing Niko and five-wave smoke checks.

---

### Task 1: Appearance content contract and runtime rig

**Files:**
- Create: `game/content/appearance_definition.gd`
- Modify: `game/content/item_definition.gd`
- Modify: `game/content/character_definition.gd`
- Create: `game/gameplay/actors/character_visual_rig.gd`
- Test: `tests/integration/item_appearance_v2_smoke.gd`

**Interfaces:**
- Produces: `CharacterVisualRig.configure(character, appearances)`, `rebuild_appearances(appearances)`, and `set_moving(moving)`.
- Consumes: `CharacterDefinition.sprite_frames`, `default_animation`, `visual_offset`, `visual_scale` and appearance arrays.

- [ ] **Step 1: Write the failing integration test**

Create two same-slot appearances with different priorities, one empty-slot appearance, and duplicate ownership. Assert that only the higher-priority same-slot sprite and one empty-slot sprite are created in depth order.

- [ ] **Step 2: Run the test to verify RED**

Run: `Godot_v4.7-stable_win64_console.exe --headless --path . --script res://tests/integration/item_appearance_v2_smoke.gd`

Expected: failure because `appearance_definition.gd` and `CharacterVisualRig` do not exist.

- [ ] **Step 3: Implement the Resource and rig**

Add the exported fields from the design. Resolve non-empty slots by greatest priority with later equal-priority input winning, preserve every empty-slot appearance, sort by `(depth, appearance_id)`, and create nearest-filtered `Sprite2D` children without scaling them.

- [ ] **Step 4: Run the focused test to verify GREEN**

Run the Step 2 command and require exit code 0 with `ITEM_APPEARANCE_V2_SMOKE_OK`.

### Task 2: Player integration and regression verification

**Files:**
- Modify: `game/gameplay/actors/player_actor.gd`
- Modify: `tests/integration/niko_v2_smoke.gd`

**Interfaces:**
- Consumes: `CharacterVisualRig` from Task 1.
- Produces: `GogoPlayerActor.rebuild_appearances()` and a `VisualRig/CharacterVisual` runtime hierarchy.

- [ ] **Step 1: Extend the failing test through the real player actor**

Build a session with duplicate item IDs and assert the player's live rig resolves and rebuilds its overlays.

- [ ] **Step 2: Implement actor integration**

Replace direct base-sprite construction with the rig, collect unique owned item definitions, connect session state changes, and delegate moving/stopped animation state.

- [ ] **Step 3: Run focused and existing smoke checks**

Run the item appearance smoke, `niko_v2_smoke.gd`, and `gogobro_v2_headless_smoke.gd`. Run `git diff --check`.

- [ ] **Step 4: Commit**

Commit the scoped content, rig, actor, tests and design documents on `main`.
