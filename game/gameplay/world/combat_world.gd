class_name CombatWorld
extends Node2D

const STATIC_WORLD_PRESENTER := preload("res://game/gameplay/world/static_world_presenter.gd")
const STATIC_SPAWN_MARKER := preload("res://game/gameplay/world/static_spawn_marker.gd")
const COMBAT_PICKUP := preload("res://game/gameplay/world/combat_pickup.gd")
const HOSTILE_PROJECTILE := preload("res://game/gameplay/world/hostile_projectile.gd")
const LOCAL_HITSTOP_MIN_SECONDS := 0.025
const LOCAL_HITSTOP_MAX_SECONDS := 0.060
const PLAYER_DAMAGE_HITSTOP_SECONDS := 0.040
const SPAWN_MIN_PLAYER_DISTANCE := 180.0
const SPAWN_RING_MIN := 320.0
const SPAWN_RING_MAX := 460.0
const SPAWN_ARENA_INSET := 40.0
const MAX_SIMULTANEOUS_ENEMIES := 160

signal wave_completed
signal run_failed
signal hud_changed(health: float, max_health: float, time_left: float, wave: int)
signal hud_snapshot_changed(snapshot: GogoCombatHudSnapshot)
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
signal projectile_contact_published(event: Dictionary)
signal enemy_defeated(
	enemy_instance_id: int,
	integer_death_global_position: Vector2i,
	xp: int,
	materials: int,
	death_sequence: int
)
signal pickup_collected(
	pickup_instance_id: int,
	kind: StringName,
	amount: int,
	integer_collection_global_position: Vector2i,
	collection_sequence: int
)

var session: GameSession
var wave_runtime := WaveRuntime.new()
var zone_runtime := ZoneRuntime.new()
var player_actor: GogoPlayerActor
var enemy_layer: Node2D
var projectile_layer: Node2D
var pickup_layer: Node2D
var effect_layer: Node2D
var player_camera: GogoCombatCamera
var feedback_presenter: GogoCombatFeedbackPresenter
var static_world_presenter: GogoStaticWorldPresenter
var weapon_trigger_runtime := GogoWeaponTriggerRuntime.new()
var arena_rect := Rect2(Vector2.ZERO, Vector2(2048.0, 1536.0))
var running := false
var _active_enemies: Array[GogoEnemyActor] = []
var _active_enemies_by_runtime_id: Dictionary = {}
var _active_pickups: Array[Node2D] = []
var _active_pickups_by_runtime_id: Dictionary = {}
var _pending_spawn_enemies: Dictionary = {}
var _projectile_source_item_ids: Dictionary = {}
var _wave_transition_committed := false
var _wave_start_materials := 0
var _local_hitstop_remaining := 0.0
var _local_hitstop_actor_phase_latched := false
var _run_failure_pending := false
var _pickup_collection_sequence := 0
var _wave_difficulty: GogoDifficultyDefinition


func _ready() -> void:
	static_world_presenter = STATIC_WORLD_PRESENTER.new() as GogoStaticWorldPresenter
	static_world_presenter.name = "StaticWorldPresenter"
	add_child(static_world_presenter)
	enemy_layer = Node2D.new()
	enemy_layer.name = "Enemies"
	add_child(enemy_layer)
	projectile_layer = Node2D.new()
	projectile_layer.name = "PlayerProjectiles"
	add_child(projectile_layer)
	pickup_layer = Node2D.new()
	pickup_layer.name = "PickupLayer"
	pickup_layer.z_index = 20
	add_child(pickup_layer)
	effect_layer = Node2D.new()
	effect_layer.name = "Effects"
	effect_layer.z_index = 40
	add_child(effect_layer)
	feedback_presenter = GogoCombatFeedbackPresenter.new()
	feedback_presenter.name = "CombatFeedbackPresenter"
	effect_layer.add_child(feedback_presenter)
	queue_redraw()


func _exit_tree() -> void:
	running = false
	_clear_active_combat_actors()


