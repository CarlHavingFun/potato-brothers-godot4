extends GdUnitTestSuite


func test_release_presets_cover_all_phase_one_desktop_platforms() -> void:
	assert_bool(FileAccess.file_exists("res://export_presets.cfg")).is_true()
	var config := ConfigFile.new()
	assert_int(config.load("res://export_presets.cfg")).is_equal(OK)
	var platforms: Array[String] = []
	for section: String in config.get_sections():
		if section.ends_with(".options"):
			continue
		if section.begins_with("preset."):
			platforms.append(String(config.get_value(section, "platform", "")))
	assert_array(platforms).contains_exactly_in_any_order(["Windows Desktop", "Linux", "macOS"])


func test_release_filter_keeps_selected_skin_but_excludes_gameplay_content_and_tooling() -> void:
	var config := ConfigFile.new()
	assert_int(config.load("res://export_presets.cfg")).is_equal(OK)
	for index: int in range(3):
		var section := "preset.%d" % index
		var excluded := String(config.get_value(section, "exclude_filter", ""))
		assert_str(excluded).contains("content_packs/default/*")
		assert_bool(excluded.contains("content_packs/*,")).is_false()
		assert_str(excluded).contains("addons/*")
		assert_str(excluded).contains("tests/*")
		assert_str(excluded).contains("tools/*")


func test_release_automation_and_ci_configuration_exist() -> void:
	assert_bool(FileAccess.file_exists("res://tools/build_release.ps1")).is_true()
	assert_bool(FileAccess.file_exists("res://tools/release_inspector/project.godot.template")).is_true()
	assert_bool(FileAccess.file_exists("res://tools/release_inspector/inspect_core_pck.gd")).is_true()
	assert_bool(FileAccess.file_exists("res://.github/workflows/phase-one.yml")).is_true()
	var build_script := FileAccess.get_file_as_string("res://tools/build_release.ps1")
	var inspector_script := FileAccess.get_file_as_string(
		"res://tools/release_inspector/inspect_core_pck.gd"
	)
	assert_str(build_script).contains("[string]$SkinManifest")
	assert_str(build_script).contains("Remove-UnselectedSkinDirectories")
	assert_str(inspector_script).contains("--skin-manifest")
