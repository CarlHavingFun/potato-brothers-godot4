extends GdUnitTestSuite


const Importer = preload("res://tools/video_sprites/video_sprite_manifest_importer.gd")
const AUTHORING_PATH := "res://reports/character_sprite_library/niko_all_actions.tres"
const RUNTIME_ROOT := "res://reports/character_sprite_library/runtime"


func after_test() -> void:
	if FileAccess.file_exists(AUTHORING_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(AUTHORING_PATH))
	for path: String in [
		RUNTIME_ROOT + "/niko_runtime_frames.tres",
		RUNTIME_ROOT + "/manifest.json",
		RUNTIME_ROOT + "/runtime_atlas_001.png",
		RUNTIME_ROOT + "/runtime_atlas_002.png",
	]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_character_library_groups_every_take_and_seeds_runtime_from_preferred_take() -> void:
	var importer = Importer.new()
	if not importer.has_method("build_character_sprite_frames"):
		fail("character-level SpriteFrames aggregation is not implemented")
		return
	var happy := _source_frames(3, 24.0, 101)
	var power := _source_frames(3, 24.0, 201)
	var idle := _source_frames(3, 24.0, 301)
	var result: Dictionary = importer.call(
		"build_character_sprite_frames",
		_config(),
		{"walk_happy": happy, "walk_power": power, "idle_take": idle}
	)
	assert_array(result.get("errors", PackedStringArray())).is_empty()
	var frames := result.get("sprite_frames") as SpriteFrames
	assert_object(frames).is_not_null()
	assert_array(frames.get_animation_names()).contains_exactly_in_any_order([
		&"idle_down",
		&"source__idle_down__calm",
		&"source__walk_down__happy",
		&"source__walk_down__power",
		&"walk_down",
	])
	assert_int(frames.get_frame_count(&"source__walk_down__happy")).is_equal(3)
	assert_int(frames.get_frame_count(&"source__walk_down__power")).is_equal(3)
	assert_int(frames.get_frame_count(&"walk_down")).is_equal(3)
	assert_float(frames.get_animation_speed(&"walk_down")).is_equal_approx(24.0, 0.001)
	assert_bool(frames.get_animation_loop(&"walk_down")).is_true()
	assert_object(frames.get_frame_texture(&"walk_down", 0)).is_same(
		happy.get_frame_texture(&"source_all", 0)
	)
	assert_bool(frames.has_animation(&"dash_down")).is_false()


func test_character_library_refuses_any_take_that_is_not_the_full_expected_frame_count() -> void:
	var result := Importer.build_character_sprite_frames(
		_config(),
		{
			"walk_happy": _source_frames(2, 24.0, 101),
			"walk_power": _source_frames(3, 24.0, 201),
			"idle_take": _source_frames(3, 24.0, 301),
		}
	)
	assert_str("\n".join(result.get("errors", PackedStringArray()))).contains(
		"walk_happy must contain exactly 3 source frames"
	)


func test_character_library_refreshes_sources_without_overwriting_human_runtime_edits() -> void:
	var importer = Importer.new()
	if not importer.has_method("build_character_sprite_frames"):
		fail("character-level SpriteFrames aggregation is not implemented")
		return
	var existing := SpriteFrames.new()
	existing.remove_animation(&"default")
	existing.add_animation(&"walk_down")
	existing.set_animation_speed(&"walk_down", 9.0)
	existing.set_animation_loop(&"walk_down", true)
	existing.add_frame(&"walk_down", _texture(777))
	existing.add_frame(&"walk_down", _texture(778), 1.5)
	existing.add_animation(&"source__walk_down__old")
	existing.add_frame(&"source__walk_down__old", _texture(1))

	var result: Dictionary = importer.call(
		"build_character_sprite_frames",
		_config(),
		{
			"walk_happy": _source_frames(3, 24.0, 101),
			"walk_power": _source_frames(3, 24.0, 201),
			"idle_take": _source_frames(3, 24.0, 301),
		},
		existing
	)
	assert_array(result.get("errors", PackedStringArray())).is_empty()
	var frames := result.get("sprite_frames") as SpriteFrames
	assert_float(frames.get_animation_speed(&"walk_down")).is_equal_approx(9.0, 0.001)
	assert_int(frames.get_frame_count(&"walk_down")).is_equal(2)
	assert_float(frames.get_frame_duration(&"walk_down", 1)).is_equal_approx(1.5, 0.001)
	assert_object(frames.get_frame_texture(&"walk_down", 0)).is_same(
		existing.get_frame_texture(&"walk_down", 0)
	)
	assert_bool(frames.has_animation(&"source__walk_down__old")).is_false()
	assert_int(frames.get_frame_count(&"source__walk_down__happy")).is_equal(3)
	assert_int(frames.get_frame_count(&"idle_down")).is_equal(3)


