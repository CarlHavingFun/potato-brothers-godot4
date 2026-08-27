class_name GogoPlayerActor
extends CharacterBody2D

const HIT_FLASH_DURATION := 0.12
const PLAYER_BODY_RADIUS := 18.0
const NIKO_VISUAL_RADIUS := 60.0
const PLAYER_WEAPON_GAP := 16.0
const NIKO_CLEAR_RADIUS := NIKO_VISUAL_RADIUS + PLAYER_WEAPON_GAP
const WEAPON_SLOT_GAP := 12.0
const DEFAULT_WEAPON_DISPLAY_BOUNDS := Vector2i(96, 64)
const DEFAULT_WEAPON_PIVOT := Vector2i(38, 40)
const SINGLE_SLOT_BOUND_FRACTION := 0.1875
const MAX_WEAPON_SLOTS := 6

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


func configure(next_session: GameSession, world: CombatWorld) -> void:
	if session != null and session != next_session and session.state_changed.is_connected(_on_session_state_changed):
		session.state_changed.disconnect(_on_session_state_changed)
	session = next_session
	combat_world = world
	player_state = session.run_state.player()
	if not session.state_changed.is_connected(_on_session_state_changed):
		session.state_changed.connect(_on_session_state_changed)


func _ready() -> void:
	add_to_group(&"gogo_player")
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = PLAYER_BODY_RADIUS
	shape.shape = circle
	add_child(shape)
	_build_character_visual_rig()
	weapon_orbit = Node2D.new()
	weapon_orbit.name = "WeaponOrbit"
	add_child(weapon_orbit)
	_build_weapons()
	queue_redraw()


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
	velocity = direction * float(player_state.final_stats.get(&"movement_speed", 220.0))
	move_and_slide()
	_update_character_visual(direction)
	if combat_world != null:
		global_position = combat_world.clamp_to_arena(
			global_position,
			weapon_arena_clamp_margin()
		)


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
	if player_state == null or session == null:
		return
	var instances: Array[GogoWeaponInstance] = []
	var display_bounds: Array[Vector2i] = []
	var pivots: Array[Vector2i] = []
	var requested_count := mini(player_state.weapon_ids.size(), MAX_WEAPON_SLOTS)
	for index in requested_count:
		var definition := session.content_snapshot.definition(player_state.weapon_ids[index], &"weapon") as GogoWeaponDefinition
		if definition == null:
			continue
		var runtime_stats := weapon_runtime.build_instance(definition, player_state)
		if runtime_stats == null:
			continue
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
	var radius := weapon_orbit_radius(count, display_bounds, pivots)
	cache_weapon_orbit_extent(radius, display_bounds, pivots)
	for index in count:
		instances[index].position = weapon_orbit_offset(index, count, radius)


func weapon_visual_footprint_radius(bounds: Vector2i, pivot: Vector2i) -> float:
	if bounds.x <= 0 or bounds.y <= 0:
		return 0.0
	var horizontal_extent := maxf(float(pivot.x), float(bounds.x - pivot.x))
	var vertical_extent := maxf(float(pivot.y), float(bounds.y - pivot.y))
	return Vector2(horizontal_extent, vertical_extent).length()


func weapon_orbit_radius(
	count: int,
	weapon_display_bounds: Array[Vector2i] = [],
	weapon_pivots: Array[Vector2i] = []
) -> float:
	if count <= 0 or count > MAX_WEAPON_SLOTS:
		return 0.0
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
			weapon_visual_footprint_radius(bounds, pivot)
		)
	if footprint_radius <= 0.0:
		footprint_radius = weapon_visual_footprint_radius(
			DEFAULT_WEAPON_DISPLAY_BOUNDS,
			DEFAULT_WEAPON_PIVOT
		)
	var close_radius := PLAYER_BODY_RADIUS + (
		float(mini(DEFAULT_WEAPON_DISPLAY_BOUNDS.x, DEFAULT_WEAPON_DISPLAY_BOUNDS.y))
		* SINGLE_SLOT_BOUND_FRACTION
	)
	if count == 1:
		return close_radius
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
	weapon_pivots: Array[Vector2i]
) -> void:
	var maximum_footprint := 0.0
	for index in weapon_display_bounds.size():
		var bounds := weapon_display_bounds[index]
		var pivot := Vector2i(bounds / 2)
		if index < weapon_pivots.size():
			pivot = weapon_pivots[index]
		maximum_footprint = maxf(
			maximum_footprint,
			weapon_visual_footprint_radius(bounds, pivot)
		)
	_weapon_orbit_extent = maxf(NIKO_VISUAL_RADIUS, maxf(radius, 0.0) + maximum_footprint)


func weapon_arena_clamp_margin() -> float:
	return maxf(NIKO_VISUAL_RADIUS, _weapon_orbit_extent)


func weapon_orbit_offset(index: int, count: int, radius: float = -1.0) -> Vector2:
	if count <= 0 or count > MAX_WEAPON_SLOTS or index < 0 or index >= count:
		return Vector2.ZERO
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


func _draw() -> void:
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
