# Independent Content Packs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Support independently versioned character and weapon packs that can be enabled or disabled at the main menu, with Niko as the first migrated character pack.

**Architecture:** Extend the existing content contract and catalog into an atomic multi-pack registry. Core stays mandatory; optional packs are validated and merged into a candidate catalog, then swapped only at the main menu. Mounted PCK replacement is staged and applied after a controlled restart.

**Tech Stack:** Godot 4.7.1, typed GDScript resources/services, PCKPacker, JSON user configuration, GdUnit4.

**Spec:** `docs/superpowers/specs/2026-08-22-independent-content-packs-design.md`

## Global Constraints

- `core` is always enabled and cannot be replaced by an optional pack.
- One character or one weapon equals one independent pack.
- Pack changes never mutate the catalog during an active run.
- Cross-pack references use fully qualified stable IDs.
- Optional packs contain no scripts, native libraries, or GDExtensions.
- PCK virtual files stay below the pack manifest directory and mount with replacement disabled.
- Enable/disable applies at the main menu; mounted PCK update/removal requires restart.
- Original videos and candidate frames remain outside the Godot project.
- Only focused content-pack, Niko integration, frontend, and one external-PCK test are run.

---

### Task 1: Pack contract and multi-pack catalog

**Files:**
- Create: `core/content/content_pack_dependency.gd`
- Modify: `core/content/content_pack_def.gd`
- Modify: `core/content/content_def.gd`
- Modify: `core/content/content_catalog.gd`
- Modify: `tests/unit/test_content_pack.gd`

**Interfaces:**
- Produces: `ContentPackDependency(pack_id, minimum_version)` resource contract.
- Produces: `ContentCatalog.register_packs(packs: Array[ContentPackDef], active_balance_pack: BalancePackDef = null) -> int`.
- Produces: `ContentDef.origin_pack_id`, used before a caller-supplied fallback pack ID.

- [ ] **Step 1: Write failing catalog tests**

Add tests constructing `core`, `character_niko`, and `weapon_sword` packs. Assert that `register_packs()` exposes all three fully qualified IDs, preserves legacy core-relative queries, records origin IDs, and rejects duplicate stable IDs atomically.

- [ ] **Step 2: Run the focused suite and observe RED**

Run:

```powershell
tools/run_tests.ps1 -GodotBinary E:\01_gobro\.tools\godot-4.7.1\Godot_v4.7.1-stable_win64.exe -TestPath res://tests/unit/test_content_pack.gd
```

Expected: failures because dependency metadata and `register_packs()` do not exist.

- [ ] **Step 3: Implement the minimal contract**

`ContentPackDependency` exports `pack_id: StringName` and `minimum_version: String`. `ContentPackDef` adds a `PackKind` enum, `pack_kind`, `display_name_key`, and `dependencies`. `ContentDef.get_stable_id()` prefers `origin_pack_id`. `register_pack()` remains a compatibility wrapper over `register_packs([pack])`.

- [ ] **Step 4: Implement atomic multi-pack indexing**

Build all candidate dictionaries locally. Assign every definition's `origin_pack_id` while indexing. Publish member dictionaries only after every pack passes. Keep `catalog.pack_id = &"core"` as the legacy unqualified-query namespace.

- [ ] **Step 5: Run GREEN and commit**

Expected: focused suite exits 0 with no failures.

Commit: `feat: add atomic multi-pack content catalog`.

### Task 2: Registry, dependency resolution, and enabled-state store

**Files:**
- Create: `core/content/content_pack_registry.gd`
- Create: `core/content/content_pack_state_store.gd`
- Create: `tests/unit/test_content_pack_registry.gd`

**Interfaces:**
- Produces: `ContentPackRegistry.build_candidate(core_pack, optional_packs, enabled_ids, balance_pack) -> Dictionary` with `catalog`, `active_pack_ids`, `errors`, and `restart_required`.
- Produces: `ContentPackStateStore.load_state() -> Dictionary` and `save_enabled(pack_ids: PackedStringArray) -> Error`.