func start_wave(next_session: GameSession, wave_definition: GogoWaveDefinition) -> Error:
	if running:
		return ERR_ALREADY_IN_USE
	if (
		next_session == null
		or wave_definition == null
		or next_session.run_state == null
		or next_session.content_snapshot == null
		or next_session.run_state.ended
		or next_session.run_state.phase != &"combat"
		or next_session.run_state.player() == null
		or not is_finite(next_session.run_state.player().current_health)
		or next_session.run_state.player().current_health <= 0.0
	):
		return ERR_INVALID_PARAMETER
	var zone := next_session.content_snapshot.definition(next_session.run_state.zone_id, &"zone") as GogoZoneDefinition
	var difficulty := next_session.content_snapshot.definition(next_session.run_state.difficulty_id, &"difficulty") as GogoDifficultyDefinition
	if zone == null or difficulty == null:
		return ERR_INVALID_DATA
	if GogoWaveResolver.resolve(next_session) == null:
		return ERR_INVALID_DATA
	if GogoWaveResolver.validate_wave(wave_definition, next_session.content_snapshot, next_session.run_state.current_wave, difficulty.spawn_multiplier) != OK:
		return ERR_INVALID_DATA
	if next_session.run_state.current_wave > next_session.run_state.total_waves and not next_session.run_state.endless:
		return ERR_INVALID_DATA
	for multiplier in [difficulty.enemy_health_multiplier, difficulty.enemy_damage_multiplier, difficulty.enemy_speed_multiplier, difficulty.spawn_multiplier]:
		if not is_finite(multiplier) or multiplier < 0.0 or multiplier > 16.0:
			return ERR_INVALID_DATA
	var next_zone_runtime := ZoneRuntime.new()
	if next_zone_runtime.configure(zone) != OK:
		return ERR_INVALID_DATA
	_clear_active_combat_actors()
	session = next_session
	_wave_difficulty = difficulty.duplicate(true) as GogoDifficultyDefinition
	_wave_difficulty.enemy_health_multiplier *= wave_definition.enemy_health_multiplier
	_wave_difficulty.enemy_damage_multiplier *= wave_definition.enemy_damage_multiplier
	_wave_difficulty.enemy_speed_multiplier *= wave_definition.enemy_speed_multiplier
	_wave_start_materials = session.run_state.player().materials
	zone_runtime = next_zone_runtime
	_wave_transition_committed = false
	arena_rect = Rect2(Vector2.ZERO, zone.arena_size)
	static_world_presenter.configure(
		session.static_asset_snapshot,
		arena_rect,
		session.run_state.run_seed,
		session.static_asset_snapshot != null and session.static_asset_snapshot.is_development_preview()
	)
	wave_runtime.begin(wave_definition, difficulty.spawn_multiplier)
	if player_actor == null:
		player_actor = GogoPlayerActor.new()
		player_actor.configure(session, self)
		player_actor.position = arena_rect.get_center()
		add_child(player_actor)
		player_actor.died.connect(_on_player_died)
		player_actor.health_changed.connect(_on_player_health_changed)
	else:
		player_actor.configure(session, self)
		player_actor.position = arena_rect.get_center()
		player_actor.rebuild_weapons()
	player_actor.reset_health_regeneration_cycle()
	if not player_actor.damage_taken.is_connected(_on_player_damage_taken):
		player_actor.damage_taken.connect(_on_player_damage_taken)
	if player_camera == null:
		player_camera = GogoCombatCamera.new()
		player_camera.name = "PlayerCamera"
		add_child(player_camera)
	player_camera.configure(player_actor, arena_rect)
	feedback_presenter.configure(player_camera, session.static_asset_snapshot)
	feedback_presenter.clear_feedback()
	running = true
	_emit_hud_snapshot(wave_runtime.wave.duration_seconds)
	return OK


func bind_weapon_feedback(weapon: GogoWeaponInstance) -> void:
	if weapon == null:
		return
	if not weapon.weapon_fired.is_connected(_on_weapon_fired):
		weapon.weapon_fired.connect(_on_weapon_fired)
	if not weapon.melee_contact.is_connected(_on_melee_contact):
		weapon.melee_contact.connect(_on_melee_contact)


func bind_projectile_feedback(projectile: GogoProjectile) -> void:
	if projectile == null:
		return
	if not projectile.source_item_id.is_empty() and projectile.runtime_instance_id > 0:
		_projectile_source_item_ids[projectile.runtime_instance_id] = projectile.source_item_id
	if not projectile.projectile_contact.is_connected(_on_projectile_contact):
		projectile.projectile_contact.connect(_on_projectile_contact)


func note_ranged_attack(weapon_instance_id: int) -> Array[Dictionary]:
	if (
		weapon_instance_id <= 0
		or session == null
		or session.run_state == null
		or session.run_state.player() == null
	):
		return []
	return weapon_trigger_runtime.note_ranged_attack(
		weapon_instance_id,
		session.run_state.player().item_ids
	)


func bind_enemy_feedback(enemy: GogoEnemyActor) -> void:
	if enemy != null and not enemy.enemy_defeated.is_connected(_on_enemy_defeated):
		enemy.enemy_defeated.connect(_on_enemy_defeated)


