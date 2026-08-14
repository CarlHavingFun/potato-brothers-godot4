extends GdUnitTestSuite


const CONTENT_PACK_SCRIPT := "res://core/content/content_pack_def.gd"
const CONTENT_DEF_SCRIPT := "res://core/content/content_def.gd"
const CONTENT_CATALOG_SCRIPT := "res://core/content/content_catalog.gd"
const CONTENT_VALIDATOR_SCRIPT := "res://core/content/content_validator.gd"
const BOOTSTRAP_LOADER_SCRIPT := "res://core/content/bootstrap_content_loader.gd"
const TEST_PACK_PATH := "user://tests/content_pack/pack.tres"
const DEFAULT_PACK_PATH := "res://content_packs/default/pack.tres"


func after_test() -> void:
	if FileAccess.file_exists(TEST_PACK_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PACK_PATH))
const DEFINITION_SCRIPTS := [
	"res://core/content/character_def.gd",
	"res://core/content/weapon_def.gd",
	"res://core/content/passive_item_def.gd",
	"res://core/content/upgrade_def.gd",
	"res://core/content/enemy_def.gd",
	"res://core/content/wave_def.gd",
]


func test_content_pack_definition_exposes_a_versioned_contract() -> void:
	assert_bool(ResourceLoader.exists(CONTENT_PACK_SCRIPT)).is_true()
	if not ResourceLoader.exists(CONTENT_PACK_SCRIPT):
		return

	var pack_script: Script = load(CONTENT_PACK_SCRIPT)
	var pack: Resource = pack_script.new()

	assert_int(pack.get("content_api_version")).is_equal(1)
	assert_str(pack.get("pack_version")).is_equal("0.1.0")


func test_content_definition_types_are_explicit_and_namespaced() -> void:
	assert_bool(ResourceLoader.exists(CONTENT_DEF_SCRIPT)).is_true()
	for script_path: String in DEFINITION_SCRIPTS:
		assert_bool(ResourceLoader.exists(script_path)).override_failure_message(script_path).is_true()
	if not ResourceLoader.exists(CONTENT_DEF_SCRIPT):
		return

	var definition_script: Script = load(CONTENT_DEF_SCRIPT)
	var definition: Resource = definition_script.new()
	definition.set("content_id", &"character/well_rounded")

	assert_str(definition.call("get_stable_id", &"potato_default")).is_equal(
		"potato_default:character/well_rounded"
	)


func test_catalog_registration_is_atomic_and_queryable_by_stable_id() -> void:
	assert_bool(ResourceLoader.exists(CONTENT_CATALOG_SCRIPT)).is_true()
	if not ResourceLoader.exists(CONTENT_CATALOG_SCRIPT):
		return

	var catalog_script: Script = load(CONTENT_CATALOG_SCRIPT)
	var duplicate_catalog: RefCounted = catalog_script.new()
	var duplicate_pack := ContentPackDef.new()
	duplicate_pack.pack_id = &"potato_default"
	var first := CharacterDef.new()
	first.content_id = &"character/well_rounded"
	var duplicate := CharacterDef.new()
	duplicate.content_id = &"character/well_rounded"
	duplicate_pack.characters = [first, duplicate]

	assert_int(duplicate_catalog.call("register_pack", duplicate_pack)).is_equal(ERR_ALREADY_EXISTS)
	assert_object(duplicate_catalog.call("get_character", &"character/well_rounded")).is_null()

	var catalog: RefCounted = catalog_script.new()
	var pack := ContentPackDef.new()
	pack.pack_id = &"potato_default"
	pack.characters = [first]

	assert_int(catalog.call("register_pack", pack)).is_equal(OK)
	assert_object(catalog.call("get_character", &"character/well_rounded")).is_same(first)
	assert_object(
		catalog.call("get_character", &"potato_default:character/well_rounded")
	).is_same(first)


func test_validator_rejects_invalid_metadata_and_content_scripts() -> void:
	assert_bool(ResourceLoader.exists(CONTENT_VALIDATOR_SCRIPT)).is_true()
	if not ResourceLoader.exists(CONTENT_VALIDATOR_SCRIPT):
		return

	var validator_script: Script = load(CONTENT_VALIDATOR_SCRIPT)
	var validator: RefCounted = validator_script.new()
	var pack := ContentPackDef.new()
	pack.pack_id = &"Invalid Pack Id"
	pack.content_api_version = 99

	var errors: PackedStringArray = validator.call(
		"validate_pack",
		pack,
		"res://tests/fixtures/invalid_content_pack"
	)
	var report := "\n".join(errors)

	assert_bool(report.contains("pack_id")).is_true()
	assert_bool(report.contains("content_api_version")).is_true()
	assert_bool(report.contains("forbidden_script.gd")).is_true()


