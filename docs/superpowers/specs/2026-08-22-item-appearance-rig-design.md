# Gogobro Item Appearance Rig Design

## Goal

Add reusable character item-appearance layering to the new runtime without modifying character scenes per item.

## Reference behavior

The read-only recovered project models each item with zero or more appearance resources. Each appearance has a slot, display priority, depth and sprite. At player construction, duplicate item copies do not duplicate visuals; competing appearances in one slot resolve by priority; accepted sprites sort by depth and share the player's animation transform.

Gogobro reimplements that responsibility in Godot 4 with original names, types and code.

## Content contract

`GogoAppearanceDefinition` is a reusable Resource with:

- `appearance_id: StringName`
- `texture: Texture2D`
- `slot: StringName`; empty means it never conflicts
- `display_priority: int`
- `depth: int`; negative is behind the base, positive is in front
- `offset: Vector2`
- `modulate: Color`

Both `CharacterDefinition` and `GogoItemDefinition` expose an array of appearances. Item copies contribute their appearance array only once.

## Runtime contract

`CharacterVisualRig` owns the base `AnimatedSprite2D` and all accepted `Sprite2D` overlays. It resolves slot conflicts, sorts by depth, and applies integer-authored offsets without changing texture scale. Its root receives the character's existing visual offset and scale, so base and overlays always share one transform.

`GogoPlayerActor` builds the rig from the selected character and current item IDs. Session state changes rebuild only the overlay list. Movement delegates play/pause to the rig. Weapons remain separate under `WeaponOrbit`.

## Initial boundary

The first version supports static item overlays, matching the original item's main path. Animated or action-specific overlay sheets, palette swaps, masking, equipment UI and actual item art are separate content work. Missing textures are ignored explicitly; no placeholder is silently substituted.

## Verification

One focused headless integration test covers: base animation preservation, duplicate item collapse, empty-slot stacking, same-slot priority replacement, depth ordering and rebuild after item removal. Existing Niko and five-wave smoke checks remain the only regressions run.