func spawn_hostile_pulse(
	source_enemy: GogoEnemyActor,
	target_actor: GogoPlayerActor,
	shot_direction: Vector2,
	shot_damage: float
) -> GogoHostileProjectile:
	if (
		source_enemy == null
		or not is_instance_valid(source_enemy)
		or target_actor == null
		or not is_instance_valid(target_actor)
		or projectile_layer == null
		or session == null
	):
		return null
	var projectile := HOSTILE_PROJECTILE.new() as GogoHostileProjectile
	projectile.name = "HostilePulse_%d" % source_enemy.runtime_instance_id
	projectile.z_index = 24
	projectile_layer.add_child(projectile)
	if not projectile.activate(
		self,
		target_actor,
		source_enemy.runtime_instance_id,
		source_enemy.global_position.round(),
		shot_direction,
		shot_damage
	):
		return null
	return projectile


func _physics_process(delta: float) -> void:
	_local_hitstop_actor_phase_latched = _local_hitstop_remaining > 0.0
	_local_hitstop_remaining = maxf(_local_hitstop_remaining - maxf(delta, 0.0), 0.0)
	if _run_failure_pending and not is_combat_simulation_frozen():
		_commit_pending_run_failure()
		return
	if not running or session == null:
		return
	session.run_state.elapsed_seconds += delta
	if player_actor != null and is_instance_valid(player_actor):
		player_actor.tick_health_regeneration(delta)
	for enemy_id in wave_runtime.tick(delta):
		_spawn_enemy(enemy_id)
	var remaining := maxf(wave_runtime.wave.duration_seconds - wave_runtime.elapsed, 0.0)
	if wave_runtime.is_finished():
		_finish_wave()
	else:
		_emit_hud_snapshot(remaining)


func request_local_hitstop(seconds: float) -> void:
	if not is_finite(seconds) or seconds <= 0.0:
		return
	_local_hitstop_remaining = maxf(
		_local_hitstop_remaining,
		clampf(seconds, LOCAL_HITSTOP_MIN_SECONDS, LOCAL_HITSTOP_MAX_SECONDS)
	)


func is_combat_simulation_frozen() -> bool:
	return _local_hitstop_actor_phase_latched or _local_hitstop_remaining > 0.0


func debug_local_hitstop_remaining() -> float:
	return _local_hitstop_remaining


func clamp_to_arena(value: Vector2, margin: float) -> Vector2:
	return Vector2(
		clampf(value.x, arena_rect.position.x + margin, arena_rect.end.x - margin),
		clampf(value.y, arena_rect.position.y + margin, arena_rect.end.y - margin)
	)


func allocate_runtime_instance_id(kind: StringName) -> int:
	if session == null:
		return 0
	return session.allocate_runtime_instance_id(kind)


func register_active_enemy(enemy: GogoEnemyActor) -> bool:
	if enemy == null or enemy.runtime_instance_id <= 0 or enemy.defeated_once:
		return false
	var runtime_id := enemy.runtime_instance_id
	if _active_enemies_by_runtime_id.has(runtime_id):
		return _active_enemies_by_runtime_id[runtime_id] == enemy
	_active_enemies_by_runtime_id[runtime_id] = enemy
	var insert_at := 0
	while insert_at < _active_enemies.size() and _active_enemies[insert_at].runtime_instance_id < runtime_id:
		insert_at += 1
	_active_enemies.insert(insert_at, enemy)
	return true


func unregister_active_enemy(runtime_instance_id: int, expected_enemy: GogoEnemyActor = null) -> void:
	if runtime_instance_id <= 0 or not _active_enemies_by_runtime_id.has(runtime_instance_id):
		return
	var registered := _active_enemies_by_runtime_id[runtime_instance_id] as GogoEnemyActor
	if expected_enemy != null and registered != expected_enemy:
		return
	_active_enemies_by_runtime_id.erase(runtime_instance_id)
	_active_enemies.erase(registered)


func active_enemy_count() -> int:
	return _active_enemies.size()


func active_enemy_at(index: int) -> GogoEnemyActor:
	if index < 0 or index >= _active_enemies.size():
		return null
	return _active_enemies[index]


func is_active_enemy(enemy: GogoEnemyActor) -> bool:
	return (
		enemy != null
		and enemy.runtime_instance_id > 0
		and _active_enemies_by_runtime_id.get(enemy.runtime_instance_id) == enemy
		and enemy.can_receive_projectile_contact()
	)


