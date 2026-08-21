# 《土豆兄弟》1:1 战斗 HUD、金钱与满栏合成 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Follow strict test-first development for every behavior change.

**Goal:** Rebuild the combat HUD against the locally installed Brotato 1280×720 reference, correct the material visual and affordability feedback, and support atomic full-inventory weapon purchase merging without regressing existing post-wave, rarity, save, or skin behavior.

**Architecture:** A focused `CombatHud` consumes the existing `HudState` instead of letting `Arena` own presentation details. Inventory and shop services own purchase transactions; UI projects their detailed outcome. The formal skin remains the sole art source and retains the existing validated 64→256 nearest-neighbor asset contract.

**Tech Stack:** Godot 4.7.1 Standard, GDScript, GdUnit4 6.2.0, sprite-gen 1.59.2, PowerShell release tooling.

## Global Constraints

- Work incrementally in the current dirty checkout. Preserve all pre-existing user edits; never reset, discard, or bulk-rewrite unrelated files.
- Reference geometry is measured at 1280×720 and mapped by exactly 1.5 to the 1920×1080 logical canvas.
- Do not copy proprietary Brotato image or font files. Use original art and official open-source font downloads with license records.
- Real reward chest visuals and probability logic remain unchanged. Only `pickup.material` is replaced.
- Existing content-pack APIs, plugin APIs, and save schema remain compatible.
- Godot binary for this run: `E:/01_gobro/.tools/godot-4.7.1/Godot_v4.7.1-stable_win64_console.exe`.
- Because the checkout was dirty before this plan, do not create commits. Report exact files changed and test evidence; the controller reviews per-task snapshots.

---

### Task 1: Atomic full-slot weapon purchase and live affordability

**Files:**
- Modify: `core/state/inventory_state.gd`
- Modify: `core/services/inventory_service.gd`
- Modify: `core/services/shop_service.gd`
- Modify: `autoloads/global.gd`
- Modify: `scenes/ui/shop_card/shop_card.gd`
- Modify: `scenes/ui/shop_panel/shop_panel.gd`
- Modify: `scenes/ui/upgrade_panel/upgrade_panel.gd`
- Modify: default English and Chinese localization catalogs
- Test: inventory, shop service, shop feedback, and upgrade/shop panel suites

**Requirements:**

- Add a detailed purchase result that reports result code, normal-add versus auto-merge mode, target slot, and resulting tier while preserving all existing integer-returning APIs.
- Only when the weapon inventory is full, merge the offered weapon into the lowest matching same-ID/same-tier slot when the tier is below 4. Keep free-slot purchases unchanged.
- Validate everything before mutation. On any failure, money, inventory, shop offer, and paid value remain unchanged. Successful merge adds the purchase price to the retained slot's paid value.
- Show a localized `Buy & Merge → Tier N` preview only when the current full inventory makes that transaction valid.
- All item, shop-refresh, and upgrade-refresh costs turn red when unaffordable, remain clickable, and return to white immediately after materials change.
- Resynchronize runtime weapon nodes, `Global.equipped_weapons`, and shop inventory cards from authoritative inventory order after auto-merge.

### Task 2: Open-source reference font stack and visual tokens

**Files:**
- Add: official Anybody Medium and Noto Sans SC Medium font assets plus their licenses
- Add: a Godot font fallback resource
- Modify: formal skin theme and skin manifest
- Modify: `tools/build_release.ps1`
- Modify: `docs/THIRD_PARTY.md`
- Test: skin presentation, localization presentation, and release configuration suites

**Requirements:**

- English and numeric glyphs use Anybody Medium; Chinese glyphs fall back to Noto Sans SC Medium.
- Bundle official upstream open-source files, record versions/sources/licenses, and update release closure validation.
- Keep the established dark panels, 2px body/button outlines, 4px headings, and 6px combat-number outlines. Do not reintroduce duplicate corner overrides or hover scaling.

### Task 3: Dedicated Brotato-reference CombatHud and non-overlapping UI states

**Files:**
- Add: `scenes/ui/combat_hud/combat_hud.gd`
- Add: `scenes/ui/combat_hud/combat_hud.tscn`
- Add: reference HUD metrics resource/script
- Modify: `scenes/arena/arena.gd`
- Modify: `scenes/arena/arena.tscn`
- Modify: pause, shop, and settlement UI scenes/scripts as required
- Test: new CombatHud scene suite plus game-root, stats-container, and shop-panel suites

**Requirements:**

- `CombatHud.apply_state(state: HudState)` is the single arena HUD update entry point; optional boss and transient-notice APIs remain separate.
- At the 1280 reference: top-left contains only HP, XP/level, materials, and material bag; top-center contains only wave and timer. Remove the bottom vitals and persistent encounter/next-wave/pickup copy.
- Map every measured coordinate by 1.5 into the logical canvas and keep key anchors within ±2 reference pixels.
- Preserve the current post-wave snapshot through UPGRADE → CHEST → SHOP and settlement (victory/defeat), matching the user's latest explicit requirement that those states keep the final battlefield frame. Release it only on next wave, restart/reset, title return, or process exit.
- Pause, defeat, victory, and boss states reuse the same HUD anchors. Stats stay a fixed 16-row, non-scroll column.
- Shop right rail is a vertical container with stats above and next-wave/refresh controls below; weapon/passive inventory is a separate footer row. No rectangles overlap at 1280×720, 1600×900, or 1920×1080.

### Task 4: Pixel-perfect red-X enemy spawn telegraph

**Files:**
- Modify: `scenes/effects/enemy_spawn_effect.gd`
- Modify: `scenes/effects/enemy_spawn_effect.tscn`
- Test: spawner/effect scene tests

**Requirements:**

- Replace the texture-based marker with an integer-coordinate red X drawn by the effect node.
- Preserve the exact 0.8-second spawn delay and provide three visible flashes before the animation-finished signal.
- No current spawn texture is resolved, and enemy creation still happens only after the telegraph finishes.

### Task 5: Curated glowing gold-shard material sprite

**Files:**
- Replace: `content_packs/skins/lets_gooooo/assets/pickups/material.png`
- Modify: formal skin asset manifest and generated asset metadata only as required
- Test: skin asset validator and skin presentation suites

**Requirements:**

- Use sprite-gen's component-row/pixel-unfake pipeline and install only curated output, never a raw generation.
- Logical art is one irregular 64×64 gold shard with a dark-gold body, bright 1px inner rim, and sparse hard-alpha edge highlights; output is exactly 256×256 by 4× nearest scaling.
- Preserve hard transparency and the existing material semantic so world drops, HUD, and shop all update together. Do not change `pickup.chest` or reward probabilities.
- Update the manifest hash/source record and pass deterministic asset validation.

### Task 6: Integrated visual verification and Windows release

**Files:**
- Add or modify only targeted regression tests and playtest documentation needed by the completed behavior
- Generated deliverables: `dist/game-prototype/windows/GamePrototype.exe`, Windows zip, and release manifest

**Requirements:**

- Run focused tests after each task, then the complete GdUnit suite, skin validator, import, phase-one acceptance, and Windows smoke export.
- Capture local QA screenshots at 1280×720, 1600×900, and 1920×1080 for combat, pause, post-wave/shop, and settlement. Brotato references stay local and untracked.
- Verify first-wave rarity limits, queued upgrades, fixed stats, post-wave snapshot lifetime, font fallback, red prices, auto-merge, and material/chest semantic separation.
- Produce the Windows executable, `GamePrototype-Windows-x86_64.zip`, and SHA-256 release manifest under `dist/game-prototype`.
