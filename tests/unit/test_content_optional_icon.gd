extends GdUnitTestSuite


func test_content_validity_does_not_require_an_icon() -> void:
	var definition := GogoContentDefinition.new()
	definition.content_id = &"test.no_icon"
	definition.display_name = "文字回退"
	definition.kind = &"item"

	assert_bool(definition.is_valid()).is_true()
	assert_str(String(definition.icon_asset_id)).is_empty()


func test_snapshot_preserves_optional_icon_binding() -> void:
	var definition := GogoContentDefinition.new()
	definition.content_id = &"test.icon"
	definition.display_name = "清晰图标"
	definition.kind = &"item"
	definition.icon_asset_id = &"static_test_icon"
	var pack := GogoContentPackDefinition.new()
	pack.pack_id = &"test.optional_icon"
	pack.definitions.append(definition)
	var snapshot := GogoContentRegistry.new().build_snapshot([pack])

	assert_object(snapshot).is_not_null()
	var restored := snapshot.definition(&"test.icon", &"item")
	assert_object(restored).is_not_null()
	assert_str(String(restored.icon_asset_id)).is_equal("static_test_icon")


func test_validation_shop_and_upgrade_content_reach_the_approved_static_icons() -> void:
	var snapshot := GogoContentRegistry.new().build_snapshot(ValidationContentFactory.create_packs())
	var item := snapshot.definition(&"gogobro.core:item/training_1", &"item") as GogoItemDefinition
	var upgrade := snapshot.definition(&"gogobro.core:upgrade/training_1", &"upgrade") as GogoUpgradeDefinition

	assert_object(item).is_not_null()
	assert_str(item.display_name).is_equal("防弹内衬")
	assert_str(String(item.icon_asset_id)).is_equal("ballistic_liner")
	assert_object(upgrade).is_not_null()
	assert_str(upgrade.display_name).is_equal("重甲头盔")
	assert_str(String(upgrade.icon_asset_id)).is_equal("one_more_round")


func test_action_button_keeps_text_and_uses_nearest_neighbor_for_icon() -> void:
	var screen := auto_free(GogoScreenBase.new()) as GogoScreenBase
	screen.build_screen("可选静态素材")
	var button := screen.add_action("文字始终保留", Callable(), false, _test_texture())

	assert_str(button.text).is_equal("文字始终保留")
	assert_object(button.icon).is_not_null()
	assert_bool(button.expand_icon).is_true()
	assert_int(button.texture_filter).is_equal(CanvasItem.TEXTURE_FILTER_NEAREST)
	assert_int(button.get_theme_constant(&"icon_max_width")).is_equal(64)


func test_action_button_without_icon_keeps_the_existing_text_path() -> void:
	var screen := auto_free(GogoScreenBase.new()) as GogoScreenBase
	screen.build_screen("文字回退")
	var button := screen.add_action("原按钮文字", Callable())

	assert_str(button.text).is_equal("原按钮文字")
	assert_object(button.icon).is_null()
	assert_bool(button.expand_icon).is_false()
	assert_int(button.texture_filter).is_equal(CanvasItem.TEXTURE_FILTER_NEAREST)


func test_content_id_tail_produces_the_frozen_difficulty_selector() -> void:
	assert_str(String(GogoScreenBase.selector_from_content_id(
		&"gogobro.core:difficulty/standard"
	))).is_equal("standard")
	assert_str(String(GogoScreenBase.selector_from_content_id(&"missing_separator"))).is_empty()


func _test_texture() -> ImageTexture:
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.9, 0.55, 0.15, 1.0))
	return ImageTexture.create_from_image(image)
