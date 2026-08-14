extends GdUnitTestSuite


const MAIN_SCENE_PATH := "res://scenes/arena/arena.tscn"


func test_configured_main_scene_resolves() -> void:
	var configured_scene: String = ProjectSettings.get_setting("application/run/main_scene", "")

	assert_str(configured_scene).is_not_empty()
	assert_bool(ResourceLoader.exists(configured_scene)).is_true()


func test_main_scene_can_be_instantiated() -> void:
	var packed_scene := load(MAIN_SCENE_PATH) as PackedScene

	assert_object(packed_scene).is_not_null()
	var arena: Node = packed_scene.instantiate()
	assert_object(arena).is_not_null()
	arena.free()


func test_tutorial_character_and_weapon_baseline_is_preserved() -> void:
	assert_int(_count_matching("res://scenes/unit/players", "player_", ".tscn", false)).is_equal(5)
	assert_int(_count_matching("res://resources/items/weapons", "item_", "_1.tres", true)).is_equal(11)
	assert_int(_count_matching("res://resources/items/weapons", "item_", ".tres", true)).is_equal(44)


func test_tutorial_upgrade_baseline_is_preserved() -> void:
	assert_int(_count_matching("res://resources/items/upgrades/data", "upgrade_", ".tres", true)).is_equal(46)


func _count_matching(path: String, prefix: String, suffix: String, recursive: bool) -> int:
	var count := 0
	for file_name in DirAccess.get_files_at(path):
		if file_name.begins_with(prefix) and file_name.ends_with(suffix):
			count += 1
	if recursive:
		for directory_name in DirAccess.get_directories_at(path):
			count += _count_matching(path.path_join(directory_name), prefix, suffix, true)
	return count
