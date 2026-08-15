extends Unit
class_name Enemy

signal reinforcement_requested(source: Enemy)

@export var flock_push := 20.0

const FLOCK_CELL_SIZE := 160.0
const MAX_FLOCK_NEIGHBORS := 8

static var _flock_members: Dictionary = {}
static var _flock_cells: Dictionary = {}
static var _flock_cache_frame := -1

@onready var vision_area: Area2D = $VisionArea
@onready var knockback_timer: Timer = $KnockbackTimer

var can_move := true
var definition: EnemyDef
var role_profile := EnemyRoleProfile.new()
var role_pulse_remaining := 2.5
var reinforcements_spawned := 0

var knockback_dir: Vector2
var knockback_power: float


func _ready() -> void:
	super._ready()
	add_to_group(GameplayEffectExecutor.ENEMY_GROUP)
	if definition != null:
		role_profile = (
			definition.behavior.to_role_profile()
			if definition.behavior != null
			else EnemyRoleRules.new().profile_for(definition.tags)
		)
		configure_presentation(&"enemy", definition.get_presentation_id(Content.catalog.pack_id))
		if definition.behavior != null:
			status_immunities = definition.behavior.status_immunities.duplicate()
	presentation_controller.set_semantic_state(&"spawn")
	role_pulse_remaining = role_profile.pulse_interval
	_flock_members[get_instance_id()] = weakref(self)
	# Neighbor lookup is handled by the shared spatial grid below. Keeping this
	# Area2D active makes crowded waves perform the same broad-phase query 250
	# times per frame and causes quadratic frame-time spikes.
	vision_area.monitoring = false
	vision_area.monitorable = false


func _exit_tree() -> void:
	_flock_members.erase(get_instance_id())

func _process(delta: float) -> void:
	if not Global.is_combat_active():
		velocity = Vector2.ZERO
		return
	
	if not can_move:
		return
	presentation_controller.set_semantic_state(&"move")
	_tick_role_behavior(delta)
	
	if not can_move_towards_player():
		return
	
	velocity = (
		(get_move_direction() + knockback_dir * knockback_power)
		* stats.speed
		* _nearby_buffer_multiplier()
		* effect_speed_multiplier()
	)
	move_and_slide()
	update_rotation()


func get_move_direction() -> Vector2:
	if not is_instance_valid(Global.player):
		return Vector2.ZERO
	
	var direction := global_position.direction_to(Global.player.global_position)
	if not is_zero_approx(role_profile.flank_angle):
		var flank_side := -1.0 if global_position.x < Global.player.global_position.x else 1.0
		direction = direction.rotated(role_profile.flank_angle * flank_side)
	_rebuild_flock_grid()
	var own_cell := _flock_cell(global_position)
	var neighbor_count := 0
	for cell_y: int in range(own_cell.y - 1, own_cell.y + 2):
		for cell_x: int in range(own_cell.x - 1, own_cell.x + 2):
			var members: Array = _flock_cells.get(Vector2i(cell_x, cell_y), [])
			for body: Enemy in members:
				if body == self or not is_instance_valid(body) or not body.is_inside_tree():
					continue
				var separation := global_position - body.global_position
				var distance_squared := separation.length_squared()
				if distance_squared <= 0.0001 or distance_squared > FLOCK_CELL_SIZE * FLOCK_CELL_SIZE:
					continue
				direction += flock_push * separation.normalized() / sqrt(distance_squared)
				neighbor_count += 1
				if neighbor_count >= MAX_FLOCK_NEIGHBORS:
					return direction
	
	return direction


func _nearby_buffer_multiplier() -> float:
	var bonus := 0.0
	var own_cell := _flock_cell(global_position)
	for cell_y: int in range(own_cell.y - 1, own_cell.y + 2):
		for cell_x: int in range(own_cell.x - 1, own_cell.x + 2):
			for body: Enemy in _flock_cells.get(Vector2i(cell_x, cell_y), []):
				if body == self or not is_instance_valid(body):
					continue
				if body.role_profile.ally_speed_bonus <= 0.0:
					continue
				if global_position.distance_squared_to(body.global_position) <= 180.0 * 180.0:
					bonus += body.role_profile.ally_speed_bonus
	return 1.0 + minf(0.35, bonus)


