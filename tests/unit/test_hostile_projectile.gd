extends GdUnitTestSuite


class RecordingPlayer:
	extends GogoPlayerActor

	var damage_call_count := 0
	var recorded_damage := 0.0


	func take_damage(amount: float) -> void:
		damage_call_count += 1
		recorded_damage += amount


func test_hostile_pulse_visual_is_16px_outlined_orange_with_pale_core() -> void:
	var projectile_script := load("res://game/gameplay/world/hostile_projectile.gd") as GDScript
	for constant_name: StringName in [
		&"VISUAL_OUTLINE_RADIUS",
		&"VISUAL_BODY_RADIUS",
		&"VISUAL_CORE_RADIUS",
		&"VISUAL_OUTLINE_COLOR",
		&"VISUAL_BODY_COLOR",
		&"VISUAL_CORE_COLOR",
	]:
		if projectile_script.get(constant_name) == null:
			assert_bool(false).is_true()
			return
	var outline_radius := float(projectile_script.get(&"VISUAL_OUTLINE_RADIUS"))
	var body_radius := float(projectile_script.get(&"VISUAL_BODY_RADIUS"))
	var core_radius := float(projectile_script.get(&"VISUAL_CORE_RADIUS"))
	var outline_color: Color = projectile_script.get(&"VISUAL_OUTLINE_COLOR")
	var body_color: Color = projectile_script.get(&"VISUAL_BODY_COLOR")
	var core_color: Color = projectile_script.get(&"VISUAL_CORE_COLOR")

	assert_float(outline_radius * 2.0).is_between(14.0, 16.0)
	assert_float(body_radius).is_less(outline_radius)
	assert_float(body_radius).is_greater_equal(5.5)
	assert_float(core_radius).is_greater(0.0)
	assert_float(core_radius).is_less(body_radius * 0.5)
	assert_float(outline_color.get_luminance()).is_less(0.2)
	assert_float(body_color.r - body_color.g).is_greater(0.2)
	assert_float(core_color.get_luminance()).is_greater(0.8)
	assert_bool(body_color.is_equal_approx(Color("e0b35d"))).is_false()
	assert_float(GogoHostileProjectile.PROJECTILE_RADIUS).is_equal(4.0)
	assert_float(GogoHostileProjectile.PLAYER_HURT_RADIUS).is_equal(18.0)
	assert_float(GogoHostileProjectile.DEFAULT_SPEED).is_equal(210.0)
	assert_float(GogoHostileProjectile.DEFAULT_LIFETIME).is_equal(2.0)


func test_hostile_pulse_uses_simple_shape_with_available_atlas_and_commits_one_swept_hit() -> void:
	GogoStaticConsumerRegistry.reset_current()
	var snapshot := _hostile_pulse_snapshot()
	var handle := snapshot.resolve_asset(
		&"projectile_hit_kit",
		&"projectile_sprite",
		&"hostile_pulse"
	)
	var player := _recording_player(Vector2(100.0, 0.0))
	var projectile := _activated_projectile(
		player,
		snapshot,
		Vector2(0.4, 0.6),
		Vector2.RIGHT,
		6.0
	)
	projectile.speed = 1000.0

	assert_int(player.damage_call_count).is_zero()
	assert_object(handle).is_not_null()
	assert_object(projectile.projectile_visual_handle).is_null()
	assert_object(projectile.projectile_sprite).is_null()
	assert_vector(projectile.global_position).is_equal(Vector2(0.0, 1.0))
	assert_bool(GogoStaticConsumerRegistry.current().records().any(
		func(record: Dictionary) -> bool:
			return (
				StringName(record.get("asset_id", &"")) == &"projectile_hit_kit"
				and StringName(record.get("role", &"")) == &"projectile_sprite"
				and StringName(record.get("selector", &"")) == &"hostile_pulse"
				and String(record.get("scene", ""))
					== "res://game/gameplay/world/hostile_projectile.gd"
			)
	)).is_false()

	projectile._physics_process(0.2)

	assert_int(player.damage_call_count).is_equal(1)
	assert_float(player.recorded_damage).is_equal(6.0)
	assert_bool(projectile.contact_committed).is_true()
	assert_bool(projectile.active).is_false()
	assert_bool(projectile.is_queued_for_deletion()).is_true()
	assert_float(projectile.global_position.x).is_equal(roundf(projectile.global_position.x))
	assert_float(projectile.global_position.y).is_equal(roundf(projectile.global_position.y))

	projectile._physics_process(0.2)
	assert_int(player.damage_call_count).is_equal(1)
	assert_float(player.recorded_damage).is_equal(6.0)


