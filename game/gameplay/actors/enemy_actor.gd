class_name GogoEnemyActor
extends CharacterBody2D

signal defeated(enemy: GogoEnemyActor, xp: int, materials: int)

var definition: GogoEnemyDefinition
var target: GogoPlayerActor
var current_health := 1.0
var touch_cooldown := 0.0
var role_timer := 0.0
var knockback_velocity := Vector2.ZERO


func configure(next_definition: GogoEnemyDefinition, next_target: GogoPlayerActor, difficulty: GogoDifficultyDefinition) -> void:
	definition = next_definition
	target = next_target
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
	if target == null or not is_instance_valid(target) or definition == null:
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
		touch_cooldown = 0.75


func take_damage(amount: float, impulse: Vector2 = Vector2.ZERO) -> void:
	current_health -= amount
	knockback_velocity += impulse
	queue_redraw()
	if current_health <= 0.0:
		defeated.emit(self, definition.xp_value, definition.material_value)
		queue_free()


func _draw() -> void:
	var color := Color("ef6b67")
	if definition != null:
		match definition.role:
			GogoEnemyDefinition.Role.SHOOTER: color = Color("b37feb")
			GogoEnemyDefinition.Role.CHARGER: color = Color("ff9f43")
	draw_circle(Vector2.ZERO, 15.0, color)
	draw_circle(Vector2(-5.0, -3.0), 2.0, Color("241f2b"))
	draw_circle(Vector2(5.0, -3.0), 2.0, Color("241f2b"))
