class_name GogoCombatPickup
extends Node2D


const DROPPED := 0
const MAGNETIZING := 1
const COLLECTED := 2
const MAGNET_ACCELERATION := 1200.0
const MAGNET_MAX_SPEED := 480.0
const CONTACT_RADIUS := 18.0

var state := DROPPED
var combat_world: Node2D
var target: GogoPlayerActor
var runtime_instance_id := 0
var source_enemy_runtime_id := 0
var reward_kind: StringName = &""
var reward_amount := 0
var reward_token: StringName = &""
var reward_reservation_id := 0
var velocity := Vector2.ZERO
var visual_handle: GogoStaticAssetHandle
var visual_sprite: Sprite2D
var fallback_visual_active := true


static func deterministic_pop_offset(enemy_runtime_id: int, pickup_runtime_id: int) -> Vector2i:
	return Vector2i(
		posmod(enemy_runtime_id * 17 + pickup_runtime_id * 31, 25) - 12,
		posmod(enemy_runtime_id * 29 + pickup_runtime_id * 13, 25) - 12
	)


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
	if (
		next_world == null
		or next_target == null
		or next_runtime_instance_id <= 0
		or next_source_enemy_runtime_id <= 0
		or not [GameSession.REWARD_EXPERIENCE, GameSession.REWARD_SUPPLY].has(next_reward_kind)
		or next_reward_amount <= 0
		or next_reward_token.is_empty()
		or next_reward_reservation_id <= 0
	):
		return false
	combat_world = next_world
	target = next_target
	runtime_instance_id = next_runtime_instance_id
	source_enemy_runtime_id = next_source_enemy_runtime_id
	reward_kind = next_reward_kind
	reward_amount = next_reward_amount
	reward_token = next_reward_token
	reward_reservation_id = next_reward_reservation_id
	visual_handle = next_visual_handle
	state = DROPPED
	velocity = Vector2.ZERO
	_sync_visual()
	global_position = death_global_position + Vector2(
		deterministic_pop_offset(source_enemy_runtime_id, runtime_instance_id)
	)
	return true


func _physics_process(delta: float) -> void:
	if state == COLLECTED or target == null or not is_instance_valid(target):
		return
	var pickup_range := 0.0
	if target.player_state != null:
		pickup_range = maxf(float(target.player_state.final_stats.get(&"pickup_range", 0.0)), 0.0)
	var to_target := target.global_position - global_position
	if to_target.length() <= CONTACT_RADIUS:
		collect_now()
		return
	if state == DROPPED:
		if to_target.length() > pickup_range:
			return
		state = MAGNETIZING
	var safe_delta := maxf(delta, 0.0)
	var desired_velocity := to_target.normalized() * MAGNET_MAX_SPEED
	velocity = velocity.move_toward(desired_velocity, MAGNET_ACCELERATION * safe_delta)
	global_position += velocity * safe_delta
	if global_position.distance_to(target.global_position) <= CONTACT_RADIUS:
		collect_now()


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
	fallback_visual_active = visual_handle == null or visual_handle.texture == null
	if not fallback_visual_active:
		visual_sprite = Sprite2D.new()
		visual_sprite.name = "StaticVisual"
		visual_sprite.centered = false
		visual_sprite.texture = visual_handle.texture
		visual_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		visual_sprite.position = -Vector2(visual_handle.pivot_px)
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
	var fill := Color("89d4f5") if reward_kind == GameSession.REWARD_EXPERIENCE else Color("e0b35d")
	var points := PackedVector2Array([
		Vector2(0, -8), Vector2(8, 0), Vector2(0, 8), Vector2(-8, 0),
	])
	draw_colored_polygon(points, fill)
	draw_polyline(PackedVector2Array([points[0], points[1], points[2], points[3], points[0]]), Color("242a33"), 2.0)
