class_name TestVideoSpriteStudioImporter
extends GdUnitTestSuite


const Importer = preload("res://tools/video_sprite_studio/godot_sprite_frames_importer.gd")


func _manifest(count: int, fps := 10.0, loop := true) -> Dictionary:
	var rects: Array = []
	var durations: Array = []
	for index in count:
		rects.append({"x": index * 256, "y": 0, "w": 256, "h": 256})
		durations.append(100.0)
	return {
		"game_input": "atlas.png",
		"cell": {"width": 256, "height": 256},
		"animation": {"rows": {"walk_down": {
			"frames": count, "fps": fps, "loop": loop, "durations_ms": durations,
		}}},
		"frame_layout": {
			"sheetWidth": count * 256, "sheetHeight": 256,
			"rows": {"walk_down": rects},
		},
	}


func test_merge_supports_arbitrary_frame_count_and_preserves_other_animations() -> void:
	var existing := SpriteFrames.new()
	existing.remove_animation(&"default")
	existing.add_animation(&"idle_down")
	existing.set_animation_speed(&"idle_down", 7.0)
	existing.set_animation_loop(&"idle_down", true)
	existing.add_frame(&"idle_down", ImageTexture.create_from_image(Image.create(1, 1, false, Image.FORMAT_RGBA8)))
	var texture := ImageTexture.create_from_image(Image.create(17 * 256, 256, false, Image.FORMAT_RGBA8))

	var result: Dictionary = Importer.merge_animation(existing, _manifest(17), &"walk_down", texture)

	assert_array(result.get("errors", PackedStringArray())).is_empty()
	var merged := result["sprite_frames"] as SpriteFrames
	assert_bool(merged.has_animation(&"idle_down")).is_true()
	assert_float(merged.get_animation_speed(&"idle_down")).is_equal(7.0)
	assert_int(merged.get_frame_count(&"idle_down")).is_equal(1)
	assert_int(merged.get_frame_count(&"walk_down")).is_equal(17)
	assert_float(merged.get_animation_speed(&"walk_down")).is_equal(10.0)
	assert_bool(merged.get_animation_loop(&"walk_down")).is_true()
	var frame := merged.get_frame_texture(&"walk_down", 16) as AtlasTexture
	assert_object(frame).is_not_null()
	assert_object(frame.region).is_equal(Rect2(4096, 0, 256, 256))


func test_merge_replaces_only_named_animation_and_keeps_explicit_duration() -> void:
	var existing := SpriteFrames.new()
	existing.remove_animation(&"default")
	existing.add_animation(&"walk_down")
	existing.add_frame(&"walk_down", ImageTexture.create_from_image(Image.create(1, 1, false, Image.FORMAT_RGBA8)))
	var manifest := _manifest(1, 12.0, false)
	manifest["animation"]["rows"]["walk_down"]["durations_ms"] = [250.0]
	var texture := ImageTexture.create_from_image(Image.create(256, 256, false, Image.FORMAT_RGBA8))

	var result: Dictionary = Importer.merge_animation(existing, manifest, &"walk_down", texture)

	assert_array(result.get("errors", PackedStringArray())).is_empty()
	var merged := result["sprite_frames"] as SpriteFrames
	assert_int(merged.get_frame_count(&"walk_down")).is_equal(1)
	assert_bool(merged.get_animation_loop(&"walk_down")).is_false()
	assert_float(merged.get_frame_duration(&"walk_down", 0)).is_equal_approx(3.0, 0.001)


func test_merge_rejects_empty_and_out_of_bounds_layouts() -> void:
	var texture := ImageTexture.create_from_image(Image.create(256, 256, false, Image.FORMAT_RGBA8))
	var empty := _manifest(0)
	var empty_result: Dictionary = Importer.merge_animation(null, empty, &"walk_down", texture)
	assert_array(empty_result.get("errors", PackedStringArray())).contains(["walk_down must contain at least one frame"])

	var invalid := _manifest(1)
	invalid["frame_layout"]["rows"]["walk_down"][0]["x"] = 256
	var invalid_result: Dictionary = Importer.merge_animation(null, invalid, &"walk_down", texture)
	assert_array(invalid_result.get("errors", PackedStringArray())).contains(["walk_down rectangle 0 exceeds atlas bounds"])
