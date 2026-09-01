class_name GogoEnemyActor
extends CharacterBody2D

const HIT_FLASH_SECONDS := 0.055
const HIT_SQUASH_SECONDS := 0.090
const HIT_FLASH_GAIN := 0.42
const HIT_SQUASH_X := 0.10
const HIT_SQUASH_Y := 0.08
const TARGET_LOCAL_HITSTOP_MAX_SECONDS := 0.050
const CHARGE_TELEGRAPH_SECONDS := 0.42
const CHARGE_RECOVERY_SECONDS := 2.20
const CHARGE_SPEED_MULTIPLIER := 3.20
const CHARGE_WARNING_TINT := Color(1.0, 0.52, 0.34, 1.0)
const BODY_RADIUS := 14.0
const ENEMY_COLLISION_LAYER := 1 << 1
const WORLD_COLLISION_LAYER := 1 << 7
const HIT_FLASH_SHADER_CODE := """
shader_type canvas_item;

uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	COLOR = vec4(mix(source.rgb, vec3(1.0), flash_amount), source.a);
}
"""

signal defeated(enemy: GogoEnemyActor, xp: int, materials: int)
signal enemy_defeated(
	enemy_instance_id: int,
	integer_death_global_position: Vector2i,
	xp: int,
	materials: int,
	death_sequence: int
)

var definition: GogoEnemyDefinition
var target: GogoPlayerActor
var current_health := 1.0
var touch_cooldown := 0.0
var role_timer := 0.0
var knockback_velocity := Vector2.ZERO
var defeated_once := false
var combat_world: CombatWorld
var runtime_instance_id := 0
var death_sequence := 0
var _next_damage_reservation_id := 1
var _reserved_damage_id := 0
var _reserved_damage_amount := 0.0
var _reserved_damage_impulse := Vector2.ZERO
var visual_sprite: Sprite2D
var fallback_visual_active := true
var _hit_flash_remaining := 0.0
var _hit_squash_remaining := 0.0
var _target_local_hitstop_remaining := 0.0
var _hit_flash_material: ShaderMaterial
var _charge_telegraph_remaining := 0.0
var _committed_charge_direction := Vector2.ZERO


func configure(
	next_definition: GogoEnemyDefinition,
	next_target: GogoPlayerActor,
	difficulty: GogoDifficultyDefinition,
	next_world: CombatWorld = null,
	next_runtime_instance_id: int = 0
) -> void:
	definition = next_definition
	target = next_target
	combat_world = next_world
	runtime_instance_id = next_runtime_instance_id
	if combat_world != null:
		combat_world.bind_enemy_feedback(self)
	death_sequence = 0
	defeated_once = false
	_next_damage_reservation_id = 1
	_reserved_damage_id = 0
	_reserved_damage_amount = 0.0
	_reserved_damage_impulse = Vector2.ZERO
	_hit_flash_remaining = 0.0
	_hit_squash_remaining = 0.0
	_target_local_hitstop_remaining = 0.0
	_charge_telegraph_remaining = 0.0
	_committed_charge_direction = Vector2.ZERO
	modulate = Color.WHITE
	current_health = definition.max_health * difficulty.enemy_health_multiplier
	if is_node_ready():
		_sync_visual()


func _ready() -> void:
	add_to_group(&"gogo_enemy")
	collision_layer = ENEMY_COLLISION_LAYER
	collision_mask = ENEMY_COLLISION_LAYER | WORLD_COLLISION_LAYER
	_sync_visual()
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = BODY_RADIUS
	shape.shape = circle
	add_child(shape)
	queue_redraw()


func _sync_visual() -> void:
	var texture: Texture2D
	if definition != null:
		texture = definition.visual_texture
	fallback_visual_active = texture == null
	if fallback_visual_active:
		if visual_sprite != null:
			remove_child(visual_sprite)
			visual_sprite.queue_free()
			visual_sprite = null
		_hit_flash_material = null
		queue_redraw()
		return
	if visual_sprite == null:
		visual_sprite = Sprite2D.new()
		visual_sprite.name = "VisualSprite"
		add_child(visual_sprite)
	visual_sprite.texture = texture
	visual_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	visual_sprite.centered = true
	visual_sprite.position = Vector2.ZERO
	visual_sprite.offset = Vector2.ZERO
	_ensure_hit_flash_material()
	_apply_hit_visual()
	queue_redraw()


