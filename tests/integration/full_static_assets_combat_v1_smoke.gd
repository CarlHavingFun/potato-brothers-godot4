extends GdUnitTestSuite


const OUTPUT_DIR_URI := "user://full-static-assets-combat-v1"
const CAPTURE_URI := OUTPUT_DIR_URI + "/combat-1280x720.png"
const PAUSE_CAPTURE_URI := OUTPUT_DIR_URI + "/pause-1280x720.png"
const COVERAGE_URI := OUTPUT_DIR_URI + "/gogobro-static-coverage-v1.json"
const REGISTRY_PATH := "res://game/content/assets/gogobro_static_assets_v1.json"
const CAPTURE_SIZE := Vector2i(1280, 720)
const CAPTURE_ARENA_SIZE := Vector2(1280, 720)
const CAPTURE_ENEMY_COUNT := 10
const CAPTURE_ENEMY_HALF_EXTENT := Vector2(22.0, 22.0)
const CAPTURE_ENEMY_MINIMUM_SEPARATION := 66.0
const CAPTURE_ENEMY_WEAPON_GAP := 28.0
const APP_SCENE := preload("res://game/app/app_root.tscn")
const TARGET_ENEMY_ID: StringName = &"gogobro.core:enemy/drifter"
const CAPTURE_ENEMY_IDS: Array[StringName] = [
	&"gogobro.core:enemy/drifter",
	&"gogobro.core:enemy/spark",
	&"gogobro.core:enemy/rammer",
]
const SKYLINE_GRENADE_ID: StringName = &"gogobro.preview:item/skyline_grenade"
const CAPTURE_WEAPON_IDS: Array[StringName] = [
	&"gogobro.preview:weapon/wood_stock_assault_rifle",
	&"gogobro.preview:weapon/heavy_bolt_sniper",
	&"gogobro.preview:weapon/suppressed_carbine",
	&"gogobro.preview:weapon/heavy_hand_cannon",
	&"gogobro.preview:weapon/bullpup_pdw",
	&"gogobro.preview:weapon/folding_stock_submachine_gun",
]
const CAPTURE_ITEM_IDS: Array[StringName] = [
	SKYLINE_GRENADE_ID,
	&"gogobro.preview:item/smoke_shell_helmet",
	&"gogobro.preview:item/corner_lucky_claw",
	&"gogobro.preview:item/sneaky_site_mask",
]
const EXPECTED_AUDIO_EVENT_CLASSES: Array[StringName] = [
	&"weapon_fired",
	&"projectile_contact",
	&"melee_contact",
	&"enemy_defeated",
	&"player_damage_taken",
	&"pickup_collected",
]
const EXPECTED_AUDIO_SHOT_VARIANTS: Array[StringName] = [
	&"rapid", &"rifle", &"heavy", &"suppressed",
]
const EXPECTED_AUDIO_CONTACT_VARIANTS: Array[StringName] = [
	&"normal", &"critical", &"pierce_exit", &"explosion",
]
const HUD_SCREEN_EXCLUSION_RECTS: Array[Rect2] = [
	Rect2(0, 0, 368, 244),
	Rect2(448, 0, 384, 112),
]
const EXPECTED_WORLD_EVIDENCE_COUNTS := {
	"community_server_floor": 1,
	"community_server_decor_pack": 6,
	"hazard_beacon": 1,
	"supply_crate": 1,
	"weapon_rack": 1,
	"medical_pickup": 1,
	"site_hold_turret": 1,
	"spawn_marker": 1,
}
const EXPECTED_DECOR_SELECTORS: Array[StringName] = [
	&"decor_variant_01",
	&"decor_variant_02",
	&"decor_variant_03",
	&"decor_variant_04",
	&"decor_variant_05",
	&"decor_variant_06",
]
const CAPTURE_ENEMY_ANCHOR_FACTORS: Array[Vector2] = [
	Vector2(0.32, 0.23), Vector2(0.68, 0.24), Vector2(0.78, 0.26),
	Vector2(0.88, 0.32), Vector2(0.96, 0.40), Vector2(0.91, 0.50),
	Vector2(0.95, 0.62), Vector2(0.88, 0.72), Vector2(0.76, 0.62),
	Vector2(0.72, 0.80), Vector2(0.63, 0.83), Vector2(0.54, 0.90),
	Vector2(0.42, 0.86), Vector2(0.32, 0.82), Vector2(0.22, 0.86),
	Vector2(0.12, 0.78), Vector2(0.16, 0.64), Vector2(0.08, 0.56),
	Vector2(0.14, 0.43), Vector2(0.24, 0.38), Vector2(0.30, 0.27),
	Vector2(0.40, 0.18), Vector2(0.58, 0.18), Vector2(0.74, 0.18),
	Vector2(0.84, 0.42), Vector2(0.82, 0.58), Vector2(0.66, 0.91),
	Vector2(0.48, 0.92), Vector2(0.28, 0.74), Vector2(0.10, 0.68),
	Vector2(0.18, 0.52), Vector2(0.20, 0.32), Vector2(0.36, 0.30),
]

var _shot_count := 0
var _impact_count := 0
var _impact_kinds_observed: Dictionary = {}
var _impact_sources: Dictionary = {}
var _pickup_collection_count := 0
var _pickup_kinds_observed: Dictionary = {}
var _real_melee_events: Array[Dictionary] = []
var _real_player_damage_events: Array[Dictionary] = []


func before_test() -> void:
	_shot_count = 0
	_impact_count = 0
	_impact_kinds_observed.clear()
	_impact_sources.clear()
	_pickup_collection_count = 0
	_pickup_kinds_observed.clear()
	_real_melee_events.clear()
	_real_player_damage_events.clear()


func test_capture_enemy_geometry_gate_rejects_rings_and_radial_jitter() -> void:
	var center := Vector2(640.0, 360.0)
	var perfect_ring: Array[Vector2] = []
	var radial_jitter_only: Array[Vector2] = []
	var angular_jitter_only: Array[Vector2] = []
	for index in CAPTURE_ENEMY_COUNT:
		var equal_angle := TAU * float(index) / float(CAPTURE_ENEMY_COUNT)
		perfect_ring.append(center + Vector2.RIGHT.rotated(equal_angle) * 330.0)
		radial_jitter_only.append(
			center + Vector2.RIGHT.rotated(equal_angle) * (270.0 + 24.0 * float(index))
		)
		var uneven_angle := equal_angle + deg_to_rad(float((index * index) % 9) * 2.5)
		angular_jitter_only.append(center + Vector2.RIGHT.rotated(uneven_angle) * 330.0)

	assert_bool(_enemy_positions_have_asymmetric_radii(perfect_ring, center)).is_false()
	assert_bool(_enemy_positions_have_unequal_angular_gaps(perfect_ring, center)).is_false()
	assert_bool(_enemy_positions_have_asymmetric_radii(radial_jitter_only, center)).is_true()
	assert_bool(_enemy_positions_have_unequal_angular_gaps(radial_jitter_only, center)).is_false()
	assert_bool(_enemy_positions_have_asymmetric_radii(angular_jitter_only, center)).is_false()
	assert_bool(_enemy_positions_have_unequal_angular_gaps(angular_jitter_only, center)).is_true()


