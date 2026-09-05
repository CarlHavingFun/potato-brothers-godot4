class_name GogoWeaponInstance
extends Node2D

const MOVEMENT_COMBAT_RUNTIME := preload("res://game/gameplay/rules/movement_combat_runtime.gd")

signal weapon_fired(
	weapon_instance_id: int,
	feedback_profile_id: StringName,
	integer_muzzle_global_position: Vector2i,
	shot_direction: Vector2,
	projectile_count: int,
	shot_sequence: int
)
signal melee_contact(
	weapon_instance_id: int,
	target_instance_id: int,
	feedback_profile_id: StringName,
	integer_contact_global_position: Vector2i,
	contact_normal: Vector2,
	damage_kind: StringName,
	impact_kind: StringName,
	melee_sequence: int
)

const PROCEDURAL_MUZZLE_LOCAL_POSITION := Vector2(28.0, 0.0)
const MELEE_CONTACT_RADIUS := 14.0
const MELEE_WINDUP_FRACTION := 0.22
const MELEE_ACTIVE_FRACTION := 0.34
const MELEE_MAX_WINDUP_SECONDS := 0.10
const MELEE_MAX_ACTIVE_SECONDS := 0.18
const MELEE_RETURN_SECONDS := 0.20
const MELEE_MAX_CARRIED_OVERSHOOT_SECONDS := 1.0 / 30.0
const MELEE_THRUST_CONTACT_PROGRESS := 0.72
const MELEE_ARC_CONTACT_PROGRESS := 0.46
const MELEE_ATTACK_READABLE_Z_INDEX := 2
const MELEE_TARGET_COLLISION_RADIUS := 14.0
const MELEE_THRUST_HALF_WIDTH := 24.0
const MELEE_ARC_HALF_ANGLE_RADIANS := 1.20
const MELEE_RECOIL_PIXELS := 25.0
const MELEE_SWEEP_ANGLE_RADIANS := 0.9 * PI
const MELEE_MOTION_THRUST: StringName = &"thrust"
const MELEE_MOTION_ARC: StringName = &"arc"
const TRIGGERED_PROJECTILE_SPEED_SCALE := 0.5
const AIM_DETECTION_MARGIN := 200.0
const VALID_FEEDBACK_PROFILES: Array[StringName] = [&"rapid", &"rifle", &"heavy", &"suppressed"]
const RECOIL_PIXELS := {
	&"rapid": 5,
	&"rifle": 25,
	&"heavy": 32,
	&"suppressed": 12,
}
const RECOIL_OUT_SECONDS := 0.10
const RECOIL_RETURN_SECONDS := 0.10
const VISIBLE_LENGTH_RATIOS := {
	&"service_pistol": 0.44, &"suppressed_tactical_pistol": 0.50,
	&"heavy_hand_cannon": 0.52, &"box_submachine_gun": 0.58,
	&"compact_submachine_gun": 0.58, &"bullpup_pdw": 0.62,
	&"folding_stock_submachine_gun": 0.62, &"wood_stock_assault_rifle": 0.72,
	&"suppressed_carbine": 0.72, &"heavy_bolt_sniper": 0.86,
	&"warmup_shiv": 0.52, &"community_tapper": 0.50,
}

enum MeleePhase { READY, WINDUP, ACTIVE, RECOVERY }

var stats: GogoWeaponRuntimeStats
var owner_actor: GogoPlayerActor
var cooldown_remaining := 0.0
var attack_flash := 0.0
var recoil_elapsed := 0.0
var recoil_active := false
var runtime_instance_id := 0
var inventory_instance_id := 0
var shot_sequence := 0
var projectile_sequence := 0
var melee_sequence := 0
var _initial_fire_phase_waiting_for_target := false
var melee_phase := MeleePhase.READY
var melee_phase_elapsed := 0.0
var melee_phase_duration := 0.0
var _melee_windup_seconds := 0.0
var _melee_active_seconds := 0.0
var _melee_recovery_seconds := 0.0
var _melee_target: Node2D
var _melee_attack_direction := Vector2.RIGHT
var _melee_contact_attempted := false
var _melee_hit_target_keys: Dictionary = {}
var _melee_motion_style: StringName = MELEE_MOTION_THRUST
var _melee_contact_alignment := Vector2.ZERO
var _melee_visual_position := Vector2.ZERO
var _melee_visual_rotation := 0.0
var _melee_rest_state_valid := false
var _melee_rest_z_index := 0
var _melee_trail_points := PackedVector2Array()
var static_asset_snapshot_override: GogoStaticAssetSnapshot
var weapon_visual_root: Node2D
var weapon_sprite: Sprite2D
var weapon_visual_handle: GogoStaticAssetHandle
var critical_roll_source: Callable
var _ranged_movement_recoil_multiplier := 1.0
var weapon_art_scale := 1.0
var weapon_opaque_bounds := Rect2i()
var visual_boundary_extent := 0.0


func configure(next_stats: GogoWeaponRuntimeStats, next_owner: GogoPlayerActor) -> void:
	stats = next_stats
	inventory_instance_id = stats.inventory_instance_id if stats != null else 0
	owner_actor = next_owner
	critical_roll_source = Callable()
	cooldown_remaining = 0.0
	attack_flash = 0.0
	recoil_elapsed = 0.0
	recoil_active = false
	runtime_instance_id = 0
	shot_sequence = 0
	projectile_sequence = 0
	melee_sequence = 0
	_ranged_movement_recoil_multiplier = 1.0
	_initial_fire_phase_waiting_for_target = false
	_reset_melee_runtime(true)
	if owner_actor != null and owner_actor.combat_world != null:
		runtime_instance_id = owner_actor.combat_world.allocate_runtime_instance_id(&"weapon")
		owner_actor.combat_world.bind_weapon_feedback(self)
	_build_static_visual()
	_update_visual_feedback()
	queue_redraw()


