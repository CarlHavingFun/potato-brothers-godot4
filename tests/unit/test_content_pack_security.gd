extends GdUnitTestSuite


func test_validator_rejects_absolute_traversal_and_core_override_paths() -> void:
	var pack := ContentPackDef.new()
	pack.pack_id = &"fixture"
	pack.translation_paths = [
		"C:/outside/game.po",
		"res://content_packs/fixture/../escape.po",
		"res://core/content/content_catalog.gd",
	]

	var report := "\n".join(ContentValidator.new().validate_pack(pack))

	assert_bool(report.contains("absolute path")).is_true()
	assert_bool(report.contains("path traversal")).is_true()
	assert_bool(report.contains("core path override")).is_true()


func test_validator_rejects_all_executable_content_extensions() -> void:
	var validator := ContentValidator.new()
	var report := "\n".join(validator.validate_virtual_paths(PackedStringArray([
		"res://content_packs/fixture/mod_main.gd",
		"res://content_packs/fixture/native.gdextension",
		"res://content_packs/fixture/native.dll",
		"res://content_packs/fixture/native.so",
		"res://content_packs/fixture/native.dylib",
		"res://content_packs/fixture/native.exe",
		"res://content_packs/fixture/managed.cs",
	]), "res://content_packs/fixture"))

	for extension: String in ["gd", "gdextension", "dll", "so", "dylib", "exe", "cs"]:
		assert_bool(report.contains(".%s" % extension)).override_failure_message(extension).is_true()


func test_validator_rejects_missing_content_references() -> void:
	var pack := ContentPackDef.new()
	pack.pack_id = &"fixture"
	var character := CharacterDef.new()
	character.content_id = &"character/missing"
	var weapon := WeaponDef.new()
	weapon.content_id = &"weapon/missing"
	var passive := PassiveItemDef.new()
	passive.content_id = &"passive/missing"
	var upgrade := UpgradeDef.new()
	upgrade.content_id = &"upgrade/missing"
	pack.characters = [character]
	pack.weapons = [weapon]
	pack.passives = [passive]
	pack.upgrades = [upgrade]

	var report := "\n".join(ContentValidator.new().validate_pack(pack))

	assert_bool(report.contains("character/missing requires a scene")).is_true()
	assert_bool(report.contains("character/missing requires stats")).is_true()
	assert_bool(report.contains("weapon/missing requires four tiers")).is_true()
	assert_bool(report.contains("passive/missing requires an item")).is_true()
	assert_bool(report.contains("upgrade/missing requires an item")).is_true()


func test_validator_rejects_scene_without_gameplay_body_contract() -> void:
	var invalid_root := Node2D.new()
	var invalid_scene := PackedScene.new()
	assert_int(invalid_scene.pack(invalid_root)).is_equal(OK)
	invalid_root.free()

	var pack := ContentPackDef.new()
	pack.pack_id = &"fixture"
	var enemy := EnemyDef.new()
	enemy.content_id = &"enemy/invalid_scene"
	enemy.scene = invalid_scene
	pack.enemies = [enemy]

	var report := "\n".join(ContentValidator.new().validate_pack(pack))

	assert_bool(report.contains("enemy/invalid_scene scene root must be CharacterBody2D")).is_true()