func test_capture_actual_six_weapon_combat_and_coverage() -> void:
	GogoStaticConsumerRegistry.reset_current()
	var root_window := auto_free(SubViewport.new()) as SubViewport
	root_window.size = CAPTURE_SIZE
	root_window.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_tree().root.add_child(root_window)
	var app := APP_SCENE.instantiate() as AppKernel
	root_window.add_child(app)
	await get_tree().process_frame
	await get_tree().process_frame
	if not _require(app.boot_result != null and app.boot_result.is_ok(), "application boot"):
		return
	var content := _capture_content_snapshot(app.content_snapshot)
	if not _require(content != null, "capture content snapshot"):
		return
	var snapshot := app.static_asset_service.active_snapshot()
	if not _require(snapshot != null and snapshot.is_development_preview(), "development preview assets"):
		return
	if not _require(content.all(&"character").size() == 1, "Niko-only character scope"):
		return
	app.begin_selection()
	app.selection_draft["character_id"] = ValidationContentFactory.CHARACTER_ID
	app.selection_draft["weapon_id"] = ValidationContentFactory.RANGED_ID
	if not _require(app.route(FlowRoute.CHARACTER_SELECT) == OK, "actual staged configuration coverage route"):
		return
	await get_tree().process_frame
	var coverage_host := app.get_node("SceneHost") as Node
	var staged_route := coverage_host.get_child(0) as Control
	var task_option := staged_route.get_node_or_null("TaskOptionButton") as OptionButton
	if not _require(
		app.scene_flow.current_route() == FlowRoute.CHARACTER_SELECT
		and staged_route.get_script() != null
		and (staged_route.get_script() as Script).resource_path
			== "res://game/ui/character_select_screen.gd"
		and task_option != null
		and task_option.is_visible_in_tree()
		and task_option.item_count == content.all(&"zone").size()
		and task_option.selected >= 0
		and task_option.get_item_metadata(task_option.selected) == ValidationContentFactory.ZONE_ID
		and task_option.get_item_icon(task_option.selected) != null
		and (staged_route.get_node("DifficultyStage") as Control).visible,
		"real visible inline task-option zone coverage"
	):
		return
	if not _require(app.route(FlowRoute.DIAGNOSTIC, {
		"message": "覆盖诊断",
		"details": ["真实战斗审计路由"],
	}) == OK, "actual diagnostic coverage route"):
		return
	await get_tree().process_frame
	var diagnostic_route := coverage_host.get_child(0) as Control
	if not _require(
		diagnostic_route.get_script() != null
		and (diagnostic_route.get_script() as Script).resource_path
			== "res://game/ui/diagnostic_screen.gd"
		and diagnostic_route.get_node_or_null("PrincipalSurface") is Panel
		and (diagnostic_route.get_node("PrincipalSurface") as Panel).is_visible_in_tree(),
		"real visible diagnostic-panel coverage"
	):
		return

	var ranged := _capture_weapons(content)
	if not _require(ranged.size() == CAPTURE_WEAPON_IDS.size(), "six stable capture weapons"):
		return
	var config := SessionConfig.new()
	config.seed = 9137
	config.character_id = ValidationContentFactory.CHARACTER_ID
	config.starting_weapon_id = ranged[0].content_id
	config.difficulty_id = ValidationContentFactory.DIFFICULTY_ID
	config.zone_id = ValidationContentFactory.ZONE_ID
	var session := GameSession.new()
	session.static_asset_snapshot = snapshot
	if not _require(session.start(config, content) == OK, "combat session start"):
		return
	var player := session.run_state.player()
	player.weapon_inventory = GogoWeaponInventory.new()
	for index in 6:
		var allocation := player.weapon_inventory.add_weapon(
			(ranged[index] as GogoWeaponDefinition).content_id,
			content
		)
		if not _require(allocation.get("error", ERR_INVALID_DATA) == OK, "six-weapon inventory allocation"):
			return
	player.item_ids = _capture_item_ids(content)
	player.materials = 87
	player.xp = 14
	player.level = 4
	app.current_session = session
	if not _require(app.route(FlowRoute.COMBAT) == OK, "actual combat route"):
		return
	await get_tree().process_frame
	await get_tree().process_frame
	var host := app.get_node("SceneHost") as Node
	var combat_screen := host.get_child(0) as Node2D
	var world := combat_screen.get("world") as CombatWorld
	var hud := combat_screen.get("hud") as GogoBrotatoCombatHud
	var audio_presenter := combat_screen.get("audio_presenter") as GogoCombatAudioPresenter
	if not _require(
		world != null and hud != null and audio_presenter != null,
		"actual combat world, fixed HUD, and combat audio presenter"
	):
		return
	var hud_shell := hud.get_node_or_null("Shell") as TextureRect
	if not _require(
		hud_shell != null
		and hud_shell.texture == null
		and not hud_shell.visible
		and not hud_shell.is_visible_in_tree()
		and hud_shell.size == Vector2(CAPTURE_SIZE)
		and hud_shell.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST
		and (hud.get_node("TopLeft/Health") as Panel).is_visible_in_tree()
		and (hud.get_node("TopCenter/Timer") as Label).is_visible_in_tree(),
		"disabled ghost shell with visible compact combat metrics"
	):
		return
	hud.call("_dismiss_control_hint")
	if not _require(not hud.control_hint.visible, "control hint dismissed before evidence capture"):
		return
	world.player_camera.clear_visual_impulses()
	await get_tree().physics_frame
	await get_tree().process_frame
	world.weapon_fired.connect(_on_weapon_fired)
	world.projectile_contact.connect(_on_projectile_contact)
	world.projectile_contact_published.connect(_on_projectile_contact_published)
	world.pickup_collected.connect(_on_pickup_collected)
	if not _require(
		world.feedback_presenter.is_physics_processing(),
		"feedback presenter ages transient effects on the real runtime clock"
	):
		return
	var upstream_audio_evidence: Dictionary = {}
	if not _require(world.static_world_presenter != null and world.static_world_presenter.issues().is_empty(), "static world presenter"):
		return
	var world_to_screen := world.get_global_transform_with_canvas()
	var world_hud_exclusions := _transform_rects(
		HUD_SCREEN_EXCLUSION_RECTS,
		world_to_screen.affine_inverse()
	)
	# Gameplay intentionally starts with no ambiguous noninteractive crates,
	# racks, beacons or devices. Asset-coverage silhouettes are mounted only by
	# this explicit validation hook and never by the ordinary combat route.
	world.static_world_presenter.mount_validation_props(config.seed, true)
	var presenter_evidence: Array = world.static_world_presenter.apply_capture_safe_layout(
		world.arena_rect,
		world_hud_exclusions
	)
	if not _require(presenter_evidence.size() == 13, "thirteen non-reward presenter evidence instances"):
		return
	if not _require(
		_transform_rect(world.arena_rect, world_to_screen).encloses(
			Rect2(Vector2.ZERO, Vector2(CAPTURE_SIZE))
		),
		"arena floor and boundary cover the complete 1280x720 route"
	):
		return
	if not _require(_off_grid_foreground_count(presenter_evidence) >= 6, "off-grid foreground composition"):
		return

	var orbit := world.player_actor.get_node_or_null("WeaponOrbit") as Node2D
	if not _require(orbit != null and orbit.get_child_count() == 6, "six orbit weapons"):
		return
	var distinct_assets: Dictionary = {}
	for child in orbit.get_children():
		var weapon := child as GogoWeaponInstance
		if not _require(weapon != null and weapon.weapon_visual_handle != null, "readable runtime weapon visual"):
			return
		distinct_assets[weapon.weapon_visual_handle.asset_id] = true
	if not _require(distinct_assets.size() == 6, "six distinct weapon silhouettes"):
		return
	if not _require(_six_weapon_footprints_are_disjoint(world.player_actor, orbit), "six rotated weapon footprints stay disjoint"):
		return
	if not _require(_six_weapon_footprints_clear_player(world.player_actor, orbit), "six rotated weapon footprints clear Niko"):
		return

	var enemy_evidence_positions := _capture_enemy_evidence_positions(
		world,
		presenter_evidence,
		world_hud_exclusions,
		session.run_state.run_seed
	)
	var repeated_enemy_positions := _capture_enemy_evidence_positions(
		world,
		presenter_evidence,
		world_hud_exclusions,
		session.run_state.run_seed
	)
	if not _require(
		enemy_evidence_positions == repeated_enemy_positions,
		"capture enemy evidence positions are deterministic for the run seed"
	):
		return
	if not _require(
		enemy_evidence_positions.size() == CAPTURE_ENEMY_COUNT,
		"ten asymmetric capture enemy positions"
	):
		return
	if not _require(
		_enemy_positions_are_capture_safe(
			enemy_evidence_positions,
			world,
			presenter_evidence,
			world_hud_exclusions
		),
		"capture enemies avoid arena edges, HUD, Niko/weapons, props, and each other"
	):
		return
	var authored_enemy_roles: Dictionary = {}
	var authored_enemy_ids: Dictionary = {}
	for index in enemy_evidence_positions.size():
		var capture_enemy_id := CAPTURE_ENEMY_IDS[index % CAPTURE_ENEMY_IDS.size()]
		world.call("_spawn_enemy", capture_enemy_id)
		var markers := world.effect_layer.find_children("SpawnMarker_*", "GogoStaticSpawnMarker", false, false)
		if not markers.is_empty():
			(markers.back() as GogoStaticSpawnMarker).complete_now()
		await get_tree().process_frame
		var enemy := world.active_enemy_at(index)
		if enemy == null:
			continue
		var visual_sprite := enemy.get_node_or_null("VisualSprite") as Sprite2D
		if not _require(
			enemy.definition.content_id == capture_enemy_id
			and enemy.definition.visual_texture != null
			and visual_sprite != null
			and visual_sprite.texture == enemy.definition.visual_texture
			and visual_sprite.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST
			and not enemy.fallback_visual_active,
			"authored nearest-filtered enemy sprite without fallback for %s" % capture_enemy_id
		):
			return
		authored_enemy_roles[enemy.definition.role] = true
		authored_enemy_ids[capture_enemy_id] = true
		enemy.global_position = enemy_evidence_positions[index]
		enemy.set_physics_process(false)
	if not _require(
		authored_enemy_roles.size() == CAPTURE_ENEMY_IDS.size()
		and authored_enemy_ids.size() == CAPTURE_ENEMY_IDS.size(),
		"one authored non-fallback sprite for every enemy role"
	):
		return
	var asymmetric_radii := _enemy_positions_have_asymmetric_radii(
		enemy_evidence_positions,
		world.player_actor.global_position
	)
	var asymmetric_angles := _enemy_positions_have_unequal_angular_gaps(
		enemy_evidence_positions,
		world.player_actor.global_position
	)
	if not _require(asymmetric_radii, "capture enemies use varied distances instead of a ring"):
		return
	if not _require(asymmetric_angles, "capture enemies use unequal angular spacing instead of a ring"):
		return
	upstream_audio_evidence = await _exercise_real_audio_upstream_events(world, session)
	if not _require(
		String(upstream_audio_evidence.get("error", "")).is_empty(),
		"real melee/player audio upstream exercise (%s)" % [upstream_audio_evidence]
	):
		return
	if not _require(
		orbit.get_child_count() == 6,
		"temporary melee probe leaves the six-weapon capture layout unchanged"
	):
		return

	if not await _wait_for_combat(12, 4, 600):
		_fail(
			"live auto-fire did not produce shots, contacts, critical, pierce, and explosion "
			+ "(weapons=%s shots=%d contacts=%d kinds=%s sources=%s)"
			% [
				CAPTURE_WEAPON_IDS,
				_shot_count,
				_impact_count,
				_impact_kinds_observed.keys(),
				_impact_sources,
			]
		)
		return
	for required_kind: StringName in [&"normal", &"critical", &"pierce_exit", &"explosion"]:
		if not _require(
			_impact_kinds_observed.has(required_kind),
			"live impact kind %s" % required_kind
		):
			return
	# Normalize any naturally dropped rewards, then create one deterministic visible
	# death so both real pickup assets are present in the captured combat route.
	world.collect_all_live_pickups()
	_pickup_collection_count = 0
	_pickup_kinds_observed.clear()
	world.call("_spawn_enemy", TARGET_ENEMY_ID)
	var pickup_enemy_markers := world.effect_layer.find_children(
		"SpawnMarker_*", "GogoStaticSpawnMarker", false, false
	)
	if not _require(not pickup_enemy_markers.is_empty(), "pickup evidence spawn marker"):
		return
	(pickup_enemy_markers.back() as GogoStaticSpawnMarker).complete_now()
	var pickup_enemy := world.active_enemy_at(world.active_enemy_count() - 1)
	if not _require(pickup_enemy != null, "pickup evidence enemy activated"):
		return
	pickup_enemy.global_position = world.clamp_to_arena(
		world.player_actor.global_position + Vector2(0, 180),
		64.0
	).round()
	pickup_enemy.take_damage(99999.0)
	if not _require(world.active_pickup_count() == 1, "one bundled pickup per defeated enemy"):
		return
	var bundled_reward_kinds: Dictionary = {}
	var bundled_pickup := world.active_pickup_at(0)
	for entry_value in bundled_pickup.get("reward_entries") as Array:
		var entry := entry_value as Dictionary
		bundled_reward_kinds[StringName(entry.get(&"kind", &""))] = true
	if not _require(
		bundled_reward_kinds.has(GameSession.REWARD_EXPERIENCE)
		and bundled_reward_kinds.has(GameSession.REWARD_SUPPLY),
		"defeated enemy bundles experience and supply rewards"
	):
		return
	# The runtime contract is one bundle per enemy. For the visual evidence frame,
	# replace that bundle with two deterministic single-kind reservations so both
	# approved pickup silhouettes are guaranteed to be visible regardless of the
	# defeated enemy's material denomination.
	world.collect_all_live_pickups()
	_pickup_collection_count = 0
	_pickup_kinds_observed.clear()
	var experience_only_source_id := 900001
	var experience_only_reservations := world._reserve_enemy_reward_snapshot(
		experience_only_source_id,
		1,
		1,
		0,
		0
	)
	if not _require(
		world.spawn_reserved_enemy_pickups(
			experience_only_source_id,
			Vector2i(world.player_actor.global_position + Vector2(76.0, 174.0)),
			experience_only_reservations
		) == 1,
		"experience-only pickup evidence spawned"
	):
		return
	var supply_only_source_id := 900002
	var supply_only_reservations := world._reserve_enemy_reward_snapshot(
		supply_only_source_id,
		1,
		0,
		2,
		0
	)
	if not _require(
		world.spawn_reserved_enemy_pickups(
			supply_only_source_id,
			Vector2i(world.player_actor.global_position + Vector2(-76.0, 174.0)),
			supply_only_reservations
		) == 1,
		"supply-only pickup evidence spawned"
	):
		return
	if not _require(world.active_pickup_count() == 2, "two single-kind pickup visuals are live"):
		return
	var live_pickup_assets: Dictionary = {}
	for pickup_index in world.active_pickup_count():
		var pickup := world.active_pickup_at(pickup_index)
		var pickup_sprite := pickup.get_node_or_null("StaticVisual") as Sprite2D
		var pickup_handle := pickup.get("visual_handle") as GogoStaticAssetHandle
		if not _require(
			pickup_sprite != null
			and pickup_sprite.texture != null
			and pickup_sprite.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST
			and pickup_handle != null,
			"dynamic pickup uses active static texture"
		):
			return
		live_pickup_assets[pickup_handle.asset_id] = true
		var pickup_capture_offset := Vector2(-76.0, 174.0)
		if pickup_index == 1:
			pickup_capture_offset = Vector2(76.0, 174.0)
		pickup.global_position = (
			world.player_actor.global_position + pickup_capture_offset
		).round()
		pickup.set_physics_process(false)
	if not _require(
		live_pickup_assets.has(&"experience_pickup")
		and live_pickup_assets.has(&"supply_pickup"),
		"experience and supply pickup visuals are both live"
	):
		return
	world.call("_spawn_enemy", TARGET_ENEMY_ID)
	await get_tree().process_frame
	var evidence_markers := world.effect_layer.find_children(
		"SpawnMarker_*",
		"GogoStaticSpawnMarker",
		false,
		false
	)
	if not _require(not evidence_markers.is_empty(), "live spawn marker evidence node"):
		return
	var evidence_marker := evidence_markers.back() as GogoStaticSpawnMarker
	evidence_marker.position = Vector2(640, 180)
	var marker_timer := evidence_marker.get_node_or_null("ActivationDelay") as Timer
	if marker_timer != null:
		marker_timer.stop()
	# The live sequence above already proves auto-fire and every impact class. Stop
	# new shots only for the final composition, then clear expired/transient feedback
	# so the two real pickup sprites and all six weapon silhouettes remain readable.
	for child in orbit.get_children():
		var capture_weapon := child as GogoWeaponInstance
		if capture_weapon != null:
			capture_weapon.set_physics_process(false)
	world.projectile_layer.process_mode = Node.PROCESS_MODE_DISABLED
	world.feedback_presenter.clear_feedback()
	world.player_camera.clear_visual_impulses()
	world.player_camera.set_physics_process(false)
	await _wait_for_capture_frame()
	await _wait_for_capture_frame()
	if not _require(
		world.feedback_presenter.active_effect_count() == 0,
		"final evidence frame has no stale hit/death feedback blocks"
	):
		return
	world_to_screen = world.get_global_transform_with_canvas()
	var world_evidence := _build_world_evidence(
		world,
		presenter_evidence,
		evidence_marker,
		snapshot,
		world_to_screen
	)
	if not _require(world_evidence.size() == 13, "thirteen visible static world evidence instances"):
		print(
			"WORLD_EVIDENCE_DIAGNOSTIC arena=%s player=%s camera=%s viewport=%s transform=%s"
			% [
				world.arena_rect,
				world.player_actor.global_position,
				world.player_camera.global_position,
				world.get_viewport_rect(),
				world_to_screen,
			]
		)
		return
	var capture_path := "headless-unavailable"
	var capture_record := {
		"path": "",
		"size": [CAPTURE_SIZE.x, CAPTURE_SIZE.y],
		"sha256": "",
		"render_backend": DisplayServer.get_name(),
		"available": false,
	}
	var output_dir := ProjectSettings.globalize_path(OUTPUT_DIR_URI)
	if DirAccess.make_dir_recursive_absolute(output_dir) != OK:
		_fail("could not create combat evidence directory")
		return
	if DisplayServer.get_name() != "headless":
		capture_path = ProjectSettings.globalize_path(CAPTURE_URI)
		var image := root_window.get_texture().get_image()
		if not _require(image != null and image.get_size() == CAPTURE_SIZE, "1280x720 combat capture"):
			return
		if image.save_png(capture_path) != OK:
			_fail("could not save combat capture")
			return
		capture_record = {
			"path": capture_path,
			"size": [CAPTURE_SIZE.x, CAPTURE_SIZE.y],
			"sha256": FileAccess.get_sha256(capture_path),
			"render_backend": DisplayServer.get_name(),
			"available": true,
		}
	world.collect_all_live_pickups()
	await get_tree().process_frame
	if not _require(
		world.active_pickup_count() == 0
		and _pickup_collection_count == 2
		and _pickup_kinds_observed.has(GameSession.REWARD_EXPERIENCE)
		and _pickup_kinds_observed.has(GameSession.REWARD_SUPPLY),
		"both dynamic pickup kinds collect through the canonical event"
	):
		return
	var audio_ledger := audio_presenter.debug_ledger()
	if not _require(
		_audio_ledger_has_complete_combat_coverage(audio_ledger),
		"combat audio debug ledger covers every event class and mapped variant (%s)"
		% [_audio_ledger_summary(audio_ledger)]
	):
		return
	if not _require(
		_audio_ledger_matches_real_upstream(audio_ledger, upstream_audio_evidence),
		"combat audio ledger entries originate from real melee and player damage paths"
	):
		return
	var pause_state_before := _pause_state_signature(app.current_session)
	combat_screen.call("_open_pause")
	var pause_overlay := combat_screen.get("pause_overlay") as Control
	var pause_opened := (
		get_tree().paused
		and pause_overlay != null
		and pause_overlay.visible
		and pause_overlay.has_node("PauseMenu/ContinueButton")
		and pause_overlay.has_node("Loadout/Weapons")
		and pause_overlay.has_node("StatsColumn/Rows")
		and pause_overlay.has_node("ExitConfirmation/ConfirmButton")
	)
	var pause_state_unchanged := _pause_state_signature(app.current_session) == pause_state_before
	await _wait_for_capture_frame()
	var pause_capture_ok := true
	var pause_capture_record := {
		"path": "",
		"size": [CAPTURE_SIZE.x, CAPTURE_SIZE.y],
		"sha256": "",
		"render_backend": DisplayServer.get_name(),
		"available": false,
	}
	if DisplayServer.get_name() != "headless":
		var pause_image := root_window.get_texture().get_image()
		pause_capture_ok = pause_image != null and pause_image.get_size() == CAPTURE_SIZE
		if pause_capture_ok:
			var pause_capture_path := ProjectSettings.globalize_path(PAUSE_CAPTURE_URI)
			pause_capture_ok = pause_image.save_png(pause_capture_path) == OK
			if pause_capture_ok:
				pause_capture_record = {
					"path": pause_capture_path,
					"size": [CAPTURE_SIZE.x, CAPTURE_SIZE.y],
					"sha256": FileAccess.get_sha256(pause_capture_path),
					"render_backend": DisplayServer.get_name(),
					"available": true,
				}
	combat_screen.call("_resume_from_pause")
	var pause_closed := not get_tree().paused and pause_overlay != null and not pause_overlay.visible
	if not _require(pause_opened, "real combat pause overlay structure"):
		return
	if not _require(pause_state_unchanged, "opening pause does not mutate run state"):
		return
	if not _require(pause_capture_ok, "1280x720 pause capture"):
		return
	if not _require(pause_closed, "pause resume restores combat processing"):
		return

	_exercise_remaining_real_consumers(content, snapshot)
	var report := GogoStaticCoverageAudit.build(
		REGISTRY_PATH,
		snapshot,
		GogoStaticConsumerRegistry.current().records()
	)
	if not _require(
		int(report.expected_units) == 68
		and int(report.covered_units) == 68
		and report.unresolved_asset_ids.is_empty()
		and report.required_visual_failures.is_empty()
		and bool(report.complete),
		"complete 68/68 real-consumer coverage (covered=%d unresolved=%s required=%s)" % [
			int(report.covered_units),
			str(report.unresolved_asset_ids),
			str(report.required_visual_failures),
		]
	):
		return
	report["capture"] = capture_record
	report["pause_capture"] = pause_capture_record
	report["live_combat"] = {
		"character_count": content.all(&"character").size(),
		"enemy_layout": {
			"run_seed": session.run_state.run_seed,
			"count": enemy_evidence_positions.size(),
			"authored_enemy_ids": authored_enemy_ids.keys().map(
				func(id: Variant) -> String: return String(id)
			),
			"authored_role_count": authored_enemy_roles.size(),
			"fallback_circle_count": 0,
			"positions": enemy_evidence_positions.map(
				func(position: Vector2) -> Array: return _vector_array(position)
			),
			"asymmetric_radii": asymmetric_radii,
			"unequal_angular_gaps": asymmetric_angles,
			"capture_safe": true,
		},
		"weapon_asset_ids": distinct_assets.keys().map(func(id: Variant) -> String: return String(id)),
		"shot_count": _shot_count,
		"contact_count": _impact_count,
		"shots_observed": _shot_count,
		"contacts_observed": _impact_count,
		"impact_kinds_observed": _impact_kinds_observed.keys().map(
			func(kind: Variant) -> String: return String(kind)
		),
		"impact_sources": _string_dictionary(_impact_sources),
		"pickup_collection_count": _pickup_collection_count,
		"pickup_kinds_observed": _pickup_kinds_observed.keys().map(
			func(kind: Variant) -> String: return String(kind)
		),
		"audio_ledger": _audio_ledger_summary(audio_ledger),
		"audio_upstream_evidence": upstream_audio_evidence,
	}
	report["world_evidence"] = {
		"arena_size": [CAPTURE_ARENA_SIZE.x, CAPTURE_ARENA_SIZE.y],
		"hud_exclusion_rects": HUD_SCREEN_EXCLUSION_RECTS.map(
			func(rect: Rect2) -> Array: return _rect_array(rect)
		),
		"records": world_evidence,
	}
	var coverage_path := ProjectSettings.globalize_path(COVERAGE_URI)
	var file := FileAccess.open(coverage_path, FileAccess.WRITE)
	if not _require(file != null, "open coverage report"):
		return
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	world.running = false
	world.call("_clear_active_combat_actors")
	root_window.free()
	await get_tree().process_frame
	print(
		"FULL_STATIC_ASSETS_COMBAT_V1_OK capture=%s coverage=%s shots=%d contacts=%d"
		% [capture_path, coverage_path, _shot_count, _impact_count]
	)