func _physics_process(delta: float) -> void:
	if combat_world != null and combat_world.is_combat_simulation_frozen():
		return
	_update_hit_visual(delta)
	var target_locally_frozen := _target_local_hitstop_remaining > 0.0
	_target_local_hitstop_remaining = maxf(
		_target_local_hitstop_remaining - maxf(delta, 0.0),
		0.0
	)
	if target_locally_frozen:
		return
	if defeated_once or target == null or not is_instance_valid(target) or definition == null:
		return
	touch_cooldown = maxf(touch_cooldown - delta, 0.0)
	role_timer -= delta
	var to_target := target.global_position - global_position
	var direction := to_target.normalized()
	match definition.role:
		GogoEnemyDefinition.Role.CHASER:
			velocity = direction * definition.movement_speed
		GogoEnemyDefinition.Role.SHOOTER:
			velocity = direction * definition.movement_speed if to_target.length() > 190.0 else -direction * definition.movement_speed * 0.45
			if role_timer <= 0.0 and to_target.length() < 300.0:
				if combat_world != null:
					combat_world.spawn_hostile_pulse(
						self,
						target,
						direction,
						definition.touch_damage * 0.75
					)
				role_timer = 1.7
		GogoEnemyDefinition.Role.CHARGER:
			if _charge_telegraph_remaining > 0.0:
				_charge_telegraph_remaining = maxf(
					_charge_telegraph_remaining - maxf(delta, 0.0),
					0.0
				)
				velocity = Vector2.ZERO
				if _charge_telegraph_remaining <= 0.0:
					knockback_velocity = (
						_committed_charge_direction
						* definition.movement_speed
						* CHARGE_SPEED_MULTIPLIER
					)
					velocity = (
						_committed_charge_direction * definition.movement_speed
						+ knockback_velocity
					)
					role_timer = CHARGE_RECOVERY_SECONDS
					_apply_hit_visual()
					queue_redraw()
			elif role_timer <= 0.0:
				_committed_charge_direction = direction
				_charge_telegraph_remaining = CHARGE_TELEGRAPH_SECONDS
				velocity = Vector2.ZERO
				_apply_hit_visual()
				queue_redraw()
			else:
				velocity = direction * definition.movement_speed + knockback_velocity
	knockback_velocity = knockback_velocity.move_toward(Vector2.ZERO, 520.0 * delta)
	move_and_slide()
	if to_target.length() <= 34.0 and touch_cooldown <= 0.0:
		target.take_damage(definition.touch_damage)
		if defeated_once or is_queued_for_deletion() or not is_inside_tree():
			return
		touch_cooldown = 0.75


func can_receive_weapon_contact() -> bool:
	return (
		definition != null
		and not defeated_once
		and not is_queued_for_deletion()
		and _reserved_damage_id == 0
	)


func can_receive_projectile_contact() -> bool:
	return can_receive_weapon_contact()


func take_damage(amount: float, impulse: Vector2 = Vector2.ZERO) -> bool:
	if _reserved_damage_id != 0:
		return false
	return _apply_damage(amount, impulse)


func _reserve_weapon_damage(amount: float, impulse: Vector2) -> int:
	if (
		not can_receive_weapon_contact()
		or amount < 0.0
		or is_nan(amount)
		or is_inf(amount)
		or not impulse.is_finite()
	):
		return 0
	var reservation_id := _next_damage_reservation_id
	_next_damage_reservation_id += 1
	_reserved_damage_id = reservation_id
	_reserved_damage_amount = amount
	_reserved_damage_impulse = impulse
	return reservation_id


func _commit_reserved_weapon_damage(reservation_id: int) -> bool:
	if reservation_id <= 0 or reservation_id != _reserved_damage_id:
		return false
	var amount := _reserved_damage_amount
	var impulse := _reserved_damage_impulse
	_reserved_damage_id = 0
	_reserved_damage_amount = 0.0
	_reserved_damage_impulse = Vector2.ZERO
	return _apply_damage(amount, impulse)


func _reserve_projectile_damage(amount: float, impulse: Vector2) -> int:
	return _reserve_weapon_damage(amount, impulse)


func _commit_reserved_projectile_damage(reservation_id: int) -> bool:
	return _commit_reserved_weapon_damage(reservation_id)


func _apply_damage(amount: float, impulse: Vector2) -> bool:
	if defeated_once or definition == null:
		return false
	var applied_damage := maxf(amount, 0.0)
	current_health = maxf(current_health - applied_damage, 0.0)
	knockback_velocity += impulse
	if applied_damage > 0.0 and current_health > 0.0:
		_trigger_hit_visual()
	queue_redraw()
	if current_health <= 0.0:
		defeated_once = true
		remove_from_group(&"gogo_enemy")
		collision_layer = 0
		collision_mask = 0
		velocity = Vector2.ZERO
		knockback_velocity = Vector2.ZERO
		set_physics_process(false)
		if combat_world != null:
			combat_world.unregister_active_enemy(runtime_instance_id, self)
		death_sequence += 1
		var death_position := Vector2i(global_position.round())
		var xp := maxi(definition.xp_value, 0)
		var materials := maxi(definition.material_value, 0)
		var reward_reservations: Dictionary = {}
		if combat_world != null and runtime_instance_id > 0:
			reward_reservations = combat_world._reserve_enemy_reward_snapshot(
				runtime_instance_id,
				death_sequence,
				xp,
				materials
			)
			combat_world.spawn_reserved_enemy_pickups(
				runtime_instance_id,
				death_position,
				reward_reservations
			)
		if runtime_instance_id > 0:
			enemy_defeated.emit(runtime_instance_id, death_position, xp, materials, death_sequence)
		defeated.emit(self, xp, materials)
		queue_free()
	return true