func nearest_active_enemy(origin: Vector2, maximum_distance: float) -> GogoEnemyActor:
	var nearest: GogoEnemyActor
	var best_distance := maximum_distance * maximum_distance
	for enemy in _active_enemies:
		if not is_active_enemy(enemy):
			continue
		var distance := origin.distance_squared_to(enemy.global_position)
		if distance < best_distance or (nearest == null and distance <= best_distance):
			best_distance = distance
			nearest = enemy
	return nearest


func register_active_pickup(pickup: Node2D) -> bool:
	if (
		pickup == null
		or int(pickup.get("runtime_instance_id")) <= 0
		or int(pickup.get("state")) == int(COMBAT_PICKUP.COLLECTED)
	):
		return false
	var runtime_id := int(pickup.get("runtime_instance_id"))
	if _active_pickups_by_runtime_id.has(runtime_id):
		return _active_pickups_by_runtime_id[runtime_id] == pickup
	_active_pickups_by_runtime_id[runtime_id] = pickup
	var insert_at := 0
	while (
		insert_at < _active_pickups.size()
		and int(_active_pickups[insert_at].get("runtime_instance_id")) < runtime_id
	):
		insert_at += 1
	_active_pickups.insert(insert_at, pickup)
	return true


func unregister_active_pickup(
	runtime_instance_id: int,
	expected_pickup: Node2D = null
) -> void:
	if runtime_instance_id <= 0 or not _active_pickups_by_runtime_id.has(runtime_instance_id):
		return
	var registered := _active_pickups_by_runtime_id[runtime_instance_id] as Node2D
	if expected_pickup != null and registered != expected_pickup:
		return
	_active_pickups_by_runtime_id.erase(runtime_instance_id)
	_active_pickups.erase(registered)


func active_pickup_count() -> int:
	return _active_pickups.size()


func active_pickup_at(index: int) -> Node2D:
	if index < 0 or index >= _active_pickups.size():
		return null
	return _active_pickups[index]


func collect_pickup(pickup: Node2D) -> StringName:
	if pickup == null or session == null:
		return GameSession.REWARD_INVALID
	var runtime_instance_id := int(pickup.get("runtime_instance_id"))
	if _active_pickups_by_runtime_id.get(runtime_instance_id) != pickup:
		return GameSession.REWARD_DUPLICATE
	unregister_active_pickup(runtime_instance_id, pickup)
	var reward_entries: Array = pickup.get("reward_entries") as Array
	if reward_entries.is_empty():
		reward_entries = [{
			&"kind": StringName(pickup.get("reward_kind")),
			&"amount": int(pickup.get("reward_amount")),
			&"token": StringName(pickup.get("reward_token")),
			&"reservation_id": int(pickup.get("reward_reservation_id")),
		}]
	var collection_position := Vector2i(pickup.global_position.round())
	var overall_result: StringName = GameSession.REWARD_APPLIED
	var applied_entry_count := 0
	var applied_visual_amount := 0
	for kind in [GameSession.REWARD_EXPERIENCE, GameSession.REWARD_SUPPLY]:
		for entry_value in reward_entries:
			if not entry_value is Dictionary:
				if overall_result == GameSession.REWARD_APPLIED:
					overall_result = GameSession.REWARD_INVALID
				continue
			var entry := entry_value as Dictionary
			if StringName(entry.get(&"kind", &"")) != kind:
				continue
			var result := session.apply_reserved_reward(
				StringName(entry.get(&"token", &"")),
				int(entry.get(&"reservation_id", 0))
			)
			if result != GameSession.REWARD_APPLIED:
				if overall_result == GameSession.REWARD_APPLIED:
					overall_result = result
				continue
			applied_entry_count += 1
			applied_visual_amount += maxi(int(entry.get(&"amount", 0)), 0)
			_pickup_collection_sequence += 1
			pickup_collected.emit(
				runtime_instance_id,
				kind,
				int(entry.get(&"amount", 0)),
				collection_position,
				_pickup_collection_sequence
			)
	if applied_entry_count > 0:
		overall_result = GameSession.REWARD_APPLIED
		if feedback_presenter != null:
			feedback_presenter.present_pickup_collected(
				runtime_instance_id,
				collection_position,
				maxi(applied_visual_amount, 1),
				_pickup_collection_sequence
			)
	elif overall_result == GameSession.REWARD_APPLIED:
		overall_result = GameSession.REWARD_INVALID
	pickup.queue_free()
	return overall_result


