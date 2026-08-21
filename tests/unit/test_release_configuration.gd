extends GdUnitTestSuite


func test_neutral_product_title_and_skin_use_an_isolated_release_save_namespace() -> void:
	var project := ConfigFile.new()
	assert_int(project.load("res://project.godot")).is_equal(OK)
	assert_str(String(project.get_value("application", "config/name", ""))).is_equal(
		"Game Prototype"
	)
	assert_str(String(project.get_value("application", "config/icon", ""))).is_equal(
		"res://content_packs/skins/lets_gooooo/assets/ui/app_icon.png"
	)
	assert_str(String(project.get_value("presentation", "skin_manifest", ""))).is_equal(
		"res://content_packs/skins/lets_gooooo/skin.tres"
	)
	var global_font_uid := String(project.get_value("gui", "theme/custom_font", ""))
	assert_bool(global_font_uid.begins_with("uid://")).is_true()
	assert_str(ResourceUID.get_id_path(ResourceUID.text_to_id(global_font_uid))).is_equal(
		"res://assets/font/brotato_font_stack.tres"
	)
	# Keep the existing internal namespace so playtest profiles survive visual
	# naming changes; it is not exposed as the window or package title.
	assert_bool(bool(project.get_value(
		"application", "config/use_custom_user_dir", false
	))).is_true()
	assert_str(String(project.get_value(
		"application", "config/custom_user_dir_name", ""
	))).is_equal("LETS_GOOOOO")


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


func test_gdunit_runner_isolates_live_windows_user_data() -> void:
	var script := FileAccess.get_file_as_string("res://tools/run_tests.ps1")

	assert_str(script).contains("lets-gooooo-gdunit-")
	assert_str(script).contains("$env:APPDATA = $testAppData")
	assert_str(script).contains("$env:LOCALAPPDATA = $testLocalAppData")
	assert_str(script).contains("$env:APPDATA = $previousAppData")
	assert_str(script).contains("$env:LOCALAPPDATA = $previousLocalAppData")


func test_release_filter_keeps_selected_skin_but_excludes_gameplay_content_and_tooling() -> void:
	var config := ConfigFile.new()
	assert_int(config.load("res://export_presets.cfg")).is_equal(OK)
	for index: int in range(3):
		var section := "preset.%d" % index
		var excluded := String(config.get_value(section, "exclude_filter", ""))
		assert_str(String(config.get_value(section, "custom_features", ""))).contains(
			"release_staging_only"
		)
		assert_str(excluded).contains("content_packs/default/*")
		assert_str(excluded).contains("content_packs/skins/dev_placeholder/*")
		assert_str(excluded).contains("content_packs/skins/test_alt/*")
		assert_bool(excluded.contains(
			"content_packs/skins/lets_gooooo/asset_manifest.json"
		)).is_false()
		assert_str(String(config.get_value(section, "include_filter", ""))).contains(
			"content_packs/skins/lets_gooooo/asset_manifest.json"
		)
		assert_str(excluded).contains("assets/ui/*")
		assert_str(excluded).contains("assets/sprites/Weapons/Melee/*")
		assert_str(excluded).contains("assets/sprites/Weapons/Range/*")
		assert_str(excluded).contains("assets/sprites/Weapons/Icons/*")
		assert_str(excluded).contains("assets/sprites/Upgrades/*")
		assert_str(excluded).contains("assets/sprites/Gold/*")
		assert_str(excluded).contains("assets/sprites/Projectiles/*")
		assert_str(excluded).contains("assets/sprites/BG.png")
		assert_str(excluded).contains("assets/sprites/Map.png")
		assert_str(excluded).contains("assets/sprites/Spawn_mark.png")
		assert_bool(excluded.contains("content_packs/*,")).is_false()
		assert_str(excluded).contains("addons/*")
		assert_str(excluded).contains("tests/*")
		assert_str(excluded).contains("tools/*")
	var preset_source := FileAccess.get_file_as_string("res://export_presets.cfg")
	assert_str(preset_source).contains("RELEASE_POLICY=STAGING_ONLY")


func test_default_mechanics_content_has_no_legacy_item_icon_dependencies() -> void:
	var pack := load("res://content_packs/default/pack.tres") as ContentPackDef
	assert_object(pack).is_not_null()
	if pack == null:
		return
	assert_int(pack.weapons.size()).is_equal(24)
	assert_int(pack.passives.size()).is_equal(60)
	assert_int(pack.upgrades.size()).is_equal(64)
	for definition: WeaponDef in pack.weapons:
		assert_int(definition.tiers.size()).is_equal(4)
		for item: ItemWeapon in definition.tiers:
			assert_object(item.item_icon).is_null()
	for definition: PassiveItemDef in pack.passives:
		assert_object(definition.item.item_icon).is_null()
	for definition: UpgradeDef in pack.upgrades:
		assert_object(definition.item.item_icon).is_null()