- [ ] **Step 1: Write failing registry tests**

Cover dependency order, missing dependency, minimum-version mismatch, dependency cycle, disabled dependency, mandatory core, duplicate pack version, and atomic failure preserving the caller's existing catalog.

- [ ] **Step 2: Write failing store tests**

Use a `user://tests/content_pack_state/` root. Assert default state, deterministic JSON, temporary-file replacement, backup recovery, and byte-for-byte preservation when replacement is injected to fail.

- [ ] **Step 3: Run RED**

Run only `test_content_pack_registry.gd`; expect missing service failures.

- [ ] **Step 4: Implement strict dependency resolution**

Resolve one pack per `pack_id`, validate semantic `major.minor.patch` versions, topologically sort dependencies, reject cycles, and call `ContentCatalog.register_packs()` only after graph validation.

- [ ] **Step 5: Implement atomic enabled-state persistence**

Store schema version 1 at `user://content_packs/enabled.json`. `core` is omitted from the file and injected by the registry. Write `.tmp`, rotate `.bak`, rename, and restore on failure using the same transaction shape as `SettingsStore`.

- [ ] **Step 6: Run GREEN and commit**

Commit: `feat: add content pack registry and state store`.

### Task 3: Bootstrap integration and main-menu apply boundary

**Files:**
- Modify: `core/content/bootstrap_content_loader.gd`
- Modify: `scenes/ui/frontend/frontend_shell.gd`
- Modify: `scenes/ui/frontend/frontend_shell.tscn`
- Modify: `tests/unit/test_content_pack.gd`
- Modify: `tests/scenes/test_frontend_shell.gd`

**Interfaces:**
- Produces: `BootstrapContentLoader.queue_enabled_pack_ids(ids) -> Dictionary`.
- Produces: `BootstrapContentLoader.apply_pending_at_main_menu(run_active: bool) -> Dictionary`.
- Emits: `catalog_changed(catalog: ContentCatalog)` only after atomic success.

- [ ] **Step 1: Write failing lifecycle tests**

Assert queued changes do not alter `catalog`; active-run apply is refused; main-menu apply swaps once; failed candidate keeps the old catalog and enabled-state file; a disabled selected character is reported for reselection.

- [ ] **Step 2: Run RED**

Run the two focused suites; expect missing queue/apply APIs and menu controls.

- [ ] **Step 3: Integrate the registry without changing startup compatibility**

Load the existing core manifest first, discover built-in optional manifests from a fixed index, read enabled state, build a candidate, and retain the existing default PCK fallback. Replace the catalog only after success and re-register translations from all active packs.

- [ ] **Step 4: Add a minimal main-menu Content Packs page**

Add a `ContentPacksButton`, a page listing discovered pack name/version/kind/state/error, Apply and Back buttons, and a restart-required status. The page queues checkbox changes and calls `apply_pending_at_main_menu(Global.current_run != null)`.

- [ ] **Step 5: Run GREEN and commit**

Commit: `feat: apply content pack changes at main menu`.

### Task 4: Safe PCK install and replacement transaction

**Files:**
- Create: `core/content/content_pack_installer.gd`
- Modify: `tools/content/build_content_pack.gd`
- Create: `tests/unit/test_content_pack_installer.gd`
- Modify: `tests/integration/test_external_content_pack.gd`

**Interfaces:**
- Produces: `ContentPackInstaller.install(pck_path, descriptor_path) -> Dictionary`.
- Produces: `ContentPackInstaller.remove(pack_id) -> Dictionary`.
- Descriptor fields: schema version, pack ID, version, manifest virtual path, source-root virtual path, PCK SHA-256, and per-file paths/hashes.

- [ ] **Step 1: Write failing transaction tests**

Cover valid install, hash mismatch, path outside manifest root, forbidden extensions, pack-ID mismatch, replacement of an unmounted version, mounted replacement returning `restart_required`, injected rename failure rollback, and exact cleanup of staging files.