func _physics_process(delta: float) -> void:
	if (
		owner_actor != null
		and owner_actor.combat_world != null
		and owner_actor.combat_world.is_combat_simulation_frozen()
	):
		return
	if stats == null or owner_actor == null:
		return
	attack_flash = maxf(attack_flash - delta * 6.0, 0.0)
	if recoil_active:
		recoil_elapsed += maxf(delta, 0.0)
		if recoil_elapsed >= RECOIL_OUT_SECONDS + RECOIL_RETURN_SECONDS:
			recoil_elapsed = RECOIL_OUT_SECONDS + RECOIL_RETURN_SECONDS
			recoil_active = false
	_update_visual_feedback()
	if stats.mode == GogoWeaponDefinition.Mode.MELEE:
		_physics_process_melee(maxf(delta, 0.0))
		return
	_physics_process_ranged(delta)


func _physics_process_ranged(delta: float) -> void:
	var target := _nearest_enemy()
	var aim_target := target if target != null else _nearest_enemy_for_aim()
	if aim_target != null:
		_update_ranged_aim(aim_target)
	else:
		_update_idle_aim()
	# Keep a configured multi-weapon opening phase intact until combat actually has
	# a target. Spawn markers can otherwise consume every short phase delay before
	# the first enemy becomes active and recreate a synchronized opening volley.
	if not (_initial_fire_phase_waiting_for_target and target == null):
		cooldown_remaining -= delta
	if target == null:
		# Do not accumulate negative cooldown while there is no valid target;
		# otherwise reacquiring a target could produce an unintended burst.
		if not _initial_fire_phase_waiting_for_target:
			cooldown_remaining = maxf(cooldown_remaining, 0.0)
		queue_redraw()
		return
	_initial_fire_phase_waiting_for_target = false
	var aim_vector: Vector2 = target.global_position - global_position
	if aim_vector.is_zero_approx() or not aim_vector.is_finite():
		aim_vector = target.global_position - _attack_range_origin()
	if aim_vector.is_zero_approx() or not aim_vector.is_finite():
		return
	if cooldown_remaining > 0.0:
		queue_redraw()
		return
	_fire_projectiles(aim_vector.normalized())
	# Preserve the existing cooldown contract even in an isolated test/fallback
	# context where no projectile layer is available.
	var attack_committed := true
	if not attack_committed:
		return
	attack_flash = 1.0
	recoil_elapsed = 0.0
	recoil_active = true
	_update_visual_feedback()
	# Preserve at most one physics-tick of overshoot so sustained fire tracks the
	# authored interval instead of drifting slower, while still forbidding catch-up bursts.
	cooldown_remaining = clampf(cooldown_remaining + stats.cooldown_seconds, 0.0, stats.cooldown_seconds)
	queue_redraw()


func _physics_process_melee(delta: float) -> void:
	_capture_melee_rest_state()
	var nearest := _nearest_enemy()
	var aim_target := nearest if nearest != null else _nearest_enemy_for_aim()
	if melee_phase != MeleePhase.READY:
		if melee_phase == MeleePhase.WINDUP and nearest != null:
			_melee_target = nearest
			_update_melee_aim(_melee_target)
			_update_melee_contact_alignment(_melee_target)
		_advance_melee_cycle(delta)
		queue_redraw()
		return

	if not (_initial_fire_phase_waiting_for_target and nearest == null):
		cooldown_remaining -= delta
	if nearest == null:
		if not _initial_fire_phase_waiting_for_target:
			cooldown_remaining = maxf(cooldown_remaining, 0.0)
		if aim_target != null:
			_update_melee_aim(aim_target)
		else:
			_update_idle_aim()
		_restore_melee_rest_visual()
		queue_redraw()
		return
	_initial_fire_phase_waiting_for_target = false
	_update_melee_aim(nearest)
	_update_visual_feedback()
	if cooldown_remaining > 0.0:
		queue_redraw()
		return
	var cycle_overshoot := maxf(-cooldown_remaining, 0.0)
	_begin_melee_cycle(nearest)
	_advance_melee_cycle(cycle_overshoot)
	queue_redraw()


func _update_ranged_aim(target: Node2D) -> void:
	if target == null or not is_instance_valid(target):
		return
	var aim_vector := target.global_position - global_position
	if aim_vector.is_zero_approx() or not aim_vector.is_finite():
		aim_vector = target.global_position - _attack_range_origin()
	if aim_vector.is_zero_approx() or not aim_vector.is_finite():
		return
	rotation = aim_vector.angle()
	_update_visual_feedback()


func _update_idle_aim() -> void:
	if owner_actor == null or not is_instance_valid(owner_actor):
		return
	rotation = owner_actor.weapon_idle_angle()
	_update_visual_feedback()


func _begin_melee_cycle(target: Node2D) -> void:
	var cycle_seconds := maxf(stats.cooldown_seconds, 0.001)
	var durations := melee_phase_durations(cycle_seconds)
	_melee_windup_seconds = float(durations.windup)
	_melee_active_seconds = float(durations.active)
	_melee_recovery_seconds = float(durations.recovery)
	cooldown_remaining = cycle_seconds
	melee_phase = MeleePhase.WINDUP
	melee_phase_elapsed = 0.0
	melee_phase_duration = _melee_windup_seconds
	_melee_target = target
	_melee_contact_attempted = false
	_melee_hit_target_keys.clear()
	_melee_motion_style = melee_motion_style_for(stats.static_asset_id, stats.definition_id)
	_melee_contact_alignment = Vector2.ZERO
	_melee_trail_points.clear()
	_update_melee_aim(target)
	_update_melee_contact_alignment(target)
	_update_melee_z_index()
	_update_visual_feedback()