func test_character_status_reports_missing_template_actions_without_static_fallback() -> void:
	var importer = Importer.new()
	if not importer.has_method("character_status"):
		fail("character action completeness reporting is not implemented")
		return
	var built: Dictionary = importer.call(
		"build_character_sprite_frames",
		_config(),
		{
			"walk_happy": _source_frames(3, 24.0, 101),
			"walk_power": _source_frames(3, 24.0, 201),
			"idle_take": _source_frames(3, 24.0, 301),
		}
	)
	var status: Dictionary = importer.call(
		"character_status", _config(), built.get("sprite_frames") as SpriteFrames
	)
	assert_array(status.get("required_actions", PackedStringArray())).contains_exactly([
		"spawn", "idle", "walk", "dash", "hit", "death", "victory",
	])
	assert_array(status.get("missing_actions", PackedStringArray())).contains_exactly([
		"spawn", "dash", "hit", "death", "victory",
	])
	assert_int(status.get("source_take_count", 0)).is_equal(3)
	assert_bool(status.get("degraded_static_fallback", true)).is_false()


func test_character_config_requires_one_action_entry_for_every_template_action() -> void:
	var parsed: Dictionary = Importer.parse_character_config_file(
		"res://tools/video_sprites/niko_character_sources.json"
	)
	assert_array(parsed.get("errors", PackedStringArray())).is_empty()
	var config := (parsed.get("config") as Dictionary).duplicate(true)
	(config["actions"] as Dictionary).erase("death")
	var report := "\n".join(Importer.validate_character_config(config))
	assert_str(report).contains("missing required action: death")


func test_install_character_library_persists_one_editable_resource_and_preserves_runtime() -> void:
	var importer = Importer.new()
	if not importer.has_method("install_character_library"):
		fail("character-level authoring resource installation is not implemented")
		return
	var first: Dictionary = importer.call(
		"install_character_library",
		_config(),
		"res://tools/sprites/niko_video_library",
		AUTHORING_PATH,
		false,
		Callable(self, "_fake_source_loader")
	)
	assert_array(first.get("errors", PackedStringArray())).is_empty()
	assert_str(first.get("authoring_path", "")).is_equal(AUTHORING_PATH)
	assert_bool(FileAccess.file_exists(AUTHORING_PATH)).is_true()
	var saved := ResourceLoader.load(
		AUTHORING_PATH, "SpriteFrames", ResourceLoader.CACHE_MODE_REPLACE
	) as SpriteFrames
	assert_object(saved).is_not_null()
	assert_int(saved.get_frame_count(&"source__walk_down__happy")).is_equal(3)
	assert_int(saved.get_frame_count(&"walk_down")).is_equal(3)
	saved.set_animation_speed(&"walk_down", 8.0)
	saved.remove_frame(&"walk_down", 1)
	assert_int(ResourceSaver.save(saved, AUTHORING_PATH)).is_equal(OK)

	var refreshed: Dictionary = importer.call(
		"install_character_library",
		_config(),
		"res://tools/sprites/niko_video_library",
		AUTHORING_PATH,
		false,
		Callable(self, "_fake_source_loader")
	)
	assert_array(refreshed.get("errors", PackedStringArray())).is_empty()
	saved = ResourceLoader.load(
		AUTHORING_PATH, "SpriteFrames", ResourceLoader.CACHE_MODE_REPLACE
	) as SpriteFrames
	assert_float(saved.get_animation_speed(&"walk_down")).is_equal_approx(8.0, 0.001)
	assert_int(saved.get_frame_count(&"walk_down")).is_equal(2)
	assert_int(saved.get_frame_count(&"source__walk_down__happy")).is_equal(3)


func test_all_walk_facings_resolve_to_the_single_front_walk_animation() -> void:
	var visual := DirectionalSpriteVisual.new()
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	frames.add_animation(&"idle_down")
	frames.add_frame(&"idle_down", _texture(50))
	frames.add_animation(&"walk_down")
	frames.add_frame(&"walk_down", _texture(51))
	visual.sprite_frames = frames
	for direction: StringName in DirectionalSpriteVisual.DIRECTIONS:
		assert_str(visual.animation_name_for(&"walk", direction)).is_equal("walk_down")
	visual.free()