func collect_all_live_pickups() -> void:
	# `_active_pickups` is maintained in runtime-ID order. Duplicate the list
	# because every successful or stale collection unregisters itself synchronously.
	var ordered_pickups := _active_pickups.duplicate()
	for pickup: Node2D in ordered_pickups:
		if pickup != null and is_instance_valid(pickup):
			pickup.call(&"collect_now")


func commit_enemy_reward_snapshot(
	enemy_instance_id: int,
	death_sequence: int,
	xp: int,
	materials: int,
	player_index: int = 0
) -> Dictionary:
	var reservations := _reserve_enemy_reward_snapshot(
		enemy_instance_id,
		death_sequence,
		xp,
		materials,
		player_index
	)
	return _apply_reserved_enemy_rewards(reservations)


func _reserve_enemy_reward_snapshot(
	enemy_instance_id: int,
	death_sequence: int,
	xp: int,
	materials: int,
	player_index: int = 0
) -> Dictionary:
	var reservations: Dictionary = {}
	if session == null or enemy_instance_id <= 0 or death_sequence <= 0 or xp < 0 or materials < 0:
		reservations[&"status"] = GameSession.REWARD_INVALID
		return reservations
	if xp > 0:
		var experience_token := enemy_reward_token(enemy_instance_id, death_sequence, GameSession.REWARD_EXPERIENCE)
		var experience_reservation := session.reserve_reward_once(
			experience_token,
			GameSession.REWARD_EXPERIENCE,
			xp,
			player_index
		)
		experience_reservation[&"amount"] = xp
		reservations[GameSession.REWARD_EXPERIENCE] = experience_reservation
	if materials > 0:
		var supply_token := enemy_reward_token(enemy_instance_id, death_sequence, GameSession.REWARD_SUPPLY)
		var supply_reservation := session.reserve_reward_once(
			supply_token,
			GameSession.REWARD_SUPPLY,
			materials,
			player_index
		)
		supply_reservation[&"amount"] = materials
		reservations[GameSession.REWARD_SUPPLY] = supply_reservation
	return reservations


func _apply_reserved_enemy_rewards(reservations: Dictionary) -> Dictionary:
	var results: Dictionary = {}
	if reservations.has(&"status"):
		results[&"status"] = reservations[&"status"]
		return results
	for kind in [GameSession.REWARD_EXPERIENCE, GameSession.REWARD_SUPPLY]:
		if not reservations.has(kind):
			continue
		var reservation: Dictionary = reservations[kind]
		var status := StringName(reservation.get("status", GameSession.REWARD_INVALID))
		if status == GameSession.REWARD_RESERVED:
			results[kind] = session.apply_reserved_reward(
				StringName(reservation.get("token", &"")),
				int(reservation.get("reservation_id", 0))
			)
		else:
			results[kind] = status
	return results


func spawn_reserved_enemy_pickups(
	enemy_runtime_instance_id: int,
	integer_death_global_position: Vector2i,
	reservations: Dictionary
) -> int:
	if (
		session == null
		or player_actor == null
		or pickup_layer == null
		or enemy_runtime_instance_id <= 0
	):
		return 0
	var reward_entries: Array[Dictionary] = []
	var material_amount := 0
	for kind in [GameSession.REWARD_EXPERIENCE, GameSession.REWARD_SUPPLY]:
		if not reservations.has(kind):
			continue
		var reservation := reservations[kind] as Dictionary
		if StringName(reservation.get("status", GameSession.REWARD_INVALID)) != GameSession.REWARD_RESERVED:
			continue
		var amount := int(reservation.get("amount", 0))
		if amount <= 0:
			continue
		reward_entries.append({
			&"kind": kind,
			&"amount": amount,
			&"token": StringName(reservation.get("token", &"")),
			&"reservation_id": int(reservation.get("reservation_id", 0)),
		})
		if kind == GameSession.REWARD_SUPPLY:
			material_amount = amount
	if reward_entries.is_empty():
		return 0
	var runtime_instance_id := allocate_runtime_instance_id(&"pickup")
	if runtime_instance_id <= 0:
		return 0
	var visual_denomination := clampi(material_amount, 1, 2) if material_amount > 0 else 1
	var visual_handle: GogoStaticAssetHandle
	if session.static_asset_snapshot != null:
		var asset_id := &"supply_pickup" if visual_denomination >= 2 else &"experience_pickup"
		visual_handle = session.static_asset_snapshot.resolve_asset(asset_id, &"world_sprite")
	var pickup := COMBAT_PICKUP.new() as Node2D
	pickup.name = "Pickup_%d_bundle" % runtime_instance_id
	pickup_layer.add_child(pickup)
	if not bool(pickup.call(
		&"configure_bundle",
		self,
		player_actor,
		runtime_instance_id,
		enemy_runtime_instance_id,
		reward_entries,
		visual_handle,
		Vector2(integer_death_global_position)
	)):
		pickup.queue_free()
		return 0
	if not register_active_pickup(pickup):
		pickup.queue_free()
		return 0
	return 1


