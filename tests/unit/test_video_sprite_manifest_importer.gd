extends GdUnitTestSuite


const Importer = preload("res://tools/video_sprites/video_sprite_manifest_importer.gd")
const Preview = preload("res://tools/video_sprites/video_sprite_preview.gd")
const Cli = preload("res://tools/video_sprites/video_sprite_library_cli.gd")
const INSTALL_ROOT := "res://reports/video_sprite_importer/preserve_selection"
const MANIFEST_PATH := INSTALL_ROOT + "/manifest.json"
const SOURCE_PATH := INSTALL_ROOT + "/source_all_frames.tres"
const SELECTION_PATH := INSTALL_ROOT + "/selection.tres"
const PREVIEW_PATH := INSTALL_ROOT + "/preview.tscn"


func after_test() -> void:
	for path: String in [PREVIEW_PATH, SELECTION_PATH, SOURCE_PATH, MANIFEST_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_valid_manifest_builds_all_explicit_frames_with_source_timing() -> void:
	var manifest := _valid_manifest(20)
	var result := Importer.build_sprite_frames(manifest, Callable(self, "_fake_texture"))
	assert_array(result.get("errors", PackedStringArray())).is_empty()
	var frames := result.get("sprite_frames") as SpriteFrames
	assert_object(frames).is_not_null()
	assert_array(frames.get_animation_names()).contains_exactly([&"source_all"])
	assert_int(frames.get_frame_count(&"source_all")).is_equal(20)
	assert_float(frames.get_animation_speed(&"source_all")).is_equal_approx(24.0, 0.001)
	assert_bool(frames.get_animation_loop(&"source_all")).is_true()
	assert_float(frames.get_frame_duration(&"source_all", 0)).is_equal_approx(
		41.666667 / 1000.0 * 24.0,
		0.0001
	)
	var seventeenth := frames.get_frame_texture(&"source_all", 16) as AtlasTexture
	assert_object(seventeenth).is_not_null()
	assert_vector(seventeenth.region.position).is_equal(Vector2(0, 256))
	assert_vector(seventeenth.region.size).is_equal(Vector2(256, 256))


func test_manifest_rejects_unsafe_or_incomplete_frame_provenance() -> void:
	var manifest := _valid_manifest(2)
	manifest["degraded_static_fallback"] = true
	(manifest["root"] as Dictionary)["y"] = 231
	var row := ((manifest["animation"] as Dictionary)["rows"] as Dictionary)["source_all"] as Dictionary
	(row["durations_ms"] as Array)[1] = 0
	var rects := ((manifest["frame_layout"] as Dictionary)["rows"] as Dictionary)["source_all"] as Array
	(rects[1] as Dictionary)["x"] = 4096
	var sources := manifest["source_frames"] as Array
	(sources[1] as Dictionary)["index"] = 0
	(sources[1] as Dictionary)["png"] = "missing.png"
	var report := "\n".join(Importer.validate_manifest(manifest))
	assert_str(report).contains("degraded_static_fallback must be false")
	assert_str(report).contains("root must be (128, 232)")
	assert_str(report).contains("duration 1 must be positive")
	assert_str(report).contains("rectangle 1 exceeds the declared sheet")
	assert_str(report).contains("indices must be contiguous")
	assert_str(report).contains("PNG not found")


func test_install_overwrites_source_but_preserves_selection_until_explicit_replace() -> void:
	_write_install_manifest()
	var first: Dictionary = Importer.install_clip(MANIFEST_PATH)
	assert_array(first.get("errors", PackedStringArray())).is_empty()
	assert_array(first.get("created", PackedStringArray())).contains([SOURCE_PATH, SELECTION_PATH])

	var selection := ResourceLoader.load(
		SELECTION_PATH, "SpriteFrames", ResourceLoader.CACHE_MODE_REPLACE
	) as SpriteFrames
	selection.set_animation_speed(&"walk_happy", 7.0)
	assert_int(ResourceSaver.save(selection, SELECTION_PATH)).is_equal(OK)
	var source := ResourceLoader.load(
		SOURCE_PATH, "SpriteFrames", ResourceLoader.CACHE_MODE_REPLACE
	) as SpriteFrames
	source.set_animation_speed(&"source_all", 3.0)
	assert_int(ResourceSaver.save(source, SOURCE_PATH)).is_equal(OK)

	var second: Dictionary = Importer.install_clip(MANIFEST_PATH)
	assert_array(second.get("errors", PackedStringArray())).is_empty()
	assert_array(second.get("updated", PackedStringArray())).contains([SOURCE_PATH])
	assert_array(second.get("preserved", PackedStringArray())).contains([SELECTION_PATH])
	selection = ResourceLoader.load(
		SELECTION_PATH, "SpriteFrames", ResourceLoader.CACHE_MODE_REPLACE
	) as SpriteFrames
	source = ResourceLoader.load(
		SOURCE_PATH, "SpriteFrames", ResourceLoader.CACHE_MODE_REPLACE
	) as SpriteFrames
	assert_float(selection.get_animation_speed(&"walk_happy")).is_equal_approx(7.0, 0.001)
	assert_float(source.get_animation_speed(&"source_all")).is_equal_approx(24.0, 0.001)

	var replaced: Dictionary = Importer.install_clip(MANIFEST_PATH, true)
	assert_array(replaced.get("errors", PackedStringArray())).is_empty()
	assert_array(replaced.get("updated", PackedStringArray())).contains([SELECTION_PATH])
	selection = ResourceLoader.load(
		SELECTION_PATH, "SpriteFrames", ResourceLoader.CACHE_MODE_REPLACE
	) as SpriteFrames
	assert_float(selection.get_animation_speed(&"walk_happy")).is_equal_approx(24.0, 0.001)


func test_preview_scene_uses_selection_nearest_filter_checkerboard_and_root_guide() -> void:
	_write_install_manifest()
	var install: Dictionary = Importer.install_clip(MANIFEST_PATH)
	assert_array(install.get("errors", PackedStringArray())).is_empty()
	var result: Dictionary = Importer.write_preview_scene(MANIFEST_PATH)
	assert_array(result.get("errors", PackedStringArray())).is_empty()
	var scene_source := FileAccess.get_file_as_string(PREVIEW_PATH)
	assert_str(scene_source).contains("selection.tres")
	assert_str(scene_source).contains("texture_filter = 1")
	assert_str(scene_source).contains("name=\"Checkerboard\"")
	assert_str(scene_source).contains("name=\"RootGuide\"")
	var preview_source := FileAccess.get_file_as_string(
		"res://tools/video_sprites/video_sprite_preview.gd"
	)
	assert_str(preview_source).contains("_draw_checkerboard")
	assert_str(preview_source).contains("_draw_root_guide")
	var packed := ResourceLoader.load(
		PREVIEW_PATH, "PackedScene", ResourceLoader.CACHE_MODE_REPLACE
	) as PackedScene
	assert_object(packed).is_not_null()
	var preview := packed.instantiate()
	assert_object(preview.get_node_or_null("Sprite")).is_not_null()
	assert_object(preview.get_node_or_null("HUD/Info")).is_not_null()
	preview.free()


func test_headless_cli_rejects_missing_and_unknown_arguments() -> void:
	var missing: Dictionary = Cli.parse_arguments([])
	assert_int(missing.get("exit_code", 0)).is_equal(2)
	assert_str("\n".join(missing.get("errors", PackedStringArray()))).contains("--manifest")
	var unknown: Dictionary = Cli.parse_arguments(["--manifest", MANIFEST_PATH, "--wat"])
	assert_int(unknown.get("exit_code", 0)).is_equal(2)
	assert_str("\n".join(unknown.get("errors", PackedStringArray()))).contains("unknown argument")


func _write_install_manifest() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(INSTALL_ROOT))
	var manifest := _valid_manifest(2)
	manifest.erase("_manifest_path")
	manifest["game_input"] = "res://tools/sprites/niko_walk_happy_proof/sprite-sheet-alpha.png"
	var layout := manifest["frame_layout"] as Dictionary
	layout["sheetWidth"] = 2048
	layout["sheetHeight"] = 256
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.WRITE)
	assert_object(file).is_not_null()
	file.store_string(JSON.stringify(manifest))
	file.close()


