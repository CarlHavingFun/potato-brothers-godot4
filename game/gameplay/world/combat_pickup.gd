class_name GogoCombatPickup
extends Node2D


const DROPPED := 0
const MAGNETIZING := 1
const COLLECTED := 2
const MAGNET_ACCELERATION := 1200.0
const MAGNET_MAX_SPEED := 480.0
const ATLAS_FRAME_SIZE := Vector2(32.0, 64.0)
const SPAWN_POP_SECONDS := 0.090
const SPAWN_LIFT_PX := 5.0
const HOVER_PERIOD_SECONDS := 0.52
const HOVER_AMPLITUDE_PX := 1.0
const MAGNET_VISUAL_COLOR := Color("fff0a6")

var state := DROPPED
var combat_world: Node2D
var target: GogoPlayerActor
var runtime_instance_id := 0
var source_enemy_runtime_id := 0
var reward_kind: StringName = &""
var reward_amount := 0
var reward_token: StringName = &""
var reward_reservation_id := 0
var reward_entries: Array[Dictionary] = []
var visual_denomination := 1
var visual_region_index := 0
var velocity := Vector2.ZERO
var visual_handle: GogoStaticAssetHandle
var visual_sprite: Sprite2D
var fallback_visual_active := true
var visual_age := 0.0
var spawn_pop_remaining := 0.0


static func deterministic_pop_offset(enemy_runtime_id: int, pickup_runtime_id: int) -> Vector2i:
	return Vector2i(
		posmod(enemy_runtime_id * 17 + pickup_runtime_id * 31, 25) - 12,
		posmod(enemy_runtime_id * 29 + pickup_runtime_id * 13, 25) - 12
	)


static func deterministic_visual_region_index(
	enemy_runtime_id: int,
	pickup_runtime_id: int
) -> int:
	return posmod(enemy_runtime_id * 17 + pickup_runtime_id * 31, 3)


static func fallback_outline_for_denomination(denomination: int) -> PackedVector2Array:
	if clampi(denomination, 1, 2) >= 2:
		return PackedVector2Array([
			Vector2(0, -10), Vector2(9, -3), Vector2(6, 10),
			Vector2(-8, 6), Vector2(-9, -4),
		])
	return PackedVector2Array([
		Vector2(0, -8), Vector2(6, -2), Vector2(3, 8),
		Vector2(-5, 4), Vector2(-6, -3),
	])


func configure(
	next_world: Node2D,
	next_target: GogoPlayerActor,
	next_runtime_instance_id: int,
	next_source_enemy_runtime_id: int,
	next_reward_kind: StringName,
	next_reward_amount: int,
	next_reward_token: StringName,
	next_reward_reservation_id: int,
	next_visual_handle: GogoStaticAssetHandle,
	death_global_position: Vector2
) -> bool:
	return configure_bundle(
		next_world,
		next_target,
		next_runtime_instance_id,
		next_source_enemy_runtime_id,
		[{
			&"kind": next_reward_kind,
			&"amount": next_reward_amount,
			&"token": next_reward_token,
			&"reservation_id": next_reward_reservation_id,
		}],
		next_visual_handle,
		death_global_position
	)


func configure_bundle(
	next_world: Node2D,
	next_target: GogoPlayerActor,
	next_runtime_instance_id: int,
	next_source_enemy_runtime_id: int,
	next_reward_entries: Array,
	next_visual_handle: GogoStaticAssetHandle,
	death_global_position: Vector2
) -> bool:
	if (
		next_world == null
		or next_target == null
		or next_runtime_instance_id <= 0
		or next_source_enemy_runtime_id <= 0
		or next_reward_entries.is_empty()
	):
		return false
	var normalized_entries: Array[Dictionary] = []
	var seen_kinds: Dictionary = {}
	for kind in [GameSession.REWARD_EXPERIENCE, GameSession.REWARD_SUPPLY]:
		for entry_value in next_reward_entries:
			if not entry_value is Dictionary:
				return false
			var entry := entry_value as Dictionary
			if StringName(entry.get(&"kind", &"")) != kind:
				continue
			if (
				int(entry.get(&"amount", 0)) <= 0
				or StringName(entry.get(&"token", &"")).is_empty()
				or int(entry.get(&"reservation_id", 0)) <= 0
			):
				return false
			if seen_kinds.has(kind):
				return false
			seen_kinds[kind] = true
			normalized_entries.append({
				&"kind": kind,
				&"amount": int(entry.get(&"amount", 0)),
				&"token": StringName(entry.get(&"token", &"")),
				&"reservation_id": int(entry.get(&"reservation_id", 0)),
			})
	if normalized_entries.size() != next_reward_entries.size():
		return false
	combat_world = next_world
	target = next_target
	runtime_instance_id = next_runtime_instance_id
	source_enemy_runtime_id = next_source_enemy_runtime_id
	reward_entries = normalized_entries
	var legacy_entry := reward_entries[0]
	reward_kind = StringName(legacy_entry.get(&"kind", &""))
	reward_amount = int(legacy_entry.get(&"amount", 0))
	reward_token = StringName(legacy_entry.get(&"token", &""))
	reward_reservation_id = int(legacy_entry.get(&"reservation_id", 0))
	visual_denomination = 1
	for entry in reward_entries:
		if StringName(entry.get(&"kind", &"")) == GameSession.REWARD_SUPPLY:
			visual_denomination = clampi(int(entry.get(&"amount", 0)), 1, 2)
			break
	visual_region_index = deterministic_visual_region_index(
		source_enemy_runtime_id,
		runtime_instance_id
	)
	visual_handle = next_visual_handle
	state = DROPPED
	velocity = Vector2.ZERO
	visual_age = 0.0
	spawn_pop_remaining = SPAWN_POP_SECONDS
	_sync_visual()
	global_position = death_global_position + Vector2(
		deterministic_pop_offset(source_enemy_runtime_id, runtime_instance_id)
	)
	return true