func _capture_content_snapshot(source: ContentSnapshot) -> ContentSnapshot:
	if source == null:
		return null
	var pack := GogoContentPackDefinition.new()
	pack.pack_id = &"gogobro.capture:pack/world_evidence"
	pack.pack_kind = &"core"
	for kind in [
		&"character",
		&"weapon",
		&"item",
		&"upgrade",
		&"enemy",
		&"zone",
		&"difficulty",
		&"wave",
		&"effect",
	]:
		for definition: GogoContentDefinition in source.all(kind):
			if definition is GogoZoneDefinition:
				(definition as GogoZoneDefinition).arena_size = CAPTURE_ARENA_SIZE
			elif definition is GogoEnemyDefinition and definition.content_id == TARGET_ENEMY_ID:
				(definition as GogoEnemyDefinition).max_health = 260.0
			pack.definitions.append(definition)
	return GogoContentRegistry.new().build_snapshot([pack])


func _build_world_evidence(
	world: CombatWorld,
	presenter_records: Array,
	marker: GogoStaticSpawnMarker,
	snapshot: GogoStaticAssetSnapshot,
	world_to_screen: Transform2D
) -> Array[Dictionary]:
	var marker_handle := snapshot.resolve_asset(&"spawn_marker", &"world_sprite")
	if not _require(marker_handle != null and marker_handle.texture != null, "spawn marker evidence handle"):
		return []
	var raw_records := presenter_records.duplicate(true)
	raw_records.append({
		"asset_id": marker_handle.asset_id,
		"selector": marker_handle.selector,
		"node": String(world.get_path_to(marker)),
		"position": Vector2i(marker.position),
		"world_rect": Rect2(
			marker.position - Vector2(marker_handle.pivot_px),
			Vector2(marker_handle.display_size_px)
		),
		"display_size_px": marker_handle.display_size_px,
		"pivot_px": marker_handle.pivot_px,
	})

	var result: Array[Dictionary] = []
	var counts: Dictionary = {}
	var decor_selectors: Array[StringName] = []
	var foreground_screen_rects: Array[Rect2] = []
	for raw_record: Variant in raw_records:
		var record := raw_record as Dictionary
		var asset_id := StringName(record.get("asset_id", &""))
		var node_path := NodePath(String(record.get("node", "")))
		var node: CanvasItem
		if asset_id == &"spawn_marker":
			node = marker
		else:
			if not _require(world.static_world_presenter.has_node(node_path), "world evidence node %s" % node_path):
				return []
			node = world.static_world_presenter.get_node(node_path) as CanvasItem
		if asset_id == &"arena_boundary_border":
			if not _require(
				node != null and not node.is_visible_in_tree() and _node_has_static_texture(node),
				"clean gameplay keeps the legacy arena boundary texture mounted but invisible"
			):
				return []
			continue
		if not _require(
			node != null and node.is_visible_in_tree() and _node_has_static_texture(node),
			"visible textured world node %s" % node_path
		):
			return []
		var world_rect := record.get("world_rect", Rect2()) as Rect2
		var screen_rect := _transform_rect(world_rect, world_to_screen)
		if not _require(
			world_rect.has_area()
			and Rect2(Vector2.ZERO, Vector2(CAPTURE_SIZE)).encloses(screen_rect),
			"world evidence rect inside 1280x720 for %s (world=%s screen=%s transform=%s)"
			% [asset_id, world_rect, screen_rect, world_to_screen]
		):
			return []
		for hud_rect in HUD_SCREEN_EXCLUSION_RECTS:
			if not _require(
				not screen_rect.intersects(hud_rect),
				"world evidence avoids HUD for %s" % asset_id
			):
				return []
		if asset_id not in [&"community_server_floor", &"arena_boundary_border"]:
			for prior_rect in foreground_screen_rects:
				if not _require(
					not screen_rect.intersects(prior_rect),
					"world evidence silhouettes do not overlap for %s" % asset_id
				):
					return []
			foreground_screen_rects.append(screen_rect)
		var key := String(asset_id)
		counts[key] = int(counts.get(key, 0)) + 1
		if asset_id == &"community_server_decor_pack":
			decor_selectors.append(StringName(record.get("selector", &"")))
		result.append({
			"asset_id": key,
			"selector": String(record.get("selector", &"")),
			"node": String(node_path),
			"position": _vector_array(Vector2(record.get("position", Vector2i.ZERO))),
			"world_rect": _rect_array(world_rect),
			"screen_rect": _rect_array(screen_rect),
		})
	if not _require(counts == EXPECTED_WORLD_EVIDENCE_COUNTS, "every world asset and six decor variants evidenced"):
		return []
	if not _require(decor_selectors.size() == EXPECTED_DECOR_SELECTORS.size(), "six decor selectors evidenced"):
		return []
	for selector in EXPECTED_DECOR_SELECTORS:
		if not _require(decor_selectors.has(selector), "decor selector %s evidenced" % selector):
			return []
	return result


