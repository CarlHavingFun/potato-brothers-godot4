extends GdUnitTestSuite


const GENERATED_ROOT := "res://reports/gdunit-niko-generated"
const GENERATED_FRAMES := GENERATED_ROOT + "/niko_v3_sprite_frames.tres"
const GENERATED_SCENE := GENERATED_ROOT + "/player_niko_v3.tscn"
const GENERATED_CHARACTER := GENERATED_ROOT + "/character_niko_v3.tres"


func after_test() -> void:
	for path: String in [GENERATED_CHARACTER, GENERATED_SCENE, GENERATED_FRAMES]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_niko_v3_manifest_contract_builds_284_frames_without_png_files() -> void:
	var manifest := _valid_manifest()
	var errors := DirectionalSpriteManifestImporter.validate_manifest(manifest)
	assert_array(errors).is_empty()

	var result := DirectionalSpriteManifestImporter.build_sprite_frames(
		manifest,
		Callable(self, "_fake_texture")
	)
	assert_array(result.get("errors", PackedStringArray())).is_empty()
	var frames := result.get("sprite_frames") as SpriteFrames
	assert_object(frames).is_not_null()
	assert_int(frames.get_animation_names().size()).is_equal(41)

	var total_frames := 0
	for animation_name: StringName in frames.get_animation_names():
		total_frames += frames.get_frame_count(animation_name)
	assert_int(total_frames).is_equal(284)
	assert_float(frames.get_animation_speed(&"idle_down")).is_equal_approx(6.0, 0.001)
	assert_bool(frames.get_animation_loop(&"idle_down")).is_true()
	assert_float(frames.get_animation_speed(&"hit_up_left")).is_equal_approx(16.0, 0.001)
	assert_bool(frames.get_animation_loop(&"death_right")).is_false()


func test_generator_builds_optional_scene_and_character_without_real_pngs() -> void:
	var manifest := _valid_manifest()
	var build_result := DirectionalSpriteManifestImporter.build_sprite_frames(
		manifest,
		Callable(self, "_fake_texture")
	)
	var frames := build_result.get("sprite_frames") as SpriteFrames
	assert_object(frames).is_not_null()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(GENERATED_ROOT))
	assert_int(ResourceSaver.save(frames, GENERATED_FRAMES)).is_equal(OK)

	var importer_script := load("res://tools/sprites/import_niko_v3.gd") as Script
	var importer := importer_script.new() as Node
	assert_int(importer.call("_write_scene", GENERATED_SCENE, GENERATED_FRAMES, manifest)).is_equal(OK)
	var scene := ResourceLoader.load(
		GENERATED_SCENE, "PackedScene", ResourceLoader.CACHE_MODE_REPLACE
	) as PackedScene
	assert_object(scene).is_not_null()
	assert_int(importer.call("_write_character_definition", GENERATED_CHARACTER, scene)).is_equal(OK)
	var definition := ResourceLoader.load(
		GENERATED_CHARACTER, "CharacterDef", ResourceLoader.CACHE_MODE_REPLACE
	) as CharacterDef
	assert_object(definition).is_not_null()
	assert_str(definition.content_id).is_equal("character/niko_v3")
	assert_object(definition.stats.icon).is_not_null()
	assert_bool(definition.stats.icon is AtlasTexture).is_true()
	assert_int(definition.stats.icon.get_width()).is_equal(256)
	assert_int(definition.stats.icon.get_height()).is_equal(256)
	var icon := definition.stats.icon as AtlasTexture
	assert_vector(icon.region.position).is_equal(Vector2.ZERO)
	assert_vector(icon.region.size).is_equal(Vector2(256, 256))
	assert_object(definition.stats.icon).is_not_same(
		Content.catalog.get_character(&"character/well_rounded").stats.icon
	)

	var player := definition.scene.instantiate() as Player
	assert_object(player.get_node_or_null("Visuals/DirectionalSpriteVisual")).is_not_null()
	assert_object(player.get_node_or_null("WeaponContainer")).is_not_null()
	player.free()
	importer.free()


