extends GdUnitTestSuite


func test_chinese_and_english_product_translations_are_registered() -> void:
	var original_locale := TranslationServer.get_locale()
	TranslationServer.set_locale("zh_CN")
	assert_str(tr("ui.title.start")).is_equal("开始游戏")
	TranslationServer.set_locale("en")
	assert_str(tr("ui.title.start")).is_equal("Start Run")
	TranslationServer.set_locale(original_locale)


func test_missing_translation_uses_explicit_english_fallback() -> void:
	assert_str(Global.translate_text(&"ui.missing.test_key", "English fallback")).is_equal(
		"English fallback"
	)


func test_settings_panel_exposes_all_phase_one_product_controls() -> void:
	var path := "res://scenes/ui/settings_panel/settings_panel.tscn"
	assert_bool(ResourceLoader.exists(path)).is_true()
	if not ResourceLoader.exists(path):
		return
	var panel: Node = auto_free(load(path).instantiate())
	add_child(panel)
	await await_idle_frame()
	for control_name: String in ["MusicSlider", "SfxSlider", "FullscreenCheck", "ResolutionOption", "AimOption", "LocaleOption"]:
		assert_object(panel.find_child(control_name, true, false)).is_not_null()


func test_all_upgrade_cards_can_be_localized_without_per_card_translation_keys() -> void:
	var original_locale := TranslationServer.get_locale()
	TranslationServer.set_locale("zh_CN")
	for definition: UpgradeDef in Content.catalog.get_upgrades():
		var localized_name: String = Content.catalog.get_upgrade_display_name(definition.item)
		var localized_description: String = Content.catalog.get_upgrade_description(definition.item)
		assert_str(localized_name).is_not_empty()
		assert_str(localized_description).is_not_empty()
		assert_bool(localized_name != definition.item.item_name).is_true()
	TranslationServer.set_locale(original_locale)


func test_shop_item_types_have_product_translations() -> void:
	var original_locale := TranslationServer.get_locale()
	TranslationServer.set_locale("zh_CN")
	assert_str(Content.catalog.get_item_type_display_name(ItemBase.ItemType.WEAPON)).is_equal("武器")
	assert_str(Content.catalog.get_item_type_display_name(ItemBase.ItemType.PASSIVE)).is_equal("被动物品")
	TranslationServer.set_locale(original_locale)


func test_runtime_ui_sources_keep_chinese_copy_out_of_scripts_and_scenes() -> void:
	var runtime_ui_files := [
		"res://scenes/ui/frontend/frontend_shell.gd",
		"res://scenes/ui/frontend/frontend_shell.tscn",
		"res://scenes/ui/settings_panel/settings_panel.gd",
		"res://scenes/ui/settings_panel/settings_panel.tscn",
		"res://scenes/ui/codex/codex_panel.gd",
		"res://scenes/ui/codex/codex_panel.tscn",
		"res://scenes/ui/shop_card/shop_card.gd",
		"res://scenes/ui/shop_card/shop_card.tscn",
	]
	for path: String in runtime_ui_files:
		var source := FileAccess.get_file_as_string(path)
		assert_bool(_contains_han_text(source)).override_failure_message(
			"Runtime UI copy must live in PO catalogs: %s" % path
		).is_false()


func test_frontend_dynamic_copy_changes_with_locale_without_mixing_languages() -> void:
	var original_locale := TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	var frontend: FrontendShell = auto_free(load(
		"res://scenes/ui/frontend/frontend_shell.tscn"
	).instantiate())
	add_child(frontend)
	await await_idle_frame()
	var character := Content.catalog.get_characters()[0]
	var weapon := Content.catalog.get_weapons()[0].tiers[0]

	assert_str(frontend.aim_mode_option.get_item_text(0)).is_equal("Auto target")
	assert_str(frontend.run_mode_option.get_item_text(0)).is_equal("Standard")
	assert_bool(_contains_han_text(frontend.call("_character_traits_text", character))).is_false()
	assert_bool(_contains_han_text(frontend.call("_weapon_stats_text", weapon))).is_false()
	frontend.begin_new_run(1, 1204, AimMode.AUTO_TARGET)
	await await_idle_frame()
	var viewport_width := frontend.get_viewport_rect().size.x
	_assert_visible_buttons_in_viewport(frontend, viewport_width, "character")

	var test_character: CharacterDef = Content.catalog.get_characters()[1]
	assert_bool(frontend.choose_character(test_character.get_stable_id(Content.catalog.pack_id))).is_true()
	await await_idle_frame()
	_assert_visible_buttons_in_viewport(frontend, viewport_width, "weapon")

	var test_weapon_id: StringName = frontend.get("_visible_weapon_ids")[0]
	assert_bool(frontend.choose_weapon(test_weapon_id)).is_true()
	await await_idle_frame()
	_assert_visible_buttons_in_viewport(frontend, viewport_width, "difficulty")

	TranslationServer.set_locale("zh_CN")
	await await_idle_frame()
	assert_str(frontend.aim_mode_option.get_item_text(0)).is_equal("自动锁定")
	assert_str(frontend.run_mode_option.get_item_text(0)).is_equal("标准模式")
	TranslationServer.set_locale(original_locale)


func _contains_han_text(value: String) -> bool:
	for index in value.length():
		var codepoint := value.unicode_at(index)
		if codepoint >= 0x3400 and codepoint <= 0x9FFF:
			return true
	return false


func _assert_visible_buttons_in_viewport(root: Node, viewport_width: float, page_name: String) -> void:
	for child: Node in root.find_children("*", "Button", true, false):
		var button := child as Button
		if button == null or not button.is_visible_in_tree():
			continue
		var rect := button.get_global_rect()
		assert_bool(rect.position.x >= 0.0 and rect.end.x <= viewport_width).override_failure_message(
			"English %s button must stay inside the viewport: %s at %s" % [
				page_name, button.text, rect
			]
		).is_true()
