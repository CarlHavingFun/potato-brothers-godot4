extends Node2D
class_name ArenaEcology

enum PickupKind { NONE, MATERIAL, HEAL, CHEST, LEGENDARY_CHEST }

const TREE_SCENE := preload("res://scenes/arena/ecology/ecology_tree.tscn")
const PICKUP_SCENE := preload("res://scenes/arena/ecology/ecology_pickup.tscn")

@export var spawn_safe_radius := 280.0
@export var spawn_safe_seconds := 2.0
@export var danger_warning_seconds := 1.2
@export var danger_active_seconds := 2.8
@export var danger_interval_seconds := 12.0

var tree_positions: Array[Vector2] = []
var pickup_kinds: Array[int] = []
var danger_enabled := false
var danger_center := Vector2.ZERO
var danger_radius := 150.0
var effective_danger_interval := 12.0
var _player: Player
var _rng := RandomNumberGenerator.new()
var _wave := 1
var _elapsed := 0.0
var _safe_time_left := 0.0
var _danger_cycle := -1
var _danger_damage_applied := false


func setup_wave(wave: int, run_seed: int, player: Player) -> void:
	_clear_runtime()
	_wave = maxi(1, wave)
	_player = player
	_elapsed = 0.0
	_safe_time_left = spawn_safe_seconds
	_danger_cycle = -1
	_danger_damage_applied = false
	danger_enabled = _wave >= 6
	danger_radius = 150.0
	effective_danger_interval = danger_interval_seconds
	if Global.current_run != null:
		var difficulty := Content.catalog.get_difficulty(Global.current_run.difficulty)
		if difficulty != null and difficulty.mutator != null and difficulty.mutator.hazards_enabled:
			effective_danger_interval *= difficulty.mutator.hazard_interval_multiplier
			danger_radius *= difficulty.mutator.hazard_radius_multiplier
	_rng.seed = run_seed ^ (_wave * 0x45D9F3B)
	var tree_count: int = maxi(3, 8 - _wave / 4)
	for tree_index in tree_count:
		var position: Vector2 = _roll_world_position(360.0)
		var tree_drop: int = _roll_tree_drop()
		tree_positions.append(position)
		if is_inside_tree():
			_spawn_tree(position, tree_drop, tree_index)
	var heal_position: Vector2 = _roll_world_position(220.0)
	pickup_kinds.append(PickupKind.HEAL)
	if is_inside_tree():
		_spawn_pickup(heal_position, PickupKind.HEAL)
	danger_center = _roll_world_position(260.0) if danger_enabled else Vector2.ZERO
	queue_redraw()


func is_spawn_position_safe(world_position: Vector2) -> bool:
	return _safe_time_left <= 0.0 or world_position.distance_to(Vector2.ZERO) >= spawn_safe_radius


func _process(delta: float) -> void:
	if not Global.is_combat_active():
		return
	_elapsed += delta
	_safe_time_left = maxf(0.0, _safe_time_left - delta)
	if not danger_enabled:
		queue_redraw()
		return
	var cycle := floori(_elapsed / effective_danger_interval)
	if cycle != _danger_cycle:
		_danger_cycle = cycle
		_danger_damage_applied = false
		danger_center = _roll_world_position(180.0)
	var cycle_time := fmod(_elapsed, effective_danger_interval)
	var danger_active := (
		cycle_time >= danger_warning_seconds
		and cycle_time < danger_warning_seconds + danger_active_seconds
	)
	if (
		danger_active
		and not _danger_damage_applied
		and is_instance_valid(_player)
		and _player.global_position.distance_to(danger_center) <= danger_radius
	):
		_danger_damage_applied = true
		_player.receive_typed_damage(
			3.0 + _wave * 0.35,
			self,
			[&"arena", &"hazard", &"danger_zone"] as Array[StringName]
		)
	queue_redraw()


func _draw() -> void:
	if _safe_time_left > 0.0:
		draw_circle(Vector2.ZERO, spawn_safe_radius, Color(0.23, 0.74, 0.62, 0.10))
		draw_arc(Vector2.ZERO, spawn_safe_radius, 0.0, TAU, 64, Color(0.43, 0.96, 0.78, 0.7), 5.0)
	if not danger_enabled:
		return
	var cycle_time := fmod(_elapsed, effective_danger_interval)
	if cycle_time >= danger_warning_seconds + danger_active_seconds:
		return
	var active := cycle_time >= danger_warning_seconds
	var fill := Color(0.88, 0.12, 0.09, 0.24 if active else 0.10)
	var edge := Color(1.0, 0.22, 0.12, 0.95 if active else 0.55)
	draw_circle(danger_center, danger_radius, fill)
	draw_arc(danger_center, danger_radius, 0.0, TAU, 64, edge, 7.0 if active else 4.0)


func _spawn_tree(world_position: Vector2, kind: int, stable_index: int = 0) -> void:
	var tree := TREE_SCENE.instantiate() as EcologyTree
	tree.position = world_position
	tree.pickup_kind = kind
	tree.configure_presentation(_prop_presentation_id(stable_index))
	tree.set_meta(&"ecology_runtime", true)
	tree.harvested.connect(_on_tree_harvested)
	add_child(tree)


func _prop_presentation_id(stable_index: int) -> StringName:
	# This stable alternation is presentation-only. It deliberately consumes no
	# RNG, so prop art cannot move spawns or change drops/combat state.
	return &"prop.weapon_rack" if posmod(stable_index, 2) == 1 else &"prop.supply_crate"


func _spawn_pickup(world_position: Vector2, kind: int) -> void:
	var pickup := PICKUP_SCENE.instantiate() as EcologyPickup
	pickup.position = world_position
	var amount: float = (
		3.0 + _wave * 0.35 if kind == PickupKind.MATERIAL else 7.0 + _wave * 0.25
	)
	pickup.configure(kind, amount)
	pickup.set_meta(&"ecology_runtime", true)
	add_child(pickup)


func _on_tree_harvested(world_position: Vector2, kind: int) -> void:
	pickup_kinds.append(kind)
	call_deferred("_spawn_pickup", to_local(world_position), kind)


func _roll_tree_drop() -> int:
	var luck: float = (
		Global.current_run.player_stats.get_stat(StatId.LUCK)
		if Global.current_run != null
		else 0.0
	)
	if Global.reward_service != null:
		return Global.reward_service.roll_drop(
			[&"source/tree"], luck, _wave, _rng.randf()
		)
	var fallback_table := DropTableDef.new()
	return fallback_table.roll(
		fallback_table.weights_for([&"source/tree"], luck, _wave), _rng.randf()
	)


func spawn_world_drop(world_position: Vector2, kind: int) -> bool:
	if kind <= PickupKind.NONE or kind > PickupKind.LEGENDARY_CHEST:
		return false
	pickup_kinds.append(kind)
	if is_inside_tree():
		call_deferred("_spawn_pickup", to_local(world_position), kind)
	return true


func _roll_world_position(minimum_center_distance: float) -> Vector2:
	for attempt in 24:
		var candidate := Vector2(_rng.randf_range(-870.0, 870.0), _rng.randf_range(-400.0, 400.0))
		if candidate.length() >= minimum_center_distance:
			return candidate
	return Vector2(700.0, 300.0)


func _clear_runtime() -> void:
	for child: Node in get_children():
		if child.has_meta(&"ecology_runtime"):
			remove_child(child)
			child.queue_free()
	tree_positions.clear()
	pickup_kinds.clear()
