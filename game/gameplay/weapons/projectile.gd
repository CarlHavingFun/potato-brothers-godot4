class_name GogoProjectile
extends Node2D

signal projectile_contact(
	projectile_instance_id: int,
	target_instance_id: int,
	feedback_profile_id: StringName,
	integer_contact_global_position: Vector2i,
	contact_normal: Vector2,
	damage_kind: StringName,
	impact_kind: StringName,
	contact_sequence: int
)

const PROJECTILE_RADIUS := 5.0
const ENEMY_HURT_RADIUS := 14.0
const CONTACT_TIE_EPSILON := 0.000001
const PIERCE_MAX_CONTACTS := 2
const EXPLOSION_RADIUS := 80.0
const SWEEP_CONTINUE_EPSILON := 0.01
const VALID_FEEDBACK_PROFILES: Array[StringName] = [&"rapid", &"rifle", &"heavy", &"suppressed"]
const VALID_IMPACT_KINDS: Array[StringName] = [&"normal", &"critical", &"pierce_exit", &"explosion"]
const PROJECTILE_ASSET_ID: StringName = &"projectile_hit_kit"
const PROJECTILE_ROLE: StringName = &"projectile_sprite"
const SKYLINE_GRENADE_SOURCE_ITEM_ID: StringName = &"gogobro.preview:item/skyline_grenade"
const SKYLINE_GRENADE_ASSET_ID: StringName = &"skyline_grenade"
const TRIGGERED_ITEM_PROJECTILE_SCALE := Vector2(0.5, 0.5)
const FALLBACK_PROJECTILE_VISUAL_RADIUS := 3.0
const PROJECTILE_SELECTORS := {
	&"rapid": &"pistol_smg_round",
	&"rifle": &"rifle_round",
	&"heavy": &"sniper_round",
	&"suppressed": &"pistol_smg_round",
}
const PROJECTILE_VISUAL_SCALES := {
	&"rapid": Vector2(0.1875, 0.1875),
	&"rifle": Vector2(0.25, 0.25),
	&"heavy": Vector2(0.25, 0.25),
	&"suppressed": Vector2(0.1875, 0.1875),
}

var direction := Vector2.RIGHT
var speed := 500.0
var damage := 1.0
var knockback := 0.0
var lifetime := 1.5
var combat_world: CombatWorld
var runtime_instance_id := 0
var weapon_instance_id := 0
var shot_sequence := 0
var projectile_sequence := 0
var feedback_profile_id: StringName = &"rifle"
var damage_kind: StringName = &"ballistic"
var impact_kind: StringName = &"normal"
var source_item_id: StringName = &""
var critical_hit := false
var explosion_damage_multiplier := 1.0
var contact_sequence := 0
var contact_committed := false
var active := true
var _hit_enemy_runtime_ids: Dictionary = {}
var static_asset_snapshot_override: GogoStaticAssetSnapshot
var projectile_sprite: Sprite2D
var projectile_visual_handle: GogoStaticAssetHandle


func activate(
	next_world: CombatWorld,
	next_runtime_instance_id: int,
	next_weapon_instance_id: int,
	next_shot_sequence: int,
	next_projectile_sequence: int,
	next_feedback_profile_id: StringName,
	next_damage_kind: StringName,
	next_impact_kind: StringName,
	next_source_item_id: StringName = &"",
	next_critical_hit: bool = false,
	next_explosion_damage_multiplier: float = 1.0
) -> void:
	combat_world = next_world
	runtime_instance_id = next_runtime_instance_id
	weapon_instance_id = next_weapon_instance_id
	shot_sequence = next_shot_sequence
	projectile_sequence = next_projectile_sequence
	feedback_profile_id = next_feedback_profile_id if VALID_FEEDBACK_PROFILES.has(next_feedback_profile_id) else &""
	damage_kind = next_damage_kind
	impact_kind = next_impact_kind if VALID_IMPACT_KINDS.has(next_impact_kind) else &"normal"
	source_item_id = next_source_item_id
	critical_hit = next_critical_hit
	explosion_damage_multiplier = maxf(next_explosion_damage_multiplier, 0.0)
	contact_sequence = 0
	contact_committed = false
	active = true
	_hit_enemy_runtime_ids.clear()
	rotation = direction.angle() if direction.is_finite() and not direction.is_zero_approx() else 0.0
	_build_static_visual()
	set_physics_process(true)


func _ready() -> void:
	queue_redraw()


