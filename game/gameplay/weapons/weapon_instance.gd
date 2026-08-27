class_name GogoWeaponInstance
extends Node2D

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
const TRIGGERED_PROJECTILE_SPEED_SCALE := 0.5
const VALID_FEEDBACK_PROFILES: Array[StringName] = [&"rapid", &"rifle", &"heavy", &"suppressed"]
const RECOIL_PIXELS := {
	&"rapid": 2,
	&"rifle": 4,
	&"heavy": 6,
	&"suppressed": 2,
}

var stats: GogoWeaponRuntimeStats
var owner_actor: GogoPlayerActor
var cooldown_remaining := 0.0
var attack_flash := 0.0
var runtime_instance_id := 0
var shot_sequence := 0
var projectile_sequence := 0
var melee_sequence := 0
var static_asset_snapshot_override: GogoStaticAssetSnapshot
var weapon_visual_root: Node2D
var weapon_sprite: Sprite2D
var weapon_visual_handle: GogoStaticAssetHandle


func configure(next_stats: GogoWeaponRuntimeStats, next_owner: GogoPlayerActor) -> void:
	stats = next_stats
	owner_actor = next_owner
	cooldown_remaining = 0.0
	attack_flash = 0.0
	runtime_instance_id = 0
	shot_sequence = 0
	projectile_sequence = 0
	melee_sequence = 0
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
	cooldown_remaining -= delta
	attack_flash = maxf(attack_flash - delta * 6.0, 0.0)
	_update_visual_feedback()
	if cooldown_remaining > 0.0:
		queue_redraw()
		return
	var target := _nearest_enemy()
	if target == null:
		# Do not accumulate negative cooldown while there is no valid target;
		# otherwise reacquiring a target could produce an unintended burst.
		cooldown_remaining = 0.0
		return
	var to_target: Vector2 = target.global_position - global_position
	rotation = to_target.angle()
	_update_visual_feedback()
	var attack_committed := false
	if stats.mode == GogoWeaponDefinition.Mode.MELEE:
		if to_target.length() > stats.attack_range:
			return
		attack_committed = _commit_melee_contact(target, to_target)
	else:
		_fire_projectiles(to_target.normalized())
		# Preserve the existing cooldown contract even in an isolated test/fallback
		# context where no projectile layer is available.
		attack_committed = true
	if not attack_committed:
		return
	attack_flash = 1.0
	_update_visual_feedback()
	# Preserve at most one physics-tick of overshoot so sustained fire tracks the
	# authored interval instead of drifting slower, while still forbidding catch-up bursts.
	cooldown_remaining = clampf(cooldown_remaining + stats.cooldown_seconds, 0.0, stats.cooldown_seconds)
	queue_redraw()


func _commit_melee_contact(target: Node2D, to_target: Vector2) -> bool:
	if target == null or to_target.is_zero_approx() or not to_target.is_finite():
		return false
	var impulse := to_target.normalized() * stats.knockback
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
			var reservation_id := enemy._reserve_weapon_damage(stats.damage, impulse)
			if reservation_id <= 0:
				return false
			melee_sequence += 1
			var contact_normal := (global_position - enemy.global_position).normalized()
			if contact_normal.is_zero_approx() or not contact_normal.is_finite():
				contact_normal = -to_target.normalized()
			var contact_position := Vector2i((enemy.global_position + contact_normal * MELEE_CONTACT_RADIUS).round())
			melee_contact.emit(
				runtime_instance_id,
				enemy.runtime_instance_id,
				stats.feedback_profile_id,
				contact_position,
				contact_normal,
				stats.damage_kind,
				stats.impact_kind,
				melee_sequence
			)
			return enemy._commit_reserved_weapon_damage(reservation_id)
		return enemy.take_damage(stats.damage, impulse)
	if target.has_method(&"take_damage"):
		return bool(target.call(&"take_damage", stats.damage, impulse))
	return false


func _nearest_enemy() -> Node2D:
	if owner_actor != null and owner_actor.combat_world != null:
		return owner_actor.combat_world.nearest_active_enemy(global_position, stats.attack_range)
	var best: Node2D
	var best_distance := INF
	for candidate in get_tree().get_nodes_in_group(&"gogo_enemy"):
		if not is_instance_valid(candidate):
			continue
		if candidate is GogoEnemyActor and (candidate as GogoEnemyActor).defeated_once:
			continue
		var distance := global_position.distance_squared_to(candidate.global_position)
		if distance < best_distance and distance <= stats.attack_range * stats.attack_range:
			best = candidate
			best_distance = distance
	return best


