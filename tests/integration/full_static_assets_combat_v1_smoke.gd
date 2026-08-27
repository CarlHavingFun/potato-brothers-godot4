extends GdUnitTestSuite


const OUTPUT_DIR_URI := "user://full-static-assets-combat-v1"
const CAPTURE_URI := OUTPUT_DIR_URI + "/combat-1280x720.png"
const COVERAGE_URI := OUTPUT_DIR_URI + "/gogobro-static-coverage-v1.json"
const REGISTRY_PATH := "res://game/content/assets/gogobro_static_assets_v1.json"
const CAPTURE_SIZE := Vector2i(1280, 720)
const APP_SCENE := preload("res://game/app/app_root.tscn")
const TARGET_ENEMY_ID: StringName = &"gogobro.core:enemy/drifter"

var _shot_count := 0
var _impact_count := 0


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
	var content := app.content_snapshot
	var snapshot := app.static_asset_service.active_snapshot()
	if not _require(snapshot != null and snapshot.is_development_preview(), "development preview assets"):
		return
	if not _require(content.all(&"character").size() == 1, "Niko-only character scope"):
		return

	var ranged := _candidate_ranged_weapons(content)
	if not _require(ranged.size() >= 6, "six distinct candidate ranged weapons"):
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
	var zone := content.definition(config.zone_id, &"zone") as GogoZoneDefinition
	zone.arena_size = Vector2(CAPTURE_SIZE)
	var target_definition := content.definition(TARGET_ENEMY_ID, &"enemy") as GogoEnemyDefinition
	target_definition.max_health = 260.0

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
	world.weapon_fired.connect(_on_weapon_fired)
	world.projectile_contact.connect(_on_projectile_contact)
	if not _require(world.static_world_presenter != null and world.static_world_presenter.issues().is_empty(), "static world presenter"):
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
			+ Vector2.RIGHT.rotated(TAU * float(index) / 10.0) * 250.0
		)
		enemy.set_physics_process(false)

	if not await _wait_for_combat(12, 4, 300):
		_fail("live auto-fire did not reach twelve shots and four contacts")
		return
	_add_capture_feedback(world)
	world.call("_spawn_enemy", TARGET_ENEMY_ID)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var capture_path := ProjectSettings.globalize_path(CAPTURE_URI)
	if DirAccess.make_dir_recursive_absolute(capture_path.get_base_dir()) != OK:
		_fail("could not create combat capture directory")
		return
	var image := root_window.get_texture().get_image()
	if not _require(image != null and image.get_size() == CAPTURE_SIZE, "1280x720 combat capture"):
		return
	if not _require(_count_visible_world_pixels(image) > 2500, "HUD leaves the combat world visible"):
		return
	if image.save_png(capture_path) != OK:
		_fail("could not save combat capture")
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
		"complete 70/70 real-consumer coverage"
	):
		return
	report["capture"] = {
		"path": ProjectSettings.globalize_path(CAPTURE_URI),
		"size": [CAPTURE_SIZE.x, CAPTURE_SIZE.y],
		"sha256": FileAccess.get_sha256(ProjectSettings.globalize_path(CAPTURE_URI)),
	}
	report["live_combat"] = {
		"character_count": content.all(&"character").size(),
		"weapon_asset_ids": distinct_assets.keys().map(func(id: Variant) -> String: return String(id)),
		"shots_observed": _shot_count,
		"contacts_observed": _impact_count,
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


func _count_visible_world_pixels(image: Image) -> int:
	var count := 0
	for y in range(210, 470, 2):
		for x in range(160, 1120, 2):
			var color := image.get_pixel(x, y)
			if maxf(color.r, maxf(color.g, color.b)) > 0.16:
				count += 1
	return count


func _candidate_ranged_weapons(content: ContentSnapshot) -> Array[GogoWeaponDefinition]:
	var result: Array[GogoWeaponDefinition] = []
	for raw: GogoContentDefinition in content.all(&"weapon"):
		var weapon := raw as GogoWeaponDefinition
		if weapon != null and weapon.mode == GogoWeaponDefinition.Mode.RANGED and weapon.tags.has(&"candidate_preview"):
			result.append(weapon)
	return result


func _capture_item_ids(content: ContentSnapshot) -> Array[StringName]:
	var result: Array[StringName] = []
	var helmet_id: StringName = &""
	for raw: GogoContentDefinition in content.all(&"item"):
		var item := raw as GogoItemDefinition
		if item.icon_asset_id == &"smoke_shell_helmet":
			helmet_id = item.content_id
			continue
		if result.size() < 7:
			result.append(item.content_id)
	if not helmet_id.is_empty():
		result.append(helmet_id)
	return result


func _wait_for_combat(minimum_shots: int, minimum_impacts: int, maximum_frames: int) -> bool:
	for _frame in maximum_frames:
		if _shot_count >= minimum_shots and _impact_count >= minimum_impacts:
			return true
		await get_tree().physics_frame
	return false


func _add_capture_feedback(world: CombatWorld) -> void:
	var center := Vector2i(world.player_actor.global_position)
	var kinds := [&"normal", &"critical", &"pierce_exit", &"explosion"]
	for index in kinds.size():
		world.feedback_presenter.present_projectile_contact(
			900 + index,
			800 + index,
			&"rifle",
			center + Vector2i(-160 + index * 105, -112),
			Vector2.LEFT,
			&"ballistic",
			kinds[index],
			1
		)


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
	var screen := GogoScreenBase.new()
	screen.static_asset_snapshot_override = snapshot
	screen.build_screen("覆盖审计")
	screen.add_static_texture(&"gogobro_wordmark", "Wordmark", Vector2(460, 115))
	screen.add_static_texture(&"zone_thumbnail", "ZoneThumbnail", Vector2(320, 180))
	screen.resolve_global_icon(&"difficulty_badge_kit", &"standard")
	screen.add_action("审计按钮", func() -> void: pass)
	screen.free()
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
	_impact_kind: StringName,
	_contact_sequence: int
) -> void:
	_impact_count += 1


func _require(condition: bool, label: String) -> bool:
	if condition:
		return true
	_fail(label)
	return false


func _fail(message: String) -> void:
	fail("FULL_STATIC_ASSETS_COMBAT_V1_FAILED: " + message)
