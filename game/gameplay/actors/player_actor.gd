class_name GogoPlayerActor
extends CharacterBody2D

signal died
signal health_changed(current: float, maximum: float)

var player_state: SessionPlayerState
var session: GameSession
var combat_world: CombatWorld
var weapon_runtime := WeaponRuntimeService.new()
var weapon_orbit: Node2D
var visual_rig: CharacterVisualRig
var character_visual: AnimatedSprite2D
var damage_cooldown := 0.0


func configure(next_session: GameSession, world: CombatWorld) -> void:
	session = next_session
	combat_world = world
	player_state = session.run_state.player()
	if not session.state_changed.is_connected(_on_session_state_changed):
		session.state_changed.connect(_on_session_state_changed)


func _ready() -> void:
	add_to_group(&"gogo_player")
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 18.0
	shape.shape = circle
	add_child(shape)
	_build_character_visual_rig()
	weapon_orbit = Node2D.new()
	weapon_orbit.name = "WeaponOrbit"
	add_child(weapon_orbit)
	_build_weapons()
	queue_redraw()


func _physics_process(delta: float) -> void:
	damage_cooldown = maxf(damage_cooldown - delta, 0.0)
	if player_state == null:
		return
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = direction * float(player_state.final_stats.get(&"movement_speed", 220.0))
	move_and_slide()
	_update_character_visual(direction)
	if combat_world != null:
		global_position = combat_world.clamp_to_arena(global_position, 24.0)


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
	player_state.current_health = maxf(player_state.current_health - final_damage, 0.0)
	damage_cooldown = 0.35
	health_changed.emit(player_state.current_health, player_state.max_health)
	queue_redraw()
	if player_state.current_health <= 0.0:
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
	var count := mini(player_state.weapon_ids.size(), 6)
	for index in count:
		var definition := session.content_snapshot.definition(player_state.weapon_ids[index], &"weapon") as GogoWeaponDefinition
		var runtime_stats := weapon_runtime.build_instance(definition, player_state)
		var instance := GogoWeaponInstance.new()
		var angle := TAU * float(index) / float(maxi(count, 1))
		instance.position = Vector2.RIGHT.rotated(angle) * 36.0
		weapon_orbit.add_child(instance)
		instance.configure(runtime_stats, self)


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