static func enemy_reward_token(enemy_instance_id: int, death_sequence: int, kind: StringName) -> StringName:
	if enemy_instance_id <= 0 or death_sequence <= 0 or not [GameSession.REWARD_EXPERIENCE, GameSession.REWARD_SUPPLY].has(kind):
		return &""
	return StringName("enemy/%d/death/%d/%s" % [enemy_instance_id, death_sequence, String(kind)])


func _spawn_enemy(enemy_id: StringName) -> void:
	if not running or _active_enemies.size() + _pending_spawn_enemies.size() >= MAX_SIMULTANEOUS_ENEMIES:
		return
	var definition := session.content_snapshot.definition(enemy_id, &"enemy") as GogoEnemyDefinition
	var difficulty := _wave_difficulty
	if definition == null or difficulty == null:
		return
	# definition() returns a copy: actor speed/damage are local, health composes
	# through configure(). The catalog and shared difficulty remain immutable.
	definition.movement_speed *= difficulty.enemy_speed_multiplier
	definition.touch_damage *= difficulty.enemy_damage_multiplier
	var runtime_instance_id := allocate_runtime_instance_id(&"enemy")
	if runtime_instance_id <= 0:
		return
	var enemy := GogoEnemyActor.new()
	enemy.configure(definition, player_actor, difficulty, self, runtime_instance_id)
	var spawn_position := _random_edge_position().round()
	_pending_spawn_enemies[runtime_instance_id] = enemy
	_queue_spawn_marker(enemy, spawn_position)


func _queue_spawn_marker(enemy: GogoEnemyActor, spawn_position: Vector2) -> void:
	var marker := STATIC_SPAWN_MARKER.new() as GogoStaticSpawnMarker
	marker.name = "SpawnMarker_%d" % enemy.runtime_instance_id
	var marker_handle: GogoStaticAssetHandle
	if session.static_asset_snapshot != null:
		marker_handle = session.static_asset_snapshot.resolve_asset(&"spawn_marker", &"world_sprite")
	marker.configure_visual(marker_handle, enemy.definition.is_boss)
	effect_layer.add_child(marker)
	marker.play(
		spawn_position,
		func() -> void: _activate_spawned_enemy(enemy, spawn_position)
	)


func _activate_spawned_enemy(enemy: GogoEnemyActor, spawn_position: Vector2) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	if not running or enemy.is_inside_tree():
		_pending_spawn_enemies.erase(enemy.runtime_instance_id)
		if not enemy.is_inside_tree():
			enemy.free()
		return
	# A fast build may reach the warning before activation. Relocate and warn
	# again, never silently materialize a body underneath the moving player.
	if spawn_position.distance_to(player_actor.global_position) < SPAWN_MIN_PLAYER_DISTANCE:
		var relocated_position := _random_edge_position().round()
		if relocated_position.distance_to(player_actor.global_position) < SPAWN_MIN_PLAYER_DISTANCE:
			# Tiny arenas/viewports may have no safe point. Drop this spawn instead
			# of recursively retrying the synchronous missing-marker fallback.
			_pending_spawn_enemies.erase(enemy.runtime_instance_id)
			enemy.free()
			return
		_queue_spawn_marker(enemy, relocated_position)
		return
	_pending_spawn_enemies.erase(enemy.runtime_instance_id)
	enemy.position = spawn_position
	enemy_layer.add_child(enemy)
	if not register_active_enemy(enemy):
		enemy.queue_free()


func _random_edge_position() -> Vector2:
	# Edge means the player's engagement ring, not the distant 2048x1536 map.
	# Use the camera's actual zoom/viewport so warnings remain readable at edges.
	var visible_size := player_camera.get_viewport_rect().size / player_camera.zoom
	var visible := Rect2(player_camera.global_position - visible_size * 0.5, visible_size)
	var safe_rect := visible.grow(-40.0).intersection(arena_rect.grow(-SPAWN_ARENA_INSET))
	var origin := player_actor.global_position
	for attempt in 64:
		var direction := Vector2.RIGHT.rotated(session.rng.randf_range(0.0, TAU))
		var candidate := origin + direction * session.rng.randf_range(SPAWN_RING_MIN, SPAWN_RING_MAX)
		if safe_rect.has_point(candidate):
			return candidate
	# Deterministic bounded fallback for camera/arena corners. Clip the ring, not
	# the player safety radius; the farthest candidate avoids rejection starvation.
	var best := safe_rect.get_center()
	for index in 16:
		var candidate := origin + Vector2.RIGHT.rotated(TAU * float(index) / 16.0) * SPAWN_RING_MIN
		candidate = Vector2(clampf(candidate.x, safe_rect.position.x, safe_rect.end.x), clampf(candidate.y, safe_rect.position.y, safe_rect.end.y))
		if candidate.distance_squared_to(origin) > best.distance_squared_to(origin):
			best = candidate
	return best


