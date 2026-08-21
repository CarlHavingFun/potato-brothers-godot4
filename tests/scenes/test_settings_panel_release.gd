extends GdUnitTestSuite


const SETTINGS_SCENE := "res://scenes/ui/settings_panel/settings_panel.tscn"


func test_settings_panel_has_five_scrollable_pages_and_fixed_footer() -> void:
	var panel: SettingsPanel = auto_free(load(SETTINGS_SCENE).instantiate()) as SettingsPanel
	add_child(panel)
	await await_idle_frame()

	assert_int(panel.tab_buttons.size()).is_equal(5)
	assert_int(panel.page_containers.size()).is_equal(5)
	for page: ScrollContainer in panel.page_containers:
		assert_object(page).is_not_null()
	assert_object(panel.get_node("SafeArea/Layout/Footer/ApplyButton")).is_not_null()
	assert_object(panel.get_node("SafeArea/Layout/Footer/CancelButton")).is_not_null()
	assert_object(panel.get_node("SafeArea/Layout/Footer/ResetButton")).is_not_null()
	assert_object(panel.conflict_dialog.get_ok_button().custom_minimum_size).is_equal(Vector2(150, 48))
	assert_object(panel.conflict_dialog.get_cancel_button().custom_minimum_size).is_equal(Vector2(150, 48))
	assert_object(panel.get_node_or_null("DisplayConfirmDialog")).is_null()
	assert_object(panel.get_node_or_null("DisplayConfirmTimer")).is_null()


func test_settings_panel_value_labels_follow_sliders() -> void:
	var panel: SettingsPanel = auto_free(load(SETTINGS_SCENE).instantiate()) as SettingsPanel
	add_child(panel)
	await await_idle_frame()

	panel.music_slider.value = 42.0
	panel.enemy_health_slider.value = 135.0
	await await_idle_frame()

	assert_str(panel.value_labels[panel.music_slider].text).is_equal("42%")
	assert_str(panel.value_labels[panel.enemy_health_slider].text).is_equal("135%")


func test_only_windowed_mode_enables_resolution_and_tabs_wrap() -> void:
	var panel: SettingsPanel = auto_free(load(SETTINGS_SCENE).instantiate()) as SettingsPanel
	add_child(panel)
	await await_idle_frame()

	panel.display_mode_option.select(SettingsPanel.DISPLAY_MODE_BORDERLESS)
	panel.call("_on_display_mode_selected", SettingsPanel.DISPLAY_MODE_BORDERLESS)
	assert_bool(panel.resolution_option.disabled).is_true()
	panel.display_mode_option.select(SettingsPanel.DISPLAY_MODE_EXCLUSIVE)
	panel.call("_on_display_mode_selected", SettingsPanel.DISPLAY_MODE_EXCLUSIVE)
	assert_bool(panel.resolution_option.disabled).is_true()
	panel.display_mode_option.select(SettingsPanel.DISPLAY_MODE_WINDOWED)
	panel.call("_on_display_mode_selected", SettingsPanel.DISPLAY_MODE_WINDOWED)
	assert_bool(panel.resolution_option.disabled).is_false()
	panel.call("_select_tab", 0)
	panel.call("_switch_tab_relative", -1)
	assert_int(panel.active_tab).is_equal(4)
	panel.call("_switch_tab_relative", 1)
	assert_int(panel.active_tab).is_equal(0)


func test_display_changes_preview_immediately_and_cancel_restores_snapshot() -> void:
	var original := Global.product_settings.copy()
	var panel: SettingsPanel = auto_free(load(SETTINGS_SCENE).instantiate()) as SettingsPanel
	add_child(panel)
	await await_idle_frame()
	panel.set_resolution_provider(func() -> Array[Vector2i]: return [Vector2i(1024, 576), Vector2i(1366, 768)])

	var listed_resolutions: Array[Vector2i] = []
	for index: int in panel.resolution_option.item_count:
		listed_resolutions.append(panel.resolution_option.get_item_metadata(index) as Vector2i)
	assert_array(listed_resolutions).contains([Vector2i(1024, 576), Vector2i(1366, 768)])

	panel.vsync_check.button_pressed = not original.vsync_enabled
	panel.call("_on_vsync_toggled", panel.vsync_check.button_pressed)
	assert_bool(Global.product_settings.vsync_enabled).is_equal(not original.vsync_enabled)
	panel.call("_on_cancel_button_pressed")
	assert_bool(Global.product_settings.is_equal_to(original)).is_true()


func test_apply_saves_immediate_display_without_confirmation() -> void:
	var original := Global.product_settings.copy()
	var panel: SettingsPanel = auto_free(load(SETTINGS_SCENE).instantiate()) as SettingsPanel
	add_child(panel)
	await await_idle_frame()
	panel.show()
	panel.vsync_check.button_pressed = not original.vsync_enabled
	panel.call("_on_vsync_toggled", panel.vsync_check.button_pressed)

	panel.call("_on_apply_button_pressed")

	assert_bool(Global.product_settings.vsync_enabled).is_equal(not original.vsync_enabled)
	assert_bool(panel.visible).is_false()
	Global.restore_product_settings(original)


func test_fixed_header_pages_and_footer_fit_720p_and_1080p() -> void:
	var viewport: SubViewport = auto_free(SubViewport.new()) as SubViewport
	viewport.size = Vector2i(1280, 720)
	add_child(viewport)
	var panel: SettingsPanel = load(SETTINGS_SCENE).instantiate() as SettingsPanel
	viewport.add_child(panel)
	await await_idle_frame()

	_assert_fixed_regions_inside_panel(panel)
	viewport.size = Vector2i(1920, 1080)
	await await_idle_frame()
	_assert_fixed_regions_inside_panel(panel)


func _assert_fixed_regions_inside_panel(panel: SettingsPanel) -> void:
	var panel_rect := panel.get_global_rect()
	for path: String in ["SafeArea/Layout/Header", "SafeArea/Layout/Tabs", "SafeArea/Layout/PageFrame", "SafeArea/Layout/Footer"]:
		var rect := (panel.get_node(path) as Control).get_global_rect()
		assert_bool(panel_rect.encloses(rect)).override_failure_message("%s was clipped by the settings panel" % path).is_true()