func _advance_melee_cycle(delta: float) -> void:
	var remaining := maxf(delta, 0.0)
	var transition_guard := 0
	while melee_phase != MeleePhase.READY and transition_guard < 6:
		transition_guard += 1
		var boundary := maxf(melee_phase_duration - melee_phase_elapsed, 0.0)
		if melee_phase == MeleePhase.ACTIVE and not _melee_contact_attempted:
			var contact_time := melee_phase_duration * _melee_contact_progress()
			if melee_phase_elapsed < contact_time:
				boundary = minf(boundary, contact_time - melee_phase_elapsed)
			else:
				_attempt_melee_contact()
				_update_visual_feedback()
				_record_melee_trail_point()
				continue
		if remaining <= 0.0:
			_update_visual_feedback()
			break
		var step := minf(remaining, boundary)
		if step > 0.0:
			melee_phase_elapsed += step
			cooldown_remaining -= step
			remaining -= step
			_update_visual_feedback()
			if melee_phase == MeleePhase.ACTIVE:
				_record_melee_trail_point()
		if melee_phase == MeleePhase.ACTIVE and not _melee_contact_attempted:
			var contact_time := melee_phase_duration * _melee_contact_progress()
			if melee_phase_elapsed + 0.000001 >= contact_time:
				_attempt_melee_contact()
				_update_visual_feedback()
				_record_melee_trail_point()
		if melee_phase_elapsed + 0.000001 < melee_phase_duration:
			if remaining > 0.0:
				continue
			break
		match melee_phase:
			MeleePhase.WINDUP:
				melee_phase = MeleePhase.ACTIVE
				melee_phase_elapsed = 0.0
				melee_phase_duration = _melee_active_seconds
				_update_visual_feedback()
				_record_melee_trail_point()
			MeleePhase.ACTIVE:
				if not _melee_contact_attempted:
					_attempt_melee_contact()
				melee_phase = MeleePhase.RECOVERY
				melee_phase_elapsed = 0.0
				melee_phase_duration = _melee_recovery_seconds
				_update_visual_feedback()
			MeleePhase.RECOVERY:
				_finish_melee_cycle(remaining)
				remaining = 0.0
			_:
				_finish_melee_cycle(remaining)
				remaining = 0.0
	queue_redraw()


func _attempt_melee_contact() -> void:
	if _melee_contact_attempted:
		return
	_melee_contact_attempted = true
	var primary_target := _valid_melee_contact_target(_melee_target)
	if primary_target == null:
		primary_target = _valid_melee_contact_target(_nearest_enemy())
	if primary_target == null:
		return
	_melee_target = primary_target
	_update_melee_aim(primary_target)
	_update_melee_contact_alignment(primary_target)
	_update_melee_z_index()
	_update_visual_feedback()
	var attack_origin := _attack_range_origin()
	var hit_any_target := false
	for target in _melee_contact_target_snapshot(primary_target):
		if not _melee_hitbox_contains_target(target, attack_origin):
			continue
		var target_key := _melee_target_key(target)
		if _melee_hit_target_keys.has(target_key):
			continue
		# Claim before damage: a damage callback may unregister or otherwise mutate
		# the target while this stable snapshot is still being traversed.
		_melee_hit_target_keys[target_key] = true
		var to_target := target.global_position - attack_origin
		if to_target.is_zero_approx() or not to_target.is_finite():
			to_target = _melee_attack_direction
		if _commit_melee_contact(target, to_target):
			hit_any_target = true
	if hit_any_target:
		attack_flash = 1.0


func _melee_contact_target_snapshot(primary_target: Node2D) -> Array[Node2D]:
	var snapshot: Array[Node2D] = []
	var included: Dictionary = {}
	var primary_key := _melee_target_key(primary_target)
	snapshot.append(primary_target)
	included[primary_key] = true
	var world := owner_actor.combat_world if owner_actor != null else null
	if world != null:
		# Copy before applying damage. Lethal commits unregister enemies and mutate
		# the world's active array, which must not skip the following candidate.
		for index in range(world.active_enemy_count()):
			var enemy := world.active_enemy_at(index)
			var candidate := _valid_melee_contact_target(enemy)
			if candidate == null:
				continue
			var key := _melee_target_key(candidate)
			if included.has(key):
				continue
			included[key] = true
			snapshot.append(candidate)
		return snapshot
	for node in get_tree().get_nodes_in_group(&"gogo_enemy"):
		var candidate := node as Node2D
		candidate = _valid_melee_contact_target(candidate)
		if candidate == null:
			continue
		var key := _melee_target_key(candidate)
		if included.has(key):
			continue
		included[key] = true
		snapshot.append(candidate)
	return snapshot


func _melee_hitbox_contains_target(target: Node2D, attack_origin: Vector2) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	var direction := _melee_attack_direction.normalized()
	if direction.is_zero_approx() or not direction.is_finite():
		return false
	var offset := target.global_position - attack_origin
	if not offset.is_finite():
		return false
	var maximum_range := maxf(stats.attack_range, 0.0)
	if offset.length_squared() > maximum_range * maximum_range:
		return false
	var forward := offset.dot(direction)
	var lateral := absf(offset.cross(direction))
	if _melee_motion_style == MELEE_MOTION_ARC:
		if forward < -MELEE_TARGET_COLLISION_RADIUS:
			return false
		var arc_half_width := (
			maxf(forward, 0.0) * tan(MELEE_ARC_HALF_ANGLE_RADIANS)
			+ MELEE_TARGET_COLLISION_RADIUS
		)
		return lateral <= arc_half_width
	return (
		forward >= -MELEE_TARGET_COLLISION_RADIUS
		and forward <= maximum_range
		and lateral <= MELEE_THRUST_HALF_WIDTH + MELEE_TARGET_COLLISION_RADIUS
	)


func _melee_target_key(target: Node2D) -> StringName:
	if target is GogoEnemyActor:
		var runtime_id := (target as GogoEnemyActor).runtime_instance_id
		if runtime_id > 0:
			return StringName("runtime/%d" % runtime_id)
	return StringName("instance/%d" % target.get_instance_id())


func _valid_melee_contact_target(candidate: Variant) -> Node2D:
	if candidate == null:
		return null
	if not is_instance_valid(candidate):
		return null
	if not candidate is Node2D:
		return null
	var target := candidate as Node2D
	if target.is_queued_for_deletion():
		return null
	if _attack_range_origin().distance_squared_to(target.global_position) > stats.attack_range * stats.attack_range:
		return null
	if target is GogoEnemyActor:
		var enemy := target as GogoEnemyActor
		if enemy.defeated_once or not enemy.can_receive_weapon_contact():
			return null
		if owner_actor != null and owner_actor.combat_world != null:
			return enemy if owner_actor.combat_world.is_active_enemy(enemy) else null
	return target


