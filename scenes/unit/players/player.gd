extends Unit
class_name Player

@export var dash_duration := 0.18
@export var dash_invulnerability_duration := 0.12
@export var dash_speed_multi := 3.4
@export var dash_cooldown := 2.5
@export var max_dash_charges := 1

@onready var dash_timer: Timer = $DashTimer
@onready var dash_invulnerability_timer: Timer = $DashInvulnerabilityTimer
@onready var dash_cooldown_timer: Timer = $DashCooldownTimer
@onready var collision: CollisionShape2D = $CollisionShape2D
@onready var trail: Trail = %Trail
@onready var weapon_container: WeaponContainer = $WeaponContainer

var current_weapons: Array[Weapon] = []

var move_dir: Vector2
var is_dashing := false
var dash_charges := 1
var enemy_slow_multiplier := 1.0
var enemy_slow_remaining := 0.0
var directional_visual: DirectionalSpriteVisual

func _ready() -> void:
	super._ready()
	directional_visual = get_node_or_null("Visuals/DirectionalSpriteVisual") as DirectionalSpriteVisual
	if directional_visual != null:
		sprite.visible = false
		health_component.on_unit_hit.connect(_on_directional_visual_hit)
		health_component.on_unit_died.connect(_on_directional_visual_died)
		flash_timer.timeout.connect(_on_directional_visual_flash_timeout)
		Global.run_phase_changed.connect(_on_directional_visual_run_phase_changed)
	if Global.current_run != null:
		max_dash_charges = Global.current_run.dash_charges
		dash_cooldown *= Global.current_run.dash_cooldown_multiplier
		dash_duration *= Global.current_run.dash_duration_multiplier
		dash_invulnerability_duration = minf(dash_invulnerability_duration, dash_duration)
		var character := Content.catalog.get_character(Global.current_run.character_id)
		if character != null:
			configure_presentation(
				&"character", character.get_presentation_id(Content.catalog.pack_id)
			)
	_set_visual_semantic_state(&"idle")
	dash_timer.wait_time = dash_duration
	dash_invulnerability_timer.wait_time = dash_invulnerability_duration
	dash_cooldown_timer.wait_time = dash_cooldown
	dash_charges = max_dash_charges


func _process(delta: float) -> void:
	if not Global.is_combat_active(): return
	if enemy_slow_remaining > 0.0:
		enemy_slow_remaining = maxf(0.0, enemy_slow_remaining - delta)
		if is_zero_approx(enemy_slow_remaining):
			enemy_slow_multiplier = 1.0
	
	move_dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	
	var movement_speed := stats.speed
	if Global.current_run != null and Global.combat_resolver != null:
		movement_speed = Global.combat_resolver.movement_speed(Global.current_run.player_stats)
	var current_velocity := move_dir * movement_speed * enemy_slow_multiplier
	if is_dashing:
		current_velocity *= dash_speed_multi
	
	velocity = current_velocity
	move_and_slide()
	position.x = clamp(position.x, -1000, 1000)
	position.y = clamp(position.y, -500, 500)
	
	if can_dash():
		start_dash()
	
	update_animations()
	update_rotation()


func apply_enemy_slow(multiplier: float, duration: float) -> void:
	enemy_slow_multiplier = minf(enemy_slow_multiplier, clampf(multiplier, 0.4, 1.0))
	enemy_slow_remaining = maxf(enemy_slow_remaining, maxf(0.0, duration))


func add_weapon(data: ItemWeapon) -> void:
	var weapon := data.scene.instantiate() as Weapon
	add_child(weapon)
	
	weapon.setup_weapon(data)
	current_weapons.append(weapon)
	weapon_container.update_weapons_position(current_weapons)


func update_animations() -> void:
	if directional_visual != null:
		directional_visual.update_motion(move_dir)
		return
	if move_dir.length() > 0:
		presentation_controller.set_semantic_state(&"move")
	else:
		presentation_controller.set_semantic_state(&"idle")


func update_rotation() -> void:
	if directional_visual != null:
		if move_dir != Vector2.ZERO:
			directional_visual.set_facing(
				DirectionalSpriteVisual.direction_from_vector(move_dir)
			)
		return
	if move_dir == Vector2.ZERO:
		return
	
	if move_dir.x >= 0.1:
		visuals.scale = Vector2(-0.5, 0.5)
	else:
		visuals.scale = Vector2(0.5, 0.5)


func start_dash() -> void:
	if is_dashing or dash_charges <= 0 or move_dir == Vector2.ZERO:
		return
	is_dashing = true
	dash_charges -= 1
	dash_timer.start()
	dash_invulnerability_timer.start()
	dash_cooldown_timer.start()
	trail.start_trail()
	visuals.modulate.a = 0.5
	collision.set_deferred("disabled", true)
	Global.dispatch_gameplay_event(
		GameplayEvent.Type.DASHED,
		{"charges": dash_charges},
		[] as Array[StringName],
		self
	)
	GameplayCues.emit_cue(&"player.dash", {"world_position": global_position})
	_set_visual_semantic_state(&"dash")


func can_dash() -> bool:
	return not is_dashing and\
	dash_charges > 0 and\
	Input.is_action_just_pressed("dash") and\
	move_dir != Vector2.ZERO


func is_facing_right() -> bool:
	if directional_visual != null:
		return directional_visual.is_facing_right()
	return visuals.scale.x == -0.5


func update_player_new_wave() -> void:
	Global.apply_stat_change("health", stats.health_increase_per_wave)
	health_component.setup(stats)


func _on_dash_timer_timeout() -> void:
	is_dashing = false
	visuals.modulate.a = 1.0
	move_dir = Vector2.ZERO
	_set_visual_semantic_state(&"idle")


func _on_dash_invulnerability_timer_timeout() -> void:
	collision.set_deferred("disabled", false)


func _on_dash_cooldown_timer_timeout() -> void:
	dash_charges = mini(max_dash_charges, dash_charges + 1)


func _on_hp_regen_timer_timeout() -> void:
	if health_component.current_health <= 0:
		return
	
	if health_component.current_health < stats.health:
		var heal := stats.hp_regen
		if Global.current_run != null and Global.combat_resolver != null:
			heal = Global.combat_resolver.recovery_amount(Global.current_run.player_stats)
		health_component.heal(heal)
		Global.on_create_heal_text.emit(self, heal)


func _set_visual_semantic_state(state: StringName) -> void:
	if directional_visual != null:
		directional_visual.set_semantic_state(state)
	else:
		presentation_controller.set_semantic_state(state)


func _on_directional_visual_hit() -> void:
	if directional_visual != null:
		directional_visual.material = Global.FLASH_MATERIAL
		flash_timer.start()
		directional_visual.trigger_action(&"hit")


func _on_directional_visual_flash_timeout() -> void:
	if directional_visual != null:
		directional_visual.material = null


func _on_directional_visual_died() -> void:
	if directional_visual == null:
		return
	var death_visual := directional_visual
	death_visual.material = null
	death_visual.trigger_action(&"death")
	var survivor_parent := get_parent()
	if survivor_parent == null:
		return
	var duration := maxf(0.1, death_visual.animation_duration(&"death"))
	death_visual.reparent(survivor_parent, true)
	get_tree().create_timer(duration).timeout.connect(death_visual.queue_free)
	directional_visual = null


func _on_directional_visual_run_phase_changed(phase: int) -> void:
	if directional_visual == null:
		return
	if phase == RunPhase.VICTORY:
		directional_visual.trigger_action(&"victory")
	elif phase == RunPhase.DEATH:
		directional_visual.trigger_action(&"death")
