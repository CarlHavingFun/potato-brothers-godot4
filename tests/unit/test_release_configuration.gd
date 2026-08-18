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
	assert_bool(FileAccess.file_exists("res://tools/build_windows_release.ps1")).is_true()
	assert_bool(FileAccess.file_exists("res://tools/install_export_templates.ps1")).is_true()
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


func test_windows_release_is_a_portable_x86_64_executable_and_external_pcks() -> void:
	var config := ConfigFile.new()
	assert_int(config.load("res://export_presets.cfg")).is_equal(OK)
	assert_str(String(config.get_value("preset.0", "platform", ""))).is_equal(
		"Windows Desktop"
	)
	assert_str(String(config.get_value("preset.0.options", "binary_format/architecture", ""))).is_equal(
		"x86_64"
	)
	assert_bool(bool(config.get_value("preset.0.options", "binary_format/embed_pck", true))).is_false()
	assert_str(String(config.get_value("preset.0", "export_path", ""))).ends_with("GOBRO.exe")


func test_windows_build_installs_matching_templates_and_smokes_an_isolated_package() -> void:
	var wrapper := FileAccess.get_file_as_string("res://tools/build_windows_release.ps1")
	var installer := FileAccess.get_file_as_string("res://tools/install_export_templates.ps1")
	var build_script := FileAccess.get_file_as_string("res://tools/build_release.ps1")
	assert_str(wrapper).contains("install_export_templates.ps1")
	assert_str(wrapper).contains("-Platforms Windows")
	assert_str(installer).contains("windows_release_x86_64.exe")
	assert_str(installer).contains("windows_debug_x86_64.exe")
	assert_str(installer).contains("Get-FileHash")
	assert_str(installer).contains("godotengine/godot/releases/download")
	assert_str(installer).contains("--continue-at")
	assert_str(build_script).contains("Assert-WindowsReleaseDirectory")
	assert_str(build_script).contains("Assert-WindowsReleaseArchive")
	assert_str(build_script).contains("GOBRO-release-smoke-")
	assert_str(build_script).contains("$env:APPDATA = $isolatedAppData")
	assert_str(build_script).contains("--quit-after")


func test_bootstrap_resources_do_not_use_script_class_names_as_runtime_type_hints() -> void:
	# Exported .tres files are remapped to binary .res files. Runtime resource
	# loaders only advertise native type hints, so a class_name hint can reject a
	# valid binary resource before its script is attached.
	var guarded_files := [
		"res://core/balance/balance_profile_registry.gd",
		"res://core/content/bootstrap_content_loader.gd",
		"res://core/presentation/skin_resolver.gd",
	]
	for path: String in guarded_files:
		var source := FileAccess.get_file_as_string(path)
		assert_bool(source.contains('ResourceLoader.load(path, "BalancePackDef"')).is_false()
		assert_bool(source.contains('ResourceLoader.load(path, "SkinPackDef"')).is_false()
		assert_bool(source.contains('ResourceLoader.load(manifest_path, "ContentPackDef"')).is_false()