func _on_player_health_changed(_current: float, _maximum: float) -> void:
	if session == null or session.run_state == null or wave_runtime.wave == null:
		return
	var remaining := maxf(wave_runtime.wave.duration_seconds - wave_runtime.elapsed, 0.0)
	_emit_hud_snapshot(remaining)


func _on_player_damage_taken(
	integer_global_position: Vector2i,
	final_damage: float,
	remaining_health: float,
	lethal: bool,
	sequence: int
) -> void:
	request_local_hitstop(PLAYER_DAMAGE_HITSTOP_SECONDS)
	if feedback_presenter != null:
		feedback_presenter.present_player_damage_taken(
			integer_global_position,
			final_damage,
			remaining_health,
			lethal,
			sequence
		)


func _emit_hud_snapshot(remaining: float) -> void:
	if session == null or session.run_state == null:
		return
	var player := session.run_state.player()
	if player == null:
		return
	var snapshot := GogoCombatHudSnapshot.create(
		player,
		remaining,
		session.run_state.current_wave,
		wave_runtime.elapsed,
		maxi(player.materials - _wave_start_materials, 0),
		session.run_state.endless,
		session.run_state.total_waves
	)
	hud_snapshot_changed.emit(snapshot)
	hud_changed.emit(snapshot.health, snapshot.maximum_health, snapshot.seconds, snapshot.wave)


func _on_player_died() -> void:
	if _wave_transition_committed:
		return
	_wave_transition_committed = true
	running = false
	_run_failure_pending = true
	_clear_active_combat_actors(true)
	if session != null:
		session.fail_run()


func _commit_pending_run_failure() -> void:
	if not _run_failure_pending:
		return
	_run_failure_pending = false
	run_failed.emit()


func _on_weapon_fired(
	weapon_instance_id: int,
	feedback_profile_id: StringName,
	integer_muzzle_global_position: Vector2i,
	shot_direction: Vector2,
	projectile_count: int,
	shot_sequence: int
) -> void:
	if feedback_presenter != null:
		feedback_presenter.present_weapon_fired(
			weapon_instance_id,
			feedback_profile_id,
			integer_muzzle_global_position,
			shot_direction,
			projectile_count,
			shot_sequence
		)
	weapon_fired.emit(
		weapon_instance_id,
		feedback_profile_id,
		integer_muzzle_global_position,
		shot_direction,
		projectile_count,
		shot_sequence
	)


func _on_projectile_contact(
	projectile_instance_id: int,
	target_instance_id: int,
	feedback_profile_id: StringName,
	integer_contact_global_position: Vector2i,
	contact_normal: Vector2,
	damage_kind: StringName,
	impact_kind: StringName,
	contact_sequence: int
) -> void:
	_request_target_local_hitstop(
		target_instance_id,
		_contact_hitstop_duration(feedback_profile_id, impact_kind)
	)
	if feedback_presenter != null:
		feedback_presenter.present_projectile_contact(
			projectile_instance_id,
			target_instance_id,
			feedback_profile_id,
			integer_contact_global_position,
			contact_normal,
			damage_kind,
			impact_kind,
			contact_sequence
		)
	projectile_contact.emit(
		projectile_instance_id,
		target_instance_id,
		feedback_profile_id,
		integer_contact_global_position,
		contact_normal,
		damage_kind,
		impact_kind,
		contact_sequence
	)
	projectile_contact_published.emit({
		"projectile_instance_id": projectile_instance_id,
		"target_instance_id": target_instance_id,
		"feedback_profile_id": feedback_profile_id,
		"integer_contact_global_position": integer_contact_global_position,
		"contact_normal": contact_normal,
		"damage_kind": damage_kind,
		"impact_kind": impact_kind,
		"contact_sequence": contact_sequence,
		"source_item_id": StringName(_projectile_source_item_ids.get(projectile_instance_id, &"")),
	})


