class_name GogoHostileProjectile
extends Node2D

const ASSET_ID: StringName = &"projectile_hit_kit"
const ASSET_ROLE: StringName = &"projectile_sprite"
const ASSET_SELECTOR: StringName = &"hostile_pulse"
const VISUAL_SCALE := Vector2(0.25, 0.25)
const PROJECTILE_RADIUS := 4.0
const PLAYER_HURT_RADIUS := GogoPlayerActor.PLAYER_BODY_RADIUS
const DEFAULT_SPEED := 210.0
const DEFAULT_LIFETIME := 2.0
const OUT_OF_BOUNDS_MARGIN := 32.0
const VISUAL_OUTLINE_RADIUS := 8.0
const VISUAL_BODY_RADIUS := 6.0
const VISUAL_CORE_RADIUS := 2.0
const VISUAL_OUTLINE_COLOR := Color("2a1218")
const VISUAL_BODY_COLOR := Color("ff5a3c")
const VISUAL_CORE_COLOR := Color("fff0d2")

var combat_world: CombatWorld
var target: GogoPlayerActor
var source_enemy_runtime_id := 0
var direction := Vector2.RIGHT
var speed := DEFAULT_SPEED
var damage := 1.0
var lifetime := DEFAULT_LIFETIME
var arena_rect := Rect2()
var active := false
var contact_committed := false
var static_asset_snapshot_override: GogoStaticAssetSnapshot
var projectile_sprite: Sprite2D
var projectile_visual_handle: GogoStaticAssetHandle
var fallback_visual_active := false
var _precise_global_position := Vector2.ZERO


func activate(
	next_world: CombatWorld,
	next_target: GogoPlayerActor,
	next_source_enemy_runtime_id: int,
	next_origin: Vector2,
	next_direction: Vector2,
	next_damage: float
) -> bool:
	combat_world = next_world
	target = next_target
	source_enemy_runtime_id = next_source_enemy_runtime_id
	if (
		target == null
		or not is_instance_valid(target)
		or not next_origin.is_finite()
		or not next_direction.is_finite()
		or next_direction.is_zero_approx()
		or not is_finite(next_damage)
		or next_damage <= 0.0
	):
		retire()
		return false
	direction = next_direction.normalized()
	damage = next_damage
	lifetime = DEFAULT_LIFETIME
	contact_committed = false
	active = true
	if combat_world != null:
		arena_rect = combat_world.arena_rect
	_precise_global_position = next_origin.round()
	global_position = _precise_global_position
	rotation = direction.angle()
	fallback_visual_active = not _build_static_visual()
	queue_redraw()
	set_physics_process(true)
	return true


func _build_static_visual() -> bool:
	if projectile_sprite != null and is_instance_valid(projectile_sprite):
		projectile_sprite.free()
	projectile_sprite = null
	projectile_visual_handle = null
	# An intentional successful procedural path, independent of asset availability.
	return true


func _draw() -> void:
	draw_circle(Vector2.ZERO, VISUAL_OUTLINE_RADIUS, VISUAL_OUTLINE_COLOR)
	draw_circle(Vector2.ZERO, VISUAL_BODY_RADIUS, VISUAL_BODY_COLOR)
	draw_circle(Vector2(1.5, -1.0), VISUAL_CORE_RADIUS, VISUAL_CORE_COLOR)


func _physics_process(delta: float) -> void:
	if combat_world != null and combat_world.is_combat_simulation_frozen():
		return
	if not active or contact_committed:
		return
	if target == null or not is_instance_valid(target) or target.is_queued_for_deletion():
		retire()
		return
	if lifetime <= 0.0:
		retire()
		return
	var travel_seconds := minf(maxf(delta, 0.0), lifetime)
	var start_global := _precise_global_position
	var end_global := start_global + direction * speed * travel_seconds
	var contact := _swept_player_contact(start_global, end_global)
	if not contact.is_empty():
		_precise_global_position = contact.position
		global_position = _precise_global_position.round()
		_commit_player_contact()
		return
	_precise_global_position = end_global
	global_position = _precise_global_position.round()
	lifetime = maxf(lifetime - travel_seconds, 0.0)
	if lifetime <= 0.0 or _is_out_of_bounds(_precise_global_position):
		retire()


func _swept_player_contact(start_global: Vector2, end_global: Vector2) -> Dictionary:
	var center := target.global_position
	var combined_radius := PROJECTILE_RADIUS + PLAYER_HURT_RADIUS
	var offset := start_global - center
	if offset.length_squared() <= combined_radius * combined_radius:
		return {"position": start_global}
	var segment := end_global - start_global
	var segment_length_squared := segment.length_squared()
	if segment_length_squared <= 0.0:
		return {}
	var b := 2.0 * offset.dot(segment)
	var c := offset.length_squared() - combined_radius * combined_radius
	var discriminant := b * b - 4.0 * segment_length_squared * c
	if discriminant < 0.0:
		return {}
	var contact_fraction := (
		-b - sqrt(discriminant)
	) / (2.0 * segment_length_squared)
	if contact_fraction < 0.0 or contact_fraction > 1.0:
		return {}
	return {"position": start_global + segment * contact_fraction}


func _commit_player_contact() -> void:
	if contact_committed or not active:
		return
	contact_committed = true
	active = false
	set_physics_process(false)
	var committed_target := target
	if committed_target != null and is_instance_valid(committed_target):
		committed_target.take_damage(damage)
	retire()


func _is_out_of_bounds(point: Vector2) -> bool:
	return arena_rect.has_area() and not arena_rect.grow(OUT_OF_BOUNDS_MARGIN).has_point(point)


func retire() -> void:
	active = false
	set_physics_process(false)
	visible = false
	if is_inside_tree() and not is_queued_for_deletion():
		queue_free()
