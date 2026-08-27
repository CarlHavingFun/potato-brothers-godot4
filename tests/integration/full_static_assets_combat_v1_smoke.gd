extends GdUnitTestSuite


const OUTPUT_DIR_URI := "user://full-static-assets-combat-v1"
const CAPTURE_URI := OUTPUT_DIR_URI + "/combat-1280x720.png"
const PAUSE_CAPTURE_URI := OUTPUT_DIR_URI + "/pause-1280x720.png"
const COVERAGE_URI := OUTPUT_DIR_URI + "/gogobro-static-coverage-v1.json"
const REGISTRY_PATH := "res://game/content/assets/gogobro_static_assets_v1.json"
const CAPTURE_SIZE := Vector2i(1280, 720)
const CAPTURE_ARENA_SIZE := Vector2(1280, 720)
const APP_SCENE := preload("res://game/app/app_root.tscn")
const TARGET_ENEMY_ID: StringName = &"gogobro.core:enemy/drifter"
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
const HUD_SCREEN_EXCLUSION_RECTS: Array[Rect2] = [
	Rect2(0, 0, 368, 244),
	Rect2(448, 0, 384, 112),
]
const EXPECTED_WORLD_EVIDENCE_COUNTS := {
	"community_server_floor": 1,
	"arena_boundary_border": 1,
	"community_server_decor_pack": 6,
	"hazard_beacon": 1,
	"supply_crate": 1,
	"weapon_rack": 1,
	"experience_pickup": 1,
	"supply_pickup": 1,
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

var _shot_count := 0
var _impact_count := 0
var _impact_kinds_observed: Dictionary = {}
var _impact_sources: Dictionary = {}


func before_test() -> void:
	_shot_count = 0
	_impact_count = 0
	_impact_kinds_observed.clear()
	_impact_sources.clear()


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
	if not _require(app.route(FlowRoute.DIFFICULTY_SELECT) == OK, "actual difficulty coverage route"):
		return
	await get_tree().process_frame
	var coverage_host := app.get_node("SceneHost") as Node
	var difficulty_route := coverage_host.get_child(0) as Control
	if not _require(
		difficulty_route.get_script() != null
		and (difficulty_route.get_script() as Script).resource_path
			== "res://game/ui/difficulty_select_screen.gd"
		and difficulty_route.get_node_or_null("SelectedDifficultyDetail/ZoneThumbnail") is TextureRect
		and (difficulty_route.get_node("SelectedDifficultyDetail/ZoneThumbnail") as TextureRect).is_visible_in_tree(),
		"real visible zone-thumbnail coverage"
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
		and diagnostic_route.get_node_or_null("PrincipalSurface") is NinePatchRect
		and (diagnostic_route.get_node("PrincipalSurface") as NinePatchRect).is_visible_in_tree(),
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
	player.weapon_ids.clear()
	for index in 6:
		player.weapon_ids.append((ranged[index] as GogoWeaponDefinition).content_id)
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
	if not _require(world != null and hud != null, "actual combat world and fixed HUD"):
		return
	var hud_shell := hud.get_node_or_null("Shell") as TextureRect
	if not _require(
		hud_shell != null
		and hud_shell.texture != null
		and hud_shell.visible
		and hud_shell.is_visible_in_tree()
		and hud_shell.size == Vector2(CAPTURE_SIZE)
		and hud_shell.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST,
		"visible 1280x720 low-border HUD shell"
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
	# Freeze only feedback aging so naturally emitted hit marks remain visible in
	# the proof frame. Weapons, projectiles, damage and event publication stay live.
	world.feedback_presenter.set_process(false)
	if not _require(world.static_world_presenter != null and world.static_world_presenter.issues().is_empty(), "static world presenter"):
		return
	var world_to_screen := world.get_global_transform_with_canvas()
	var world_hud_exclusions := _transform_rects(
		HUD_SCREEN_EXCLUSION_RECTS,
		world_to_screen.affine_inverse()
	)
	var presenter_evidence: Array = world.static_world_presenter.apply_capture_safe_layout(
		world.arena_rect,
		world_hud_exclusions
	)
	if not _require(presenter_evidence.size() == 15, "fifteen presenter evidence instances"):
		return
	if not _require(
		_transform_rect(world.arena_rect, world_to_screen).encloses(
			Rect2(Vector2.ZERO, Vector2(CAPTURE_SIZE))
		),
		"arena floor and boundary cover the complete 1280x720 route"
	):
		return
	if not _require(_off_grid_foreground_count(presenter_evidence) >= 8, "off-grid foreground composition"):
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

	for index in 10:
		world.call("_spawn_enemy", TARGET_ENEMY_ID)
		var markers := world.effect_layer.find_children("SpawnMarker_*", "GogoStaticSpawnMarker", false, false)
		if not markers.is_empty():
			(markers.back() as GogoStaticSpawnMarker).complete_now()
		await get_tree().process_frame
		var enemy := world.active_enemy_at(index)
		if enemy == null:
			continue
		enemy.global_position = (
			world.player_actor.global_position
			+ Vector2.RIGHT.rotated(TAU * float(index) / 10.0) * 330.0
		)
		enemy.set_physics_process(false)

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
	world.player_camera.clear_visual_impulses()
	world.player_camera.set_physics_process(false)
	await _wait_for_capture_frame()
	await _wait_for_capture_frame()
	world_to_screen = world.get_global_transform_with_canvas()
	var world_evidence := _build_world_evidence(
		world,
		presenter_evidence,
		evidence_marker,
		snapshot,
		world_to_screen
	)
	if not _require(world_evidence.size() == 16, "sixteen real world evidence instances"):
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
		int(report.expected_units) == 70
		and int(report.covered_units) == 70
		and report.unresolved_asset_ids.is_empty()
		and report.required_visual_failures.is_empty()
		and bool(report.complete),
		"complete 70/70 real-consumer coverage (covered=%d unresolved=%s required=%s)" % [
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
		"weapon_asset_ids": distinct_assets.keys().map(func(id: Variant) -> String: return String(id)),
		"shot_count": _shot_count,
		"contact_count": _impact_count,
		"shots_observed": _shot_count,
		"contacts_observed": _impact_count,
		"impact_kinds_observed": _impact_kinds_observed.keys().map(
			func(kind: Variant) -> String: return String(kind)
		),
		"impact_sources": _string_dictionary(_impact_sources),
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
