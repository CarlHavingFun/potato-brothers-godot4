extends Node2D
class_name ChargeBehavior


enum ChargeState {
	APPROACH,
	WINDUP,
	ATTACK,
	RECOVER,
}

enum AttackPattern {
	CHARGE,
	CHAIN,
	SLAM,
}

@export var enemy: Enemy
@export var anim_effects: AnimationPlayer
@export var prep_time := 1.0
@export var cooldown := 3.0
@export var charge_duration := 0.72
@export var recovery_duration := 0.45
@export var charge_speed_multiplier := 5.0
@export var slam_radius := 125.0
@export var slam_lunge_distance := 190.0

var current_cooldown := 0.0
var charge_attack_position := Vector2.ZERO
var charge_direction := Vector2.ZERO
var charge_state := ChargeState.APPROACH
var state_remaining := 0.0
var phase := 1
var chains_remaining := 0
var is_charging := false
var attack_sequence := 0
var current_pattern := AttackPattern.CHARGE
var slam_target := Vector2.ZERO


func _ready() -> void:
	current_cooldown = cooldown


func _process(delta: float) -> void:
	if not Global.is_combat_active() or enemy == null:
		return
	_update_phase()
	match charge_state:
		ChargeState.APPROACH:
			current_cooldown -= delta
			if current_cooldown <= 0.0 and is_instance_valid(Global.player):
				current_pattern = attack_pattern_for(attack_sequence, phase)
				attack_sequence += 1
				chains_remaining = (
					charge_chain_count(phase, _difficulty_level())
					if current_pattern == AttackPattern.CHAIN
					else 1
				)
				_start_windup(_telegraph_duration())
		ChargeState.WINDUP:
			enemy.velocity = Vector2.ZERO
			state_remaining -= delta
			if state_remaining <= 0.0:
				if current_pattern == AttackPattern.SLAM:
					_execute_slam()
				else:
					_start_charge_segment()
		ChargeState.ATTACK:
			enemy.velocity = charge_direction * enemy.stats.speed * _charge_speed()
			enemy.move_and_slide()
			state_remaining -= delta
			if state_remaining <= 0.0 \
			or enemy.global_position.distance_to(charge_attack_position) < 45.0:
				_finish_charge_segment()
		ChargeState.RECOVER:
			enemy.velocity = Vector2.ZERO
			state_remaining -= delta
			if state_remaining <= 0.0:
				charge_state = ChargeState.APPROACH
				enemy.can_move = true
				current_cooldown = cooldown * (0.68 if phase >= 2 else 1.0)
				enemy.presentation_controller.set_semantic_state(&"move")


func start_charge() -> void:
	if enemy == null or not is_instance_valid(Global.player):
		return
	current_pattern = attack_pattern_for(attack_sequence, phase)
	attack_sequence += 1
	chains_remaining = (
		charge_chain_count(phase, _difficulty_level())
		if current_pattern == AttackPattern.CHAIN
		else 1
	)
	_start_windup(_telegraph_duration())


func end_charge() -> void:
	chains_remaining = 0
	_start_recovery()


func _start_windup(duration: float) -> void:
	charge_state = ChargeState.WINDUP
	state_remaining = maxf(0.12, duration)
	is_charging = false
	enemy.can_move = false
	enemy.velocity = Vector2.ZERO
	if is_instance_valid(Global.player):
		charge_direction = enemy.global_position.direction_to(Global.player.global_position)
		charge_attack_position = Global.player.global_position + charge_direction * 120.0
		slam_target = Global.player.global_position
	enemy.presentation_controller.set_semantic_state(&"telegraph")
	GameplayCues.emit_cue(&"enemy.telegraph", {
		"presentation_id": enemy.definition.get_presentation_id(Content.catalog.pack_id) if enemy.definition != null else &"",
		"world_position": enemy.global_position,
		"shape": &"circle" if current_pattern == AttackPattern.SLAM else &"line",
		"phase": phase,
		"attack": current_pattern,
	})
	if anim_effects != null and anim_effects.has_animation(&"charge"):
		anim_effects.play(&"charge")


func _start_charge_segment() -> void:
	if is_instance_valid(Global.player):
		charge_direction = enemy.global_position.direction_to(Global.player.global_position)
		charge_attack_position = Global.player.global_position + charge_direction * 120.0
	charge_state = ChargeState.ATTACK
	state_remaining = charge_duration
	is_charging = true
	enemy.presentation_controller.set_semantic_state(&"attack")
	GameplayCues.emit_cue(&"enemy.charge", {
		"presentation_id": enemy.definition.get_presentation_id(Content.catalog.pack_id) if enemy.definition != null else &"",
		"world_position": enemy.global_position,
		"phase": phase,
	})


func _finish_charge_segment() -> void:
	is_charging = false
	chains_remaining -= 1
	if chains_remaining > 0 and is_instance_valid(Global.player):
		_start_windup(0.18)
		return
	_start_recovery()


func _execute_slam() -> void:
	var offset := slam_target - enemy.global_position
	if offset.length() > slam_lunge_distance:
		offset = offset.normalized() * slam_lunge_distance
	enemy.global_position += offset
	enemy.presentation_controller.set_semantic_state(&"attack")
	if is_instance_valid(Global.player) \
	and enemy.global_position.distance_to(Global.player.global_position) <= slam_radius:
		Global.player.health_component.take_damage(enemy.stats.damage * 1.2)
	GameplayCues.emit_cue(&"enemy.slam", {
		"presentation_id": enemy.definition.get_presentation_id(Content.catalog.pack_id) if enemy.definition != null else &"",
		"world_position": enemy.global_position,
		"radius": slam_radius,
		"phase": phase,
	})
	_start_recovery()


func _start_recovery() -> void:
	charge_state = ChargeState.RECOVER
	state_remaining = recovery_duration
	is_charging = false
	enemy.velocity = Vector2.ZERO
	enemy.presentation_controller.set_semantic_state(&"idle")


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
	current_cooldown = minf(current_cooldown, 0.5)
	GameplayCues.emit_cue(&"enemy.phase", {
		"presentation_id": enemy.definition.get_presentation_id(Content.catalog.pack_id) if enemy.definition != null else &"",
		"phase": &"frenzy",
	})


func _is_elite() -> bool:
	return enemy.definition != null and &"elite" in enemy.definition.tags


func _difficulty_level() -> int:
	return Global.current_run.difficulty if Global.current_run != null else 1


func _telegraph_duration() -> float:
	if enemy.definition != null and enemy.definition.behavior != null \
	and enemy.definition.behavior.telegraph_seconds > 0.0:
		return enemy.definition.behavior.telegraph_seconds
	return prep_time


func _charge_speed() -> float:
	return charge_speed_multiplier + (1.5 if phase >= 2 else 0.0)


static func phase_for_health(
	current_health: float,
	maximum_health: float,
	is_elite: bool,
	difficulty: int
) -> int:
	if not is_elite or maximum_health <= 0.0:
		return 1
	var threshold := 0.70 if difficulty >= 5 else 0.50
	return 2 if current_health / maximum_health <= threshold else 1


static func charge_chain_count(current_phase: int, difficulty: int) -> int:
	if current_phase < 2:
		return 1
	return 3 if difficulty >= 5 else 2


static func attack_pattern_for(sequence: int, current_phase: int) -> int:
	if current_phase < 2:
		return AttackPattern.CHARGE
	match posmod(sequence, 3):
		0:
			return AttackPattern.CHAIN
		1:
			return AttackPattern.SLAM
	return AttackPattern.CHARGE
