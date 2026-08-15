class_name EffectAlly
extends Node2D


const BASE_ATTACK_INTERVAL := 0.75
const BASE_ATTACK_RANGE := 340.0

var entity_kind: StringName = &"building"
var content_id: StringName = &""
var follow_target: Node2D
var orbit_offset := Vector2.ZERO
var damage := 4.0
var attack_interval := BASE_ATTACK_INTERVAL
var attack_range := BASE_ATTACK_RANGE
var lifetime_remaining := -1.0
var _attack_remaining := 0.25


func setup(kind: StringName, id: StringName, target: Node2D, index: int) -> void:
	entity_kind = kind
	content_id = id
	follow_target = target
	orbit_offset = Vector2.RIGHT.rotated(index * 1.7) * (72.0 + index * 8.0)
	var engineering := (
		Global.current_run.player_stats.get_stat(StatId.ENGINEERING)
		if Global.current_run != null
		else 0.0
	)
	damage = 4.0 + engineering * 0.8
	attack_range = BASE_ATTACK_RANGE + engineering * 3.0
	attack_interval = maxf(0.22, BASE_ATTACK_INTERVAL / (1.0 + engineering / 100.0))
	lifetime_remaining = 30.0 + engineering * 0.5 if kind == &"summon" else -1.0
	queue_redraw()


func _process(delta: float) -> void:
	if not Global.is_combat_active():
		return
	if entity_kind == &"summon" and is_instance_valid(follow_target):
		global_position = global_position.lerp(follow_target.global_position + orbit_offset, minf(1.0, delta * 7.0))
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
		target.apply_effect_damage(damage, self)


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
	var color := Color("7dd3fc") if entity_kind == &"summon" else Color("f6c453")
	draw_circle(Vector2.ZERO, 18.0, color)
	draw_circle(Vector2.ZERO, 9.0, Color("182331"))