func _node_has_static_texture(node: CanvasItem) -> bool:
	if node is Sprite2D:
		return (node as Sprite2D).texture != null
	if node is MultiMeshInstance2D:
		return (node as MultiMeshInstance2D).texture != null
	var sprite := node.get_node_or_null("StaticVisual") as Sprite2D
	return sprite != null and sprite.texture != null


func _six_weapon_footprints_are_disjoint(player: GogoPlayerActor, orbit: Node2D) -> bool:
	for index in orbit.get_child_count():
		var weapon := orbit.get_child(index) as GogoWeaponInstance
		if weapon == null or weapon.weapon_visual_handle == null:
			return false
		var radius := float(player.call("weapon_visual_footprint_radius",
			weapon.weapon_visual_handle.display_size_px,
			weapon.weapon_visual_handle.pivot_px
		))
		for prior in index:
			var other := orbit.get_child(prior) as GogoWeaponInstance
			var other_radius := float(player.call("weapon_visual_footprint_radius",
				other.weapon_visual_handle.display_size_px,
				other.weapon_visual_handle.pivot_px
			))
			if weapon.position.distance_to(other.position) < radius + other_radius + 12.0 - 0.001:
				return false
	return true


func _six_weapon_footprints_clear_player(player: GogoPlayerActor, orbit: Node2D) -> bool:
	for child in orbit.get_children():
		var weapon := child as GogoWeaponInstance
		if weapon == null or weapon.weapon_visual_handle == null:
			return false
		var footprint := float(player.call("weapon_visual_footprint_radius",
			weapon.weapon_visual_handle.display_size_px,
			weapon.weapon_visual_handle.pivot_px
		))
		if weapon.position.length() - footprint < 76.0:
			return false
	return true


