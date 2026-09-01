class_name GogoPlayerActor
extends CharacterBody2D

const MOVEMENT_COMBAT_RUNTIME := preload("res://game/gameplay/rules/movement_combat_runtime.gd")

const HIT_FLASH_DURATION := 0.12
const PLAYER_BODY_RADIUS := 18.0
const PICKUP_INTERACTION_RADIUS := 60.0
const PLAYER_COLLISION_LAYER := 1 << 0
const WORLD_COLLISION_LAYER := 1 << 7
const NIKO_VISUAL_RADIUS := 60.0
const PLAYER_WEAPON_GAP := 16.0
const NIKO_CLEAR_RADIUS := NIKO_VISUAL_RADIUS + PLAYER_WEAPON_GAP
const WEAPON_SLOT_GAP := 12.0
const DEFAULT_WEAPON_DISPLAY_BOUNDS := Vector2i(96, 64)
const DEFAULT_WEAPON_PIVOT := Vector2i(38, 40)
const WEAPON_CONTAINER_OFFSET := Vector2.ZERO
const WEAPON_VISUAL_SCALE := 1.0
const SINGLE_WEAPON_OFFSET := Vector2(0.0, 48.0)
const MAX_WEAPON_SLOTS := 6
const GROUND_SHADOW_CENTER := Vector2(0.0, 18.0)
const GROUND_SHADOW_SCALE := Vector2(1.0, 0.34)
const GROUND_SHADOW_COLOR := Color(0.02, 0.025, 0.03, 0.30)
const GROUND_SHADOW_RADIUS := 19.0

signal died
signal health_changed(current: float, maximum: float)
signal damage_taken(
	integer_global_position: Vector2i,
	final_damage: float,
	remaining_health: float,
	lethal: bool,
	sequence: int
)

var player_state: SessionPlayerState
var session: GameSession
var combat_world: CombatWorld
var weapon_runtime := WeaponRuntimeService.new()
var weapon_orbit: Node2D
var visual_rig: CharacterVisualRig
var character_visual: AnimatedSprite2D
var damage_cooldown := 0.0
var hit_flash_remaining := 0.0
var _weapon_orbit_extent := NIKO_VISUAL_RADIUS
var _damage_taken_sequence := 0
var _last_horizontal_facing := 1.0
var _health_regen_elapsed := 0.0
var weapon_reference_visible_height := 0.0


func configure(next_session: GameSession, world: CombatWorld) -> void:
	if session != null and session != next_session and session.state_changed.is_connected(_on_session_state_changed):
		session.state_changed.disconnect(_on_session_state_changed)
	if session != next_session:
		velocity = Vector2.ZERO
	session = next_session
	combat_world = world
	player_state = session.run_state.player()
	if not session.state_changed.is_connected(_on_session_state_changed):
		session.state_changed.connect(_on_session_state_changed)


func _ready() -> void:
	add_to_group(&"gogo_player")
	collision_layer = PLAYER_COLLISION_LAYER
	collision_mask = WORLD_COLLISION_LAYER
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = PLAYER_BODY_RADIUS
	shape.shape = circle
	add_child(shape)
	_build_character_visual_rig()
	weapon_orbit = Node2D.new()
	weapon_orbit.name = "WeaponOrbit"
	weapon_orbit.position = WEAPON_CONTAINER_OFFSET
	add_child(weapon_orbit)
	_build_weapons()
	queue_redraw()


func pickup_interaction_radius() -> float:
	return PICKUP_INTERACTION_RADIUS


func _physics_process(delta: float) -> void:
	if combat_world != null and combat_world.is_combat_simulation_frozen():
		return
	damage_cooldown = maxf(damage_cooldown - delta, 0.0)
	if hit_flash_remaining > 0.0:
		hit_flash_remaining = maxf(hit_flash_remaining - delta, 0.0)
		if hit_flash_remaining <= 0.0 and visual_rig != null:
			visual_rig.set_hit_flash(false)
	if player_state == null:
		return
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if absf(direction.x) > 0.001:
		_last_horizontal_facing = signf(direction.x)
	velocity = MOVEMENT_COMBAT_RUNTIME.move_toward_velocity(
		velocity,
		direction,
		float(player_state.final_stats.get(&"movement_speed", 220.0)),
		delta,
		float(player_state.final_stats.get(&"counter_strafe_brake", 0.0))
	)
	move_and_slide()
	_update_character_visual(direction)
	if combat_world != null:
		var clamped_position := combat_world.clamp_to_arena(
			global_position,
			weapon_arena_clamp_margin()
		)
		if not clamped_position.is_equal_approx(global_position):
			velocity = Vector2.ZERO
		global_position = clamped_position