func test_validator_rejects_missing_enemy_scene_and_unknown_wave_enemy() -> void:
	var pack := ContentPackDef.new()
	pack.pack_id = &"potato_default"

	var enemy := EnemyDef.new()
	enemy.content_id = &"enemy/chaser"
	pack.enemies = [enemy]

	var spawn := WaveSpawnDef.new()
	spawn.enemy_id = &"enemy/missing"
	var wave := WaveDef.new()
	wave.content_id = &"wave/1"
	wave.wave_number = 1
	wave.spawns = [spawn]
	pack.waves = [wave]

	var errors := ContentValidator.new().validate_pack(pack)
	var report := "\n".join(errors)

	assert_bool(report.contains("enemy/chaser requires a scene")).is_true()
	assert_bool(report.contains("wave/1 references unknown enemy enemy/missing")).is_true()


func test_bootstrap_loads_a_valid_manifest_before_game_content_is_used() -> void:
	assert_bool(ResourceLoader.exists(BOOTSTRAP_LOADER_SCRIPT)).is_true()
	if not ResourceLoader.exists(BOOTSTRAP_LOADER_SCRIPT):
		return

	var pack := ContentPackDef.new()
	pack.pack_id = &"potato_default"
	var character := CharacterDef.new()
	character.content_id = &"character/well_rounded"
	var default_character := Content.catalog.get_character(&"character/well_rounded")
	character.scene = default_character.scene
	character.stats = default_character.stats
	pack.characters = [character]
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(TEST_PACK_PATH.get_base_dir())
	)
	assert_int(ResourceSaver.save(pack, TEST_PACK_PATH)).is_equal(OK)

	var loader_script: Script = load(BOOTSTRAP_LOADER_SCRIPT)
	var loader: Node = auto_free(loader_script.new())

	assert_int(loader.call("load_manifest", TEST_PACK_PATH)).is_equal(OK)
	var catalog: RefCounted = loader.get("catalog")
	var loaded_character: CharacterDef = catalog.call("get_character", &"character/well_rounded")
	assert_object(loaded_character).is_not_null()
	assert_str(loaded_character.get_stable_id(&"potato_default")).is_equal(
		"potato_default:character/well_rounded"
	)


func test_default_content_pack_registers_the_phase_one_content_targets() -> void:
	assert_bool(ResourceLoader.exists(DEFAULT_PACK_PATH)).is_true()
	if not ResourceLoader.exists(DEFAULT_PACK_PATH):
		return

	var pack: ContentPackDef = load(DEFAULT_PACK_PATH)
	assert_str(pack.pack_id).is_equal("potato_default")
	assert_int(pack.characters.size()).is_equal(6)
	assert_int(pack.weapons.size()).is_equal(11)
	assert_int(pack.passives.size()).is_equal(20)
	assert_int(pack.upgrades.size()).is_equal(64)
	assert_int(pack.enemies.size()).is_equal(8)
	assert_int(pack.waves.size()).is_equal(10)
	for weapon: WeaponDef in pack.weapons:
		assert_int(weapon.tiers.size()).override_failure_message(String(weapon.content_id)).is_equal(4)

	var errors := ContentValidator.new().validate_pack(pack, "res://content_packs/default")
	assert_array(errors).is_empty()
	var catalog := ContentCatalog.new()
	assert_int(catalog.register_pack(pack)).is_equal(OK)
	assert_object(catalog.get_character(&"character/well_rounded")).is_not_null()
	assert_object(catalog.get_weapon(&"weapon/pistol")).is_not_null()
	assert_object(catalog.get_character(&"character/almighty")).is_not_null()
	assert_object(catalog.get_enemy(&"enemy/mouse_dog")).is_not_null()


