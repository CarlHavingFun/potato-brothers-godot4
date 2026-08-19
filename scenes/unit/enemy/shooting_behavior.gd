extends Node2D
class_name ShootingBehavior


enum ShootingState {
	APPROACH,
	WINDUP,
	ATTACK,
	RECOVER,
}

enum AttackPattern {
	SPREAD,
	RADIAL,
	FOCUSED_BURST,
}

@export var enemy: Enemy
@export var fire_pos: Marker2D
@export var cooldown := 3.0
@export var telegraph_duration := 0.35
@export var recovery_duration := 0.55
@export var projectile_count := 3
@export var arc_angle := 45.0
@export var projectile_scene: PackedScene
@export var projectile_speed := 1800.0

var current_cooldown := 0.0
var shooting_state := ShootingState.APPROACH
var state_remaining := 0.0
var phase := 1
var attack_sequence := 0


func _ready() -> void:
	current_cooldown = cooldown


func _process(delta: float) -> void:
	if not Global.is_combat_active() or enemy == null:
		return
	if enemy.is_ranged_attack_interrupted():
		_interrupt_attack()
		return
	_update_phase()
	match shooting_state:
		ShootingState.APPROACH:
			current_cooldown -= delta
			if current_cooldown <= 0.0 and is_instance_valid(Global.player):
				_start_windup()
		ShootingState.WINDUP:
			enemy.velocity = Vector2.ZERO
			state_remaining -= delta
			if state_remaining <= 0.0:
				_start_attack()
		ShootingState.ATTACK:
			state_remaining -= delta
			if state_remaining <= 0.0:
				_start_recovery()
		ShootingState.RECOVER:
			enemy.velocity = Vector2.ZERO
			state_remaining -= delta
			if state_remaining <= 0.0:
				shooting_state = ShootingState.APPROACH
				enemy.can_move = true
				current_cooldown = cooldown * (0.62 if phase >= 2 else 1.0)
				enemy.presentation_controller.set_semantic_state(&"move")


func shoot() -> void:
	if (
		enemy == null
		or enemy.is_ranged_attack_interrupted()
		or not is_instance_valid(Global.player)
	):
		return
	_start_windup()


func _start_windup() -> void:
	shooting_state = ShootingState.WINDUP
	state_remaining = _telegraph_duration()
	enemy.can_move = false
	enemy.velocity = Vector2.ZERO
	enemy.presentation_controller.set_semantic_state(&"telegraph")
	var pattern := attack_pattern_for(attack_sequence, phase)
	GameplayCues.emit_cue(&"enemy.telegraph", {
		"presentation_id": enemy.definition.get_presentation_id(Content.catalog.pack_id) if enemy.definition != null else &"",
		"world_position": enemy.global_position,
		"shape": &"radial" if pattern == AttackPattern.RADIAL else &"cone",
		"phase": phase,
	})


func _start_attack() -> void:
	if enemy.is_ranged_attack_interrupted():
		_interrupt_attack()
		return
	shooting_state = ShootingState.ATTACK
	state_remaining = 0.12
	enemy.presentation_controller.set_semantic_state(&"attack")
	var pattern := attack_pattern_for(attack_sequence, phase)
	attack_sequence += 1
	match pattern:
		AttackPattern.RADIAL:
			_fire_radial(10 if _difficulty_level() >= 5 else 8)
		AttackPattern.FOCUSED_BURST:
			_fire_focused_burst()
		_:
			_fire_spread(projectile_count + (2 if phase >= 2 else 0), arc_angle)
	GameplayCues.emit_cue(&"enemy.ranged_attack", {
		"presentation_id": enemy.definition.get_presentation_id(Content.catalog.pack_id) if enemy.definition != null else &"",
		"world_position": enemy.global_position,
		"pattern": pattern,
		"phase": phase,
	})


func _start_recovery() -> void:
	shooting_state = ShootingState.RECOVER
	state_remaining = recovery_duration
	enemy.velocity = Vector2.ZERO
	enemy.presentation_controller.set_semantic_state(&"idle")