func take_damage(amount: float) -> void:
	if damage_cooldown > 0.0 or player_state == null:
		return
	var dodge := clampf(float(player_state.final_stats.get(&"dodge", 0.0)), 0.0, 0.6)
	if session.rng.randf() < dodge:
		damage_cooldown = 0.15
		return
	var armor := float(player_state.final_stats.get(&"armor", 0.0))
	var reduction := armor / (armor + 15.0) if armor >= 0.0 else armor / (15.0 - armor)
	var final_damage := maxf(amount * (1.0 - reduction), 1.0)
	var health_before := player_state.current_health
	player_state.current_health = maxf(player_state.current_health - final_damage, 0.0)
	damage_cooldown = 0.35
	var lethal := player_state.current_health <= 0.0
	if lethal:
		hit_flash_remaining = 0.0
		if visual_rig != null:
			visual_rig.set_dead(true)
	else:
		hit_flash_remaining = HIT_FLASH_DURATION
		if visual_rig != null:
			visual_rig.set_hit_flash(true)
	health_changed.emit(player_state.current_health, player_state.max_health)
	if player_state.current_health < health_before:
		_damage_taken_sequence += 1
		damage_taken.emit(
			Vector2i(global_position.round()),
			final_damage,
			player_state.current_health,
			lethal,
			_damage_taken_sequence
		)
	queue_redraw()
	if lethal:
		died.emit()


func heal(amount: float) -> void:
	if player_state == null:
		return
	player_state.current_health = minf(player_state.current_health + amount, player_state.max_health)
	health_changed.emit(player_state.current_health, player_state.max_health)


func reset_health_regeneration_cycle() -> void:
	_health_regen_elapsed = 0.0


func tick_health_regeneration(delta: float) -> float:
	if player_state == null:
		_health_regen_elapsed = 0.0
		return 0.0
	var health_regen := float(player_state.final_stats.get(&"health_regen", 0.0))
	var interval := GogoCombatStatRuntime.health_regen_interval_seconds(health_regen)
	if (
		not is_finite(interval)
		or player_state.current_health <= 0.0
		or player_state.current_health >= player_state.max_health
	):
		_health_regen_elapsed = 0.0
		return 0.0
	_health_regen_elapsed += maxf(delta, 0.0)
	var tick_count := int(floor(_health_regen_elapsed / interval))
	if tick_count <= 0:
		return 0.0
	_health_regen_elapsed -= float(tick_count) * interval
	var health_before := player_state.current_health
	heal(float(tick_count))
	if player_state.current_health >= player_state.max_health:
		_health_regen_elapsed = 0.0
	return player_state.current_health - health_before


func rebuild_weapons() -> void:
	if weapon_orbit == null:
		return
	for child in weapon_orbit.get_children(): child.queue_free()
	_build_weapons()


func rebuild_appearances() -> void:
	if visual_rig == null:
		return
	visual_rig.rebuild_appearances(_collect_appearances())


