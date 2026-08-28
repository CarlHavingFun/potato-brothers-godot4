extends GdUnitTestSuite


const SHIPPING_STATIC_ROOT := "res://game/assets/gogobro_static"


func test_shipping_png_imports_preserve_exact_rgba8_pixels_for_release_validation() -> void:
	var png_paths := PackedStringArray()
	_collect_png_paths(SHIPPING_STATIC_ROOT, png_paths)
	assert_int(png_paths.size()).is_greater_equal(70)
	for png_path in png_paths:
		var import_path := png_path + ".import"
		assert_bool(FileAccess.file_exists(import_path)).override_failure_message(
			"Missing shipping PNG import sidecar: %s" % import_path
		).is_true()
		if not FileAccess.file_exists(import_path):
			continue
		var import_config := ConfigFile.new()
		var load_error := import_config.load(import_path)
		assert_int(load_error).override_failure_message(
			"Shipping PNG import sidecar must parse: %s" % import_path
		).is_equal(OK)
		if load_error != OK:
			continue
		assert_bool(bool(import_config.get_value("params", "process/fix_alpha_border", true))).override_failure_message(
			"Shipping PNG import must keep transparent RGB and RGBA8 hashes stable: %s" % import_path
		).is_false()


func _collect_png_paths(path: String, output: PackedStringArray) -> void:
	var directory := DirAccess.open(path)
	assert_object(directory).override_failure_message(
		"Unable to inspect shipping static directory: %s" % path
	).is_not_null()
	if directory == null:
		return
	for child in directory.get_directories():
		_collect_png_paths(path.path_join(child), output)
	for file_name in directory.get_files():
		if file_name.ends_with(".png"):
			output.append(path.path_join(file_name))
