class_name EffectAlly
extends Node2D


signal projectile_requested(
	origin: Vector2,
	target: Node2D,
	damage_amount: float,
	source: Node2D,
	metadata: Dictionary
)

const BASE_ATTACK_INTERVAL := 0.75
const BASE_ATTACK_RANGE := 340.0
const TURRET_ATTACK_INTERVAL := 0.82
const TURRET_ATTACK_RANGE := 440.0
const DRONE_ATTACK_INTERVAL := 0.48
const DRONE_ATTACK_RANGE := 285.0

var entity_kind: StringName = &"building"
var content_id: StringName = &""
var follow_target: Node2D
var orbit_offset := Vector2.ZERO
var damage := 4.0
var attack_interval := BASE_ATTACK_INTERVAL
var attack_range := BASE_ATTACK_RANGE
var lifetime_remaining := -1.0
var _attack_remaining := 0.25
var _orbit_phase := 0.0
var _projectile_callback: Callable
var _skin_visual: Sprite2D


func setup(kind: StringName, id: StringName, target: Node2D, index: int) -> void:
	entity_kind = kind
	content_id = id
	follow_target = target
	orbit_offset = Vector2.RIGHT.rotated(index * 1.7) * (72.0 + index * 8.0)
	var engineering: float = (
		Global.current_run.player_stats.get_stat(StatId.ENGINEERING)
		if Global.current_run != null
		else 0.0
	)
	if kind == &"summon":
		damage = 3.0 + engineering * 0.55
		attack_range = DRONE_ATTACK_RANGE + engineering * 2.0
		attack_interval = maxf(0.18, DRONE_ATTACK_INTERVAL / (1.0 + engineering / 100.0))
		lifetime_remaining = 26.0 + engineering * 0.45
	else:
		damage = 5.0 + engineering * 0.9
		attack_range = TURRET_ATTACK_RANGE + engineering * 3.0
		attack_interval = maxf(0.28, TURRET_ATTACK_INTERVAL / (1.0 + engineering / 100.0))
		lifetime_remaining = -1.0
	_apply_skin_visual()
	queue_redraw()


func _apply_skin_visual() -> void:
	if Presentation.active_skin == null:
		return
	var presentation_id := &"ally.drone" if entity_kind == &"summon" else &"ally.turret"
	var table: Variant = Presentation.active_skin.asset_tables.get(&"ally/world", {})
	if table is not Dictionary or not (table as Dictionary).has(presentation_id):
		return
	var texture := Presentation.resolve_texture(&"ally", presentation_id, null, &"world")
	if texture == null:
		return
	if not is_instance_valid(_skin_visual):
		_skin_visual = Sprite2D.new()
		_skin_visual.name = "SkinVisual"
		_skin_visual.scale = Vector2.ONE * 0.30
		_skin_visual.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(_skin_visual)
	_skin_visual.texture = texture


func set_projectile_callback(callback: Callable) -> void:
	_projectile_callback = callback


func _process(delta: float) -> void:
	if not Global.is_combat_active():
		return
	if entity_kind == &"summon" and is_instance_valid(follow_target):
		_orbit_phase = fmod(_orbit_phase + delta * 1.4, TAU)
		var moving_offset: Vector2 = orbit_offset.rotated(_orbit_phase)
		global_position = global_position.lerp(
			follow_target.global_position + moving_offset, minf(1.0, delta * 7.0)
		)
	if lifetime_remaining >= 0.0:
		lifetime_remaining -= delta
		if lifetime_remaining <= 0.0:
			queue_free()
			return
	_attack_remaining -= delta
	if _attack_remaining > 0.0:
		return
	_attack_remaining = attack_interval
	var target := _nearest_enemy()
	if target != null:
		request_attack(target)


func request_attack(target: Node2D) -> bool:
	if not is_instance_valid(target):
		return false
	var metadata: Dictionary = {
		"entity_kind": entity_kind,
		"content_id": content_id,
		"projectile_speed": 720.0 if entity_kind == &"building" else 540.0,
		"homing": entity_kind == &"summon",
	}
	if _projectile_callback.is_valid():
		_projectile_callback.call(global_position, target, damage, self, metadata)
		return true
	if not projectile_requested.get_connections().is_empty():
		projectile_requested.emit(global_position, target, damage, self, metadata)
		return true
	# Backward-compatible fallback for arenas that have not attached a projectile
	# factory yet. The callback/signal is the stable integration point.
	if target.has_method("apply_effect_damage"):
		target.call("apply_effect_damage", damage, self)
		return true
	return false


func _nearest_enemy() -> Enemy:
	var nearest: Enemy
	var nearest_distance := attack_range * attack_range
	for candidate: Node in get_tree().get_nodes_in_group(GameplayEffectExecutor.ENEMY_GROUP):
		if candidate is not Enemy:
			continue
		var enemy := candidate as Enemy
		var distance := global_position.distance_squared_to(enemy.global_position)
		if distance <= nearest_distance:
			nearest = enemy
			nearest_distance = distance
	return nearest


func _draw() -> void:
	if is_instance_valid(_skin_visual) and _skin_visual.texture != null:
		return
	var color := Color("7dd3fc") if entity_kind == &"summon" else Color("f6c453")
	if entity_kind == &"summon":
		draw_circle(Vector2.ZERO, 16.0, color)
		draw_line(Vector2(-24, 0), Vector2(24, 0), Color("d7f3ff"), 5.0)
	else:
		draw_rect(Rect2(-18.0, -14.0, 36.0, 28.0), color)
		draw_line(Vector2.ZERO, Vector2(28.0, 0.0), Color("fff1b8"), 8.0)
	draw_circle(Vector2.ZERO, 8.0, Color("182331"))