func _enemy_positions_have_asymmetric_radii(positions: Array[Vector2], center: Vector2) -> bool:
	if positions.size() < 4:
		return false
	var radii: Array[float] = []
	var radius_buckets: Dictionary = {}
	for position in positions:
		var radius := position.distance_to(center)
		radii.append(radius)
		radius_buckets[int(roundf(radius / 24.0))] = true
	radii.sort()
	return radius_buckets.size() >= 4 and radii.back() - radii.front() >= 72.0


func _enemy_positions_have_unequal_angular_gaps(
	positions: Array[Vector2],
	center: Vector2
) -> bool:
	if positions.size() < 4:
		return false
	var angles: Array[float] = []
	for position in positions:
		angles.append(fposmod((position - center).angle(), TAU))
	angles.sort()
	var gaps: Array[float] = []
	for index in angles.size():
		var next_angle := angles[(index + 1) % angles.size()]
		if index == angles.size() - 1:
			next_angle += TAU
		gaps.append(next_angle - angles[index])
	gaps.sort()
	return gaps.back() - gaps.front() >= deg_to_rad(12.0)


func _capture_enemy_evidence_positions(
	world: CombatWorld,
	presenter_records: Array,
	hud_exclusions: Array[Rect2],
	run_seed: int
) -> Array[Vector2]:
	var candidates: Array[Vector2] = CAPTURE_ENEMY_ANCHOR_FACTORS.duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed ^ 0x5EED330
	for index in range(candidates.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var held := candidates[index]
		candidates[index] = candidates[swap_index]
		candidates[swap_index] = held
	var positions: Array[Vector2] = []
	for factor in candidates:
		var position := world.arena_rect.position + factor * world.arena_rect.size
		position += Vector2(rng.randi_range(-13, 13), rng.randi_range(-11, 11))
		position = position.round()
		if _capture_enemy_position_is_safe(
			position,
			positions,
			world,
			presenter_records,
			hud_exclusions
		):
			positions.append(position)
			if positions.size() == CAPTURE_ENEMY_COUNT:
				break
	return positions


func _enemy_positions_are_capture_safe(
	positions: Array[Vector2],
	world: CombatWorld,
	presenter_records: Array,
	hud_exclusions: Array[Rect2]
) -> bool:
	if positions.size() != CAPTURE_ENEMY_COUNT:
		return false
	var accepted: Array[Vector2] = []
	for position in positions:
		if not _capture_enemy_position_is_safe(
			position,
			accepted,
			world,
			presenter_records,
			hud_exclusions
		):
			return false
		accepted.append(position)
	return true


func _capture_enemy_position_is_safe(
	position: Vector2,
	accepted_positions: Array[Vector2],
	world: CombatWorld,
	presenter_records: Array,
	hud_exclusions: Array[Rect2]
) -> bool:
	var enemy_rect := Rect2(
		position - CAPTURE_ENEMY_HALF_EXTENT,
		CAPTURE_ENEMY_HALF_EXTENT * 2.0
	)
	if not world.arena_rect.encloses(enemy_rect) or _rect_intersects_any(enemy_rect, hud_exclusions):
		return false
	var player_clearance := (
		world.player_actor.weapon_arena_clamp_margin()
		+ CAPTURE_ENEMY_HALF_EXTENT.length()
		+ CAPTURE_ENEMY_WEAPON_GAP
	)
	if position.distance_to(world.player_actor.global_position) < player_clearance:
		return false
	for raw_record: Variant in presenter_records:
		var record := raw_record as Dictionary
		if not String(record.get("node", "")).begins_with("Props/"):
			continue
		var prop_rect := record.get("world_rect", Rect2()) as Rect2
		if prop_rect.has_area() and enemy_rect.intersects(prop_rect):
			return false
	for accepted in accepted_positions:
		if position.distance_to(accepted) < CAPTURE_ENEMY_MINIMUM_SEPARATION:
			return false
	return true


func _rect_intersects_any(rect: Rect2, others: Array[Rect2]) -> bool:
	for other in others:
		if rect.intersects(other):
			return true
	return false


func _off_grid_foreground_count(records: Array) -> int:
	var count := 0
	for raw_record: Variant in records:
		var record := raw_record as Dictionary
		if String(record.get("node", "")).begins_with("Props/"):
			var position := record.get("position", Vector2i.ZERO) as Vector2i
			if position.x % 64 != 0 or position.y % 64 != 0:
				count += 1
	return count


func _transform_rects(rects: Array[Rect2], transform: Transform2D) -> Array[Rect2]:
	var result: Array[Rect2] = []
	for rect in rects:
		result.append(_transform_rect(rect, transform))
	return result


func _transform_rect(rect: Rect2, transform: Transform2D) -> Rect2:
	var points := [
		transform * rect.position,
		transform * Vector2(rect.end.x, rect.position.y),
		transform * rect.end,
		transform * Vector2(rect.position.x, rect.end.y),
	]
	var minimum := points[0] as Vector2
	var maximum := minimum
	for point: Vector2 in points:
		minimum = minimum.min(point)
		maximum = maximum.max(point)
	return Rect2(minimum, maximum - minimum)


func _rect_array(rect: Rect2) -> Array:
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]