func _valid_manifest(frame_count: int) -> Dictionary:
	var rects: Array = []
	var source_frames: Array = []
	var durations: Array = []
	for index in frame_count:
		var rect := {
			"x": (index % 16) * 256,
			"y": (index / 16) * 256,
			"w": 256,
			"h": 256,
		}
		rects.append(rect)
		durations.append(41.666667)
		source_frames.append({
			"index": index,
			"source_frame": index + 1,
			"timestamp_seconds": float(index) / 24.0,
			"duration_ms": 41.666667,
			"png": "res://tools/sprites/niko_walk_happy_proof/sprite-sheet-alpha.png",
			"sha256": "fixture",
			"rect": rect.duplicate(true),
		})
	return {
		"schema_version": 1,
		"kind": "pixelmotion-video-sprite-library",
		"engine": "pixelmotion2d-video-library",
		"clip_id": "walk_happy",
		"game_input": "res://tools/sprites/niko_walk_happy_proof/sprite-sheet-alpha.png",
		"degraded_static_fallback": false,
		"_manifest_path": "res://reports/video_sprite_importer/manifest.json",
		"source": {
			"frame_count": frame_count,
			"fps": {"numerator": 24, "denominator": 1, "value": 24.0},
		},
		"cell": {"width": 256, "height": 256, "safe_margin": 24},
		"root": {"x": 128, "y": 232},
		"animation": {"rows": {"source_all": {
			"frames": frame_count,
			"fps": 24.0,
			"fps_rational": {"numerator": 24, "denominator": 1},
			"durations_ms": durations,
			"loop": true,
		}}},
		"frame_layout": {
			"sheetWidth": 4096,
			"sheetHeight": 512,
			"cellWidth": 256,
			"cellHeight": 256,
			"rows": {"source_all": rects},
		},
		"source_frames": source_frames,
	}


func _fake_texture(_path: String) -> Texture2D:
	var texture := GradientTexture2D.new()
	texture.width = 4096
	texture.height = 512
	return texture

func test_manifest_accepts_the_sprite_gen_full_frame_engine_and_rejects_unknown_engines() -> void:
	var manifest := _valid_manifest(3)
	manifest["engine"] = "pixelmotion2d-cutout+sprite-gen-pixel-unfake"
	assert_array(Importer.validate_manifest(manifest)).is_empty()

	manifest["engine"] = "unknown-resizer"
	assert_str("\n".join(Importer.validate_manifest(manifest))).contains(
		"engine must be one of"
	)
