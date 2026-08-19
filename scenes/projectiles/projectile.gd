extends Node2D
class_name Projectile


const PIXEL_ART_PROJECTILE_SCALE := 0.125

@export var hitbox: HitboxComponent

var velocity: Vector2
var pierce_remaining := 0
var bounce_remaining := 0
var _hit_targets: Dictionary = {}
var presentation_id: StringName
var pierce_damage_retention := 0.75
var bounce_damage_retention := 0.65
var runtime_motion: StringName = &"linear"
var boomerang_outbound_duration := 0.28
var _motion_elapsed := 0.0
var _returning := false
var _return_target: Node2D
var _pending_damage_multiplier := 1.0
var _damage_decay_queued := false
var _homing_target: Node2D
var _homing_turn_speed := 0.0
var _base_sprite_scale := Vector2.ONE
var _base_sprite_modulate := Color.WHITE
var _base_sprite_z_index := 0
var _presentation_baseline_captured := false
var _temporary_speed_scale := 1.0
var _temporary_speed_remaining := 0.0


func _ready() -> void:
	add_to_group(&"presentation_projectiles")
	_capture_presentation_baseline()
	refresh_presentation_settings()

func _process(delta: float) -> void:
	if _temporary_speed_remaining > 0.0:
		_temporary_speed_remaining = maxf(0.0, _temporary_speed_remaining - delta)
		if is_zero_approx(_temporary_speed_remaining):
			_temporary_speed_scale = 1.0
	_update_homing(delta)
	if runtime_motion == &"boomerang":
		_motion_elapsed += delta
		if not _returning and _motion_elapsed >= boomerang_outbound_duration:
			_returning = true
		if _returning and is_instance_valid(_return_target):
			var distance := global_position.distance_to(_return_target.global_position)
			if distance <= maxf(20.0, velocity.length() * delta):
				queue_free()
				return
			velocity = global_position.direction_to(
				_return_target.global_position
			) * velocity.length()
			rotation = velocity.angle()
	position += velocity * delta * _temporary_speed_scale


func apply_temporary_speed_multiplier(multiplier: float, duration: float) -> void:
	_temporary_speed_scale = minf(_temporary_speed_scale, clampf(multiplier, 0.1, 1.0))
	_temporary_speed_remaining = maxf(_temporary_speed_remaining, maxf(0.0, duration))


func temporary_speed_multiplier() -> float:
	return _temporary_speed_scale


func is_enemy_projectile() -> bool:
	return _is_enemy_projectile()


func configure_homing(target: Node2D, turn_speed: float = 7.0) -> void:
	_homing_target = target
	_homing_turn_speed = maxf(0.0, turn_speed)


func _update_homing(delta: float) -> void:
	if not is_instance_valid(_homing_target) or _homing_turn_speed <= 0.0:
		return
	var desired_velocity := global_position.direction_to(_homing_target.global_position) * velocity.length()
	if desired_velocity.is_zero_approx():
		return
	var turn := clampf(
		velocity.angle_to(desired_velocity),
		-_homing_turn_speed * delta,
		_homing_turn_speed * delta
	)
	velocity = velocity.rotated(turn)
	rotation = velocity.angle()


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
	projectile_presentation_id: StringName = &"projectile.enemy",
	pattern_modifiers: Dictionary = {}
) -> void:
	self.velocity = velocity
	rotation = velocity.angle()
	pierce_remaining = maxi(0, pierce)
	bounce_remaining = maxi(0, bounce)
	pierce_damage_retention = clampf(
		float(pattern_modifiers.get("pierce_damage_retention", 0.75)), 0.0, 1.0
	)
	bounce_damage_retention = clampf(
		float(pattern_modifiers.get("bounce_damage_retention", 0.65)), 0.0, 1.0
	)
	runtime_motion = StringName(str(pattern_modifiers.get("runtime_motion", "linear")))
	boomerang_outbound_duration = maxf(
		0.05, float(pattern_modifiers.get("boomerang_outbound_duration", 0.28))
	)
	_return_target = unit
	presentation_id = projectile_presentation_id
	var projectile_sprite := get_node_or_null("Sprite2D") as Sprite2D
	if projectile_sprite != null:
		projectile_sprite.texture = Presentation.resolve_texture(
			&"projectile", presentation_id
		)
		projectile_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		if projectile_sprite.texture != null and maxf(
			projectile_sprite.texture.get_width(),
			projectile_sprite.texture.get_height()
		) >= 128.0:
			projectile_sprite.scale = Vector2.ONE * PIXEL_ART_PROJECTILE_SCALE
		# _ready() captures the mechanical sprite before the skin texture is
		# selected. Re-capture after replacing it so accessibility contrast can
		# always restore the actual skinned size and colour.
		_presentation_baseline_captured = false
	refresh_presentation_settings()
	if hitbox:
		hitbox.setup(
			damage, critical, knockback, unit, effect_source, effect_tags,
			pattern_modifiers
		)