func _build_weapons() -> void:
	_cache_weapon_reference_height()
	if player_state == null or session == null:
		return
	var instances: Array[GogoWeaponInstance] = []
	var display_bounds: Array[Vector2i] = []
	var pivots: Array[Vector2i] = []
	var records := player_state.weapon_inventory.records()
	var requested_count := mini(records.size(), MAX_WEAPON_SLOTS)
	for index in requested_count:
		var record: Dictionary = records[index]
		var definition := session.content_snapshot.definition(record.content_id, &"weapon") as GogoWeaponDefinition
		if definition == null:
			continue
		var runtime_stats := weapon_runtime.build_instance(definition, player_state, record.quality)
		if runtime_stats == null:
			continue
		runtime_stats.inventory_instance_id = record.instance_id
		var instance := GogoWeaponInstance.new()
		weapon_orbit.add_child(instance)
		instance.configure(runtime_stats, self)
		instances.append(instance)
		if instance.weapon_visual_handle != null:
			display_bounds.append(instance.weapon_visual_handle.display_size_px)
			pivots.append(instance.weapon_visual_handle.pivot_px)
		else:
			display_bounds.append(DEFAULT_WEAPON_DISPLAY_BOUNDS)
			pivots.append(DEFAULT_WEAPON_PIVOT)
	var count := instances.size()
	var visual_scale := weapon_visual_scale(count)
	for instance in instances:
		instance.scale = Vector2.ONE * visual_scale
	var radius := weapon_orbit_radius(count, display_bounds, pivots)
	cache_weapon_orbit_extent(radius, display_bounds, pivots, visual_scale)
	for index in count:
		instances[index].set_initial_fire_phase(index, count)
		var orbit_offset := weapon_orbit_offset(index, count, radius)
		instances[index].position = orbit_offset
		instances[index].z_index = weapon_visual_z_index(orbit_offset)
		_weapon_orbit_extent = maxf(
			_weapon_orbit_extent,
			(WEAPON_CONTAINER_OFFSET + orbit_offset).length()
			+ instances[index].visual_boundary_extent * visual_scale
		)


func _cache_weapon_reference_height() -> void:
	weapon_reference_visible_height = 0.0
	if character_visual == null or character_visual.sprite_frames == null:
		return
	var frames := character_visual.sprite_frames
	var animation := character_visual.animation
	if session != null and session.content_snapshot != null and player_state != null:
		var definition := session.content_snapshot.definition(player_state.character_id, &"character") as CharacterDefinition
		if definition != null: animation = definition.default_animation
	if not frames.has_animation(animation) or frames.get_frame_count(animation) == 0:
		return
	var image := frames.get_frame_texture(animation, 0).get_image()
	if image == null: return
	var visual_scale_y := absf(character_visual.scale.y)
	if visual_rig != null: visual_scale_y *= absf(visual_rig.scale.y)
	weapon_reference_visible_height = float(image.get_used_rect().size.y) * visual_scale_y


func weapon_visual_scale(count: int) -> float:
	return WEAPON_VISUAL_SCALE if count > 0 and count <= MAX_WEAPON_SLOTS else 1.0


func weapon_visual_footprint_radius(
	bounds: Vector2i,
	pivot: Vector2i,
	visual_scale: float = 1.0
) -> float:
	if bounds.x <= 0 or bounds.y <= 0:
		return 0.0
	var horizontal_extent := maxf(float(pivot.x), float(bounds.x - pivot.x))
	var vertical_extent := maxf(float(pivot.y), float(bounds.y - pivot.y))
	return Vector2(horizontal_extent, vertical_extent).length() * maxf(visual_scale, 0.0)


func weapon_orbit_radius(
	count: int,
	weapon_display_bounds: Array[Vector2i] = [],
	weapon_pivots: Array[Vector2i] = []
) -> float:
	if count <= 0 or count > MAX_WEAPON_SLOTS:
		return 0.0
	if count == 1:
		return SINGLE_WEAPON_OFFSET.length()
	var footprint_radius := 0.0
	for index in weapon_display_bounds.size():
		var bounds := weapon_display_bounds[index]
		if bounds.x <= 0 or bounds.y <= 0:
			continue
		var pivot := Vector2i(bounds / 2)
		if index < weapon_pivots.size():
			pivot = weapon_pivots[index]
		footprint_radius = maxf(
			footprint_radius,
			weapon_visual_footprint_radius(bounds, pivot, weapon_visual_scale(count))
		)
	if footprint_radius <= 0.0:
		footprint_radius = weapon_visual_footprint_radius(
			DEFAULT_WEAPON_DISPLAY_BOUNDS,
			DEFAULT_WEAPON_PIVOT,
			weapon_visual_scale(count)
		)
	var half_socket_angle := PI / float(count)
	var socket_sine := sin(half_socket_angle)
	if socket_sine <= 0.0 or not is_finite(socket_sine):
		return 0.0
	var player_clear_radius := NIKO_CLEAR_RADIUS + footprint_radius
	var neighbor_clear_radius := (
		(footprint_radius * 2.0 + WEAPON_SLOT_GAP)
		/ (2.0 * socket_sine)
	)
	return maxf(player_clear_radius, neighbor_clear_radius)