func test_selection_and_player_creation_do_not_embed_specific_content_paths() -> void:
	assert_str(ProjectSettings.get_setting("autoload/Content", "")).is_equal(
		"*res://core/content/bootstrap_content_loader.gd"
	)
	var selection_scene_source := FileAccess.get_file_as_string(
		"res://scenes/ui/selection_panel/selection_panel.tscn"
	)
	var global_source := FileAccess.get_file_as_string("res://autoloads/global.gd")

	assert_bool(selection_scene_source.contains("stats_player_")).is_false()
	assert_bool(selection_scene_source.contains("item_axe_1.tres")).is_false()
	assert_bool(global_source.contains("available_players")).is_false()


func test_catalog_builds_the_shop_pool_and_resolves_namespaced_item_ids() -> void:
	var shop_items: Array[ItemBase] = Content.catalog.get_shop_items()

	assert_int(shop_items.size()).is_equal(64)
	var pistol := Content.catalog.get_weapon(&"weapon/pistol")
	assert_str(Content.catalog.get_item_stable_id(pistol.tiers[0])).is_equal(
		"potato_default:weapon/pistol"
	)
	assert_object(
		Content.catalog.get_weapon_tier(&"potato_default:weapon/pistol", 1)
	).is_same(pistol.tiers[0])
	var cape := Content.catalog.get_passive(&"passive/cape")
	assert_str(Content.catalog.get_item_stable_id(cape.item)).is_equal(
		"potato_default:passive/cape"
	)


func test_shop_scene_does_not_embed_default_content_resources() -> void:
	var shop_scene_source := FileAccess.get_file_as_string(
		"res://scenes/ui/shop_panel/shop_panel.tscn"
	)
	var shop_script_source := FileAccess.get_file_as_string(
		"res://scenes/ui/shop_panel/shop_panel.gd"
	)

	assert_bool(shop_scene_source.contains("item_axe_1.tres")).is_false()
	assert_bool(shop_scene_source.contains("passive_cape.tres")).is_false()
	assert_bool(shop_scene_source.contains("shop_items =")).is_false()
	assert_bool(shop_script_source.contains("Content.catalog.get_shop_items()")).is_true()


func test_catalog_exposes_wave_and_difficulty_definitions() -> void:
	var waves := Content.catalog.get_waves()
	assert_int(waves.size()).is_equal(10)
	assert_array(waves.map(func(wave: WaveDef): return int(wave.duration))).is_equal(
		[30, 35, 40, 45, 50, 55, 60, 65, 70, 90]
	)
	assert_float(Content.catalog.get_difficulty(5).health_multiplier).is_equal(1.70)
	assert_float(Content.catalog.get_difficulty(5).spawn_density_multiplier).is_equal(1.40)


func test_arena_and_spawner_do_not_embed_default_wave_or_enemy_resources() -> void:
	var arena_source := FileAccess.get_file_as_string("res://scenes/arena/arena.tscn")
	var spawner_source := FileAccess.get_file_as_string("res://scenes/arena/spawner.gd")

	assert_bool(arena_source.contains("wave_1_to_5.tres")).is_false()
	assert_bool(arena_source.contains("stats_enemy_charger.tres")).is_false()
	assert_bool(arena_source.contains("enemy_collection =")).is_false()
	assert_bool(arena_source.contains("waves_data =")).is_false()
	assert_bool(spawner_source.contains("Content.catalog.get_waves()")).is_true()
	assert_bool(spawner_source.contains("DifficultyDef.for_level")).is_false()


func test_catalog_builds_upgrade_pool_with_namespaced_ids() -> void:
	var upgrade_items: Array[ItemUpgrade] = Content.catalog.get_upgrade_items()
	assert_int(upgrade_items.size()).is_equal(64)

	var health_upgrade := Content.catalog.get_upgrade(
		&"upgrade/max_health/common"
	)
	assert_str(Content.catalog.get_item_stable_id(health_upgrade.item)).is_equal(
		"potato_default:upgrade/max_health/common"
	)


func test_upgrade_scene_does_not_embed_default_upgrade_resources() -> void:
	var scene_source := FileAccess.get_file_as_string(
		"res://scenes/ui/upgrade_panel/upgrade_panel.tscn"
	)
	var script_source := FileAccess.get_file_as_string(
		"res://scenes/ui/upgrade_panel/upgrade_panel.gd"
	)

	assert_bool(scene_source.contains("upgrade_health_1.tres")).is_false()
	assert_bool(scene_source.contains("upgrade_list =")).is_false()
	assert_bool(script_source.contains("Content.catalog.get_upgrade_items()")).is_true()
