# Potato Brothers Fusion Design

## Product boundary

Phase 1 is a complete ten-wave game. It merges the strongest existing content
from both local projects, keeps the tutorial's universal dash, defaults to
automatic targeting, and provides optional mouse aiming. Phase 2 does not begin
until the phase-1 build has passed automated checks and a user playtest.

## Content

- Six characters: Well Rounded, Knight, Brawler, Bunny, Crazy, and Almighty.
- Eleven four-tier weapon families. Fist, Pistol, and SMG merge both sources.
- Twenty passive items.
- Sixteen stat families, each with common, rare, epic, and legendary upgrades.
- Seven normal or special enemies plus MouseDog as the wave-ten boss.
- Five difficulties with increasing health, damage, speed, and spawn density.

## Architecture

Static Godot resources are immutable definitions. A fresh `RunState` owns all
mutable state for one run, while `MetaProgress` owns unlocks and settings.
`RunDirector` controls phases; dedicated wave, combat, inventory, shop, and
reward services implement rules without mutating shared resources.

Content uses stable identifiers and translation keys. Unity JSON is migration
input only. Production builds never read the Unity project or call its former
remote services.

## Quality strategy

GdUnit4 is the deterministic regression gate. Godot MCP/CLI drives the live
editor and game for scene-tree, collision, input, runtime-error, screenshot,
and performance verification. Development addons and tests are excluded from
exports.