func cache_weapon_orbit_extent(
	radius: float,
	weapon_display_bounds: Array[Vector2i],
	weapon_pivots: Array[Vector2i],
	visual_scale: float = 1.0
) -> void:
	var maximum_footprint := 0.0
	for index in weapon_display_bounds.size():
		var bounds := weapon_display_bounds[index]
		var pivot := Vector2i(bounds / 2)
		if index < weapon_pivots.size():
			pivot = weapon_pivots[index]
		maximum_footprint = maxf(
			maximum_footprint,
			weapon_visual_footprint_radius(bounds, pivot, visual_scale)
		)
	_weapon_orbit_extent = maxf(NIKO_VISUAL_RADIUS, maxf(radius, 0.0) + maximum_footprint)


func weapon_arena_clamp_margin() -> float:
	return maxf(NIKO_VISUAL_RADIUS, _weapon_orbit_extent)


func weapon_orbit_offset(index: int, count: int, radius: float = -1.0) -> Vector2:
	if count <= 0 or count > MAX_WEAPON_SLOTS or index < 0 or index >= count:
		return Vector2.ZERO
	if count == 1:
		return SINGLE_WEAPON_OFFSET
	var resolved_radius := radius
	if not is_finite(resolved_radius) or resolved_radius <= 0.0:
		resolved_radius = weapon_orbit_radius(
			count,
			[DEFAULT_WEAPON_DISPLAY_BOUNDS],
			[DEFAULT_WEAPON_PIVOT]
		)
	if resolved_radius <= 0.0:
		return Vector2.ZERO
	var angle := TAU * float(index) / float(count)
	return Vector2.RIGHT.rotated(angle) * resolved_radius


func weapon_visual_z_index(orbit_offset: Vector2) -> int:
	# Brotato draws the ordinary weapon container after the character; all equipped
	# weapons therefore remain readable in front instead of changing depth by slot.
	return 1


func weapon_idle_angle() -> float:
	return PI if _last_horizontal_facing < 0.0 else 0.0


func _draw() -> void:
	draw_set_transform(GROUND_SHADOW_CENTER, 0.0, GROUND_SHADOW_SCALE)
	draw_circle(Vector2.ZERO, GROUND_SHADOW_RADIUS, GROUND_SHADOW_COLOR)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if character_visual != null:
		return
	var body_color := Color("86d98b") if damage_cooldown <= 0.0 else Color("ffffff")
	draw_circle(Vector2(0.0, 5.0), 22.0, Color("2b2d33"))
	draw_circle(Vector2(0.0, 0.0), 20.0, body_color)
	draw_circle(Vector2(-7.0, -4.0), 2.5, Color("1a1b20"))
	draw_circle(Vector2(7.0, -4.0), 2.5, Color("1a1b20"))
	draw_line(Vector2(-6.0, 7.0), Vector2(6.0, 7.0), Color("1a1b20"), 2.0)


func _build_character_visual_rig() -> void:
	if player_state == null or session == null or session.content_snapshot == null:
		return
	var definition := session.content_snapshot.definition(player_state.character_id, &"character") as CharacterDefinition
	if definition == null or definition.sprite_frames == null or definition.default_animation.is_empty():
		return
	if not definition.sprite_frames.has_animation(definition.default_animation):
		return
	visual_rig = CharacterVisualRig.new()
	visual_rig.name = "VisualRig"
	add_child(visual_rig)
	if visual_rig.configure(definition, _collect_appearances()) != OK:
		visual_rig.queue_free()
		visual_rig = null
		return
	character_visual = visual_rig.base_sprite


func _update_character_visual(direction: Vector2) -> void:
	if visual_rig == null:
		return
	visual_rig.set_moving(not direction.is_zero_approx())


func _collect_appearances() -> Array[GogoAppearanceDefinition]:
	var result: Array[GogoAppearanceDefinition] = []
	if session == null or session.content_snapshot == null or player_state == null:
		return result
	var character := session.content_snapshot.definition(player_state.character_id, &"character") as CharacterDefinition
	if character != null:
		result.append_array(character.appearances)
	var seen_items: Dictionary = {}
	for item_id in player_state.item_ids:
		if seen_items.has(item_id):
			continue
		seen_items[item_id] = true
		var item := session.content_snapshot.definition(item_id, &"item") as GogoItemDefinition
		if item != null:
			result.append_array(item.appearances)
	return result


func _on_session_state_changed() -> void:
	rebuild_appearances()