func test_hostile_pulse_retires_on_timeout_and_out_of_bounds() -> void:
	var snapshot := _hostile_pulse_snapshot()
	var player := _recording_player(Vector2(1000.0, 0.0))
	var timed_out := _activated_projectile(
		player,
		snapshot,
		Vector2.ZERO,
		Vector2.RIGHT,
		2.0
	)
	timed_out.speed = 10.0
	timed_out.lifetime = 0.05

	timed_out._physics_process(0.1)

	assert_bool(timed_out.active).is_false()
	assert_bool(timed_out.contact_committed).is_false()
	assert_bool(timed_out.is_queued_for_deletion()).is_true()
	assert_int(player.damage_call_count).is_zero()

	var outside := _activated_projectile(
		player,
		snapshot,
		Vector2.ZERO,
		Vector2.RIGHT,
		2.0
	)
	outside.arena_rect = Rect2(Vector2(-10.0, -10.0), Vector2(20.0, 20.0))
	outside.speed = 100.0

	outside._physics_process(0.5)

	assert_bool(outside.active).is_false()
	assert_bool(outside.contact_committed).is_false()
	assert_bool(outside.is_queued_for_deletion()).is_true()
	assert_int(player.damage_call_count).is_zero()


func test_hostile_pulse_retires_when_target_becomes_invalid() -> void:
	var snapshot := _hostile_pulse_snapshot()
	var player := RecordingPlayer.new()
	add_child(player)
	player.global_position = Vector2(100.0, 0.0)
	var projectile := _activated_projectile(
		player,
		snapshot,
		Vector2.ZERO,
		Vector2.RIGHT,
		2.0
	)

	player.free()
	projectile._physics_process(0.1)

	assert_bool(projectile.active).is_false()
	assert_bool(projectile.contact_committed).is_false()
	assert_bool(projectile.is_queued_for_deletion()).is_true()


func test_missing_static_snapshot_keeps_same_simple_shape_and_damage_entity() -> void:
	var player := _recording_player(Vector2(100.0, 0.0))
	var projectile := auto_free(GogoHostileProjectile.new()) as GogoHostileProjectile
	add_child(projectile)

	assert_bool(projectile.activate(
		null,
		player,
		72,
		Vector2.ZERO,
		Vector2.RIGHT,
		6.0
	)).is_true()
	assert_bool(projectile.fallback_visual_active).is_false()
	assert_object(projectile.projectile_visual_handle).is_null()
	assert_object(projectile.projectile_sprite).is_null()
	projectile.speed = 1000.0

	projectile._physics_process(0.2)

	assert_int(player.damage_call_count).is_equal(1)
	assert_float(player.recorded_damage).is_equal(6.0)
	assert_bool(projectile.contact_committed).is_true()
	assert_bool(projectile.active).is_false()
	assert_bool(projectile.is_queued_for_deletion()).is_true()


func test_world_spawns_hostile_simple_shape_when_session_snapshot_is_missing() -> void:
	var world := auto_free(CombatWorld.new()) as CombatWorld
	add_child(world)
	world.session = GameSession.new()
	var player := _recording_player(Vector2(100.0, 0.0))
	var source := auto_free(GogoEnemyActor.new()) as GogoEnemyActor
	add_child(source)
	source.runtime_instance_id = 73
	source.global_position = Vector2.ZERO

	var projectile := world.spawn_hostile_pulse(
		source,
		player,
		Vector2.RIGHT,
		6.0
	)

	assert_object(projectile).is_not_null()
	if projectile == null:
		return
	assert_bool(projectile.fallback_visual_active).is_false()
	assert_object(projectile.get_parent()).is_same(world.projectile_layer)
	projectile.speed = 1000.0
	projectile._physics_process(0.2)
	assert_int(player.damage_call_count).is_equal(1)


func _recording_player(global_position: Vector2) -> RecordingPlayer:
	var player := auto_free(RecordingPlayer.new()) as RecordingPlayer
	add_child(player)
	player.global_position = global_position
	return player


func _activated_projectile(
	player: RecordingPlayer,
	snapshot: GogoStaticAssetSnapshot,
	origin: Vector2,
	direction: Vector2,
	damage: float
) -> GogoHostileProjectile:
	var projectile := auto_free(GogoHostileProjectile.new()) as GogoHostileProjectile
	projectile.static_asset_snapshot_override = snapshot
	add_child(projectile)
	assert_bool(projectile.activate(null, player, 71, origin, direction, damage)).is_true()
	return projectile


func _hostile_pulse_snapshot() -> GogoStaticAssetSnapshot:
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	image.fill_rect(Rect2i(12, 26, 40, 12), Color8(238, 70, 42, 255))
	var handle := GogoStaticAssetHandle.new()
	handle._configure({
		"binding_key": &"projectile_hit_kit|projectile_sprite|hostile_pulse",
		"asset_id": &"projectile_hit_kit",
		"role": &"projectile_sprite",
		"selector": &"hostile_pulse",
		"display_size_px": Vector2i(64, 64),
		"display_scale": Vector2.ONE,
		"pivot_px": Vector2i(32, 32),
		"anchors_px": {},
		"atlas_rect_px": Rect2i(192, 0, 64, 64),
	}, ImageTexture.create_from_image(image))
	var snapshot := GogoStaticAssetSnapshot.new()
	snapshot._configure(
		1,
		"hostile-pulse-fixture",
		70,
		{&"projectile_hit_kit": &"ready"},
		{"projectile_hit_kit|projectile_sprite|hostile_pulse": handle},
		{},
		{},
		{},
		[]
	)
	return snapshot
