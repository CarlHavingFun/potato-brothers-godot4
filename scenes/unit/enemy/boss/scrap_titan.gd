class_name ScrapTitanBoss
extends Enemy


enum BossState {
	TRACK,
	TELEGRAPH,
	BURST,
	RECOVER,
}

enum AttackKind {
	RADIAL,
	AIMED_VOLLEY,
	GROUND_PULSE,
}

@export var attack_cooldown := 3.2
@export var overdrive_attack_cooldown := 1.8
@export var telegraph_duration := 0.65
@export var recovery_duration := 0.45
@export var projectile_speed := 620.0
@export var projectile_scene: PackedScene
@export var ground_pulse_radius := 225.0

var boss_state := BossState.TRACK
var state_time := 0.0
var cooldown_left := 1.5
var overdrive := false
var attack_sequence := 0
var current_attack := AttackKind.RADIAL


func _process(delta: float) -> void:
	if not Global.is_combat_active():
		return
	match boss_state:
		BossState.TRACK:
			super._process(delta)
			cooldown_left -= delta
			if cooldown_left <= 0.0:
				_start_telegraph()
		BossState.TELEGRAPH:
			velocity = Vector2.ZERO
			state_time -= delta
			visuals.modulate = Color(1.0, 0.72, 0.2) if int(state_time * 16.0) % 2 == 0 else Color.WHITE
			if state_time <= 0.0:
				boss_state = BossState.BURST
		BossState.BURST:
			presentation_controller.set_semantic_state(&"attack")
			_execute_current_attack()
			boss_state = BossState.RECOVER
			state_time = recovery_duration
			presentation_controller.set_semantic_state(&"idle")
		BossState.RECOVER:
			velocity = Vector2.ZERO
			state_time -= delta
			if state_time <= 0.0:
				boss_state = BossState.TRACK
				can_move = true
				visuals.modulate = Color(1.0, 0.55, 0.24) if overdrive else Color.WHITE


func _on_hurtbox_component_on_damaged(hitbox: HitboxComponent) -> void:
	super._on_hurtbox_component_on_damaged(hitbox)
	if overdrive or health_component.max_health <= 0.0:
		return
	var difficulty := Global.current_run.difficulty if Global.current_run != null else 1
	if should_enter_overdrive(health_component.current_health, health_component.max_health, difficulty):
		overdrive = true
		cooldown_left = minf(cooldown_left, overdrive_attack_cooldown)
		visuals.modulate = Color(1.0, 0.55, 0.24)
		GameplayCues.emit_cue(&"boss.phase", {
			"phase": &"overdrive",
			"presentation_id": definition.get_presentation_id(Content.catalog.pack_id) if definition != null else &"enemy.scrap_titan",
		})


static func should_enter_overdrive(current_health: float, maximum_health: float, difficulty: int) -> bool:
	if maximum_health <= 0.0:
		return false
	var threshold := 0.45 if difficulty >= 5 else 0.30
	return current_health / maximum_health <= threshold


static func burst_projectile_count(difficulty: int, is_overdrive: bool) -> int:
	return 8 + (2 if difficulty >= 3 else 0) + (6 if is_overdrive else 0)


static func attack_kind_for(sequence: int, _is_overdrive: bool) -> int:
	match posmod(sequence, 3):
		1:
			return AttackKind.AIMED_VOLLEY
		2:
			return AttackKind.GROUND_PULSE
	return AttackKind.RADIAL


func _start_telegraph() -> void:
	current_attack = attack_kind_for(attack_sequence, overdrive)
	attack_sequence += 1
	boss_state = BossState.TELEGRAPH
	state_time = telegraph_duration * (1.25 if current_attack == AttackKind.GROUND_PULSE else 1.0)
	can_move = false
	presentation_controller.set_semantic_state(&"telegraph")
	GameplayCues.emit_cue(&"enemy.telegraph", {
		"presentation_id": definition.get_presentation_id(Content.catalog.pack_id) if definition != null else &"enemy.scrap_titan",
		"world_position": global_position,
		"shape": &"circle" if current_attack != AttackKind.AIMED_VOLLEY else &"cone",
		"attack": current_attack,
	})


func _execute_current_attack() -> void:
	match current_attack:
		AttackKind.AIMED_VOLLEY:
			_emit_aimed_volley()
		AttackKind.GROUND_PULSE:
			_emit_ground_pulse()
		_:
			_emit_radial_burst()
	cooldown_left = overdrive_attack_cooldown if overdrive else attack_cooldown


func _emit_radial_burst() -> void:
	if projectile_scene == null or get_tree() == null:
		return
	var difficulty := Global.current_run.difficulty if Global.current_run != null else 1
	var count := burst_projectile_count(difficulty, overdrive)
	for index: int in count:
		_spawn_projectile(
			Vector2.RIGHT.rotated(TAU * float(index) / float(count)),
			projectile_speed
		)
	GameplayCues.emit_cue(&"boss.radial_burst", {
		"count": count,
		"world_position": global_position,
	})


func _emit_aimed_volley() -> void:
	if projectile_scene == null or get_tree() == null or not is_instance_valid(Global.player):
		return
	var direction := global_position.direction_to(Global.player.global_position)
	var count := 7 if overdrive else 5
	for index: int in count:
		var angle := lerpf(-24.0, 24.0, float(index) / float(maxi(1, count - 1)))
		_spawn_projectile(direction.rotated(deg_to_rad(angle)), projectile_speed * 1.35)
	GameplayCues.emit_cue(&"boss.aimed_volley", {
		"count": count,
		"world_position": global_position,
	})


func _emit_ground_pulse() -> void:
	if is_instance_valid(Global.player) \
	and global_position.distance_to(Global.player.global_position) <= ground_pulse_radius:
		Global.player.health_component.take_damage(stats.damage * (1.4 if overdrive else 1.15))
	GameplayCues.emit_cue(&"boss.ground_pulse", {
		"radius": ground_pulse_radius,
		"world_position": global_position,
	})


func _spawn_projectile(direction: Vector2, speed: float) -> void:
	var projectile := projectile_scene.instantiate() as Projectile
	if projectile == null:
		return
	get_tree().root.add_child(projectile)
	projectile.global_position = global_position
	projectile.set_projectile(direction * speed, stats.damage, false, 1.0, self)
	var projectile_sprite := projectile.get_node_or_null("Sprite2D") as Sprite2D
	if projectile_sprite != null:
		projectile_sprite.texture = Presentation.resolve_texture(
			&"projectile", &"projectile.enemy", projectile_sprite.texture
		)
