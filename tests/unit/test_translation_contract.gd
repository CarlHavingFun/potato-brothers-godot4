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
