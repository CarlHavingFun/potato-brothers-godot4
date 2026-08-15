# Runtime Regression Fix Design

## Scope

Fix four player-visible regressions without changing combat balance outside the confirmed contact-damage cadence:

- Fullscreen can always be left with F11 or Alt+Enter, including while paused.
- Character and weapon selection cards show a persistent, mutually exclusive selection indicator.
- Weapons resolve an enemy detection Area2D back to its owning Enemy and resume automatic attacks.
- Enemy body contact repeats damage every 0.75 seconds while overlap continues; projectiles and player melee remain single-hit.

## Design

`Global` owns the window-mode shortcut because it is an always-present autoload. It processes input while the scene tree is paused, updates `MetaProgress.fullscreen`, applies the display mode, and persists the setting. The existing Settings panel remains the discoverable menu route.

`SelectionCard` becomes a toggle button with a visible selected overlay. `SelectionPanel` assigns separate `ButtonGroup` instances to character and weapon cards so each row has exactly one selection while preserving the selected choice until Continue.

`Weapon` stores `Enemy` nodes, not the overlapping hurtbox Areas. Entry and exit handlers resolve `area.get_parent()` and ignore unrelated Areas. Target cleanup also removes invalid or freed enemies before nearest-target selection.

`HitboxComponent.repeat_interval` defaults to zero. Only enemy contact hitboxes opt into `0.75`; `HurtboxComponent` tracks those overlaps and re-emits damage on the configured interval until `area_exited`. This avoids changing projectile and player melee semantics.

## Verification

GdUnit regression tests cover shortcut state, selection visuals/groups, target resolution and cooldown start, and repeated-vs-single-hit behavior. Final verification runs the complete suite under Godot 4.7.1, then performs a live Godot MCP play/input/runtime-tree/error/screenshot cycle using a 4.7.1 editor.