func test_release_automation_and_ci_configuration_exist() -> void:
	assert_bool(FileAccess.file_exists("res://tools/build_release.ps1")).is_true()
	assert_bool(FileAccess.file_exists("res://tools/build_windows_release.ps1")).is_true()
	assert_bool(FileAccess.file_exists("res://tools/install_export_templates.ps1")).is_true()
	assert_bool(FileAccess.file_exists("res://tools/release_inspector/project.godot.template")).is_true()
	assert_bool(FileAccess.file_exists("res://tools/release_inspector/inspect_core_pck.gd")).is_true()
	assert_bool(FileAccess.file_exists("res://tools/assets/validate_skin_assets.gd")).is_true()
	assert_bool(FileAccess.file_exists("res://.github/workflows/phase-one.yml")).is_true()
	var build_script := FileAccess.get_file_as_string("res://tools/build_release.ps1")
	var inspector_script := FileAccess.get_file_as_string(
		"res://tools/release_inspector/inspect_core_pck.gd"
	)
	var inspector_project := FileAccess.get_file_as_string(
		"res://tools/release_inspector/project.godot.template"
	)
	var workflow := FileAccess.get_file_as_string("res://.github/workflows/phase-one.yml")
	assert_str(build_script).contains("[string]$SkinManifest")
	assert_str(build_script).contains("$FormalSkinManifest")
	assert_str(build_script).contains("Assert-FormalSkinAssetManifest")
	assert_str(build_script).contains("$FormalGlobalFontResource")
	assert_str(build_script).contains("Set-FormalGlobalFontConfiguration")
	assert_bool(build_script.contains(
		"$projectText = $projectText -replace '(?m)^theme/custom_font=.*"
	)).is_false()
	assert_str(build_script).contains("Asset manifest is required for the formal release skin")
	assert_str(build_script).contains("Remove-UnselectedSkinDirectories")
	assert_str(build_script).contains("validate_skin_assets.gd")
	assert_str(build_script).contains("--asset-manifest")
	assert_str(inspector_script).contains("--skin-manifest")
	assert_str(inspector_script).contains("--asset-manifest")
	assert_str(inspector_script).contains("FileAccess.file_exists(asset_manifest)")
	assert_str(inspector_script).contains("JSON.parse_string")
	assert_str(inspector_script).contains("FORMAL_GLOBAL_FONT_PATH")
	assert_str(inspector_script).contains("res://project.binary")
	assert_str(inspector_script).contains("gui/theme/custom_font")
	assert_str(inspector_script).contains("_validate_exported_global_font")
	assert_str(inspector_script).contains(
		"Asset manifest must be packaged beside the selected skin manifest"
	)
	assert_str(inspector_script).contains("APPROVED_SKIN_ART_EXTENSIONS")
	assert_str(inspector_script).contains("ALLOWED_DYNAMIC_ART_ROOTS")
	assert_str(inspector_script).contains("ALLOWED_CORE_ART_FILES")
	assert_str(inspector_script).contains("res://assets/sprites/Players/")
	assert_str(inspector_script).contains("res://assets/sprites/Enemies/")
	assert_str(inspector_script).contains("res://assets/sprites/shadow.png")
	assert_bool(inspector_script.contains("ALLOWED_CORE_ART_ROOTS")).is_false()
	assert_bool(inspector_script.contains("res://assets/sprites/Weapons/Icons/")).is_false()
	assert_bool(inspector_script.contains("res://assets/sprites/Upgrades/")).is_false()
	assert_str(inspector_script).contains(".jpg")
	assert_str(inspector_script).contains(".psd")
	assert_str(inspector_script).contains(".aseprite")
	assert_str(inspector_script).contains(".zip")
	assert_str(inspector_script).contains("FORBIDDEN_SKIN_ARTIFACTS")
	assert_bool(inspector_project.contains("GOBRO")).is_false()
	assert_str(inspector_project).contains("Core PCK Release Inspector")
	assert_str(workflow).contains("lets-gooooo-gdunit.xml")
	assert_str(workflow).contains("lets-gooooo-${{ matrix.platform }}")
	assert_bool(workflow.contains("potato-brothers")).is_false()


