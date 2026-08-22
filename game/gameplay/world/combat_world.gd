class_name CombatWorld
extends Node2D

signal wave_completed
signal run_failed
signal hud_changed(health: float, max_health: float, time_left: float, wave: int)

var session: GameSession
var wave_runtime := WaveRuntime.new()
var zone_runtime := ZoneRuntime.new()
var player_actor: GogoPlayerActor
var enemy_layer: Node2D
var projectile_layer: Node2D
var effect_layer: Node2D
var player_camera: GogoCombatCamera
var arena_rect := Rect2(Vector2.ZERO, Vector2(2048.0, 1536.0))
var running := false


func _ready() -> void:
	enemy_layer = Node2D.new()
	enemy_layer.name = "Enemies"
	add_child(enemy_layer)
	projectile_layer = Node2D.new()
	projectile_layer.name = "PlayerProjectiles"
	add_child(projectile_layer)
	effect_layer = Node2D.new()
	effect_layer.name = "Effects"
	add_child(effect_layer)
	queue_redraw()


func start_wave(next_session: GameSession, wave_definition: GogoWaveDefinition) -> Error:
	if next_session == null or wave_definition == null:
		return ERR_INVALID_PARAMETER
	session = next_session
	var zone := session.content_snapshot.definition(session.run_state.zone_id, &"zone") as GogoZoneDefinition
	var difficulty := session.content_snapshot.definition(session.run_state.difficulty_id, &"difficulty") as GogoDifficultyDefinition
	if zone_runtime.configure(zone) != OK or difficulty == null:
		return ERR_INVALID_DATA
	arena_rect = Rect2(Vector2.ZERO, zone.arena_size)
	wave_runtime.begin(wave_definition, difficulty.spawn_multiplier)
	if player_actor == null:
		player_actor = GogoPlayerActor.new()
		player_actor.configure(session, self)
		player_actor.position = arena_rect.get_center()
		add_child(player_actor)
		player_actor.died.connect(_on_player_died)
		player_actor.health_changed.connect(_on_player_health_changed)
	if player_camera == null:
		player_camera = GogoCombatCamera.new()
		player_camera.name = "PlayerCamera"
		add_child(player_camera)
	player_camera.configure(player_actor, arena_rect)
	running = true
	return OK


func _physics_process(delta: float) -> void:
	if not running or session == null:
		return
	session.run_state.elapsed_seconds += delta
	for enemy_id in wave_runtime.tick(delta):
		_spawn_enemy(enemy_id)
	var player := session.run_state.player()
	var remaining := maxf(wave_runtime.wave.duration_seconds - wave_runtime.elapsed, 0.0)
	hud_changed.emit(player.current_health, player.max_health, remaining, session.run_state.current_wave)
	if wave_runtime.is_finished():
		_finish_wave()


func clamp_to_arena(value: Vector2, margin: float) -> Vector2:
	return Vector2(
		clampf(value.x, arena_rect.position.x + margin, arena_rect.end.x - margin),
		clampf(value.y, arena_rect.position.y + margin, arena_rect.end.y - margin)
	)


func _spawn_enemy(enemy_id: StringName) -> void:
	var definition := session.content_snapshot.definition(enemy_id, &"enemy") as GogoEnemyDefinition
	var difficulty := session.content_snapshot.definition(session.run_state.difficulty_id, &"difficulty") as GogoDifficultyDefinition
	if definition == null or difficulty == null:
		return
	var enemy := GogoEnemyActor.new()
	enemy.configure(definition, player_actor, difficulty)
	enemy.position = _random_edge_position()
	enemy_layer.add_child(enemy)
	enemy.defeated.connect(_on_enemy_defeated)


func _random_edge_position() -> Vector2:
	var side := session.rng.randi_range(0, 3)
	match side:
		0: return Vector2(session.rng.randf_range(20.0, arena_rect.size.x - 20.0), 20.0)
		1: return Vector2(arena_rect.size.x - 20.0, session.rng.randf_range(20.0, arena_rect.size.y - 20.0))
		2: return Vector2(session.rng.randf_range(20.0, arena_rect.size.x - 20.0), arena_rect.size.y - 20.0)
		_: return Vector2(20.0, session.rng.randf_range(20.0, arena_rect.size.y - 20.0))


func _on_enemy_defeated(_enemy: GogoEnemyActor, xp: int, materials: int) -> void:
	var player := session.run_state.player()
	player.add_xp(xp)
	player.add_materials(materials)


func _on_player_health_changed(current: float, maximum: float) -> void:
	var remaining := maxf(wave_runtime.wave.duration_seconds - wave_runtime.elapsed, 0.0)
	hud_changed.emit(current, maximum, remaining, session.run_state.current_wave)


func _on_player_died() -> void:
	running = false
	session.fail_run()
	run_failed.emit()


func _finish_wave() -> void:
	running = false
	for enemy in enemy_layer.get_children(): enemy.queue_free()
	for projectile in projectile_layer.get_children(): projectile.queue_free()
	session.finish_wave()
	wave_completed.emit()


func _draw() -> void:
	draw_rect(arena_rect, Color("20252e"), true)
	for x in range(0, int(arena_rect.size.x), 64):
		draw_line(Vector2(x, 0), Vector2(x, arena_rect.size.y), Color(1, 1, 1, 0.025), 1.0)
	for y in range(0, int(arena_rect.size.y), 64):
		draw_line(Vector2(0, y), Vector2(arena_rect.size.x, y), Color(1, 1, 1, 0.025), 1.0)
	draw_rect(arena_rect, Color("657081"), false, 3.0)