func _vector_array(vector: Vector2) -> Array:
	return [vector.x, vector.y]


func _capture_weapons(content: ContentSnapshot) -> Array[GogoWeaponDefinition]:
	var result: Array[GogoWeaponDefinition] = []
	for content_id in CAPTURE_WEAPON_IDS:
		var weapon := content.definition(content_id, &"weapon") as GogoWeaponDefinition
		if weapon == null or weapon.mode != GogoWeaponDefinition.Mode.RANGED:
			return []
		result.append(weapon)
	return result


func _capture_item_ids(content: ContentSnapshot) -> Array[StringName]:
	var result: Array[StringName] = []
	for content_id in CAPTURE_ITEM_IDS:
		if content.has_definition(content_id, &"item"):
			result.append(content_id)
	return result


func _wait_for_combat(minimum_shots: int, minimum_impacts: int, maximum_frames: int) -> bool:
	for _frame in maximum_frames:
		if (
			_shot_count >= minimum_shots
			and _impact_count >= minimum_impacts
			and _impact_kinds_observed.has(&"normal")
			and _impact_kinds_observed.has(&"critical")
			and _impact_kinds_observed.has(&"pierce_exit")
			and _impact_kinds_observed.has(&"explosion")
			and _impact_sources.get(&"explosion", &"") == SKYLINE_GRENADE_ID
		):
			return true
		await get_tree().physics_frame
	return false