func _tick_role_behavior(delta: float) -> void:
	if (
		role_profile.heal_amount <= 0.0
		and role_profile.hazard_damage <= 0.0
		and role_profile.material_steal <= 0
		and role_profile.slow_multiplier >= 1.0
		and not role_profile.can_spawn_reinforcements
		and role_profile.ambush_distance <= 0.0
	):
		return
	role_pulse_remaining -= delta
	if role_pulse_remaining > 0.0:
		return
	role_pulse_remaining = role_profile.pulse_interval
	if role_profile.heal_amount > 0.0:
		_heal_nearby_allies()
	if not is_instance_valid(Global.player):
		return
	var player_distance := global_position.distance_to(Global.player.global_position)
	if player_distance <= role_profile.effect_radius:
		if role_profile.hazard_damage > 0.0:
			Global.player.health_component.take_damage(role_profile.hazard_damage)
		if role_profile.material_steal > 0:
			Global.try_spend_materials(role_profile.material_steal)
		if role_profile.slow_multiplier < 1.0:
			Global.player.apply_enemy_slow(role_profile.slow_multiplier, role_profile.pulse_interval)
	if role_profile.can_spawn_reinforcements and reinforcements_spawned < 2:
		reinforcements_spawned += 1
		reinforcement_requested.emit(self)
	if role_profile.ambush_distance > 0.0 and is_instance_valid(Global.player):
		var side := -1.0 if global_position.x > Global.player.global_position.x else 1.0
		global_position = Global.player.global_position + Vector2(side * role_profile.ambush_distance, -80.0)
		GameplayCues.emit_cue(&"enemy.telegraph", {
			"presentation_id": definition.get_presentation_id(Content.catalog.pack_id) if definition != null else &"",
			"world_position": global_position,
			"shape": &"ambush",
		})


func _heal_nearby_allies() -> void:
	var radius_squared := role_profile.effect_radius * role_profile.effect_radius
	for member_ref: WeakRef in _flock_members.values():
		var ally := member_ref.get_ref() as Enemy
		if ally == null or ally == self or not ally.is_inside_tree():
			continue
		if global_position.distance_squared_to(ally.global_position) <= radius_squared:
			ally.health_component.heal(role_profile.heal_amount)


static func _flock_cell(world_position: Vector2) -> Vector2i:
	return Vector2i(
		floori(world_position.x / FLOCK_CELL_SIZE),
		floori(world_position.y / FLOCK_CELL_SIZE)
	)


static func _rebuild_flock_grid() -> void:
	var physics_frame := Engine.get_physics_frames()
	if _flock_cache_frame == physics_frame:
		return
	_flock_cache_frame = physics_frame
	_flock_cells.clear()
	for instance_id: int in _flock_members.keys():
		var member_ref := _flock_members[instance_id] as WeakRef
		var member := member_ref.get_ref() as Enemy if member_ref != null else null
		if not is_instance_valid(member) or not member.is_inside_tree():
			_flock_members.erase(instance_id)
			continue
		var cell := _flock_cell(member.global_position)
		if not _flock_cells.has(cell):
			_flock_cells[cell] = []
		var members: Array = _flock_cells[cell]
		members.append(member)


func update_rotation() -> void:
	if not is_instance_valid(Global.player):
		return
	
	var player_pos := Global.player.global_position
	var moving_right := global_position.x < player_pos.x
	visuals.scale = Vector2(-0.5, 0.5) if moving_right else Vector2(0.5, 0.5)


func can_move_towards_player() -> bool:
	return is_instance_valid(Global.player) and\
	global_position.distance_to(Global.player.global_position) > 60  


func apply_knockback(knock_dir: Vector2, knock_power: float) -> void:
	knockback_dir = knock_dir
	knockback_power = knock_power
	if knockback_timer.time_left > 0:
		knockback_timer.stop()
		reset_knockback()
	
	knockback_timer.start()


func reset_knockback() -> void:
	knockback_dir = Vector2.ZERO
	knockback_power = 0.0


func destroy_enemy() -> void:
	can_move = false
	presentation_controller.set_semantic_state(&"death")
	await anim_player.animation_finished
	queue_free()


func _on_knockback_timer_timeout() -> void:
	reset_knockback()


func _on_hurtbox_component_on_damaged(hitbox: HitboxComponent) -> void:
	super._on_hurtbox_component_on_damaged(hitbox)
	
	if hitbox.knockback_power > 0:
		var dir := hitbox.source.global_position.direction_to(global_position)
		apply_knockback(dir, hitbox.knockback_power)


func incoming_damage_multiplier() -> float:
	return role_profile.damage_taken_multiplier


func _on_health_component_on_unit_died() -> void:
	Global.dispatch_gameplay_event(
		GameplayEvent.Type.KILLED, {}, [], kill_credit_source(Global.player), self
	)
	Global.on_enemy_died.emit(self)