func _update_melee_aim(target: Node2D) -> void:
	if target == null or not is_instance_valid(target):
		return
	var attack_vector := target.global_position - _attack_range_origin()
	var aim_vector := target.global_position - global_position
	if aim_vector.is_zero_approx() or not aim_vector.is_finite():
		aim_vector = attack_vector
	if aim_vector.is_zero_approx() or not aim_vector.is_finite():
		return
	rotation = aim_vector.angle()
	if not attack_vector.is_zero_approx() and attack_vector.is_finite():
		_melee_attack_direction = attack_vector.normalized()


func _update_melee_contact_alignment(target: Node2D) -> void:
	if target == null or not is_instance_valid(target):
		return
	var to_target := target.global_position - _attack_range_origin()
	if to_target.is_zero_approx() or not to_target.is_finite():
		to_target = _melee_attack_direction
	if to_target.is_zero_approx() or not to_target.is_finite():
		return
	var contact_normal := (global_position - target.global_position).normalized()
	if contact_normal.is_zero_approx() or not contact_normal.is_finite():
		contact_normal = -to_target.normalized()
	var desired_global := target.global_position + contact_normal * MELEE_CONTACT_RADIUS
	var desired_local := to_local(desired_global)
	var contact_pose := _melee_contact_pose_without_alignment()
	var anchor := _melee_contact_anchor_local()
	anchor.y *= _visual_facing_y()
	var pose_contact := (
		anchor.rotated(float(contact_pose.rotation))
		+ contact_pose.position as Vector2
	)
	_melee_contact_alignment = desired_local - pose_contact


func _finish_melee_cycle(overshoot_seconds: float) -> void:
	melee_phase = MeleePhase.READY
	melee_phase_elapsed = 0.0
	melee_phase_duration = 0.0
	cooldown_remaining = -minf(
		maxf(overshoot_seconds, 0.0),
		MELEE_MAX_CARRIED_OVERSHOOT_SECONDS
	)
	_melee_target = null
	_melee_contact_attempted = false
	_melee_hit_target_keys.clear()
	_melee_contact_alignment = Vector2.ZERO
	_melee_trail_points.clear()
	_restore_melee_rest_visual()


func _reset_melee_runtime(restore_rest: bool) -> void:
	if restore_rest and _melee_rest_state_valid:
		z_index = _melee_rest_z_index
	melee_phase = MeleePhase.READY
	melee_phase_elapsed = 0.0
	melee_phase_duration = 0.0
	_melee_windup_seconds = 0.0
	_melee_active_seconds = 0.0
	_melee_recovery_seconds = 0.0
	_melee_target = null
	_melee_attack_direction = Vector2.RIGHT
	_melee_contact_attempted = false
	_melee_hit_target_keys.clear()
	_melee_motion_style = MELEE_MOTION_THRUST
	_melee_contact_alignment = Vector2.ZERO
	_melee_visual_position = Vector2.ZERO
	_melee_visual_rotation = 0.0
	_melee_rest_state_valid = false
	_melee_rest_z_index = 0
	_melee_trail_points.clear()


func _capture_melee_rest_state() -> void:
	if _melee_rest_state_valid:
		return
	_melee_rest_state_valid = true
	_melee_rest_z_index = z_index


func _restore_melee_rest_visual() -> void:
	_melee_visual_position = Vector2.ZERO
	_melee_visual_rotation = 0.0
	if _melee_rest_state_valid:
		z_index = _melee_rest_z_index
	_update_visual_feedback()


func _update_melee_z_index() -> void:
	# Preserve the orbit's front/back read while resting and winding up, then lift
	# the committed strike above enemies. An upper weapon otherwise disappears
	# completely behind the target exactly when the player needs to read contact.
	if (
		melee_phase == MeleePhase.ACTIVE
		or (
			melee_phase == MeleePhase.RECOVERY
			and _melee_recovery_return_progress() < 1.0
		)
	):
		z_index = MELEE_ATTACK_READABLE_Z_INDEX
		return
	if melee_phase == MeleePhase.READY and _melee_rest_state_valid:
		z_index = _melee_rest_z_index
		return
	z_index = -1 if _melee_attack_direction.y < -0.05 else 1


static func melee_phase_durations(cooldown_seconds: float) -> Dictionary:
	var cycle := maxf(cooldown_seconds, 0.001)
	var windup := minf(cycle * MELEE_WINDUP_FRACTION, MELEE_MAX_WINDUP_SECONDS)
	var active := minf(cycle * MELEE_ACTIVE_FRACTION, MELEE_MAX_ACTIVE_SECONDS)
	var recovery := maxf(cycle - windup - active, 0.0)
	return {&"windup": windup, &"active": active, &"recovery": recovery}


static func melee_motion_style_for(
	static_asset_id: StringName,
	definition_id: StringName = &""
) -> StringName:
	var identity := (String(static_asset_id) + " " + String(definition_id)).to_lower()
	if identity.contains("community_tapper") or identity.contains("karambit") or identity.contains("claw"):
		return MELEE_MOTION_ARC
	if (
		identity.contains("shiv")
		or identity.contains("bayonet")
		or identity.contains("dagger")
		or identity.contains("spear")
		or identity.contains("rapier")
	):
		return MELEE_MOTION_THRUST
	return MELEE_MOTION_THRUST


func debug_melee_phase_name() -> StringName:
	match melee_phase:
		MeleePhase.WINDUP:
			return &"windup"
		MeleePhase.ACTIVE:
			return &"active"
		MeleePhase.RECOVERY:
			return &"recovery"
		_:
			return &"ready"


func debug_melee_phase_progress() -> float:
	if melee_phase_duration <= 0.0:
		return 0.0
	return clampf(melee_phase_elapsed / melee_phase_duration, 0.0, 1.0)


func debug_melee_motion_style() -> StringName:
	return _melee_motion_style


