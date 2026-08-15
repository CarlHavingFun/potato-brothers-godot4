extends Node2D
class_name Projectile

@export var hitbox: HitboxComponent

var velocity: Vector2
var pierce_remaining := 0
var bounce_remaining := 0
var _hit_targets: Dictionary = {}
var presentation_id: StringName

func _process(delta: float) -> void:
	position += velocity * delta


func set_projectile(
	velocity: Vector2,
	damage: float,
	critical: bool,
	knockback: float,
	unit: Node2D,
	effect_source: Object = null,
	effect_tags: Array[StringName] = [],
	pierce: int = 0,
	bounce: int = 0,
	projectile_presentation_id: StringName = &"projectile.enemy"
) -> void:
	self.velocity = velocity
	rotation = velocity.angle()
	pierce_remaining = maxi(0, pierce)
	bounce_remaining = maxi(0, bounce)
	presentation_id = projectile_presentation_id
	var projectile_sprite := get_node_or_null("Sprite2D") as Sprite2D
	if projectile_sprite != null:
		projectile_sprite.texture = Presentation.resolve_texture(
			&"projectile", presentation_id
		)
	if hitbox:
		hitbox.setup(damage, critical, knockback, unit, effect_source, effect_tags)
	

func _on_visible_on_screen_notifier_2d_screen_exited() -> void:
	queue_free()


func _on_hitbox_component_on_hit_hurtbox(hurtbox: HurtboxComponent) -> void:
	var target := _resolve_enemy(hurtbox)
	if target != null:
		_hit_targets[target.get_instance_id()] = true
	if bounce_remaining > 0 and _bounce_to_next_target():
		bounce_remaining -= 1
		return
	if pierce_remaining > 0:
		pierce_remaining -= 1
		return
	queue_free()


func _resolve_enemy(node: Node) -> Enemy:
	var current := node
	while current != null:
		if current is Enemy:
			return current as Enemy
		current = current.get_parent()
	return null


func _bounce_to_next_target() -> bool:
	var nearest: Enemy
	var nearest_distance := 420.0 * 420.0
	for candidate: Node in get_tree().get_nodes_in_group(GameplayEffectExecutor.ENEMY_GROUP):
		if candidate is not Enemy or _hit_targets.has(candidate.get_instance_id()):
			continue
		var enemy := candidate as Enemy
		var distance := global_position.distance_squared_to(enemy.global_position)
		if distance < nearest_distance:
			nearest = enemy
			nearest_distance = distance
	if nearest == null:
		return false
	velocity = global_position.direction_to(nearest.global_position) * velocity.length()
	rotation = velocity.angle()
	return true
