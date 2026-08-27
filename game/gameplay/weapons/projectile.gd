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
const VALID_FEEDBACK_PROFILES: Array[StringName] = [&"rapid", &"rifle", &"heavy", &"suppressed"]
const VALID_IMPACT_KINDS: Array[StringName] = [&"normal", &"critical", &"pierce_exit", &"explosion"]
const PROJECTILE_ASSET_ID: StringName = &"projectile_hit_kit"
const PROJECTILE_ROLE: StringName = &"projectile_sprite"
const PROJECTILE_SELECTORS := {
	&"rapid": &"pistol_smg_round",
	&"rifle": &"rifle_round",
	&"heavy": &"sniper_round",
	&"suppressed": &"pistol_smg_round",
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
var contact_sequence := 0
var contact_committed := false
var active := true
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
	next_impact_kind: StringName
) -> void:
	combat_world = next_world
	runtime_instance_id = next_runtime_instance_id
	weapon_instance_id = next_weapon_instance_id
	shot_sequence = next_shot_sequence
	projectile_sequence = next_projectile_sequence
	feedback_profile_id = next_feedback_profile_id if VALID_FEEDBACK_PROFILES.has(next_feedback_profile_id) else &""
	damage_kind = next_damage_kind
	impact_kind = next_impact_kind if VALID_IMPACT_KINDS.has(next_impact_kind) else &"normal"
	contact_sequence = 0
	contact_committed = false
	active = true
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
	var selector := selector_for_feedback_profile(feedback_profile_id)
	if selector.is_empty():
		return
	var snapshot := static_asset_snapshot_override
	if snapshot == null and combat_world != null and combat_world.session != null:
		snapshot = combat_world.session.static_asset_snapshot
	if snapshot == null:
		return
	projectile_visual_handle = snapshot.resolve_asset(PROJECTILE_ASSET_ID, PROJECTILE_ROLE, selector)
	if projectile_visual_handle == null or projectile_visual_handle.texture == null:
		projectile_visual_handle = null
		return
	projectile_sprite = Sprite2D.new()
	projectile_sprite.name = "ProjectileSprite"
	projectile_sprite.centered = false
	projectile_sprite.texture = projectile_visual_handle.texture
	projectile_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	projectile_sprite.position = -Vector2(projectile_visual_handle.pivot_px)
	add_child(projectile_sprite)
	queue_redraw()


static func selector_for_feedback_profile(profile_id: StringName) -> StringName:
	return PROJECTILE_SELECTORS.get(profile_id, &"") as StringName


func _physics_process(delta: float) -> void:
	if not active or contact_committed:
		return
	if lifetime <= 0.0:
		retire()
		return
	var travel_seconds := minf(maxf(delta, 0.0), lifetime)
	var start_global := global_position
	var end_global := start_global + direction * speed * travel_seconds
	var contact := _first_swept_contact(start_global, end_global)
	if not contact.is_empty():
		global_position = contact.projectile_center
		var enemy := contact.enemy as GogoEnemyActor
		var canonical_activation := _has_valid_canonical_activation(enemy)
		if combat_world != null and not canonical_activation:
			contact_committed = true
			retire()
			return
		var damage_reservation_id := 0
		if canonical_activation:
			damage_reservation_id = enemy._reserve_projectile_damage(damage, direction * knockback)
			if damage_reservation_id <= 0:
				contact_committed = true
				retire()
				return
		contact_committed = true
		if canonical_activation:
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
			enemy.take_damage(damage, direction * knockback)
		retire()
		return
	global_position = end_global
	lifetime = maxf(lifetime - travel_seconds, 0.0)
	if lifetime <= 0.0:
		retire()


func _first_swept_contact(start_global: Vector2, end_global: Vector2) -> Dictionary:
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
	draw_circle(Vector2.ZERO, PROJECTILE_RADIUS, Color("f5d76e"))
	draw_circle(Vector2.ZERO, 2.0, Color.WHITE)
