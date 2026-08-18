extends GdUnitTestSuite


func test_camera_trauma_is_clamped_and_decays_deterministically() -> void:
	var camera := auto_free(Camera.new()) as Camera
	camera.noise.seed = 99
	camera.add_trauma(2.0)

	assert_float(camera.trauma).is_equal(1.0)
	camera._process(0.25)

	assert_float(camera.trauma).is_less(1.0)
	assert_float(camera.offset.length()).is_greater(0.0)
	camera._process(2.0)
	assert_float(camera.trauma).is_equal(0.0)
	assert_object(camera.offset).is_equal(Vector2.ZERO)


func test_feedback_profiles_distinguish_normal_critical_and_player_damage() -> void:
	var normal := CombatFeedbackProfile.for_cue(&"hit.normal")
	var critical := CombatFeedbackProfile.for_cue(&"hit.critical")
	var player_damage := CombatFeedbackProfile.for_cue(&"player.damaged")

	assert_float(normal.hit_stop_seconds).is_greater(0.0)
	assert_float(critical.hit_stop_seconds).is_greater(normal.hit_stop_seconds)
	assert_int(player_damage.priority).is_greater(critical.priority)
	assert_float(critical.damage_text_scale).is_greater(1.0)


func test_feedback_profile_overrides_are_clamped_and_skin_driven() -> void:
	var profile := CombatFeedbackProfile.for_cue(&"hit.normal", {
		"hit_stop_seconds": 5.0,
		"hit_stop_scale": -3.0,
		"audio_pitch_min": 1.15,
		"audio_pitch_max": 0.2,
		"priority": 500,
	})

	assert_float(profile.hit_stop_seconds).is_equal(0.2)
	assert_float(profile.hit_stop_scale).is_equal(0.01)
	assert_float(profile.audio_pitch_max).is_equal(1.15)
	assert_int(profile.priority).is_equal(100)


func test_high_frequency_feedback_is_coalesced_per_semantic_cue() -> void:
	var presenter := auto_free(GameplayCuePresenter.new()) as GameplayCuePresenter
	var profile := CombatFeedbackProfile.for_cue(&"hit.normal", {
		"minimum_interval_seconds": 0.05,
	})

	assert_bool(presenter.can_present_feedback(&"hit.normal", profile, 1_000_000)).is_true()
	assert_bool(presenter.can_present_feedback(&"hit.normal", profile, 1_020_000)).is_false()
	assert_bool(presenter.can_present_feedback(&"hit.normal", profile, 1_060_000)).is_true()
	assert_bool(presenter.can_present_feedback(&"hit.critical", profile, 1_020_000)).is_true()


func test_presentation_settings_prefer_product_values_and_fall_back_per_field() -> void:
	var product_settings := {
		"screen_shake_intensity": 0.25,
		"gamepad_rumble_intensity": 0.6,
		"show_damage_numbers": false,
	}
	var legacy_settings := {
		"screen_shake_intensity": 0.8,
		"controller_vibration_intensity": 0.6,
		"show_damage_numbers": true,
		"show_boss_health_bar": false,
	}

	assert_float(float(GameplayCuePresenter.setting_from_sources(
		product_settings, legacy_settings, &"screen_shake_intensity", 1.0
	))).is_equal(0.25)
	assert_float(float(GameplayCuePresenter.setting_from_sources(
		product_settings, legacy_settings, &"gamepad_rumble_intensity", 1.0
	))).is_equal(0.6)
	assert_bool(bool(GameplayCuePresenter.setting_from_sources(
		product_settings, legacy_settings, &"show_damage_numbers", true
	))).is_false()
	assert_bool(bool(GameplayCuePresenter.setting_from_sources(
		product_settings, legacy_settings, &"show_boss_health_bar", true
	))).is_false()


func test_shake_and_rumble_settings_scale_only_presentation_definitions() -> void:
	var shake := {"strength": 12.0}
	var rumble := {"weak": 0.4, "strong": 0.8, "duration": 0.2}
	var scaled_shake: Dictionary = GameplayCuePresenter.scaled_shake_definition(shake, 0.25)
	var scaled_rumble: Dictionary = GameplayCuePresenter.scaled_rumble_definition(rumble, 0.5)

	assert_float(float(scaled_shake.strength)).is_equal(3.0)
	assert_float(float(scaled_rumble.weak)).is_equal(0.2)
	assert_float(float(scaled_rumble.strong)).is_equal(0.4)
	assert_float(float(scaled_rumble.duration)).is_equal(0.2)
	assert_float(float(shake.strength)).is_equal(12.0)
	assert_float(float(rumble.strong)).is_equal(0.8)
	assert_float(float(GameplayCuePresenter.scaled_rumble_definition(rumble, 0.0).duration)).is_equal(0.0)


func test_reduce_flashes_can_disable_flash_without_touching_unit_health() -> void:
	var unit: Unit = auto_free(
		load("res://scenes/unit/enemy/enemy_chaser_slow.tscn").instantiate() as Unit
	) as Unit
	add_child(unit)
	await await_idle_frame()
	var health_before: float = unit.health_component.current_health

	unit.set_flash_material(true)
	assert_object(unit.sprite.material).is_null()
	assert_float(unit.health_component.current_health).is_equal(health_before)

	unit.set_flash_material(false)
	assert_object(unit.sprite.material).is_same(Global.FLASH_MATERIAL)
	assert_float(unit.health_component.current_health).is_equal(health_before)


func test_health_bar_visibility_rules_distinguish_player_boss_and_normal_enemy() -> void:
	assert_bool(Unit.health_bar_visible_for(true, false, false, true)).is_false()
	assert_bool(Unit.health_bar_visible_for(false, true, true, false)).is_false()
	assert_bool(Unit.health_bar_visible_for(false, false, false, false)).is_true()


func test_high_contrast_projectiles_do_not_change_collision_contract() -> void:
	var projectile: Projectile = auto_free(
		load("res://scenes/projectiles/projectile_pistol.tscn").instantiate() as Projectile
	) as Projectile
	add_child(projectile)
	await await_idle_frame()
	var sprite := projectile.get_node("Sprite2D") as Sprite2D
	var collision_shape := projectile.get_node("HitboxComponent/CollisionShape2D") as CollisionShape2D
	var original_scale: Vector2 = sprite.scale
	var original_layer: int = projectile.hitbox.collision_layer
	var original_mask: int = projectile.hitbox.collision_mask
	var original_shape: Shape2D = collision_shape.shape

	projectile.apply_high_contrast(true)

	assert_float(sprite.scale.length()).is_greater(original_scale.length())
	assert_int(projectile.hitbox.collision_layer).is_equal(original_layer)
	assert_int(projectile.hitbox.collision_mask).is_equal(original_mask)
	assert_object(collision_shape.shape).is_same(original_shape)

	projectile.apply_high_contrast(false)
	assert_object(sprite.scale).is_equal(original_scale)