func _build_static_visual() -> void:
	if projectile_sprite != null and is_instance_valid(projectile_sprite):
		projectile_sprite.free()
	projectile_sprite = null
	projectile_visual_handle = null
	var asset_id := PROJECTILE_ASSET_ID
	var role := PROJECTILE_ROLE
	var selector := selector_for_feedback_profile(feedback_profile_id)
	var triggered_item_visual := source_item_id == SKYLINE_GRENADE_SOURCE_ITEM_ID
	if triggered_item_visual:
		asset_id = SKYLINE_GRENADE_ASSET_ID
		role = &"icon"
		selector = &""
	elif selector.is_empty():
		return
	else:
		# Ordinary rounds are draw-native even when the old atlas is available.
		# Keep selector helpers only for compatibility; no texture consumer here.
		queue_redraw()
		return
	var snapshot := static_asset_snapshot_override
	if snapshot == null and combat_world != null and combat_world.session != null:
		snapshot = combat_world.session.static_asset_snapshot
	if snapshot == null:
		return
	projectile_visual_handle = snapshot.resolve_asset(asset_id, role, selector)
	if projectile_visual_handle == null or projectile_visual_handle.texture == null:
		projectile_visual_handle = null
		return
	projectile_sprite = Sprite2D.new()
	projectile_sprite.name = "TriggeredItemProjectileSprite" if triggered_item_visual else "ProjectileSprite"
	projectile_sprite.centered = false
	projectile_sprite.texture = projectile_visual_handle.texture
	projectile_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if triggered_item_visual:
		projectile_sprite.scale = TRIGGERED_ITEM_PROJECTILE_SCALE
	else:
		projectile_sprite.scale = visual_scale_for_feedback_profile(feedback_profile_id)
	projectile_sprite.position = (
		-Vector2(projectile_visual_handle.pivot_px) * projectile_sprite.scale
	)
	add_child(projectile_sprite)
	GogoStaticConsumerRegistry.observe_handle(
		projectile_visual_handle,
		"res://game/gameplay/weapons/projectile.gd",
		"%s/%s" % [projectile_sprite.name, String(projectile_visual_handle.selector)]
	)
	queue_redraw()


static func selector_for_feedback_profile(profile_id: StringName) -> StringName:
	return PROJECTILE_SELECTORS.get(profile_id, &"") as StringName


static func visual_scale_for_feedback_profile(profile_id: StringName) -> Vector2:
	return PROJECTILE_VISUAL_SCALES.get(profile_id, Vector2.ONE) as Vector2


func _physics_process(delta: float) -> void:
	if combat_world != null and combat_world.is_combat_simulation_frozen():
		return
	if not active or contact_committed:
		return
	if lifetime <= 0.0:
		retire()
		return
	var travel_seconds := minf(maxf(delta, 0.0), lifetime)
	var start_global := global_position
	var end_global := start_global + direction * speed * travel_seconds
	var sweep_start := start_global
	while active:
		var contact := _first_swept_contact(sweep_start, end_global, _hit_enemy_runtime_ids)
		if contact.is_empty():
			break
		global_position = contact.projectile_center
		var enemy := contact.enemy as GogoEnemyActor
		var canonical_activation := _has_valid_canonical_activation(enemy)
		if combat_world != null and not canonical_activation:
			contact_committed = true
			retire()
			return
		var contact_damage := _contact_damage()
		var damage_reservation_id := 0
		if canonical_activation:
			damage_reservation_id = enemy._reserve_projectile_damage(contact_damage, direction * knockback)
			if damage_reservation_id <= 0:
				contact_committed = true
				retire()
				return
		contact_committed = true
		if canonical_activation:
			_hit_enemy_runtime_ids[enemy.runtime_instance_id] = true
			contact_sequence += 1
			projectile_contact.emit(
				runtime_instance_id,
				enemy.runtime_instance_id,
				feedback_profile_id,
				Vector2i(contact.surface_position.round()),
				contact.normal,
				damage_kind,
				impact_kind,
				contact_sequence
			)
			if is_instance_valid(enemy):
				enemy._commit_reserved_projectile_damage(damage_reservation_id)
		else:
			enemy.take_damage(contact_damage, direction * knockback)
		if canonical_activation and impact_kind == &"explosion":
			_apply_explosion_damage(contact.projectile_center, enemy)
		if (
			canonical_activation
			and impact_kind == &"pierce_exit"
			and contact_sequence < PIERCE_MAX_CONTACTS
		):
			contact_committed = false
			var normalized_direction := direction.normalized()
			sweep_start = contact.projectile_center + normalized_direction * SWEEP_CONTINUE_EPSILON
			if normalized_direction.dot(end_global - sweep_start) > 0.0:
				continue
			global_position = end_global
			break
		retire()
		return
	global_position = end_global
	lifetime = maxf(lifetime - travel_seconds, 0.0)
	if lifetime <= 0.0:
		retire()


