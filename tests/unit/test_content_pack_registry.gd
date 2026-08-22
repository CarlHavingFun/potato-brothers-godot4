extends GdUnitTestSuite


const TEST_ROOT := "user://tests/content_pack_state"
const DependencyScript := preload("res://core/content/content_pack_dependency.gd")
const RegistryScript := preload("res://core/content/content_pack_registry.gd")
const StateStoreScript := preload("res://core/content/content_pack_state_store.gd")


func after_test() -> void:
	for suffix: String in ["", ".tmp", ".bak"]:
		var path := TEST_ROOT.path_join("enabled.json") + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_registry_resolves_dependencies_and_builds_one_catalog() -> void:
	var core := _pack(&"core", ContentPackDef.PackKind.CORE)
	var niko := _pack(&"character_niko", ContentPackDef.PackKind.CHARACTER)
	var character := CharacterDef.new()
	character.content_id = &"character/niko"
	niko.characters = [character]
	var dependency := DependencyScript.new()
	dependency.pack_id = &"core"
	dependency.minimum_version = "0.1.0"
	niko.dependencies = [dependency]
	var optional: Array[ContentPackDef] = [niko]

	var result: Dictionary = RegistryScript.new().build_candidate(
		core, optional, PackedStringArray(["character_niko"])
	)
	assert_array(result.errors).is_empty()
	assert_object(result.catalog.get_character(&"character_niko:character/niko")).is_same(character)
	assert_array(result.active_pack_ids).contains_exactly(["core", "character_niko"])


func test_registry_rejects_disabled_dependency_and_cycles_atomically() -> void:
	var core := _pack(&"core", ContentPackDef.PackKind.CORE)
	var niko := _pack(&"character_niko", ContentPackDef.PackKind.CHARACTER)
	var character := CharacterDef.new()
	character.content_id = &"character/niko"
	niko.characters = [character]
	var weapon := _pack(&"weapon_sword", ContentPackDef.PackKind.WEAPON)
	var weapon_def := WeaponDef.new()
	weapon_def.content_id = &"weapon/sword"
	weapon.weapons = [weapon_def]
	niko.dependencies = [_dependency(&"weapon_sword")]
	weapon.dependencies = [_dependency(&"character_niko")]
	var optional: Array[ContentPackDef] = [niko, weapon]

	var missing: Dictionary = RegistryScript.new().build_candidate(
		core, optional, PackedStringArray(["character_niko"])
	)
	assert_object(missing.catalog).is_null()
	assert_bool("requires enabled dependency" in String(missing.errors[0])).is_true()
	var cycle: Dictionary = RegistryScript.new().build_candidate(
		core, optional, PackedStringArray(["character_niko", "weapon_sword"])
	)
	assert_object(cycle.catalog).is_null()
	assert_bool("cycle" in String(cycle.errors[0])).is_true()


func test_enabled_state_round_trip_is_sorted_and_recovers_backup() -> void:
	var store := StateStoreScript.new(TEST_ROOT)
	assert_int(store.save_enabled(PackedStringArray(["weapon_sword", "core", "character_niko"]))).is_equal(OK)
	assert_array(store.load_state().enabled_pack_ids).contains_exactly([
		"character_niko", "weapon_sword"
	])
	DirAccess.rename_absolute(
		ProjectSettings.globalize_path(store.state_path()),
		ProjectSettings.globalize_path(store.state_path() + ".bak")
	)
	assert_array(store.load_state().enabled_pack_ids).contains_exactly([
		"character_niko", "weapon_sword"
	])
	assert_bool(store.recovered_from_backup).is_true()


func _pack(pack_id: StringName, kind: int) -> ContentPackDef:
	var pack := ContentPackDef.new()
	pack.pack_id = pack_id
	pack.pack_kind = kind
	pack.pack_version = "1.0.0"
	return pack


func _dependency(pack_id: StringName) -> Resource:
	var dependency := DependencyScript.new()
	dependency.pack_id = pack_id
	dependency.minimum_version = "1.0.0"
	return dependency
