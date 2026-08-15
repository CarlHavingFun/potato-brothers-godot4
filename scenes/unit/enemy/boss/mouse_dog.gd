class_name MouseDogBoss
extends Enemy


enum BossState {
	TRACK,
	WINDUP,
	DASH,
	RECOVER,
}

@export var attack_cooldown := 2.5
@export var enraged_attack_cooldown := 1.25
@export var windup_duration := 0.35
@export var dash_duration := 0.35
@export var recovery_duration := 0.25
@export var dash_speed_multiplier := 7.0
@export var enraged_dash_speed_multiplier := 9.0

var boss_state := BossState.TRACK
var state_time := 0.0
var cooldown_left := 1.0
var dash_direction := Vector2.ZERO
var enraged := false


func _process(delta: float) -> void:
	if not Global.is_combat_active():
		return
	match boss_state:
		BossState.TRACK:
			super._process(delta)
			cooldown_left -= delta
			if cooldown_left <= 0.0 and is_instance_valid(Global.player):
				_start_windup()
		BossState.WINDUP:
			velocity = Vector2.ZERO
			state_time -= delta
			visuals.modulate = Color(1.0, 0.35, 0.35) if int(state_time * 20.0) % 2 == 0 else Color.WHITE
			if state_time <= 0.0:
				_start_dash()
		BossState.DASH:
			var multiplier := enraged_dash_speed_multiplier if enraged else dash_speed_multiplier
			velocity = dash_direction * stats.speed * multiplier
			move_and_slide()
			state_time -= delta
			if state_time <= 0.0:
				_start_recovery()
		BossState.RECOVER:
			velocity = Vector2.ZERO
			state_time -= delta
			if state_time <= 0.0:
				boss_state = BossState.TRACK
				can_move = true
				visuals.modulate = Color(1.0, 0.65, 0.65) if enraged else Color.WHITE


func _on_hurtbox_component_on_damaged(hitbox: HitboxComponent) -> void:
	super._on_hurtbox_component_on_damaged(hitbox)
	if enraged or health_component.max_health <= 0.0:
		return
	var difficulty := Global.current_run.difficulty if Global.current_run != null else 1
	if should_enrage(health_component.current_health, health_component.max_health, difficulty):
		_enter_enrage()


static func should_enrage(current_health: float, maximum_health: float, difficulty: int) -> bool:
	if maximum_health <= 0.0:
		return false
	var threshold := 0.65 if difficulty >= 5 else 0.50
	return current_health / maximum_health <= threshold


func _start_windup() -> void:
	boss_state = BossState.WINDUP
	state_time = windup_duration
	can_move = false
	dash_direction = global_position.direction_to(Global.player.global_position)
	presentation_controller.set_semantic_state(&"telegraph")
	GameplayCues.emit_cue(&"enemy.telegraph", {
		"presentation_id": definition.get_presentation_id(Content.catalog.pack_id) if definition != null else &"enemy.mouse_dog",
		"world_position": global_position,
	})


func _start_dash() -> void:
	boss_state = BossState.DASH
	state_time = dash_duration
	visuals.modulate = Color(1.0, 0.2, 0.2)
	presentation_controller.set_semantic_state(&"attack")
	GameplayCues.emit_cue(&"boss.attack", {
		"presentation_id": definition.get_presentation_id(Content.catalog.pack_id) if definition != null else &"enemy.mouse_dog",
		"world_position": global_position,
	})


func _start_recovery() -> void:
	boss_state = BossState.RECOVER
	state_time = recovery_duration
	cooldown_left = enraged_attack_cooldown if enraged else attack_cooldown
	presentation_controller.set_semantic_state(&"idle")


func _enter_enrage() -> void:
	enraged = true
	GameplayCues.emit_cue(&"boss.phase", {
		"phase": &"enraged",
		"presentation_id": definition.get_presentation_id(Content.catalog.pack_id) if definition != null else &"enemy.mouse_dog",
	})
	cooldown_left = minf(cooldown_left, enraged_attack_cooldown)
	visuals.modulate = Color(1.0, 0.65, 0.65)
