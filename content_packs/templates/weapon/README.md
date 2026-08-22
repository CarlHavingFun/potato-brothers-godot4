# Independent weapon pack template

Copy this directory to `content_packs/weapons/<name>/` and rename
`pack.tres.example` to `pack.tres`.

- Pack ID: `weapon_<name>` using lowercase letters, digits, and underscores.
- Pack kind: `ContentPackDef.PackKind.WEAPON` (`2`).
- Exactly one `WeaponDef` with local ID `weapon/<name>` and all of its tiers.
- Declare `core` as a dependency. Cross-pack references must be fully
  qualified; optional packs never silently override another pack.
- Keep tiers, scenes, sprites, icons, and translations below this directory.
  Do not include scripts, native libraries, source videos, or candidate frames.
- Register built-in shipping packs in `content_packs/builtin_packs.json`.

The generic release script discovers every
`content_packs/weapons/*/pack.tres`, produces a versioned PCK plus descriptor,
and places them under `dist/content_packs/` and each platform build.

Enable or disable it from **Content Packs** on the main menu. Catalog changes
apply only when no run is active; mounted update/removal requires restart.