func _fire_spread(count: int, spread_angle: float) -> void:
	if not _can_fire():
		return
	var direction := enemy.global_position.direction_to(Global.player.global_position)
	var safe_count := maxi(1, count)
	var start_angle := -spread_angle * 0.5
	var angle_step := spread_angle / float(maxi(1, safe_count - 1))
	for index: int in safe_count:
		_spawn_projectile(
			direction.rotated(deg_to_rad(start_angle + angle_step * index)),
			projectile_speed
		)


func _fire_radial(count: int) -> void:
	if not _can_fire():
		return
	var safe_count := maxi(1, count)
	for index: int in safe_count:
		_spawn_projectile(Vector2.RIGHT.rotated(TAU * float(index) / float(safe_count)), projectile_speed * 0.72)


func _fire_focused_burst() -> void:
	if not _can_fire():
		return
	var direction := enemy.global_position.direction_to(Global.player.global_position)
	for index: int in 3:
		var offset_degrees := float(index - 1) * 4.0
		_spawn_projectile(direction.rotated(deg_to_rad(offset_degrees)), projectile_speed * (0.88 + index * 0.12))


func _spawn_projectile(direction: Vector2, speed: float) -> void:
	var projectile := projectile_scene.instantiate() as Projectile
	if projectile == null:
		return
	get_tree().root.add_child(projectile)
	projectile.global_position = fire_pos.global_position if fire_pos != null else enemy.global_position
	projectile.set_projectile(direction * speed, enemy.stats.damage, false, 0.0, enemy)


func _can_fire() -> bool:
	return (
		projectile_scene != null
		and get_tree() != null
		and enemy != null
		and not enemy.is_ranged_attack_interrupted()
		and is_instance_valid(Global.player)
	)


func _interrupt_attack() -> void:
	if enemy == null:
		return
	if shooting_state != ShootingState.APPROACH:
		GameplayCues.emit_cue(&"enemy.ranged_interrupted", {
			"presentation_id": enemy.definition.get_presentation_id(
				Content.catalog.pack_id
			) if enemy.definition != null else &"",
			"world_position": enemy.global_position,
		})
	shooting_state = ShootingState.APPROACH
	state_remaining = 0.0
	current_cooldown = maxf(current_cooldown, cooldown * 0.5)
	enemy.can_move = true
	enemy.velocity = Vector2.ZERO
	enemy.presentation_controller.set_semantic_state(&"move")


func _update_phase() -> void:
	if phase >= 2 or enemy.health_component == null:
		return
	var next_phase := phase_for_health(
		enemy.health_component.current_health,
		enemy.health_component.max_health,
		_is_elite(),
		_difficulty_level()
	)
	if next_phase <= phase:
		return
	phase = next_phase
	current_cooldown = minf(current_cooldown, 0.4)
	GameplayCues.emit_cue(&"enemy.phase", {
		"presentation_id": enemy.definition.get_presentation_id(Content.catalog.pack_id) if enemy.definition != null else &"",
		"phase": &"overcharged",
	})


func _is_elite() -> bool:
	return enemy.definition != null and &"elite" in enemy.definition.tags


func _difficulty_level() -> int:
	return Global.current_run.difficulty if Global.current_run != null else 1


func _telegraph_duration() -> float:
	if enemy.definition != null and enemy.definition.behavior != null \
	and enemy.definition.behavior.telegraph_seconds > 0.0:
		return maxf(0.15, enemy.definition.behavior.telegraph_seconds)
	return telegraph_duration


static func phase_for_health(
	current_health: float,
	maximum_health: float,
	is_elite: bool,
	difficulty: int
) -> int:
	if not is_elite or maximum_health <= 0.0:
		return 1
	var threshold := 0.60 if difficulty >= 5 else 0.40
	return 2 if current_health / maximum_health <= threshold else 1


static func attack_pattern_for(sequence: int, current_phase: int) -> int:
	if current_phase < 2:
		return AttackPattern.SPREAD
	match posmod(sequence, 3):
		1:
			return AttackPattern.RADIAL
		2:
			return AttackPattern.FOCUSED_BURST
	return AttackPattern.SPREAD
