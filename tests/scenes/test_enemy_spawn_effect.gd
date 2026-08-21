extends GdUnitTestSuite


const SPAWN_EFFECT_SCENE := preload("res://scenes/effects/enemy_spawn_effect.tscn")
const EXPECTED_FLASH_TIMES := [0.0, 0.15, 0.3, 0.45, 0.6, 0.75]
const EXPECTED_FLASH_VALUES := [false, true, false, true, false, true]
const GEOMETRY_CONSTANTS := [
	&"OUTLINE_BACKSLASH",
	&"OUTLINE_SLASH",
	&"FILL_BACKSLASH",
	&"FILL_SLASH",
]


func after_test() -> void:
	Global.end_run()


func test_spawn_marker_is_solid_code_drawn_geometry_without_texture_dependency() -> void:
	var effect: Node2D = auto_free(SPAWN_EFFECT_SCENE.instantiate()) as Node2D
	add_child(effect)
	await await_idle_frame()

	assert_bool(effect is Sprite2D).override_failure_message(
		"The spawn warning must be code-drawn Node2D geometry, not a texture-backed Sprite2D."
	).is_false()
	var source := FileAccess.get_file_as_string(
		"res://scenes/effects/enemy_spawn_effect.gd"
	)
	assert_bool(source.contains("draw_colored_polygon")).is_true()
	assert_bool(source.contains("Presentation")).is_false()
	assert_bool(source.contains("resolve_texture")).is_false()

	var constants := (effect.get_script() as Script).get_script_constant_map()
	for constant_name: StringName in GEOMETRY_CONSTANTS:
		assert_bool(constants.has(constant_name)).override_failure_message(
			"Missing marker polygon constant: %s" % constant_name
		).is_true()
		if not constants.has(constant_name):
			continue
		var polygon := constants.get(constant_name) as Array
		assert_int(polygon.size()).is_greater_equal(4)
		for point: Vector2 in polygon:
			assert_vector(point).override_failure_message(
				"Spawn-marker points must use integer local coordinates."
			).is_equal(point.round())

	assert_bool(constants.has(&"OUTLINE_COLOR")).is_true()
	assert_bool(constants.has(&"FILL_COLOR")).is_true()
	if constants.has(&"OUTLINE_COLOR") and constants.has(&"FILL_COLOR"):
		var outline_color: Color = constants[&"OUTLINE_COLOR"]
		var fill_color: Color = constants[&"FILL_COLOR"]
		assert_float(outline_color.a).is_equal(1.0)
		assert_float(fill_color.a).is_equal(1.0)
		assert_bool(fill_color.r > 0.7 and fill_color.g < 0.3 and fill_color.b < 0.3).is_true()


func test_spawn_warning_is_exactly_point_eight_seconds_with_three_discrete_flashes() -> void:
	var effect: Node2D = auto_free(SPAWN_EFFECT_SCENE.instantiate()) as Node2D
	add_child(effect)
	await await_idle_frame()
	var animation_player := effect.get_node("AnimationPlayer") as AnimationPlayer
	var animation := animation_player.get_animation(&"spawn")

	assert_object(animation).is_not_null()
	if animation == null:
		return
	assert_float(animation.length).is_equal_approx(0.8, 0.0001)
	var track := animation.find_track(NodePath(".:visible"), Animation.TYPE_VALUE)
	assert_int(track).override_failure_message(
		"The solid X should flash through a discrete visible track, not translucent fades."
	).is_greater_equal(0)
	if track < 0:
		return
	assert_int(animation.track_get_key_count(track)).is_equal(6)
	assert_int(animation.value_track_get_update_mode(track)).is_equal(Animation.UPDATE_DISCRETE)
	var visible_flash_count := 0
	for key_index: int in range(animation.track_get_key_count(track)):
		assert_float(animation.track_get_key_time(track, key_index)).is_equal_approx(
			EXPECTED_FLASH_TIMES[key_index], 0.0001
		)
		var is_visible := bool(animation.track_get_key_value(track, key_index))
		assert_bool(is_visible).is_equal(EXPECTED_FLASH_VALUES[key_index])
		if is_visible:
			visible_flash_count += 1
	assert_int(visible_flash_count).is_equal(3)


func test_spawner_waits_for_warning_before_registering_enemy() -> void:
	Global.begin_run(4401, null, 0)
	var fixture := await _new_spawner_fixture()
	var host := fixture.host as Node2D
	var spawner := fixture.spawner as Spawner
	var definition := Content.catalog.get_enemy(&"enemy/chaser_slow")
	spawner.wave_timer.start(5.0)

	spawner.call("_spawn_enemy_definition", definition, Vector2(111.0, 222.0))
	await await_idle_frame()
	assert_int(spawner.get_active_enemy_count()).is_zero()
	assert_int(_spawn_effect_count(host)).is_equal(1)

	await get_tree().create_timer(0.35).timeout
	assert_int(spawner.get_active_enemy_count()).override_failure_message(
		"Enemy creation must remain behind the 0.8-second warning await."
	).is_zero()

	await get_tree().create_timer(0.55).timeout
	assert_int(spawner.get_active_enemy_count()).is_equal(1)
	assert_int(_spawn_effect_count(host)).is_zero()


func test_stopping_wave_during_warning_prevents_enemy_creation() -> void:
	Global.begin_run(4402, null, 0)
	var fixture := await _new_spawner_fixture()
	var host := fixture.host as Node2D
	var spawner := fixture.spawner as Spawner
	var definition := Content.catalog.get_enemy(&"enemy/chaser_slow")
	spawner.wave_timer.start(5.0)

	spawner.call("_spawn_enemy_definition", definition, Vector2(111.0, 222.0))
	await get_tree().create_timer(0.2).timeout
	spawner.wave_timer.stop()
	await get_tree().create_timer(0.7).timeout

	assert_int(spawner.get_active_enemy_count()).is_zero()
	assert_int(_spawn_effect_count(host)).is_zero()


func _new_spawner_fixture() -> Dictionary:
	var host := auto_free(Node2D.new()) as Node2D
	add_child(host)
	var spawner := Spawner.new()
	spawner.name = "Spawner"
	var spawn_timer := Timer.new()
	spawn_timer.name = "SpawnTimer"
	spawn_timer.one_shot = true
	spawner.add_child(spawn_timer)
	var wave_timer := Timer.new()
	wave_timer.name = "WaveTimer"
	wave_timer.one_shot = true
	spawner.add_child(wave_timer)
	host.add_child(spawner)
	await await_idle_frame()
	return {"host": host, "spawner": spawner}


func _spawn_effect_count(host: Node) -> int:
	var count := 0
	for child: Node in host.get_children():
		if child is EnemySpawnEffect:
			count += 1
	return count