func _wait_for_capture_frame() -> void:
	await get_tree().process_frame
	# `frame_post_draw` is not emitted by Godot's headless display server. Waiting on
	# it made the same real-combat test hang until GdUnit's five-minute watchdog.
	# Non-headless OpenGL capture still waits for the rendered frame before reading
	# the SubViewport texture; headless runs validate gameplay and coverage only.
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw


func _exercise_real_audio_upstream_events(
	world: CombatWorld,
	session: GameSession
) -> Dictionary:
	var target := _first_safe_melee_target(world)
	if target == null:
		return {"error": "no nonlethal active enemy for melee probe"}
	var orbit := world.player_actor.get_node_or_null("WeaponOrbit") as Node2D
	if orbit == null or world.projectile_layer == null:
		return {"error": "missing real weapon orbit or projectile layer"}
	var capture_weapons: Array[GogoWeaponInstance] = []
	var capture_weapon_process_states: Array[bool] = []
	for child in orbit.get_children():
		var capture_weapon := child as GogoWeaponInstance
		if capture_weapon == null:
			continue
		capture_weapons.append(capture_weapon)
		capture_weapon_process_states.append(capture_weapon.is_physics_processing())
		capture_weapon.set_physics_process(false)
	var projectile_process_mode := world.projectile_layer.process_mode
	world.projectile_layer.process_mode = Node.PROCESS_MODE_DISABLED
	var initial_hitstop_cleared := await _wait_for_local_hitstop_clear(world, 30)

	_real_melee_events.clear()
	var melee_weapon := GogoWeaponInstance.new()
	melee_weapon.name = "AudioSmokeMeleeProbe"
	world.add_child(melee_weapon)
	melee_weapon.set_physics_process(false)
	melee_weapon.configure(_audio_smoke_melee_stats(), world.player_actor)
	var target_position_before := target.global_position
	target.global_position = world.player_actor.global_position + Vector2(24.0, 0.0)
	melee_weapon.global_position = target.global_position - Vector2(12.0, 0.0)
	melee_weapon.melee_contact.connect(_on_real_melee_contact)
	var target_health_before := target.current_health
	melee_weapon._physics_process(0.0)
	melee_weapon._physics_process(melee_weapon.debug_melee_seconds_until_contact() + 0.001)
	var target_health_after := target.current_health
	var melee_hitstop_observed := target.is_target_locally_frozen()
	# Capture enemies are intentionally process-disabled for a stable evidence
	# composition, so advance only this target's local hitstop clock explicitly.
	target._physics_process(target.debug_target_local_hitstop_remaining() + 0.001)
	var melee_hitstop_cleared := not target.is_target_locally_frozen()
	var melee_event: Dictionary = _real_melee_events.back() if not _real_melee_events.is_empty() else {}
	var melee_evidence := {
		"weapon_instance_id": melee_weapon.runtime_instance_id,
		"target_instance_id": target.runtime_instance_id,
		"sequence": melee_weapon.melee_sequence,
		"signal_sequence": int(melee_event.get("sequence", 0)),
		"was_active_target": world.is_active_enemy(target),
		"health_before": target_health_before,
		"health_after": target_health_after,
		"hitstop_observed": melee_hitstop_observed,
		"hitstop_cleared": melee_hitstop_cleared,
	}
	target.global_position = target_position_before
	melee_weapon.free()

	_real_player_damage_events.clear()
	var player_state := world.player_actor.player_state
	var player_health_floor := minf(player_state.max_health, 20.0)
	player_state.current_health = maxf(player_state.current_health, player_health_floor)
	var player_health_before := player_state.current_health
	var had_dodge := player_state.final_stats.has(&"dodge")
	var original_dodge: Variant = player_state.final_stats.get(&"dodge", 0.0)
	var original_damage_cooldown := world.player_actor.damage_cooldown
	var original_rng_state := session.rng.state
	player_state.final_stats[&"dodge"] = 0.0
	world.player_actor.damage_cooldown = 0.0
	world.player_actor.damage_taken.connect(_on_real_player_damage_taken)
	world.player_actor.take_damage(1.0)
	if world.player_actor.damage_taken.is_connected(_on_real_player_damage_taken):
		world.player_actor.damage_taken.disconnect(_on_real_player_damage_taken)
	session.rng.state = original_rng_state
	if had_dodge:
		player_state.final_stats[&"dodge"] = original_dodge
	else:
		player_state.final_stats.erase(&"dodge")
	world.player_actor.damage_cooldown = original_damage_cooldown
	var player_health_after := player_state.current_health
	var player_hitstop_observed := world.debug_local_hitstop_remaining() > 0.0
	var player_hitstop_cleared := await _wait_for_local_hitstop_clear(world, 30)
	var player_event: Dictionary = (
		_real_player_damage_events.back() if not _real_player_damage_events.is_empty() else {}
	)
	var player_evidence := {
		"sequence": int(player_event.get("sequence", 0)),
		"health_before": player_health_before,
		"health_after": player_health_after,
		"hitstop_observed": player_hitstop_observed,
		"hitstop_cleared": player_hitstop_cleared,
	}

	world.projectile_layer.process_mode = projectile_process_mode
	for index in capture_weapons.size():
		capture_weapons[index].set_physics_process(capture_weapon_process_states[index])
	var error := ""
	if not initial_hitstop_cleared:
		error = "pre-existing local hitstop did not clear"
	elif _real_melee_events.size() != 1:
		error = "real melee weapon did not emit exactly one contact"
	elif not is_equal_approx(target_health_before - target_health_after, 1.0):
		error = "real melee reservation/commit did not apply exactly one damage"
	elif int(melee_event.get("weapon_instance_id", 0)) != int(melee_evidence.weapon_instance_id):
		error = "melee signal weapon id did not match the real weapon"
	elif int(melee_event.get("target_instance_id", 0)) != int(melee_evidence.target_instance_id):
		error = "melee signal target id did not match the active enemy"
	elif int(melee_event.get("sequence", 0)) != int(melee_evidence.sequence):
		error = "melee signal sequence did not match the real weapon sequence"
	elif _real_player_damage_events.size() != 1:
		error = "real player take_damage did not emit exactly once"
	elif not player_health_after < player_health_before:
		error = "real player take_damage did not reduce health"
	return {
		"error": error,
		"melee": melee_evidence,
		"player_hit": player_evidence,
	}


func _first_safe_melee_target(world: CombatWorld) -> GogoEnemyActor:
	for index in world.active_enemy_count():
		var enemy := world.active_enemy_at(index)
		if enemy != null and world.is_active_enemy(enemy) and enemy.current_health > 2.0:
			return enemy
	return null


func _audio_smoke_melee_stats() -> GogoWeaponRuntimeStats:
	var stats := GogoWeaponRuntimeStats.new()
	stats.mode = GogoWeaponDefinition.Mode.MELEE
	stats.attack_range = 28.0
	stats.cooldown_seconds = 0.55
	stats.damage = 1.0
	stats.knockback = 0.0
	stats.feedback_profile_id = &"heavy"
	stats.damage_kind = &"melee"
	stats.impact_kind = &"normal"
	return stats