func _fire_projectiles(base_direction: Vector2) -> int:
	var world := owner_actor.combat_world
	if world == null or world.projectile_layer == null or not base_direction.is_finite() or base_direction.is_zero_approx():
		return 0
	var normalized_direction := base_direction.normalized()
	var muzzle_position := Vector2i(integer_muzzle_global_position())
	var next_shot_sequence := shot_sequence + 1
	var actual_projectile_count := 0
	for index in stats.projectile_count:
		var projectile := GogoProjectile.new()
		var offset := float(index) - float(stats.projectile_count - 1) * 0.5
		projectile.direction = normalized_direction.rotated(deg_to_rad(offset * stats.spread_degrees)).normalized()
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
			stats.impact_kind
		)
		world.bind_projectile_feedback(projectile)
		world.projectile_layer.add_child(projectile)
		projectile.global_position = Vector2(muzzle_position)
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
			source_item_id
		)
		world.bind_projectile_feedback(projectile)
		world.projectile_layer.add_child(projectile)
		projectile.global_position = Vector2(muzzle_position)


func integer_muzzle_global_position() -> Vector2:
	return to_global(_visible_muzzle_local_position()).round()


func _build_static_visual() -> void:
	if weapon_visual_root != null and is_instance_valid(weapon_visual_root):
		weapon_visual_root.free()
	weapon_visual_root = null
	weapon_sprite = null
	weapon_visual_handle = null
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
	weapon_visual_root = Node2D.new()
	weapon_visual_root.name = "WeaponVisualRoot"
	add_child(weapon_visual_root)
	weapon_sprite = Sprite2D.new()
	weapon_sprite.name = "WeaponSprite"
	weapon_sprite.centered = false
	weapon_sprite.texture = weapon_visual_handle.texture
	weapon_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	weapon_sprite.position = -Vector2(weapon_visual_handle.pivot_px)
	weapon_visual_root.add_child(weapon_sprite)
	GogoStaticConsumerRegistry.observe_handle(
		weapon_visual_handle,
		"res://game/gameplay/weapons/weapon_instance.gd",
		"WeaponVisualRoot/WeaponSprite/%s" % String(stats.static_asset_id)
	)


func _update_visual_feedback() -> void:
	if weapon_visual_root == null or not is_instance_valid(weapon_visual_root):
		return
	var recoil_max := int(RECOIL_PIXELS.get(stats.feedback_profile_id, 4)) if stats != null else 4
	var recoil := roundi(float(recoil_max) * attack_flash)
	weapon_visual_root.position = Vector2(-recoil, 0.0)
	weapon_visual_root.scale = Vector2(1.0, _visual_facing_y())
	if weapon_sprite != null:
		var brightness := 1.0 + 0.45 * attack_flash
		weapon_sprite.modulate = Color(brightness, brightness, brightness, 1.0)


func _visible_muzzle_local_position() -> Vector2:
	if weapon_visual_handle == null:
		return PROCEDURAL_MUZZLE_LOCAL_POSITION
	var muzzle_variant: Variant = weapon_visual_handle.anchors_px.get("muzzle")
	if not muzzle_variant is Vector2i:
		return PROCEDURAL_MUZZLE_LOCAL_POSITION
	var muzzle := Vector2(muzzle_variant as Vector2i) - Vector2(weapon_visual_handle.pivot_px)
	muzzle.y *= _visual_facing_y()
	if weapon_visual_root != null and is_instance_valid(weapon_visual_root):
		muzzle += weapon_visual_root.position
	return muzzle


func _visual_facing_y() -> float:
	return -1.0 if cos(rotation) < 0.0 else 1.0


func _draw() -> void:
	if weapon_sprite != null:
		return
	var color := Color("f27d42") if stats != null and stats.mode == GogoWeaponDefinition.Mode.MELEE else Color("70b8ff")
	if attack_flash > 0.0:
		color = Color.WHITE
	draw_line(Vector2.ZERO, PROCEDURAL_MUZZLE_LOCAL_POSITION, color, 7.0, false)
	draw_circle(PROCEDURAL_MUZZLE_LOCAL_POSITION, 5.0, color)