func _physics_process(delta: float) -> void:
	if state == COLLECTED or target == null or not is_instance_valid(target):
		return
	_update_visual_feedback(delta)
	var pickup_range := 0.0
	if target.player_state != null:
		pickup_range = maxf(float(target.player_state.final_stats.get(&"pickup_range", 0.0)), 0.0)
	var to_target := target.global_position - global_position
	var contact_radius := target.pickup_interaction_radius()
	if to_target.length() <= contact_radius:
		collect_now()
		return
	if state == DROPPED:
		if to_target.length() > pickup_range:
			return
		state = MAGNETIZING
		_update_visual_feedback(0.0)
	var safe_delta := maxf(delta, 0.0)
	var desired_velocity := to_target.normalized() * MAGNET_MAX_SPEED
	velocity = velocity.move_toward(desired_velocity, MAGNET_ACCELERATION * safe_delta)
	global_position += velocity * safe_delta
	if global_position.distance_to(target.global_position) <= contact_radius:
		collect_now()


func _update_visual_feedback(delta: float) -> void:
	var safe_delta := maxf(delta, 0.0)
	visual_age += safe_delta
	spawn_pop_remaining = maxf(spawn_pop_remaining - safe_delta, 0.0)
	if visual_sprite == null or not is_instance_valid(visual_sprite):
		return
	var vertical_offset := 0.0
	if spawn_pop_remaining > 0.0:
		var pop_progress := 1.0 - spawn_pop_remaining / SPAWN_POP_SECONDS
		vertical_offset = -roundf(sin(pop_progress * PI) * SPAWN_LIFT_PX)
	else:
		vertical_offset = roundf(
			sin(visual_age * TAU / HOVER_PERIOD_SECONDS) * HOVER_AMPLITUDE_PX
		)
	visual_sprite.position = Vector2(-16.0, -32.0 + vertical_offset)
	visual_sprite.modulate = MAGNET_VISUAL_COLOR if state == MAGNETIZING else Color.WHITE


func collect_now() -> StringName:
	if state == COLLECTED:
		return GameSession.REWARD_DUPLICATE
	# Even immediate contact and wave-end collection pass through the state machine's
	# middle state; no valid path skips DROPPED -> MAGNETIZING -> COLLECTED.
	if state == DROPPED:
		state = MAGNETIZING
	# Commit the terminal pickup state before applying the reservation so synchronous
	# reward listeners cannot re-enter this pickup and grant the same reward twice.
	state = COLLECTED
	velocity = Vector2.ZERO
	set_physics_process(false)
	queue_redraw()
	if combat_world == null or not is_instance_valid(combat_world):
		return GameSession.REWARD_INVALID
	return StringName(combat_world.call(&"collect_pickup", self))


func _sync_visual() -> void:
	if visual_sprite != null and is_instance_valid(visual_sprite):
		visual_sprite.free()
	visual_sprite = null
	fallback_visual_active = visual_handle == null or visual_handle.texture == null
	if not fallback_visual_active:
		visual_sprite = Sprite2D.new()
		visual_sprite.name = "StaticVisual"
		visual_sprite.centered = false
		visual_sprite.texture = visual_handle.texture
		visual_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		visual_sprite.region_enabled = true
		visual_sprite.region_rect = Rect2(
			Vector2(float(visual_region_index) * ATLAS_FRAME_SIZE.x, 0.0),
			ATLAS_FRAME_SIZE
		)
		visual_sprite.position = Vector2(-16.0, -32.0)
		add_child(visual_sprite)
		GogoStaticConsumerRegistry.observe_handle(
			visual_handle,
			"res://game/gameplay/world/combat_pickup.gd",
			String(get_path_to(visual_sprite))
		)
	queue_redraw()


func _exit_tree() -> void:
	if combat_world != null and is_instance_valid(combat_world):
		combat_world.call(&"unregister_active_pickup", runtime_instance_id, self)


func _draw() -> void:
	if not fallback_visual_active or state == COLLECTED:
		return
	var points := fallback_outline_for_denomination(visual_denomination)
	draw_colored_polygon(points, Color("e0b35d"))
	draw_polyline(
		PackedVector2Array([points[0], points[1], points[2], points[3], points[4], points[0]]),
		Color("242a33"),
		2.0
	)