- [ ] **Step 2: Run RED**

Run only installer and external pack suites.

- [ ] **Step 3: Emit hardened descriptors from the builder**

Build one descriptor next to every PCK. Normalize virtual paths, reject links and path traversal at source, and set `replace_files=false`.

- [ ] **Step 4: Implement the installer transaction**

Use `user://content_packs/installed/.staging/`, validate before moving, preserve the prior installed index and PCK on failure, and mark update/removal of mounted packs for restart rather than claiming live replacement.

- [ ] **Step 5: Run GREEN and commit**

Commit: `feat: add transactional content pack installation`.

### Task 5: Migrate Niko into the first character pack

**Files:**
- Create: `content_packs/characters/niko/pack.tres`
- Create: `content_packs/characters/niko/character_niko.tres`
- Move: `scenes/unit/players/player_niko.tscn` to `content_packs/characters/niko/niko.tscn`
- Move: `tools/sprites/niko_character_library/runtime/*` to `content_packs/characters/niko/animations/`
- Modify: `Niko动画工作台.tscn`
- Modify: `content_packs/default/pack.tres`
- Modify: `tools/build_release.ps1`
- Modify: `tests/unit/test_niko_player_integration.gd`

**Interfaces:**
- Produces pack ID `character_niko` and stable character ID `character_niko:character/niko`.
- Produces a self-contained pack with no runtime reference to `tools/`.

- [ ] **Step 1: Write failing migration tests**

Assert Niko's manifest exists, contains exactly one character, uses the independent stable ID, all scene/resource dependencies stay within the pack or trusted core, enabling adds Niko, disabling removes Niko, the workbench references the pack animation library, and release scripts contain no Niko-specific copy workaround.

- [ ] **Step 2: Run RED**

Run only Niko integration and registry suites.

- [ ] **Step 3: Move resources with dependency fixup**

Use Godot-aware resource moves or exhaustive literal-reference updates. Keep shared player scripts in core. Move runtime SpriteFrames/atlases/manifest, create the Niko `CharacterDef`, and restore `core:character/well_rounded` to `player_well_rounded.tscn`.

- [ ] **Step 4: Register Niko in the built-in pack index**

Enable `character_niko` by default for development compatibility. The root workbench continues to edit the pack's total SpriteFrames directly.

- [ ] **Step 5: Remove build workaround and validate containment**

Delete the special Niko staging-copy block. Build Niko's independent PCK with the generic builder and verify no `tools/` paths appear in its descriptor or resources.

- [ ] **Step 6: Run GREEN and commit**

Commit: `feat: migrate Niko to an independent character pack`.

### Task 6: Add a weapon-pack template and release integration

**Files:**
- Create: `content_packs/templates/weapon/README.md`
- Create: `content_packs/templates/weapon/pack.tres.example`
- Create: `content_packs/templates/character/README.md`
- Create: `content_packs/templates/character/pack.tres.example`
- Modify: `tools/build_release.ps1`
- Modify: `README.md`
- Modify: `tests/unit/test_release_configuration.gd`

**Interfaces:**
- Produces generic discovery/build of every enabled built-in character/weapon pack.
- Documents exact IDs, dependency syntax, directories, build command, and main-menu behavior.

- [ ] **Step 1: Write failing release tests**

Assert release enumeration is generic, every migrated pack emits a versioned PCK and descriptor, and no pack-specific file list exists in the release script.

- [ ] **Step 2: Run RED**

Run release configuration suite only.

- [ ] **Step 3: Implement generic pack enumeration and templates**

Enumerate manifests below `content_packs/characters/*/pack.tres` and `content_packs/weapons/*/pack.tres`, invoke the existing builder, and copy outputs into `dist/content_packs/`.

- [ ] **Step 4: Run focused final verification**

Run content pack, registry, installer, Niko integration, frontend shell, release configuration, and one external-PCK integration suite. Run one Godot headless import and `git diff --check`.

- [ ] **Step 5: Commit**

Commit: `build: package independent character and weapon content`.