func debug_melee_seconds_until_contact() -> float:
	if stats == null or stats.mode != GogoWeaponDefinition.Mode.MELEE:
		return 0.0
	var durations := melee_phase_durations(stats.cooldown_seconds)
	var style := melee_motion_style_for(stats.static_asset_id, stats.definition_id)
	var contact_progress := (
		MELEE_ARC_CONTACT_PROGRESS
		if style == MELEE_MOTION_ARC
		else MELEE_THRUST_CONTACT_PROGRESS
	)
	return float(durations.windup) + float(durations.active) * contact_progress


func debug_melee_contact_global_position() -> Vector2:
	return _visible_melee_contact_global_position()


func set_initial_fire_phase(slot_index: int, slot_count: int) -> void:
	_reset_melee_runtime(true)
	cooldown_remaining = initial_fire_phase_delay(
		stats.cooldown_seconds if stats != null else 0.0,
		slot_index,
		slot_count
	)
	_initial_fire_phase_waiting_for_target = cooldown_remaining > 0.0


func set_critical_roll_source(source: Callable) -> void:
	critical_roll_source = source


func _roll_critical_hit() -> bool:
	if stats == null or stats.critical_chance <= 0.0:
		return false
	if stats.critical_chance >= 1.0:
		return true
	var roll := 1.0
	if critical_roll_source.is_valid():
		roll = float(critical_roll_source.call())
	elif owner_actor != null and owner_actor.session != null:
		roll = owner_actor.session.rng.randf()
	return GogoCombatStatRuntime.is_critical_roll(stats.critical_chance, roll)


static func _impact_kind_for_hit(base_impact_kind: StringName, is_critical: bool) -> StringName:
	if is_critical and base_impact_kind == &"normal":
		return &"critical"
	return base_impact_kind


static func initial_fire_phase_delay(
	cooldown_seconds: float,
	slot_index: int,
	slot_count: int
) -> float:
	if cooldown_seconds <= 0.0 or slot_count <= 1 or slot_index <= 0:
		return 0.0
	var stable_slot_index := mini(slot_index, slot_count - 1)
	return cooldown_seconds * float(stable_slot_index) / float(slot_count)


func _commit_melee_contact(target: Node2D, to_target: Vector2) -> bool:
	if target == null or to_target.is_zero_approx() or not to_target.is_finite():
		return false
	var impulse := to_target.normalized() * stats.knockback
	var rolled_critical := stats.impact_kind != &"critical" and _roll_critical_hit()
	var is_critical := stats.impact_kind == &"critical" or rolled_critical
	var contact_impact_kind := _impact_kind_for_hit(stats.impact_kind, rolled_critical)
	var contact_damage := GogoCombatStatRuntime.damage_after_combat_stats(
		stats.damage,
		is_critical,
		stats.impact_kind == &"explosion",
		stats.explosion_damage_multiplier
	)
	if target is GogoEnemyActor:
		var enemy := target as GogoEnemyActor
		var world := owner_actor.combat_world if owner_actor != null else null
		if (
			world != null
			and runtime_instance_id > 0
			and enemy.runtime_instance_id > 0
			and world.is_active_enemy(enemy)
			and VALID_FEEDBACK_PROFILES.has(stats.feedback_profile_id)
		):
			var reservation_id := enemy._reserve_weapon_damage(contact_damage, impulse)
			if reservation_id <= 0:
				return false
			melee_sequence += 1
			var contact_normal := (global_position - enemy.global_position).normalized()
			if contact_normal.is_zero_approx() or not contact_normal.is_finite():
				contact_normal = -to_target.normalized()
			# Every target receives feedback on its own near edge. The visual contact
			# anchor is aligned to this same point for the primary target, while nearby
			# secondary targets no longer stack all effects at the primary blade tip.
			var contact_position := Vector2i((
				enemy.global_position + contact_normal * MELEE_CONTACT_RADIUS
			).round())
			melee_contact.emit(
				runtime_instance_id,
				enemy.runtime_instance_id,
				stats.feedback_profile_id,
				contact_position,
				contact_normal,
				stats.damage_kind,
				contact_impact_kind,
				melee_sequence
			)
			return enemy._commit_reserved_weapon_damage(reservation_id)
		return enemy.take_damage(contact_damage, impulse)
	if target.has_method(&"take_damage"):
		return bool(target.call(&"take_damage", contact_damage, impulse))
	return false


func _nearest_enemy() -> Node2D:
	var attack_origin := _attack_range_origin()
	if owner_actor != null and owner_actor.combat_world != null:
		return owner_actor.combat_world.nearest_active_enemy(attack_origin, stats.attack_range)
	var best: Node2D
	var best_distance := INF
	for candidate in get_tree().get_nodes_in_group(&"gogo_enemy"):
		if not is_instance_valid(candidate):
			continue
		if candidate is GogoEnemyActor and (candidate as GogoEnemyActor).defeated_once:
			continue
		var distance := attack_origin.distance_squared_to(candidate.global_position)
		if distance < best_distance and distance <= stats.attack_range * stats.attack_range:
			best = candidate
			best_distance = distance
	return best


func _nearest_enemy_for_aim() -> Node2D:
	var attack_origin := _attack_range_origin()
	var detection_range := maxf(stats.attack_range, 0.0) + AIM_DETECTION_MARGIN
	if owner_actor != null and owner_actor.combat_world != null:
		return owner_actor.combat_world.nearest_active_enemy(attack_origin, detection_range)
	var best: Node2D
	var best_distance := INF
	var detection_range_squared := detection_range * detection_range
	for candidate in get_tree().get_nodes_in_group(&"gogo_enemy"):
		if not is_instance_valid(candidate):
			continue
		if candidate is GogoEnemyActor and (candidate as GogoEnemyActor).defeated_once:
			continue
		var distance := attack_origin.distance_squared_to(candidate.global_position)
		if distance < best_distance and distance <= detection_range_squared:
			best = candidate
			best_distance = distance
	return best


func _attack_range_origin() -> Vector2:
	# Weapon sockets are presentation geometry. Keep range, target acquisition, and
	# melee knockback centered on the player so a right-side visual socket cannot
	# make equal-distance enemies behave differently on opposite sides.
	if owner_actor != null and is_instance_valid(owner_actor):
		return owner_actor.global_position
	return global_position