func _on_melee_contact(
	weapon_instance_id: int,
	target_instance_id: int,
	feedback_profile_id: StringName,
	integer_contact_global_position: Vector2i,
	contact_normal: Vector2,
	damage_kind: StringName,
	impact_kind: StringName,
	melee_sequence: int
) -> void:
	_request_target_local_hitstop(
		target_instance_id,
		_contact_hitstop_duration(feedback_profile_id, impact_kind)
	)
	if feedback_presenter != null:
		feedback_presenter.present_melee_contact(
			weapon_instance_id,
			target_instance_id,
			feedback_profile_id,
			integer_contact_global_position,
			contact_normal,
			damage_kind,
			impact_kind,
			melee_sequence
		)
	melee_contact.emit(
		weapon_instance_id,
		target_instance_id,
		feedback_profile_id,
		integer_contact_global_position,
		contact_normal,
		damage_kind,
		impact_kind,
		melee_sequence
	)


static func _contact_hitstop_duration(
	feedback_profile_id: StringName,
	_impact_kind: StringName
) -> float:
	return 0.035 if feedback_profile_id == &"heavy" else 0.0


func _request_target_local_hitstop(target_instance_id: int, seconds: float) -> void:
	if target_instance_id <= 0 or seconds <= 0.0:
		return
	var target_enemy := _active_enemies_by_runtime_id.get(target_instance_id) as GogoEnemyActor
	if target_enemy == null or not is_instance_valid(target_enemy) or target_enemy.defeated_once:
		return
	target_enemy.request_target_local_hitstop(seconds)


func _on_enemy_defeated(
	enemy_instance_id: int,
	integer_death_global_position: Vector2i,
	xp: int,
	materials: int,
	death_sequence: int
) -> void:
	if feedback_presenter != null:
		feedback_presenter.present_enemy_defeated(
			enemy_instance_id,
			integer_death_global_position,
			xp,
			materials,
			death_sequence
		)
	enemy_defeated.emit(enemy_instance_id, integer_death_global_position, xp, materials, death_sequence)


func _finish_wave() -> void:
	if _wave_transition_committed:
		return
	_wave_transition_committed = true
	collect_all_live_pickups()
	_emit_hud_snapshot(0.0)
	running = false
	_clear_active_combat_actors()
	session.finish_wave()
	wave_completed.emit()


func _clear_active_combat_actors(preserve_terminal_hit_feedback := false) -> void:
	if not preserve_terminal_hit_feedback:
		_local_hitstop_remaining = 0.0
		_local_hitstop_actor_phase_latched = false
		_run_failure_pending = false
	weapon_trigger_runtime.reset()
	_projectile_source_item_ids.clear()
	_active_enemies.clear()
	_active_enemies_by_runtime_id.clear()
	_active_pickups.clear()
	_active_pickups_by_runtime_id.clear()
	if enemy_layer != null:
		for enemy in enemy_layer.get_children():
			if enemy is GogoEnemyActor:
				(enemy as GogoEnemyActor).retire_without_reward()
			else:
				enemy.queue_free()
	if projectile_layer != null:
		for projectile in projectile_layer.get_children():
			if projectile is GogoProjectile:
				(projectile as GogoProjectile).retire()
			elif projectile is GogoHostileProjectile:
				(projectile as GogoHostileProjectile).retire()
			else:
				projectile.queue_free()
	if pickup_layer != null:
		for pickup in pickup_layer.get_children():
			pickup.queue_free()
	if feedback_presenter != null and not preserve_terminal_hit_feedback:
		feedback_presenter.clear_feedback()
	if effect_layer != null:
		for child in effect_layer.get_children():
			if child is GogoStaticSpawnMarker:
				(child as GogoStaticSpawnMarker).cancel()
	for pending_enemy: GogoEnemyActor in _pending_spawn_enemies.values():
		if pending_enemy != null and is_instance_valid(pending_enemy):
			if pending_enemy.is_inside_tree():
				pending_enemy.retire_without_reward()
			else:
				pending_enemy.free()
	_pending_spawn_enemies.clear()


func _draw() -> void:
	draw_rect(arena_rect, Color(0.48, 0.52, 0.48), true)
	for x in range(0, int(arena_rect.size.x), 64):
		draw_line(Vector2(x, 0), Vector2(x, arena_rect.size.y), Color(1, 1, 1, 0.025), 1.0)
	for y in range(0, int(arena_rect.size.y), 64):
		draw_line(Vector2(0, y), Vector2(arena_rect.size.x, y), Color(1, 1, 1, 0.025), 1.0)
	draw_rect(arena_rect, Color("657081"), false, 3.0)