func request_target_local_hitstop(seconds: float) -> void:
	if not is_finite(seconds) or seconds <= 0.0 or defeated_once:
		return
	_target_local_hitstop_remaining = maxf(
		_target_local_hitstop_remaining,
		minf(seconds, TARGET_LOCAL_HITSTOP_MAX_SECONDS)
	)


func is_target_locally_frozen() -> bool:
	return _target_local_hitstop_remaining > 0.0


func debug_target_local_hitstop_remaining() -> float:
	return _target_local_hitstop_remaining


func is_charge_telegraphing() -> bool:
	return _charge_telegraph_remaining > 0.0


func debug_charge_telegraph_remaining() -> float:
	return _charge_telegraph_remaining


func debug_committed_charge_direction() -> Vector2:
	return _committed_charge_direction


func _trigger_hit_visual() -> void:
	_hit_flash_remaining = HIT_FLASH_SECONDS
	_hit_squash_remaining = HIT_SQUASH_SECONDS
	_apply_hit_visual()


func _update_hit_visual(delta: float) -> void:
	if _hit_flash_remaining <= 0.0 and _hit_squash_remaining <= 0.0:
		return
	_hit_flash_remaining = maxf(_hit_flash_remaining - maxf(delta, 0.0), 0.0)
	_hit_squash_remaining = maxf(_hit_squash_remaining - maxf(delta, 0.0), 0.0)
	_apply_hit_visual()


func _apply_hit_visual() -> void:
	var flash_weight := clampf(
		_hit_flash_remaining / HIT_FLASH_SECONDS,
		0.0,
		1.0
	)
	if visual_sprite == null:
		var brightness := 1.0 + HIT_FLASH_GAIN * flash_weight
		var base_tint := CHARGE_WARNING_TINT if is_charge_telegraphing() else Color.WHITE
		modulate = Color(
			base_tint.r * brightness,
			base_tint.g * brightness,
			base_tint.b * brightness,
			1.0
		)
		return
	modulate = CHARGE_WARNING_TINT if is_charge_telegraphing() else Color.WHITE
	_ensure_hit_flash_material()
	_hit_flash_material.set_shader_parameter(&"flash_amount", flash_weight * HIT_FLASH_GAIN)
	var squash_weight := clampf(
		_hit_squash_remaining / HIT_SQUASH_SECONDS,
		0.0,
		1.0
	)
	visual_sprite.scale = Vector2(
		1.0 + HIT_SQUASH_X * squash_weight,
		1.0 - HIT_SQUASH_Y * squash_weight
	)


func _ensure_hit_flash_material() -> void:
	if visual_sprite == null:
		return
	if _hit_flash_material == null:
		var flash_shader := Shader.new()
		flash_shader.code = HIT_FLASH_SHADER_CODE
		_hit_flash_material = ShaderMaterial.new()
		_hit_flash_material.shader = flash_shader
	visual_sprite.material = _hit_flash_material


func retire_without_reward() -> void:
	if defeated_once and is_queued_for_deletion():
		return
	defeated_once = true
	_reserved_damage_id = 0
	_reserved_damage_amount = 0.0
	_reserved_damage_impulse = Vector2.ZERO
	remove_from_group(&"gogo_enemy")
	collision_layer = 0
	collision_mask = 0
	velocity = Vector2.ZERO
	knockback_velocity = Vector2.ZERO
	set_physics_process(false)
	if combat_world != null:
		combat_world.unregister_active_enemy(runtime_instance_id, self)
	queue_free()


func _exit_tree() -> void:
	if combat_world != null:
		combat_world.unregister_active_enemy(runtime_instance_id, self)


static func visual_color_for_role(role: GogoEnemyDefinition.Role) -> Color:
	match role:
		GogoEnemyDefinition.Role.SHOOTER:
			return Color("9aa75a")
		GogoEnemyDefinition.Role.CHARGER:
			return Color("d68a3a")
		_:
			return Color("b86d52")


func _draw() -> void:
	if is_charge_telegraphing():
		draw_arc(Vector2.ZERO, 21.0, 0.0, TAU, 24, Color("ff4438"), 3.0)
		draw_line(Vector2.ZERO, _committed_charge_direction * 29.0, Color("ffd45a"), 3.0)
	if not fallback_visual_active:
		return
	var role := GogoEnemyDefinition.Role.CHASER
	if definition != null:
		role = definition.role
	draw_circle(Vector2.ZERO, 16.0, Color("241f2b"))
	draw_circle(Vector2.ZERO, 14.0, visual_color_for_role(role))
	draw_circle(Vector2(-5.0, -3.0), 2.0, Color("241f2b"))
	draw_circle(Vector2(5.0, -3.0), 2.0, Color("241f2b"))