func _fire_projectiles(base_direction: Vector2) -> int:
	var world := owner_actor.combat_world
	if world == null or world.projectile_layer == null or not base_direction.is_finite() or base_direction.is_zero_approx():
		return 0
	var normalized_direction := base_direction.normalized()
	var moving_recoil_control := 0.0
	if owner_actor.player_state != null:
		moving_recoil_control = float(owner_actor.player_state.final_stats.get(
			&"moving_recoil_control",
			0.0
		))
	var movement_penalty := MOVEMENT_COMBAT_RUNTIME.ranged_movement_penalty(
		owner_actor.velocity,
		moving_recoil_control
	)
	var movement_spread_degrees := float(movement_penalty.get(&"spread_degrees", 0.0))
	_ranged_movement_recoil_multiplier = float(movement_penalty.get(&"recoil_multiplier", 1.0))
	var muzzle_position := Vector2i(integer_muzzle_global_position())
	var next_shot_sequence := shot_sequence + 1
	var actual_projectile_count := 0
	for index in stats.projectile_count:
		var projectile := GogoProjectile.new()
		var rolled_critical := stats.impact_kind != &"critical" and _roll_critical_hit()
		var projectile_impact_kind := _impact_kind_for_hit(stats.impact_kind, rolled_critical)
		var offset := float(index) - float(stats.projectile_count - 1) * 0.5
		var movement_offset := offset * movement_spread_degrees
		if stats.projectile_count == 1:
			movement_offset = movement_spread_degrees * (-0.5 if next_shot_sequence % 2 else 0.5)
		projectile.direction = normalized_direction.rotated(
			deg_to_rad(offset * stats.spread_degrees + movement_offset)
		).normalized()
		projectile.speed = stats.projectile_speed
		projectile.damage = stats.damage
		projectile.knockback = stats.knockback
		projectile_sequence += 1
		projectile.activate(
			world,
			world.allocate_runtime_instance_id(&"projectile"),
			runtime_instance_id,
			next_shot_sequence,
			projectile_sequence,
			stats.feedback_profile_id,
			stats.damage_kind,
			projectile_impact_kind,
			&"",
			rolled_critical,
			stats.explosion_damage_multiplier
		)
		world.bind_projectile_feedback(projectile)
		world.projectile_layer.add_child(projectile)
		projectile.launch_from(global_position, Vector2(muzzle_position))
		actual_projectile_count += 1
	if (
		actual_projectile_count > 0
		and runtime_instance_id > 0
		and VALID_FEEDBACK_PROFILES.has(stats.feedback_profile_id)
	):
		shot_sequence = next_shot_sequence
		weapon_fired.emit(
			runtime_instance_id,
			stats.feedback_profile_id,
			muzzle_position,
			normalized_direction,
			actual_projectile_count,
			shot_sequence
		)
		_spawn_item_triggered_projectiles(
			world,
			muzzle_position,
			normalized_direction,
			shot_sequence
		)
	return actual_projectile_count


func _spawn_item_triggered_projectiles(
	world: CombatWorld,
	muzzle_position: Vector2i,
	direction: Vector2,
	current_shot_sequence: int
) -> void:
	if world == null or stats == null or runtime_instance_id <= 0:
		return
	for event: Dictionary in world.note_ranged_attack(runtime_instance_id):
		var impact_kind := StringName(event.get("impact_kind", &""))
		var source_item_id := StringName(event.get("source_item_id", &""))
		var damage_scale := float(event.get("damage_scale", 0.0))
		if impact_kind != &"explosion" or source_item_id.is_empty() or damage_scale <= 0.0:
			continue
		var projectile := GogoProjectile.new()
		var rolled_critical := _roll_critical_hit()
		projectile.direction = direction
		projectile.speed = maxf(stats.projectile_speed * TRIGGERED_PROJECTILE_SPEED_SCALE, 1.0)
		projectile.damage = stats.damage * damage_scale
		projectile.knockback = stats.knockback
		projectile_sequence += 1
		projectile.activate(
			world,
			world.allocate_runtime_instance_id(&"projectile"),
			runtime_instance_id,
			current_shot_sequence,
			projectile_sequence,
			stats.feedback_profile_id,
			stats.damage_kind,
			impact_kind,
			source_item_id,
			rolled_critical,
			stats.explosion_damage_multiplier
		)
		world.bind_projectile_feedback(projectile)
		world.projectile_layer.add_child(projectile)
		projectile.launch_from(global_position, Vector2(muzzle_position))


func integer_muzzle_global_position() -> Vector2:
	return to_global(_visible_muzzle_local_position()).round()


func _build_static_visual() -> void:
	if weapon_visual_root != null and is_instance_valid(weapon_visual_root):
		weapon_visual_root.free()
	weapon_visual_root = null
	weapon_sprite = null
	weapon_visual_handle = null
	weapon_art_scale = 1.0
	weapon_opaque_bounds = Rect2i()
	visual_boundary_extent = 0.0
	if stats == null or stats.static_asset_id.is_empty():
		return
	var snapshot := static_asset_snapshot_override
	if snapshot == null and owner_actor != null and owner_actor.session != null:
		snapshot = owner_actor.session.static_asset_snapshot
	if snapshot == null:
		return
	weapon_visual_handle = snapshot.resolve_asset(stats.static_asset_id, &"world_sprite")
	if weapon_visual_handle == null or weapon_visual_handle.texture == null:
		weapon_visual_handle = null
		return
	_cache_visual_geometry()
	weapon_visual_root = Node2D.new()
	weapon_visual_root.name = "WeaponVisualRoot"
	add_child(weapon_visual_root)
	weapon_sprite = Sprite2D.new()
	weapon_sprite.name = "WeaponSprite"
	weapon_sprite.centered = false
	weapon_sprite.texture = weapon_visual_handle.texture
	weapon_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	weapon_sprite.scale = Vector2.ONE * weapon_art_scale
	weapon_sprite.position = -Vector2(weapon_visual_handle.pivot_px) * weapon_art_scale
	weapon_visual_root.add_child(weapon_sprite)
	GogoStaticConsumerRegistry.observe_handle(
		weapon_visual_handle,
		"res://game/gameplay/weapons/weapon_instance.gd",
		"WeaponVisualRoot/WeaponSprite/%s" % String(stats.static_asset_id)
	)


