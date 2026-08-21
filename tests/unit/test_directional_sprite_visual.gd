extends GdUnitTestSuite


func test_direction_quantization_uses_godot_screen_coordinates() -> void:
	var cases := {
		Vector2.DOWN: &"down",
		Vector2(1, 1): &"down_right",
		Vector2.RIGHT: &"right",
		Vector2(1, -1): &"up_right",
		Vector2.UP: &"up",
		Vector2(-1, -1): &"up_left",
		Vector2.LEFT: &"left",
		Vector2(-1, 1): &"down_left",
	}
	for input: Vector2 in cases:
		assert_str(DirectionalSpriteVisual.direction_from_vector(input)).override_failure_message(
			str(input)
		).is_equal(String(cases[input]))


func test_zero_motion_preserves_last_facing_and_switches_to_idle() -> void:
	var visual := auto_free(DirectionalSpriteVisual.new()) as DirectionalSpriteVisual
	visual.sprite_frames = _minimal_sprite_frames()
	add_child(visual)
	await await_idle_frame()

	visual.update_motion(Vector2(-1, -1))
	assert_str(visual.last_facing).is_equal("up_left")
	assert_str(visual.current_action).is_equal("walk")

	visual.update_motion(Vector2.ZERO)
	assert_str(visual.last_facing).is_equal("up_left")
	assert_str(visual.current_action).is_equal("idle")
	assert_str(visual.animation).is_equal("idle_up_left")


func test_action_priority_is_terminal_then_transient_then_movement() -> void:
	var visual := auto_free(DirectionalSpriteVisual.new()) as DirectionalSpriteVisual
	visual.sprite_frames = _minimal_sprite_frames()
	add_child(visual)
	await await_idle_frame()

	visual.update_motion(Vector2.DOWN)
	visual.trigger_action(&"dash")
	assert_str(visual.current_action).is_equal("dash")
	visual.trigger_action(&"hit")
	assert_str(visual.current_action).is_equal("hit")
	visual.trigger_action(&"victory")
	assert_str(visual.current_action).is_equal("victory")
	visual.trigger_action(&"death")
	assert_str(visual.current_action).is_equal("death")

	visual.clear_action(&"death")
	assert_str(visual.current_action).is_equal("victory")
	visual.clear_action(&"victory")
	assert_str(visual.current_action).is_equal("hit")
	visual.clear_action(&"hit")
	assert_str(visual.current_action).is_equal("dash")
	visual.clear_action(&"dash")
	assert_str(visual.current_action).is_equal("walk")


func test_victory_uses_its_front_only_fallback() -> void:
	var visual := auto_free(DirectionalSpriteVisual.new()) as DirectionalSpriteVisual
	visual.sprite_frames = _minimal_sprite_frames()
	add_child(visual)
	await await_idle_frame()

	visual.set_facing(&"up")
	visual.trigger_action(&"victory")

	assert_str(visual.current_action).is_equal("victory")
	assert_str(visual.animation).is_equal("victory_down")


func test_missing_transient_animation_does_not_latch_the_idle_fallback() -> void:
	var visual := auto_free(DirectionalSpriteVisual.new()) as DirectionalSpriteVisual
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	frames.add_animation(&"idle_down")
	frames.set_animation_loop(&"idle_down", true)
	frames.add_frame(&"idle_down", GradientTexture2D.new())
	visual.sprite_frames = frames
	add_child(visual)
	await await_idle_frame()

	assert_bool(visual.trigger_action(&"dash")).is_false()
	assert_str(visual.current_action).is_equal("idle")
	assert_str(visual.animation).is_equal("idle_down")


func test_player_detects_directional_visual_without_changing_weapon_container() -> void:
	var player := auto_free(
		load("res://scenes/unit/players/player_well_rounded.tscn").instantiate()
	) as Player
	var visual := auto_free(DirectionalSpriteVisual.new()) as DirectionalSpriteVisual
	visual.name = "DirectionalSpriteVisual"
	visual.sprite_frames = _minimal_sprite_frames()
	player.get_node("Visuals").add_child(visual)
	add_child(player)
	await await_idle_frame()

	assert_object(player.directional_visual).is_same(visual)
	assert_bool(player.sprite.visible).is_false()
	assert_object(player.weapon_container).is_same(player.get_node("WeaponContainer"))

	player.move_dir = Vector2(1, -1)
	player.update_animations()
	assert_str(visual.last_facing).is_equal("up_right")
	assert_str(visual.current_action).is_equal("walk")

	player.start_dash()
	assert_bool(player.is_dashing).is_true()
	assert_str(visual.current_action).is_equal("dash")
	assert_int(visual.sprite_frames.get_frame_count(&"dash_up_right")).is_equal(6)
	assert_float(visual.animation_duration(&"dash")).is_equal_approx(0.4, 0.001)

	player._on_dash_timer_timeout()
	assert_bool(player.is_dashing).is_false()
	assert_str(visual.current_action).is_equal("dash")
	visual.call("_on_animation_finished")
	assert_str(visual.current_action).is_equal("idle")
	player.is_dashing = true
	player.update_animations()
	assert_str(visual.current_action).is_equal("idle")
	player.is_dashing = false

	player.health_component.on_unit_hit.emit()
	assert_str(visual.current_action).is_equal("hit")
	assert_object(visual.material).is_same(Global.FLASH_MATERIAL)
	player.flash_timer.stop()
	player.flash_timer.timeout.emit()
	assert_object(visual.material).is_null()
	player.health_component.on_unit_died.emit()
	assert_str(visual.current_action).is_equal("death")
	assert_object(visual.material).is_null()
	assert_object(player.directional_visual).is_null()
	assert_object(visual.get_parent()).is_same(self)


func _minimal_sprite_frames() -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	var texture := GradientTexture2D.new()
	var action_specs := {
		&"idle": {"frame_count": 6, "fps": 6.0, "loop": true},
		&"walk": {"frame_count": 8, "fps": 10.0, "loop": true},
		&"dash": {"frame_count": 6, "fps": 15.0, "loop": false},
		&"hit": {"frame_count": 4, "fps": 16.0, "loop": false},
		&"death": {"frame_count": 10, "fps": 10.0, "loop": false},
	}
	for direction: StringName in DirectionalSpriteVisual.DIRECTIONS:
		for action: StringName in action_specs:
			var spec := action_specs[action] as Dictionary
			_add_animation(
				frames,
				StringName("%s_%s" % [action, direction]),
				texture,
				int(spec["frame_count"]),
				float(spec["fps"]),
				bool(spec["loop"])
			)
	_add_animation(frames, &"victory_down", texture, 12, 10.0, false)
	return frames


func _add_animation(
	frames: SpriteFrames,
	animation_name: StringName,
	texture: Texture2D,
	frame_count: int,
	fps: float,
	loop: bool
) -> void:
	frames.add_animation(animation_name)
	frames.set_animation_speed(animation_name, fps)
	frames.set_animation_loop(animation_name, loop)
	for _frame_index in frame_count:
		frames.add_frame(animation_name, texture)
