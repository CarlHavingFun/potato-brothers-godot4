extends GdUnitTestSuite


var panel: UpgradePanel


func before_test() -> void:
	Global.end_run()
	Global.begin_run(901, null, 0)
	panel = auto_free(load("res://scenes/ui/upgrade_panel/upgrade_panel.tscn").instantiate())
	add_child(panel)
	await await_idle_frame()


func after_test() -> void:
	Global.end_run()


func test_upgrade_refresh_price_color_updates_when_materials_change() -> void:
	panel.load_upgrades(3)

	assert_object(panel.refresh_button.get_theme_color("font_color")).is_equal(Color(1.0, 0.25, 0.25, 1.0))
	Global.add_materials(Global.reward_service.upgrade_refresh_price(Global.current_run, 3))
	assert_object(panel.refresh_button.get_theme_color("font_color")).is_equal(Color.WHITE)