func _cache_visual_geometry() -> void:
	# Texture alpha readback is build-time only, never in the physics loop.
	var image := weapon_visual_handle.texture.get_image()
	if image != null:
		weapon_opaque_bounds = image.get_used_rect()
	var longest := maxi(weapon_opaque_bounds.size.x, weapon_opaque_bounds.size.y)
	if owner_actor != null and owner_actor.weapon_reference_visible_height > 0.0 and longest > 0 and VISIBLE_LENGTH_RATIOS.has(stats.static_asset_id):
		weapon_art_scale = owner_actor.weapon_reference_visible_height * float(VISIBLE_LENGTH_RATIOS[stats.static_asset_id]) / float(longest)
	var bounds := Rect2(weapon_opaque_bounds)
	if not bounds.has_area():
		bounds = Rect2(Vector2.ZERO, Vector2(weapon_visual_handle.display_size_px))
	var pivot := Vector2(weapon_visual_handle.pivot_px)
	var source_points: Array[Vector2] = [bounds.position, Vector2(bounds.end.x,bounds.position.y), bounds.end, Vector2(bounds.position.x,bounds.end.y)]
	var muzzle: Variant = weapon_visual_handle.anchors_px.get("muzzle")
	if muzzle is Vector2i: source_points.append(Vector2(muzzle))
	# The movement penalty asymptote is finite; use its upper bound without
	# modifying actual-speed response, recoil timing or per-profile translation.
	var max_recoil := ceilf(float(RECOIL_PIXELS.get(stats.feedback_profile_id,25)) * (1.0 + MOVEMENT_COMBAT_RUNTIME.MOVEMENT_RECOIL_MULTIPLIER_AT_REFERENCE * MOVEMENT_COMBAT_RUNTIME.MAX_ASYMPTOTIC_SPEED_RATIO))
	if stats.mode == GogoWeaponDefinition.Mode.MELEE: max_recoil = MELEE_RECOIL_PIXELS
	for point in source_points:
		var delta := (point - pivot) * weapon_art_scale
		visual_boundary_extent = maxf(visual_boundary_extent, maxf(delta.length(), (delta - Vector2(max_recoil,0)).length()))
	# A rounded spawn can move sqrt(0.5)px; retain the real projectile radius.
	visual_boundary_extent += GogoProjectile.PROJECTILE_RADIUS + 0.75


func _update_visual_feedback() -> void:
	if stats != null and stats.mode == GogoWeaponDefinition.Mode.MELEE:
		_update_melee_visual_pose()
		_update_melee_z_index()
		if weapon_visual_root != null and is_instance_valid(weapon_visual_root):
			weapon_visual_root.position = _melee_visual_position
			weapon_visual_root.rotation = _melee_visual_rotation
			weapon_visual_root.scale = Vector2(1.0, _visual_facing_y())
			if weapon_sprite != null:
				weapon_sprite.modulate = Color.WHITE
		return
	if weapon_visual_root == null or not is_instance_valid(weapon_visual_root):
		return
	var recoil_max := int(RECOIL_PIXELS.get(stats.feedback_profile_id, 25)) if stats != null else 25
	var recoil := roundi(
		float(recoil_max) * _ranged_movement_recoil_multiplier * _ranged_recoil_factor()
	)
	weapon_visual_root.position = Vector2(-recoil, 0.0)
	weapon_visual_root.rotation = 0.0
	weapon_visual_root.scale = Vector2(1.0, _visual_facing_y())
	if weapon_sprite != null:
		var brightness := 1.0 + 0.45 * attack_flash
		weapon_sprite.modulate = Color(brightness, brightness, brightness, 1.0)


func _ranged_recoil_factor() -> float:
	if not recoil_active:
		# Keep direct feedback-preview tooling compatible: setting attack_flash without
		# starting a shot still previews the peak recoil pose.
		return clampf(attack_flash, 0.0, 1.0)
	if recoil_elapsed <= RECOIL_OUT_SECONDS:
		var out_t := recoil_elapsed / RECOIL_OUT_SECONDS
		return 1.0 - pow(1.0 - clampf(out_t, 0.0, 1.0), 3.0)
	var return_t := (
		(recoil_elapsed - RECOIL_OUT_SECONDS)
		/ RECOIL_RETURN_SECONDS
	)
	return pow(1.0 - clampf(return_t, 0.0, 1.0), 3.0)


func _visible_muzzle_local_position() -> Vector2:
	if weapon_visual_handle == null:
		return PROCEDURAL_MUZZLE_LOCAL_POSITION
	var muzzle_variant: Variant = weapon_visual_handle.anchors_px.get("muzzle")
	if not muzzle_variant is Vector2i:
		return PROCEDURAL_MUZZLE_LOCAL_POSITION
	var muzzle := (Vector2(muzzle_variant as Vector2i) - Vector2(weapon_visual_handle.pivot_px)) * weapon_art_scale
	muzzle.y *= _visual_facing_y()
	if weapon_visual_root != null and is_instance_valid(weapon_visual_root):
		muzzle += weapon_visual_root.position
	return muzzle


func _update_melee_visual_pose() -> void:
	var pose := _melee_pose(melee_phase, debug_melee_phase_progress(), _melee_motion_style)
	var alignment_weight := 0.0
	match melee_phase:
		MeleePhase.WINDUP:
			alignment_weight = 0.0
		MeleePhase.ACTIVE:
			alignment_weight = _smoothstep01(
				debug_melee_phase_progress() / maxf(_melee_contact_progress(), 0.001)
			)
		MeleePhase.RECOVERY:
			alignment_weight = 1.0 - _melee_recovery_return_progress()
	_melee_visual_position = (pose.position as Vector2) + _melee_contact_alignment * alignment_weight
	_melee_visual_rotation = float(pose.rotation)