func _wait_for_local_hitstop_clear(world: CombatWorld, maximum_frames: int) -> bool:
	for _frame in maximum_frames:
		if not world.is_combat_simulation_frozen():
			return true
		await get_tree().physics_frame
	return not world.is_combat_simulation_frozen()


func _audio_ledger_has_complete_combat_coverage(ledger: Array[Dictionary]) -> bool:
	var summary := _audio_ledger_summary(ledger)
	var event_classes := summary.event_classes_observed as Array
	var shot_variants := summary.shot_variants_observed as Array
	var contact_variants := summary.contact_variants_observed as Array
	for event_class in EXPECTED_AUDIO_EVENT_CLASSES:
		if not event_classes.has(String(event_class)):
			return false
	for variant in EXPECTED_AUDIO_SHOT_VARIANTS:
		if not shot_variants.has(String(variant)):
			return false
	for variant in EXPECTED_AUDIO_CONTACT_VARIANTS:
		if not contact_variants.has(String(variant)):
			return false
	return true


func _audio_ledger_summary(ledger: Array[Dictionary]) -> Dictionary:
	var event_classes: Dictionary = {}
	var shot_variants: Dictionary = {}
	var contact_variants: Dictionary = {}
	for event in ledger:
		var event_class := StringName(event.get("event_class", &""))
		var variant := StringName(event.get("variant", &""))
		event_classes[String(event_class)] = true
		if event_class == &"weapon_fired":
			shot_variants[String(variant)] = true
		elif event_class in [&"projectile_contact", &"melee_contact"]:
			contact_variants[String(variant)] = true
	return {
		"entry_count": ledger.size(),
		"event_classes_observed": event_classes.keys(),
		"shot_variants_observed": shot_variants.keys(),
		"contact_variants_observed": contact_variants.keys(),
	}


func _audio_ledger_matches_real_upstream(
	ledger: Array[Dictionary],
	evidence: Dictionary
) -> bool:
	if evidence.is_empty():
		return false
	var melee := evidence.get("melee", {}) as Dictionary
	var player_hit := evidence.get("player_hit", {}) as Dictionary
	for event in ledger:
		var event_class := StringName(event.get("event_class", &""))
		if (
			event_class == &"melee_contact"
			and int(event.get("source_instance_id", 0)) == int(melee.get("weapon_instance_id", -1))
			and int(event.get("target_instance_id", 0)) == int(melee.get("target_instance_id", -1))
			and int(event.get("sequence", 0)) == int(melee.get("sequence", -1))
			and float(melee.get("health_before", 0.0)) > float(melee.get("health_after", 0.0))
		):
			melee["ledger_matched"] = true
		elif (
			event_class == &"player_damage_taken"
			and int(event.get("sequence", 0)) == int(player_hit.get("sequence", -1))
			and is_equal_approx(
				float(event.get("remaining_health", -1.0)),
				float(player_hit.get("health_after", -2.0))
			)
			and float(player_hit.get("health_before", 0.0)) > float(player_hit.get("health_after", 0.0))
		):
			player_hit["ledger_matched"] = true
	return (
		bool(melee.get("ledger_matched", false))
		and bool(melee.get("was_active_target", false))
		and bool(melee.get("hitstop_observed", false))
		and bool(melee.get("hitstop_cleared", false))
		and bool(player_hit.get("ledger_matched", false))
		and bool(player_hit.get("hitstop_observed", false))
		and bool(player_hit.get("hitstop_cleared", false))
	)


func _pause_state_signature(session: GameSession) -> Dictionary:
	if session == null or session.run_state == null:
		return {}
	var player := session.run_state.player()
	if player == null:
		return {}
	return {
		"phase": session.run_state.phase,
		"wave": session.run_state.current_wave,
		"ended": session.run_state.ended,
		"health": player.current_health,
		"materials": player.materials,
		"weapons": player.weapon_ids.duplicate(),
		"items": player.item_ids.duplicate(),
	}


func _exercise_remaining_real_consumers(
	content: ContentSnapshot,
	snapshot: GogoStaticAssetSnapshot
) -> void:
	for kind in [&"weapon", &"item", &"upgrade"]:
		for definition: GogoContentDefinition in content.all(kind):
			var card := GogoStaticCardPresenter.build_card(definition, "已接入", snapshot)
			card.free()
	var player := SessionPlayerState.new()
	for raw: GogoContentDefinition in content.all(&"weapon"):
		var weapon := GogoWeaponInstance.new()
		weapon.static_asset_snapshot_override = snapshot
		weapon.configure(
			WeaponRuntimeService.new().build_instance(raw as GogoWeaponDefinition, player),
			null
		)
		weapon.free()
	var marker := GogoStaticSpawnMarker.new()
	marker.configure_visual(snapshot.resolve_asset(&"spawn_marker", &"world_sprite"))
	marker.free()
	var projectile := GogoProjectile.new()
	projectile.static_asset_snapshot_override = snapshot
	projectile.activate(null, 1, 1, 1, 1, &"rifle", &"ballistic", &"normal")
	projectile.free()


func _on_weapon_fired(
	_weapon_instance_id: int,
	_feedback_profile_id: StringName,
	_integer_muzzle_global_position: Vector2i,
	_shot_direction: Vector2,
	_projectile_count: int,
	_shot_sequence: int
) -> void:
	_shot_count += 1


func _on_projectile_contact(
	_projectile_instance_id: int,
	_target_instance_id: int,
	_feedback_profile_id: StringName,
	_integer_contact_global_position: Vector2i,
	_contact_normal: Vector2,
	_damage_kind: StringName,
	impact_kind: StringName,
	_contact_sequence: int
) -> void:
	_impact_count += 1
	_impact_kinds_observed[impact_kind] = true


func _on_projectile_contact_published(event: Dictionary) -> void:
	var impact_kind := StringName(event.get("impact_kind", &""))
	var source_item_id := StringName(event.get("source_item_id", &""))
	if not impact_kind.is_empty() and not source_item_id.is_empty():
		_impact_sources[impact_kind] = source_item_id


func _on_pickup_collected(
	_pickup_instance_id: int,
	kind: StringName,
	_amount: int,
	_integer_collection_global_position: Vector2i,
	_collection_sequence: int
) -> void:
	_pickup_collection_count += 1
	_pickup_kinds_observed[kind] = true


func _on_real_melee_contact(
	weapon_instance_id: int,
	target_instance_id: int,
	_feedback_profile_id: StringName,
	_integer_contact_global_position: Vector2i,
	_contact_normal: Vector2,
	_damage_kind: StringName,
	_impact_kind: StringName,
	sequence: int
) -> void:
	_real_melee_events.append({
		"weapon_instance_id": weapon_instance_id,
		"target_instance_id": target_instance_id,
		"sequence": sequence,
	})


func _on_real_player_damage_taken(
	_integer_global_position: Vector2i,
	final_damage: float,
	remaining_health: float,
	lethal: bool,
	sequence: int
) -> void:
	_real_player_damage_events.append({
		"final_damage": final_damage,
		"remaining_health": remaining_health,
		"lethal": lethal,
		"sequence": sequence,
	})


func _string_dictionary(source: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key: Variant in source:
		result[String(key)] = String(source[key])
	return result


func _require(condition: bool, label: String) -> bool:
	if condition:
		return true
	_fail(label)
	return false


func _fail(message: String) -> void:
	fail("FULL_STATIC_ASSETS_COMBAT_V1_FAILED: " + message)
