extends GdUnitTestSuite


const PLAYER_ACTOR := preload("res://game/gameplay/actors/player_actor.gd")
const ENEMY_ACTOR := preload("res://game/gameplay/actors/enemy_actor.gd")


func test_combat_hud_uses_local_backplates_without_restoring_a_fullscreen_shell() -> void:
	var hud := auto_free(GogoBrotatoCombatHud.new()) as GogoBrotatoCombatHud
	var top_left_backing := hud.get_node_or_null("TopLeft/Backing") as Panel
	var top_center_backing := hud.get_node_or_null("TopCenter/Backing") as Panel
	assert_object(top_left_backing).is_not_null()
	assert_object(top_center_backing).is_not_null()
	if top_left_backing != null:
		var style := top_left_backing.get_theme_stylebox(&"panel") as StyleBoxFlat
		assert_object(style).is_not_null()
		if style != null:
			assert_float(style.bg_color.a).is_greater_equal(0.55)
	if top_center_backing != null:
		var style := top_center_backing.get_theme_stylebox(&"panel") as StyleBoxFlat
		assert_object(style).is_not_null()
		if style != null:
			assert_float(style.bg_color.a).is_greater_equal(0.55)
	assert_bool((hud.get_node("Shell") as TextureRect).visible).is_false()


func test_player_and_enemy_define_grounded_noninteractive_shadows() -> void:
	assert_vector(PLAYER_ACTOR.GROUND_SHADOW_CENTER).is_equal(Vector2(0.0, 18.0))
	assert_vector(PLAYER_ACTOR.GROUND_SHADOW_SCALE).is_equal(Vector2(1.0, 0.34))
	assert_float(PLAYER_ACTOR.GROUND_SHADOW_COLOR.a).is_equal_approx(0.30, 0.001)
	assert_vector(ENEMY_ACTOR.GROUND_SHADOW_CENTER).is_equal(Vector2(0.0, 13.0))
	assert_vector(ENEMY_ACTOR.GROUND_SHADOW_SCALE).is_equal(Vector2(1.0, 0.36))
	assert_float(ENEMY_ACTOR.GROUND_SHADOW_COLOR.a).is_equal_approx(0.28, 0.001)


func test_enemy_hit_readability_is_longer_and_brighter_but_still_bounded() -> void:
	assert_float(ENEMY_ACTOR.HIT_FLASH_SECONDS).is_equal_approx(0.075, 0.0001)
	assert_float(ENEMY_ACTOR.HIT_SQUASH_SECONDS).is_equal_approx(0.110, 0.0001)
	assert_float(ENEMY_ACTOR.HIT_FLASH_GAIN).is_equal_approx(0.58, 0.0001)
	assert_bool(ENEMY_ACTOR.HIT_FLASH_SECONDS < 0.10).is_true()
	assert_bool(ENEMY_ACTOR.HIT_SQUASH_SECONDS < 0.15).is_true()