func _melee_pose(phase: int, progress: float, motion_style: StringName) -> Dictionary:
	var t := clampf(progress, 0.0, 1.0)
	if phase == MeleePhase.READY:
		return {&"position": Vector2.ZERO, &"rotation": 0.0}
	if motion_style == MELEE_MOTION_ARC:
		var side_range := minf(maxf(stats.attack_range, 0.0) * 0.35, 42.0)
		var forward_range := minf(maxf(stats.attack_range, 0.0) * 0.30, 36.0)
		match phase:
			MeleePhase.WINDUP:
				var eased := _smoothstep01(t)
				return {
					&"position": Vector2(-MELEE_RECOIL_PIXELS, -side_range) * eased,
					&"rotation": lerpf(0.0, -MELEE_SWEEP_ANGLE_RADIANS, eased),
				}
			MeleePhase.ACTIVE:
				var eased := _smoothstep01(t)
				return {
					&"position": Vector2(-MELEE_RECOIL_PIXELS, -side_range).lerp(
						Vector2(forward_range, side_range), eased
					),
					&"rotation": lerpf(
						-MELEE_SWEEP_ANGLE_RADIANS,
						MELEE_SWEEP_ANGLE_RADIANS,
						eased
					),
				}
			MeleePhase.RECOVERY:
				var returned := _melee_recovery_return_progress()
				return {
					&"position": Vector2(forward_range, side_range).lerp(Vector2.ZERO, returned),
					&"rotation": lerpf(MELEE_SWEEP_ANGLE_RADIANS, 0.0, returned),
				}
	else:
		var thrust_range := minf(maxf(stats.attack_range, 0.0), 120.0)
		match phase:
			MeleePhase.WINDUP:
				var eased := _smoothstep01(t)
				return {
					&"position": Vector2(-MELEE_RECOIL_PIXELS * eased, 0.0),
					&"rotation": lerpf(0.0, -0.10, eased),
				}
			MeleePhase.ACTIVE:
				var eased := _smoothstep01(t)
				return {
					&"position": Vector2(lerpf(-MELEE_RECOIL_PIXELS, thrust_range, eased), 0.0),
					&"rotation": lerpf(-0.10, 0.05, eased),
				}
			MeleePhase.RECOVERY:
				var returned := _melee_recovery_return_progress()
				return {
					&"position": Vector2(thrust_range, 0.0).lerp(Vector2.ZERO, returned),
					&"rotation": lerpf(0.05, 0.0, returned),
				}
	return {&"position": Vector2.ZERO, &"rotation": 0.0}


func _melee_contact_pose_without_alignment() -> Dictionary:
	return _melee_pose(
		MeleePhase.ACTIVE,
		_melee_contact_progress(),
		_melee_motion_style
	)


func _melee_contact_progress() -> float:
	return (
		MELEE_ARC_CONTACT_PROGRESS
		if _melee_motion_style == MELEE_MOTION_ARC
		else MELEE_THRUST_CONTACT_PROGRESS
	)


func _melee_recovery_return_progress() -> float:
	if melee_phase != MeleePhase.RECOVERY or melee_phase_duration <= 0.0:
		return 0.0
	var return_seconds := minf(MELEE_RETURN_SECONDS, melee_phase_duration)
	if return_seconds <= 0.0:
		return 1.0
	return _smoothstep01(melee_phase_elapsed / return_seconds)


func _melee_contact_anchor_local() -> Vector2:
	if weapon_visual_handle != null:
		var contact_variant: Variant = weapon_visual_handle.anchors_px.get("contact")
		if contact_variant is Vector2i:
			return (Vector2(contact_variant as Vector2i) - Vector2(weapon_visual_handle.pivot_px)) * weapon_art_scale
	return PROCEDURAL_MUZZLE_LOCAL_POSITION


func _visible_melee_contact_local_position() -> Vector2:
	var anchor := _melee_contact_anchor_local()
	if weapon_visual_root != null and is_instance_valid(weapon_visual_root):
		return weapon_visual_root.transform * anchor
	anchor.y *= _visual_facing_y()
	return anchor.rotated(_melee_visual_rotation) + _melee_visual_position


func _visible_melee_contact_global_position() -> Vector2:
	return to_global(_visible_melee_contact_local_position())


func _record_melee_trail_point() -> void:
	if melee_phase != MeleePhase.ACTIVE:
		return
	var next_point := _visible_melee_contact_local_position().round()
	if not _melee_trail_points.is_empty() and _melee_trail_points[-1].distance_to(next_point) < 1.0:
		return
	_melee_trail_points.append(next_point)
	while _melee_trail_points.size() > 7:
		_melee_trail_points.remove_at(0)


static func _smoothstep01(value: float) -> float:
	var t := clampf(value, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _visual_facing_y() -> float:
	return -1.0 if cos(rotation) < 0.0 else 1.0


func _draw() -> void:
	if stats != null and stats.mode == GogoWeaponDefinition.Mode.MELEE:
		_draw_melee_trail()
	if weapon_sprite != null:
		return
	var color := Color("f27d42") if stats != null and stats.mode == GogoWeaponDefinition.Mode.MELEE else Color("70b8ff")
	if attack_flash > 0.0 and (stats == null or stats.mode != GogoWeaponDefinition.Mode.MELEE):
		color = Color.WHITE
	if stats != null and stats.mode == GogoWeaponDefinition.Mode.MELEE:
		draw_set_transform(
			_melee_visual_position,
			_melee_visual_rotation,
			Vector2(1.0, _visual_facing_y())
		)
	draw_line(Vector2.ZERO, PROCEDURAL_MUZZLE_LOCAL_POSITION, color, 7.0, false)
	draw_circle(PROCEDURAL_MUZZLE_LOCAL_POSITION, 5.0, color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_melee_trail() -> void:
	if _melee_trail_points.size() < 2:
		return
	var strength := 1.0
	if melee_phase == MeleePhase.RECOVERY:
		strength = 1.0 - _melee_recovery_return_progress()
	if strength <= 0.0:
		return
	var underlay := Color(0.95, 0.20, 0.20, 0.32 * strength)
	var highlight := Color(1.0, 0.88, 0.62, 0.72 * strength)
	draw_polyline(_melee_trail_points, underlay, 7.0, false)
	draw_polyline(_melee_trail_points, highlight, 3.0, false)
