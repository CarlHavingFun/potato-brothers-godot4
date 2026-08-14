extends GdUnitTestSuite


const CONTENT_PACK_SCRIPT := "res://core/content/content_pack_def.gd"
const CONTENT_DEF_SCRIPT := "res://core/content/content_def.gd"
const CONTENT_CATALOG_SCRIPT := "res://core/content/content_catalog.gd"
const CONTENT_VALIDATOR_SCRIPT := "res://core/content/content_validator.gd"
const BOOTSTRAP_LOADER_SCRIPT := "res://core/content/bootstrap_content_loader.gd"
const TEST_PACK_PATH := "user://tests/content_pack/pack.tres"


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


func test_bootstrap_loads_a_valid_manifest_before_game_content_is_used() -> void:
	assert_bool(ResourceLoader.exists(BOOTSTRAP_LOADER_SCRIPT)).is_true()
	if not ResourceLoader.exists(BOOTSTRAP_LOADER_SCRIPT):
		return

	var pack := ContentPackDef.new()
	pack.pack_id = &"potato_default"
	var character := CharacterDef.new()
	character.content_id = &"character/well_rounded"
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