func refresh_presentation_settings() -> void:
	apply_high_contrast(
		GameplayCuePresenter.runtime_bool(&"high_contrast_projectiles", false)
	)


func apply_high_contrast(enabled: bool) -> void:
	_capture_presentation_baseline()
	var projectile_sprite := get_node_or_null("Sprite2D") as Sprite2D
	if projectile_sprite == null:
		return
	if not enabled:
		projectile_sprite.scale = _base_sprite_scale
		projectile_sprite.modulate = _base_sprite_modulate
		projectile_sprite.z_index = _base_sprite_z_index
		return
	projectile_sprite.scale = _base_sprite_scale * 1.35
	projectile_sprite.modulate = (
		Color(1.0, 0.25, 0.52, 1.0)
		if _is_enemy_projectile()
		else Color(1.0, 0.92, 0.18, 1.0)
	)
	projectile_sprite.z_index = maxi(_base_sprite_z_index, 100)


func _capture_presentation_baseline() -> void:
	if _presentation_baseline_captured:
		return
	var projectile_sprite := get_node_or_null("Sprite2D") as Sprite2D
	if projectile_sprite == null:
		return
	_base_sprite_scale = projectile_sprite.scale
	_base_sprite_modulate = projectile_sprite.modulate
	_base_sprite_z_index = projectile_sprite.z_index
	_presentation_baseline_captured = true


func _is_enemy_projectile() -> bool:
	return hitbox != null and bool(hitbox.collision_layer & 4)


func _on_visible_on_screen_notifier_2d_screen_exited() -> void:
	queue_free()


func _on_hitbox_component_on_hit_hurtbox(hurtbox: HurtboxComponent) -> void:
	var target := _resolve_enemy(hurtbox)
	if target != null:
		_hit_targets[target.get_instance_id()] = true
	if bounce_remaining > 0 and _bounce_to_next_target():
		bounce_remaining -= 1
		_queue_transition_damage_decay(&"bounce")
		return
	if pierce_remaining > 0:
		pierce_remaining -= 1
		_queue_transition_damage_decay(&"pierce")
		return
	queue_free()


func apply_transition_damage_decay(transition: StringName) -> void:
	if hitbox == null:
		return
	var retention := (
		bounce_damage_retention
		if transition == &"bounce"
		else pierce_damage_retention
	)
	hitbox.damage *= clampf(retention, 0.0, 1.0)
	hitbox.display_damage = hitbox.damage


func _queue_transition_damage_decay(transition: StringName) -> void:
	_pending_damage_multiplier *= (
		bounce_damage_retention
		if transition == &"bounce"
		else pierce_damage_retention
	)
	if _damage_decay_queued:
		return
	_damage_decay_queued = true
	call_deferred("_apply_pending_damage_decay")


func _apply_pending_damage_decay() -> void:
	if hitbox != null:
		hitbox.damage *= clampf(_pending_damage_multiplier, 0.0, 1.0)
		hitbox.display_damage = hitbox.damage
	_pending_damage_multiplier = 1.0
	_damage_decay_queued = false


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
