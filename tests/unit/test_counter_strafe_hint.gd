extends GdUnitTestSuite


func test_first_wave_control_hint_makes_counter_strafe_discoverable_without_covering_play() -> void:
	var hud := auto_free(GogoBrotatoCombatHud.new()) as GogoBrotatoCombatHud
	add_child(hud)
	var hint := hud.get_node("ControlHint") as Control
	var hint_text := hint.get_node("HintContent/HintText") as Label
	assert_bool(hint.visible).is_true()
	assert_str(hint_text.text).contains("反向急停")
	assert_float(hint.size.x).is_greater_equal(340.0)
	assert_bool(Rect2(440, 200, 400, 320).intersects(Rect2(hint.position, hint.size))).is_false()
