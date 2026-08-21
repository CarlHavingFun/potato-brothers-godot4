extends GdUnitTestSuite


const SCENE_PATH := "res://scenes/ui/stats_container/stats_container.tscn"

var _previous_locale := ""


func before_test() -> void:
	_previous_locale = TranslationServer.get_locale()
	Global.end_run()


func after_test() -> void:
	TranslationServer.set_locale(_previous_locale)
	Global.end_run()


func test_stats_container_displays_level_and_all_stats_without_scrolling() -> void:
	Global.begin_run(160, null, 0)
	Global.current_run.level = 7
	for stat_id in StatId.size():
		Global.current_run.player_stats.set_stat(stat_id, float(stat_id) + 0.5)
	Global.current_run.player_stats.set_stat(StatId.MAX_HEALTH, 15.0)
	Global.current_run.player_stats.set_stat(StatId.DAMAGE, 12.5)
	Global.current_run.player_stats.set_stat(StatId.MELEE_DAMAGE, -3.0)

	var panel := auto_free((load(SCENE_PATH) as PackedScene).instantiate()) as StatsContainer
	add_child(panel)
	await await_idle_frame()
	panel.refresh_stats()

	assert_int(panel.stat_row_count()).is_equal(StatId.size())
	assert_object(panel.find_child("ScrollContainer", true, false)).is_null()
	var grid := panel.get_node_or_null("MarginContainer/VBoxContainer/StatsGrid") as GridContainer
	assert_object(grid).is_not_null()
	if grid == null:
		return
	assert_int(grid.columns).is_equal(1)
	assert_float(panel.custom_minimum_size.x).is_less_equal(400.0)
	assert_float(panel.custom_minimum_size.y).is_less_equal(720.0)
	assert_str(panel.call("level_value_text")).is_equal("7")
	assert_str(panel.value_text_for_stat(StatId.MAX_HEALTH)).is_equal("15")
	assert_str(panel.value_text_for_stat(StatId.DAMAGE)).is_equal("12.5%")
	assert_str(panel.value_text_for_stat(StatId.MELEE_DAMAGE)).is_equal("-3")
	assert_str(panel.value_text_for_stat(StatId.CRITICAL_CHANCE)).ends_with("%")
	for stat_id in StatId.size():
		assert_object(panel.call("icon_texture_for_stat", stat_id)).is_not_null()


func test_stat_values_use_positive_negative_and_neutral_reference_colors() -> void:
	Global.begin_run(162, null, 0)
	Global.current_run.player_stats.set_stat(StatId.DAMAGE, 12.0)
	Global.current_run.player_stats.set_stat(StatId.MELEE_DAMAGE, -3.0)
	Global.current_run.player_stats.set_stat(StatId.ARMOR, 0.0)
	var panel := auto_free((load(SCENE_PATH) as PackedScene).instantiate()) as StatsContainer
	add_child(panel)
	await await_idle_frame()
	panel.refresh_stats()

	assert_bool(panel.has_method("value_color_for_stat")).is_true()
	if not panel.has_method("value_color_for_stat"):
		return
	assert_object(panel.call("value_color_for_stat", StatId.DAMAGE)).is_equal(
		Color("72e04d")
	)
	assert_object(panel.call("value_color_for_stat", StatId.MELEE_DAMAGE)).is_equal(
		Color("e54a45")
	)
	assert_object(panel.call("value_color_for_stat", StatId.ARMOR)).is_equal(
		Color("f2f2f2")
	)


func test_chinese_stat_titles_are_localized_and_never_expose_internal_keys() -> void:
	TranslationServer.set_locale("zh_CN")
	Global.begin_run(161, null, 0)
	var panel := auto_free((load(SCENE_PATH) as PackedScene).instantiate()) as StatsContainer
	add_child(panel)
	await await_idle_frame()
	panel.refresh_stats()

	for stat_id in StatId.size():
		var title := panel.title_text_for_stat(stat_id)
		assert_str(title).is_not_empty()
		assert_str(title).not_contains("stat.")
		assert_str(title).not_contains("_")
	assert_str(panel.title_text_for_stat(StatId.DAMAGE)).is_equal("伤害")
	assert_str(panel.title_text_for_stat(StatId.MELEE_DAMAGE)).is_equal("近战伤害")
	var title := panel.get_node_or_null("MarginContainer/VBoxContainer/Title") as Label
	var level_name := panel.get_node_or_null(
		"MarginContainer/VBoxContainer/LevelRow/Name"
	) as Label
	assert_object(title).is_not_null()
	assert_object(level_name).is_not_null()
	if title == null or level_name == null:
		return
	assert_str(title.text).is_equal("属性")
	assert_str(level_name.text).is_equal("当前等级")


func test_stats_container_reads_values_only_through_the_stat_id_api() -> void:
	var source := FileAccess.get_file_as_string(
		"res://scenes/ui/stats_container/stats_container.gd"
	)

	assert_str(source).contains("Global.get_stat_value_by_id(stat_id)")
	assert_str(source).not_contains("Global.get_stat_value(\"")
