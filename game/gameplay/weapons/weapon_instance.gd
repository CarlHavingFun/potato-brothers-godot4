class_name GogoWeaponInstance
extends Node2D

var stats: GogoWeaponRuntimeStats
var owner_actor: GogoPlayerActor
var cooldown_remaining := 0.0
var attack_flash := 0.0


func configure(next_stats: GogoWeaponRuntimeStats, next_owner: GogoPlayerActor) -> void:
	stats = next_stats
	owner_actor = next_owner
	queue_redraw()


func _physics_process(delta: float) -> void:
	if stats == null or owner_actor == null:
		return
	cooldown_remaining -= delta
	attack_flash = maxf(attack_flash - delta * 6.0, 0.0)
	if cooldown_remaining > 0.0:
		queue_redraw()
		return
	var target := _nearest_enemy()
	if target == null:
		return
	var to_target: Vector2 = target.global_position - global_position
	rotation = to_target.angle()
	if stats.mode == GogoWeaponDefinition.Mode.MELEE:
		if to_target.length() > stats.attack_range:
			return
		target.take_damage(stats.damage, to_target.normalized() * stats.knockback)
		attack_flash = 1.0
	else:
		_fire_projectiles(to_target.normalized())
		attack_flash = 1.0
	cooldown_remaining = stats.cooldown_seconds
	queue_redraw()


func _nearest_enemy() -> Node2D:
	var best: Node2D
	var best_distance := INF
	for candidate in get_tree().get_nodes_in_group(&"gogo_enemy"):
		if not is_instance_valid(candidate):
			continue
		var distance := global_position.distance_squared_to(candidate.global_position)
		if distance < best_distance and (stats.mode == GogoWeaponDefinition.Mode.RANGED or distance <= stats.attack_range * stats.attack_range):
			best = candidate
			best_distance = distance
	return best


func _fire_projectiles(base_direction: Vector2) -> void:
	var world := owner_actor.combat_world
	if world == null:
		return
	for index in stats.projectile_count:
		var projectile := GogoProjectile.new()
		var offset := float(index) - float(stats.projectile_count - 1) * 0.5
		projectile.direction = base_direction.rotated(deg_to_rad(offset * stats.spread_degrees))
		projectile.speed = stats.projectile_speed
		projectile.damage = stats.damage
		projectile.knockback = stats.knockback
		projectile.global_position = global_position
		world.projectile_layer.add_child(projectile)


func _draw() -> void:
	var color := Color("f27d42") if stats != null and stats.mode == GogoWeaponDefinition.Mode.MELEE else Color("70b8ff")
	if attack_flash > 0.0:
		color = Color.WHITE
	draw_line(Vector2.ZERO, Vector2(28.0, 0.0), color, 7.0, true)
	draw_circle(Vector2(28.0, 0.0), 5.0, color)
