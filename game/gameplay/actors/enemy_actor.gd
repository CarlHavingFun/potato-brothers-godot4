class_name GogoEnemyActor
extends CharacterBody2D

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
	current_health = definition.max_health * difficulty.enemy_health_multiplier


func _ready() -> void:
	add_to_group(&"gogo_enemy")
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 14.0
	shape.shape = circle
	add_child(shape)
	queue_redraw()


func _physics_process(delta: float) -> void:
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
				target.take_damage(definition.touch_damage * 0.75)
				if defeated_once or is_queued_for_deletion() or not is_inside_tree():
					return
				role_timer = 1.7
		GogoEnemyDefinition.Role.CHARGER:
			if role_timer <= 0.0:
				knockback_velocity = direction * definition.movement_speed * 3.2
				role_timer = 2.2
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
	current_health = maxf(current_health - maxf(amount, 0.0), 0.0)
	knockback_velocity += impulse
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
		if runtime_instance_id > 0:
			enemy_defeated.emit(runtime_instance_id, death_position, xp, materials, death_sequence)
		if not reward_reservations.is_empty():
			combat_world._apply_reserved_enemy_rewards(reward_reservations)
		defeated.emit(self, xp, materials)
		queue_free()
	return true


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
	var role := GogoEnemyDefinition.Role.CHASER
	if definition != null:
		role = definition.role
	draw_circle(Vector2.ZERO, 16.0, Color("241f2b"))
	draw_circle(Vector2.ZERO, 14.0, visual_color_for_role(role))
	draw_circle(Vector2(-5.0, -3.0), 2.0, Color("241f2b"))
	draw_circle(Vector2(5.0, -3.0), 2.0, Color("241f2b"))
