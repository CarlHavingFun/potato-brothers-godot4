extends Area2D
class_name HitboxComponent

signal on_hit_hurtbox(hurtbox: HurtboxComponent)
signal hit_confirmed(result: HitResult)

@export_range(0.0, 10.0, 0.05, "or_greater") var repeat_interval := 0.0

var damage := 1.0
var display_damage := 1.0
var critical := false
var knockback_power := 0.0
var source: Node2D
var gameplay_source: Object
var gameplay_tags: Array[StringName] = []
var hit_modifiers: Dictionary = {}

func enable() -> void:
	set_deferred("monitoring", true)
	set_deferred("monitorable", true)

func disable() -> void:
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)

func setup(
	damage: float,
	critical: bool,
	knockback: float,
	source: Node2D,
	effect_source: Object = null,
	effect_tags: Array[StringName] = [],
	modifiers: Dictionary = {}
) -> void:
	self.damage = damage
	display_damage = damage
	self.critical = critical
	knockback_power = knockback
	self.source = source
	gameplay_source = effect_source if effect_source != null else source
	gameplay_tags = effect_tags.duplicate()
	hit_modifiers = modifiers.duplicate(true)


func confirm_hit(result: HitResult) -> void:
	if result == null or not result.landed:
		return
	_apply_status_modifier(result)
	_apply_explosion_modifier(result)
	hit_confirmed.emit(result)
	if is_instance_valid(gameplay_source) and gameplay_source.has_method("on_hit_confirmed"):
		gameplay_source.call("on_hit_confirmed", result)


func _apply_status_modifier(result: HitResult) -> void:
	var status_id := StringName(str(hit_modifiers.get("status_id", "")))
	if status_id.is_empty() or not is_instance_valid(result.target):
		return
	if not result.target.has_method("apply_effect_status"):
		return
	result.target.call("apply_effect_status", {
		"status_id": status_id,
		"duration": maxf(0.0, float(hit_modifiers.get("status_duration", 2.5))),
		"stacks": maxi(1, int(hit_modifiers.get("status_stacks", 1))),
		"amount": result.damage * maxf(
			0.0, float(hit_modifiers.get("status_damage_scale", 0.1))
		),
	}, gameplay_source)


func _apply_explosion_modifier(result: HitResult) -> void:
	var radius := maxf(0.0, float(hit_modifiers.get("explosion_radius", 0.0)))
	if radius <= 0.0 or not is_instance_valid(result.target) or result.target is not Node2D:
		return
	var tree := get_tree()
	if tree == null:
		return
	var center := result.target as Node2D
	var candidates: Array[Node2D] = []
	for candidate: Node in tree.get_nodes_in_group(GameplayEffectExecutor.ENEMY_GROUP):
		if candidate == result.target or candidate is not Node2D:
			continue
		if not candidate.has_method("apply_effect_damage"):
			continue
		var target := candidate as Node2D
		if center.global_position.distance_squared_to(target.global_position) <= radius * radius:
			candidates.append(target)
	candidates.sort_custom(func(first: Node2D, second: Node2D) -> bool:
		var first_distance := center.global_position.distance_squared_to(first.global_position)
		var second_distance := center.global_position.distance_squared_to(second.global_position)
		if not is_equal_approx(first_distance, second_distance):
			return first_distance < second_distance
		return first.get_instance_id() < second.get_instance_id()
	)
	var explosion_damage := result.damage * maxf(
		0.0, float(hit_modifiers.get("explosion_damage_scale", 0.5))
	)
	for target: Node2D in candidates:
		target.call("apply_effect_damage", explosion_damage, gameplay_source)


func _on_area_entered(area: Area2D) -> void:
	if area is HurtboxComponent:
		on_hit_hurtbox.emit(area)
