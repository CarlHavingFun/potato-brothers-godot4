extends GdUnitTestSuite


const Importer = preload("res://tools/sprites/sprite_gen_state_importer.gd")


func test_valid_manifest_builds_eight_timed_frames_from_explicit_rectangles() -> void:
	var manifest := _valid_manifest()
	var rects := ((manifest["frame_layout"] as Dictionary)["rows"] as Dictionary)["walk_down"] as Array
	for index in rects.size():
		(rects[index] as Dictionary)["x"] = (7 - index) * 256
	var result := Importer.build_sprite_frames(
		manifest,
		&"walk_down",
		Callable(self, "_fake_texture")
	)
	assert_array(result.get("errors", PackedStringArray())).is_empty()
	var frames := result.get("sprite_frames") as SpriteFrames
	assert_object(frames).is_not_null()
	assert_int(frames.get_animation_names().size()).is_equal(1)
	assert_int(frames.get_frame_count(&"walk_down")).is_equal(8)
	assert_float(frames.get_animation_speed(&"walk_down")).is_equal_approx(10.0, 0.001)
	assert_bool(frames.get_animation_loop(&"walk_down")).is_true()
	assert_float(frames.get_frame_duration(&"walk_down", 0)).is_equal_approx(1.0, 0.001)
	var first := frames.get_frame_texture(&"walk_down", 0) as AtlasTexture
	assert_object(first).is_not_null()
	assert_vector(first.region.position).is_equal(Vector2(1792, 0))
	assert_vector(first.region.size).is_equal(Vector2(256, 256))


func test_manifest_rejects_missing_state_and_degraded_fallback() -> void:
	var manifest := _valid_manifest()
	manifest["degraded_static_fallback"] = true
	var animation := manifest["animation"] as Dictionary
	(animation["rows"] as Dictionary).erase("walk_down")
	var report := "\n".join(Importer.validate_manifest(manifest, &"walk_down"))
	assert_str(report).contains("degraded_static_fallback must be false")
	assert_str(report).contains("missing animation state: walk_down")


func test_manifest_rejects_wrong_cell_frame_count_and_duration() -> void:
	var manifest := _valid_manifest()
	(manifest["cell"] as Dictionary)["width"] = 128
	var row := ((manifest["animation"] as Dictionary)["rows"] as Dictionary)["walk_down"] as Dictionary
	row["frames"] = 7
	(row["durations_ms"] as Array).pop_back()
	var report := "\n".join(Importer.validate_manifest(manifest, &"walk_down"))
	assert_str(report).contains("cell must be 256x256")
	assert_str(report).contains("walk_down frames must be 8")
	assert_str(report).contains("walk_down durations_ms must contain 8 values")


func test_manifest_rejects_out_of_bounds_rectangle_and_missing_duration_array() -> void:
	var manifest := _valid_manifest()
	var rects := ((manifest["frame_layout"] as Dictionary)["rows"] as Dictionary)["walk_down"] as Array
	(rects[7] as Dictionary)["x"] = 2048
	var row := ((manifest["animation"] as Dictionary)["rows"] as Dictionary)["walk_down"] as Dictionary
	row.erase("durations_ms")
	var report := "\n".join(Importer.validate_manifest(manifest, &"walk_down"))
	assert_str(report).contains("walk_down durations_ms must be an array")
	assert_str(report).contains("walk_down rectangle 7 exceeds the declared sheet")


func test_build_rejects_missing_or_wrong_size_atlas() -> void:
	var missing := Importer.build_sprite_frames(
		_valid_manifest(), &"walk_down", Callable(self, "_missing_texture")
	)
	assert_str("\n".join(missing.get("errors", PackedStringArray()))).contains("could not load atlas")
	var wrong_size := Importer.build_sprite_frames(
		_valid_manifest(), &"walk_down", Callable(self, "_wrong_size_texture")
	)
	assert_str("\n".join(wrong_size.get("errors", PackedStringArray()))).contains("manifest declares 2048x256")


func test_parse_rejects_missing_manifest_file() -> void:
	var result := Importer.parse_manifest_file(
		"res://tools/sprites/niko_walk_happy_proof/does-not-exist.json",
		&"walk_down"
	)
	assert_str("\n".join(result.get("errors", PackedStringArray()))).contains("manifest not found")


func _valid_manifest() -> Dictionary:
	var rects: Array = []
	for index in 8:
		rects.append({"x": index * 256, "y": 0, "w": 256, "h": 256})
	return {
		"engine": "component-row",
		"game_input": "sprite-sheet-alpha.png",
		"degraded_static_fallback": false,
		"_manifest_path": "res://tools/sprites/niko_walk_happy_proof/manifest.json",
		"cell": {"width": 256, "height": 256},
		"animation": {
			"rows": {
				"walk_down": {
					"frames": 8,
					"fps": 10,
					"loop": true,
					"durations_ms": [100, 100, 100, 100, 100, 100, 100, 100],
				}
			}
		},
		"frame_layout": {
			"sheetWidth": 2048,
			"sheetHeight": 256,
			"rows": {"walk_down": rects},
		},
	}


func _fake_texture(_path: String) -> Texture2D:
	var texture := GradientTexture2D.new()
	texture.width = 2048
	texture.height = 256
	return texture


func _missing_texture(_path: String) -> Texture2D:
	return null


func _wrong_size_texture(_path: String) -> Texture2D:
	var texture := GradientTexture2D.new()
	texture.width = 1024
	texture.height = 256
	return texture