func test_acceptance_import_uses_recovery_mode_to_avoid_editor_plugin_side_effects() -> void:
	var acceptance_script := FileAccess.get_file_as_string(
		"res://tools/run_phase_one_acceptance.ps1"
	)
	assert_str(acceptance_script).contains("--recovery-mode")


func test_windows_release_is_a_portable_x86_64_executable_and_external_pcks() -> void:
	var config := ConfigFile.new()
	assert_int(config.load("res://export_presets.cfg")).is_equal(OK)
	assert_str(String(config.get_value("preset.0", "platform", ""))).is_equal(
		"Windows Desktop"
	)
	assert_str(String(config.get_value("preset.0.options", "binary_format/architecture", ""))).is_equal(
		"x86_64"
	)
	assert_str(String(config.get_value("preset.0.options", "application/icon", ""))).is_equal(
		"res://content_packs/skins/lets_gooooo/assets/ui/app_icon.png"
	)
	assert_bool(bool(config.get_value("preset.0.options", "binary_format/embed_pck", true))).is_false()
	assert_str(String(config.get_value("preset.0", "export_path", ""))).ends_with("GamePrototype.exe")


func test_windows_build_installs_matching_templates_and_smokes_an_isolated_package() -> void:
	var wrapper := FileAccess.get_file_as_string("res://tools/build_windows_release.ps1")
	var installer := FileAccess.get_file_as_string("res://tools/install_export_templates.ps1")
	var build_script := FileAccess.get_file_as_string("res://tools/build_release.ps1")
	assert_str(wrapper).contains("install_export_templates.ps1")
	assert_str(wrapper).contains("-Platforms Windows")
	assert_str(wrapper).contains("content_packs/skins/lets_gooooo/skin.tres")
	assert_str(installer).contains("windows_release_x86_64.exe")
	assert_str(installer).contains("windows_debug_x86_64.exe")
	assert_str(installer).contains("Get-FileHash")
	assert_str(installer).contains("godotengine/godot/releases/download")
	assert_str(installer).contains("--continue-at")
	assert_str(build_script).contains("Assert-WindowsReleaseDirectory")
	assert_str(build_script).contains("Assert-WindowsReleaseArchive")
	assert_str(build_script).contains("game-prototype-release-smoke-")
	assert_str(build_script).contains("$env:APPDATA = $isolatedAppData")
	assert_str(build_script).contains("-RedirectStandardOutput")
	assert_str(build_script).contains("-RedirectStandardError")
	assert_str(build_script).contains("Exported runtime did not load the formal global font")
	assert_str(build_script).contains(
		"MECHANICS_CONTENT_READY weapons=24 passives=60 upgrades=64 presentation_icons=0"
	)
	var bootstrap := FileAccess.get_file_as_string(
		"res://core/content/bootstrap_content_loader.gd"
	)
	assert_str(bootstrap).contains("_validate_default_mechanics_contract")
	assert_str(bootstrap).contains(
		"MECHANICS_CONTENT_READY weapons=24 passives=60 upgrades=64 presentation_icons=0"
	)
	assert_str(build_script).contains("--quit-after")


func test_release_staging_imports_the_font_before_enabling_it_globally() -> void:
	var build_script := FileAccess.get_file_as_string("res://tools/build_release.ps1")
	var bootstrap_index := build_script.find(
		"$projectText = Set-StagingBootstrapFontConfiguration $projectText"
	)
	var initial_import_index := build_script.find(
		"Invoke-Godot $initialStagingImportArguments"
	)
	var formal_font_index := build_script.find(
		"$projectText = Set-FormalGlobalFontConfiguration $projectText $stagingProject"
	)
	var verified_import_index := build_script.find(
		"Invoke-Godot $verifiedStagingImportArguments"
	)
	assert_int(bootstrap_index).is_greater_equal(0)
	assert_int(initial_import_index).is_greater(bootstrap_index)
	assert_int(formal_font_index).is_greater(initial_import_index)
	assert_int(verified_import_index).is_greater(formal_font_index)
	assert_str(build_script).contains("Formal font binary imported data is missing")


func test_release_godot_processes_fail_on_logged_errors_and_unicode_corruption() -> void:
	var build_script := FileAccess.get_file_as_string("res://tools/build_release.ps1")
	assert_str(build_script).contains("$GodotFailureOutputPattern")
	assert_str(build_script).contains("Unicode parsing error")
	assert_str(build_script).contains("@(& $GodotBinary @Arguments 2>&1)")
	assert_str(build_script).contains("Godot logged errors")
	assert_str(build_script).contains("$RuntimeFailureOutputPattern")


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