func _first_swept_contact(
	start_global: Vector2,
	end_global: Vector2,
	excluded_enemy_runtime_ids: Dictionary = {}
) -> Dictionary:
	var best_enemy: GogoEnemyActor
	var best_t := INF
	var fallback_candidates: Array = []
	var candidate_count := 0
	if combat_world != null:
		candidate_count = combat_world.active_enemy_count()
	elif get_tree() != null:
		fallback_candidates = get_tree().get_nodes_in_group(&"gogo_enemy")
		candidate_count = fallback_candidates.size()
	for index in candidate_count:
		var candidate: Variant = combat_world.active_enemy_at(index) if combat_world != null else fallback_candidates[index]
		if not candidate is GogoEnemyActor:
			continue
		var enemy := candidate as GogoEnemyActor
		if not is_instance_valid(enemy) or not enemy.can_receive_projectile_contact():
			continue
		if enemy.runtime_instance_id > 0 and excluded_enemy_runtime_ids.has(enemy.runtime_instance_id):
			continue
		if combat_world != null and not combat_world.is_active_enemy(enemy):
			continue
		var hit_t := _segment_circle_entry_t(
			start_global,
			end_global,
			enemy.global_position,
			ENEMY_HURT_RADIUS + PROJECTILE_RADIUS
		)
		var earlier := hit_t < best_t - CONTACT_TIE_EPSILON
		var equal_with_lower_runtime_id := (
			absf(hit_t - best_t) <= CONTACT_TIE_EPSILON
			and enemy.runtime_instance_id > 0
			and (best_enemy == null or best_enemy.runtime_instance_id <= 0 or enemy.runtime_instance_id < best_enemy.runtime_instance_id)
		)
		if earlier or equal_with_lower_runtime_id:
			best_t = hit_t
			best_enemy = enemy
	if best_enemy == null:
		return {}
	var projectile_center := start_global.lerp(end_global, best_t)
	var normal := (projectile_center - best_enemy.global_position).normalized()
	if normal.is_zero_approx() or not normal.is_finite():
		normal = -direction.normalized()
	if normal.is_zero_approx() or not normal.is_finite():
		normal = Vector2.LEFT
	return {
		"enemy": best_enemy,
		"projectile_center": projectile_center,
		"surface_position": best_enemy.global_position + normal * ENEMY_HURT_RADIUS,
		"normal": normal,
		"travel_fraction": best_t,
	}


func _contact_damage() -> float:
	return GogoCombatStatRuntime.damage_after_combat_stats(
		damage,
		critical_hit or impact_kind == &"critical",
		impact_kind == &"explosion",
		explosion_damage_multiplier
	)


func _apply_explosion_damage(epicenter: Vector2, direct_enemy: GogoEnemyActor) -> void:
	if combat_world == null:
		return
	var candidates: Array[GogoEnemyActor] = []
	for index in combat_world.active_enemy_count():
		candidates.append(combat_world.active_enemy_at(index))
	var radius_squared := EXPLOSION_RADIUS * EXPLOSION_RADIUS
	for enemy in candidates:
		if (
			enemy == null
			or enemy == direct_enemy
			or not is_instance_valid(enemy)
			or not combat_world.is_active_enemy(enemy)
			or enemy.global_position.distance_squared_to(epicenter) > radius_squared
		):
			continue
		var impulse_direction := (enemy.global_position - epicenter).normalized()
		if not impulse_direction.is_finite() or impulse_direction.is_zero_approx():
			impulse_direction = direction.normalized()
		enemy.take_damage(_contact_damage(), impulse_direction * knockback)


func _has_valid_canonical_activation(enemy: GogoEnemyActor) -> bool:
	return (
		combat_world != null
		and runtime_instance_id > 0
		and weapon_instance_id > 0
		and shot_sequence > 0
		and projectile_sequence > 0
		and enemy != null
		and enemy.runtime_instance_id > 0
		and combat_world.is_active_enemy(enemy)
		and VALID_FEEDBACK_PROFILES.has(feedback_profile_id)
		and not damage_kind.is_empty()
		and VALID_IMPACT_KINDS.has(impact_kind)
	)


func _segment_circle_entry_t(start_global: Vector2, end_global: Vector2, center: Vector2, radius: float) -> float:
	var offset := start_global - center
	var radius_squared := radius * radius
	if offset.length_squared() <= radius_squared:
		return 0.0
	var segment := end_global - start_global
	var a := segment.length_squared()
	if a <= 0.000001:
		return INF
	var b := 2.0 * offset.dot(segment)
	var c := offset.length_squared() - radius_squared
	var discriminant := b * b - 4.0 * a * c
	if discriminant < 0.0:
		return INF
	var root := sqrt(discriminant)
	var denominator := 2.0 * a
	var entry := (-b - root) / denominator
	if entry >= 0.0 and entry <= 1.0:
		return entry
	var exit := (-b + root) / denominator
	return exit if exit >= 0.0 and exit <= 1.0 else INF


func retire() -> void:
	if not active:
		return
	active = false
	set_physics_process(false)
	queue_free()


func _draw() -> void:
	if projectile_sprite != null:
		return
	if source_item_id == SKYLINE_GRENADE_SOURCE_ITEM_ID:
		draw_circle(Vector2.ZERO, 8.0, Color("252b2d"))
		draw_circle(Vector2.ZERO, 5.0, Color("64735b"))
		draw_line(Vector2(-2.0, -7.0), Vector2(4.0, -11.0), Color("f2a23a"), 3.0, false)
		return
	draw_rect(Rect2(-7.0, -3.0, 14.0, 6.0), Color("242a28"), true)
	draw_rect(Rect2(-6.0, -2.0, 12.0, 4.0), Color("fff1ca"), true)
