# Independent Character and Weapon Content Packs

Date: 2026-08-22

## Goal

Make every playable character and every weapon an independently installable,
enableable, disableable, updateable, and replaceable content pack.

The active content catalog is immutable during a run. Pack-state changes are
applied only from the main menu. Pack files may never invalidate live character
or weapon instances.

## Current constraints

The current project has a versioned `ContentPackDef`, validation, PCK building,
and external PCK mounting, but it is still a single-pack system:

- `ContentCatalog.register_pack()` rejects a second pack.
- `BootstrapContentLoader.load_manifest()` replaces the entire catalog.
- `ContentPackDef` has no dependency or replacement metadata.
- the default pack contains all core characters and weapons.
- Niko's shipping animation resource is under `tools/`, and the release build
  copies it into a runtime directory as a special case.

Godot can mount a PCK but cannot safely unmount it in the same process. Catalog
enable/disable changes can therefore apply at the main menu, while replacing or
removing an already mounted PCK requires a controlled application restart.

## Architecture decision

Add a multi-pack registry on top of the existing trusted content definitions,
validator, builder, and catalog. Do not create a parallel content system.

There are three pack classes:

- `core`: required shared mechanics, base scenes, and content not migrated yet;
- `character`: exactly one primary playable character;
- `weapon`: exactly one primary weapon, including all of its tiers.

The core pack is always enabled. Character and weapon packs are optional.

## Source layout

```text
res://content_packs/
├── core/
│   ├── pack.tres
│   └── shared content not yet extracted
├── characters/
│   ├── niko/
│   │   ├── pack.tres
│   │   ├── character_niko.tres
│   │   ├── niko.tscn
│   │   ├── niko_animations.tres
│   │   ├── atlases/
│   │   ├── icons/
│   │   └── i18n/
│   └── <character_id>/
└── weapons/
    ├── sword/
    │   ├── pack.tres
    │   ├── weapon_sword.tres
    │   ├── sword.tscn
    │   ├── tiers/
    │   ├── sprites/
    │   ├── icons/
    │   └── i18n/
    └── <weapon_id>/
```

`tools/` contains only importers, generators, validators, and development
previews. Original videos and full candidate-frame sets remain outside the
Godot project. A pack contains only runtime assets and its manifest.

Build output uses one file per pack:

```text
dist/content_packs/character_niko-1.0.0.pck
dist/content_packs/weapon_sword-1.0.0.pck
```

## Pack contract

Extend `ContentPackDef` with:

- `pack_kind`: `core`, `character`, or `weapon`;
- `display_name_key`;
- `dependencies`: required pack IDs with minimum compatible versions.

Keep the existing `pack_id`, `pack_version`, and `content_api_version` fields.
Do not add arbitrary load priority or unrestricted overrides.

Recommended IDs are stable and lowercase:

```text
character_niko
weapon_sword
```

The content in those packs receives fully qualified stable IDs:

```text
character_niko:character/niko
weapon_sword:weapon/sword
```

Cross-pack references must use fully qualified IDs. An unqualified reference
inside the core pack remains core-relative for compatibility. New optional
packs may not rely on ambiguous unqualified references.

A replacement is a newer compatible version with the same `pack_id`. One pack
may not silently shadow another pack's stable content IDs. General-purpose mod
overrides are outside this design.

Dependencies are strict in the first version:

- missing or incompatible dependencies keep the dependent pack disabled;
- dependency cycles are rejected;
- dependencies are loaded in topological order;
- errors name the exact missing pack or incompatible version.

Optional dependencies are intentionally deferred.

## Registry and catalog

Add a `ContentPackRegistry` responsible for:

1. discovering built-in manifests and installed PCK descriptors;
2. validating paths, hashes, API versions, pack kinds, and dependencies;
3. resolving exactly one installed version for each `pack_id`;
4. calculating the enabled dependency graph;
5. building a candidate multi-pack catalog;
6. atomically publishing the candidate only after every pack passes.

Refactor `ContentCatalog` to register an ordered array of packs. Every indexed
definition retains its origin `pack_id`; stable IDs are computed using that
origin. Duplicate fully qualified IDs are rejected without mutating the live
catalog.

The live catalog is replaced as one object. UI, shops, character selection, and
run creation never observe a partially registered set of packs.

## Enable-state lifecycle

The desired enabled-pack list is stored in a versioned user configuration, not
inside project resources:

```text
user://content_packs/enabled.json
```

`core` is implicit and cannot be disabled.

During a run:

- the active catalog is an immutable snapshot;
- enable/disable requests are recorded as pending;
- no live player, weapon, shop pool, or drop table is changed.

At the main menu:

- the UI displays pending changes;
- applying changes builds and validates a candidate catalog;
- success swaps the catalog and refreshes menu-facing content;
- failure keeps the old catalog and enabled configuration byte-for-byte.

If a disabled character is referenced by the current profile, character
selection requires a new valid choice. Disabled weapons disappear from future
shops, drops, and starting-loadout choices. Save data keeps stable IDs so that
re-enabling a pack can restore the reference.

## Install, update, and removal

Installed third-party packs live outside the project:

```text
user://content_packs/installed/
```

Installation and update use a transaction:

1. copy the candidate PCK and contents descriptor to a staging name;
2. verify hashes, allowed virtual paths, manifest type, API version, and pack
   dependency metadata;
3. reject scripts, native libraries, GDExtensions, and path overlays outside the
   pack's unique namespace;
4. atomically place the verified file in the installed directory;
5. update the installed index only after the file is durable.

PCKs are mounted with file replacement disabled. Pack virtual paths must stay
inside the canonical directory containing that pack's manifest, such as
`res://content_packs/characters/niko/`. The contents descriptor records this
root, and installation rejects every entry outside it.

Enable/disable can rebuild the catalog at the main menu because disabled packs
remain mounted but unregistered. Updating, replacing, or uninstalling a PCK
that was mounted in the current process is staged and marked `restart_required`.
The main menu performs a controlled restart before the new file becomes active.

Failed validation or restart preparation keeps the previous installed version
and catalog active.

## Main-menu management surface

Add a small Content Packs screen that shows:

- pack name, kind, installed version, and enabled state;
- dependency or compatibility errors;
- pending changes;
- whether applying requires catalog reload or application restart.

The screen supports enable, disable, install, update, replace, and uninstall.
It does not edit character animation frames or weapon art.

## Niko migration

Niko is the first reference implementation:

1. create `content_packs/characters/niko/`;
2. move the Niko runtime scene, total `SpriteFrames`, atlases, icon, definition,
   and translations into that pack;
3. assign `pack_id = character_niko` and content ID `character/niko`;
4. keep the root `Niko动画工作台.tscn` as the human editing entry, referencing
   the pack's total `SpriteFrames`;
5. remove Niko runtime assets from `tools/`;
6. remove the Niko-specific release-copy workaround;
7. stop using Niko as an implicit replacement for
   `core:character/well_rounded`; Niko becomes its own catalog character;
8. verify enabled, disabled, update, rollback, and restart-required states.

Generated source clips and experimental previews may remain in `tools/` until
they are no longer needed, but the game and Niko pack may not reference them.

## Incremental migration

Do not split every current character and weapon at once.

1. implement registry, multi-pack catalog, configuration, and focused tests;
2. migrate Niko as the character-pack template;
3. migrate one simple weapon as the weapon-pack template;
4. add the main-menu management screen;
5. require all new characters and weapons to use the templates;
6. migrate existing core content gradually, keeping `main` runnable after every
   extraction.

The core pack may temporarily contain legacy characters and weapons. A migrated
definition must be removed from core in the same change that introduces its
independent pack, preventing duplicate IDs.

## Failure behavior

- A bad optional pack never prevents the core game from starting.
- A candidate catalog is never published partially.
- Missing dependencies and ID collisions are explicit user-visible errors.
- A failed update preserves the previous pack file and enabled state.
- Pack changes are refused while a run is active.
- A restart-required operation cannot claim success until the restarted process
  validates and activates the staged version.

## Focused acceptance checks

- core plus two independent packs can register simultaneously;
- character and weapon packs can be enabled and disabled independently at the
  main menu;
- a running session keeps its original catalog snapshot;
- duplicate IDs, dependency cycles, missing dependencies, and incompatible API
  versions fail atomically;
- an updated PCK is staged and requires restart when the old version is mounted;
- failed replacement restores the previous installed index and pack file;
- disabled content disappears from new selections and shop pools;
- Niko has no runtime dependency on `tools/`;
- release output contains one independently versioned PCK per migrated pack.

Only focused registry, catalog, PCK transaction, Niko migration, and one real
headless integration sample are required. Unrelated gameplay suites are not
part of this migration gate.