func test_publish_runtime_excludes_sources_repacks_pages_and_preserves_timing() -> void:
	var importer = Importer.new()
	if not importer.has_method("publish_character_runtime"):
		fail("compact character runtime publication is not implemented")
		return
	var authoring := SpriteFrames.new()
	authoring.remove_animation(&"default")
	authoring.add_animation(&"source__walk_down__happy")
	authoring.add_frame(&"source__walk_down__happy", _solid_texture(Color.MAGENTA))
	authoring.add_animation(&"idle_down")
	authoring.set_animation_speed(&"idle_down", 6.0)
	authoring.set_animation_loop(&"idle_down", true)
	authoring.add_frame(&"idle_down", _solid_texture(Color.RED), 1.25)
	authoring.add_frame(&"idle_down", _solid_texture(Color.GREEN), 0.75)
	authoring.add_animation(&"walk_down")
	authoring.set_animation_speed(&"walk_down", 10.0)
	authoring.set_animation_loop(&"walk_down", true)
	for colour: Color in [Color.BLUE, Color.YELLOW, Color.CYAN]:
		authoring.add_frame(&"walk_down", _solid_texture(colour))

	var result: Dictionary = importer.call(
		"publish_character_runtime",
		authoring,
		"niko",
		RUNTIME_ROOT,
		Callable(self, "_load_png_texture"),
		2,
		2
	)
	assert_array(result.get("errors", PackedStringArray())).is_empty()
	assert_int(result.get("page_count", 0)).is_equal(2)
	assert_int(result.get("frame_count", 0)).is_equal(5)
	assert_bool(FileAccess.file_exists(RUNTIME_ROOT + "/runtime_atlas_001.png")).is_true()
	assert_bool(FileAccess.file_exists(RUNTIME_ROOT + "/runtime_atlas_002.png")).is_true()
	assert_bool(FileAccess.file_exists(RUNTIME_ROOT + "/manifest.json")).is_true()
	var runtime := ResourceLoader.load(
		RUNTIME_ROOT + "/niko_runtime_frames.tres",
		"SpriteFrames",
		ResourceLoader.CACHE_MODE_REPLACE
	) as SpriteFrames
	assert_object(runtime).is_not_null()
	assert_array(runtime.get_animation_names()).contains_exactly_in_any_order([
		&"idle_down", &"walk_down",
	])
	assert_int(runtime.get_frame_count(&"idle_down")).is_equal(2)
	assert_int(runtime.get_frame_count(&"walk_down")).is_equal(3)
	assert_float(runtime.get_animation_speed(&"walk_down")).is_equal_approx(10.0, 0.001)
	assert_bool(runtime.get_animation_loop(&"walk_down")).is_true()
	assert_float(runtime.get_frame_duration(&"idle_down", 0)).is_equal_approx(1.25, 0.001)
	var manifest: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(RUNTIME_ROOT + "/manifest.json")
	) as Dictionary
	assert_bool(manifest.get("degraded_static_fallback", true)).is_false()
	assert_int((manifest.get("pages", []) as Array).size()).is_equal(2)
	assert_int(
		(((manifest["frame_layout"] as Dictionary)["rows"] as Dictionary)["walk_down"] as Array).size()
	).is_equal(3)


func test_publish_runtime_rejects_missing_idle_without_writing_a_fallback() -> void:
	var importer = Importer.new()
	if not importer.has_method("publish_character_runtime"):
		fail("compact character runtime publication is not implemented")
		return
	var authoring := SpriteFrames.new()
	authoring.remove_animation(&"default")
	authoring.add_animation(&"walk_down")
	authoring.add_frame(&"walk_down", _solid_texture(Color.BLUE))
	var result: Dictionary = importer.call(
		"publish_character_runtime", authoring, "niko", RUNTIME_ROOT,
		Callable(self, "_load_png_texture"), 2, 2
	)
	assert_str("\n".join(result.get("errors", PackedStringArray()))).contains("idle_down")
	assert_bool(FileAccess.file_exists(RUNTIME_ROOT + "/niko_runtime_frames.tres")).is_false()


func _config() -> Dictionary:
	return {
		"schema_version": 1,
		"character_id": "niko",
		"expected_source_frame_count": 3,
		"required_actions": ["spawn", "idle", "walk", "dash", "hit", "death", "victory"],
		"actions": {
			"idle": {
				"loop": true,
				"preferred_take": "calm",
				"takes": [{"name": "calm", "clip_id": "idle_take"}],
			},
			"walk": {
				"loop": true,
				"preferred_take": "happy",
				"takes": [
					{"name": "happy", "clip_id": "walk_happy"},
					{"name": "power", "clip_id": "walk_power"},
				],
			},
		},
	}


func _source_frames(count: int, fps: float, texture_seed: int) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	frames.add_animation(&"source_all")
	frames.set_animation_speed(&"source_all", fps)
	frames.set_animation_loop(&"source_all", true)
	for index in count:
		frames.add_frame(&"source_all", _texture(texture_seed + index), 1.0 + index * 0.1)
	return frames


func _texture(width: int) -> Texture2D:
	var texture := GradientTexture2D.new()
	texture.width = width
	texture.height = 256
	return texture


func _fake_source_loader(path: String) -> SpriteFrames:
	if path.ends_with("/walk_happy/source_all_frames.tres"):
		return _source_frames(3, 24.0, 101)
	if path.ends_with("/walk_power/source_all_frames.tres"):
		return _source_frames(3, 24.0, 201)
	if path.ends_with("/idle_take/source_all_frames.tres"):
		return _source_frames(3, 24.0, 301)
	return null


func _solid_texture(colour: Color) -> Texture2D:
	var image := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	image.fill(colour)
	return ImageTexture.create_from_image(image)


func _load_png_texture(path: String) -> Texture2D:
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	return ImageTexture.create_from_image(image) if not image.is_empty() else null