func test_manifest_rejects_missing_direction_and_wrong_pivot() -> void:
	var manifest := _valid_manifest()
	manifest["pivot"] = {"x": 128, "y": 200}
	var idle := (manifest["actions"] as Dictionary)["idle"] as Dictionary
	var directions := idle["directions"] as Dictionary
	directions.erase("up_left")

	var report := "\n".join(DirectionalSpriteManifestImporter.validate_manifest(manifest))
	assert_str(report).contains("pivot must be (128, 232)")
	assert_str(report).contains("idle missing direction: up_left")


func test_manifest_rejects_paths_outside_the_project() -> void:
	var manifest := _valid_manifest()
	var idle := (manifest["actions"] as Dictionary)["idle"] as Dictionary
	var directions := idle["directions"] as Dictionary
	var down := directions["down"] as Dictionary
	down["atlas"] = "E:/outside/idle_down.png"

	var report := "\n".join(DirectionalSpriteManifestImporter.validate_manifest(manifest))
	assert_str(report).contains("idle_down atlas must resolve inside res://")


func test_manifest_rejects_multi_row_atlas_selection() -> void:
	var manifest := _valid_manifest()
	var idle := (manifest["actions"] as Dictionary)["idle"] as Dictionary
	var down := (idle["directions"] as Dictionary)["down"] as Dictionary
	down["row"] = 0

	var report := "\n".join(DirectionalSpriteManifestImporter.validate_manifest(manifest))
	assert_str(report).contains("idle_down row is unsupported")


func test_build_rejects_atlas_dimensions_larger_than_the_exact_strip() -> void:
	var result := DirectionalSpriteManifestImporter.build_sprite_frames(
		_valid_manifest(),
		Callable(self, "_oversized_texture")
	)

	var report := "\n".join(result.get("errors", PackedStringArray()))
	assert_str(report).contains("expected exactly")


func test_niko_translation_keys_are_available_in_english_and_chinese() -> void:
	var original_locale := TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	assert_str(tr("character.niko_v3.name")).is_equal("Niko")
	assert_str(tr("character.niko_v3.description")).contains("eight-direction")
	TranslationServer.set_locale("zh_CN")
	assert_str(tr("character.niko_v3.name")).is_equal("尼科")
	assert_str(tr("character.niko_v3.description")).contains("八方向")
	TranslationServer.set_locale(original_locale)


func _valid_manifest() -> Dictionary:
	var manifest := {
		"schema_version": 1,
		"frame_size": {"width": 256, "height": 256},
		"pivot": {"x": 128, "y": 232},
		"godot_visual_scale": 0.7,
		"actions": {},
	}
	var actions := manifest["actions"] as Dictionary
	for action: StringName in DirectionalSpriteManifestImporter.ACTION_CONTRACT:
		var contract := DirectionalSpriteManifestImporter.ACTION_CONTRACT[action] as Dictionary
		var action_data := {
			"frame_count": contract["frame_count"],
			"fps": contract["fps"],
			"loop": contract["loop"],
			"directions": {},
		}
		var expected_directions: Array[StringName] = (
			[&"down"] as Array[StringName]
			if int(contract["directions"]) == 1
			else DirectionalSpriteManifestImporter.REQUIRED_DIRECTIONS
		)
		for direction: StringName in expected_directions:
			(action_data["directions"] as Dictionary)[String(direction)] = {
				"atlas": "res://fixtures/%s_%s.png" % [action, direction],
				"frame_count": contract["frame_count"],
			}
		actions[String(action)] = action_data
	return manifest


func _fake_texture(_path: String) -> Texture2D:
	var frame_count := 0
	var filename := _path.get_file()
	for action: StringName in DirectionalSpriteManifestImporter.ACTION_CONTRACT:
		if filename.begins_with("%s_" % action):
			frame_count = int(
				(DirectionalSpriteManifestImporter.ACTION_CONTRACT[action] as Dictionary)["frame_count"]
			)
			break
	var texture := GradientTexture2D.new()
	texture.width = frame_count * 256
	texture.height = 256
	return texture


func _oversized_texture(path: String) -> Texture2D:
	var texture := _fake_texture(path) as GradientTexture2D
	texture.width += 256
	return texture
