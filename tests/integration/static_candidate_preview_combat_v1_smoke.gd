extends SceneTree

const OUTPUT_DIR_URI := "user://static-candidate-preview-combat-v1"
const FIRE_CAPTURE_URI := OUTPUT_DIR_URI + "/fire-1280x720.png"
const IMPACT_CAPTURE_URI := OUTPUT_DIR_URI + "/impact-1280x720.png"
const REPORT_URI := OUTPUT_DIR_URI + "/report.json"
const CAPTURE_SIZE := Vector2i(1280, 720)
const TARGET_ENEMY_ID: StringName = &"gogobro.core:enemy/drifter"

var _shot_count := 0
var _impact_count := 0
var _last_muzzle := Vector2i.ZERO
var _last_contact := Vector2i.ZERO


func _initialize() -> void:
	var root_window := get_root()
	root_window.size = CAPTURE_SIZE

	var kernel := AppKernel.new()
	root_window.add_child(kernel)
	kernel.configure(null, null)
	var boot_result := kernel.boot()
	if not _require(boot_result.status == BootResult.Status.OK, "debug kernel boot"):
		return
	var static_snapshot := kernel.static_asset_service.active_snapshot()
	if not _require(static_snapshot != null and static_snapshot.is_development_preview(), "candidate preview overlay active"):
		return
	if not _require(kernel.content_snapshot.all(&"character").size() == 1, "Niko is the only character"):
		return

	var config := SessionConfig.new()
	config.seed = 47
	config.character_id = ValidationContentFactory.CHARACTER_ID
	config.starting_weapon_id = ValidationContentFactory.RANGED_ID
	config.difficulty_id = ValidationContentFactory.DIFFICULTY_ID
	config.zone_id = ValidationContentFactory.ZONE_ID
	var session := GameSession.new()
	session.static_asset_snapshot = static_snapshot
	if not _require(session.start(config, kernel.content_snapshot) == OK, "candidate preview session start"):
		return
	for _extra_weapon in 5:
		session.run_state.player().weapon_ids.append(ValidationContentFactory.RANGED_ID)

	var world := CombatWorld.new()
	world.name = "CandidatePreviewCombatWorld"
	root_window.add_child(world)
	await process_frame
	var wave := GogoWaveDefinition.new()
	wave.content_id = &"test.preview:wave/capture"
	wave.display_name = "候选素材实机验证"
	wave.wave_number = 1
	wave.duration_seconds = 20.0
	if not _require(world.start_wave(session, wave) == OK, "candidate preview combat start"):
		return
	world.weapon_fired.connect(_on_weapon_fired)
	world.projectile_contact.connect(_on_projectile_contact)
	await process_frame

	var weapon_orbit := world.player_actor.get_node_or_null("WeaponOrbit") as Node2D
	if not _require(weapon_orbit != null and weapon_orbit.get_child_count() == 6, "six Brotato-style orbit weapons"):
		return
	var weapon := weapon_orbit.get_child(0) as GogoWeaponInstance
	if not _require(weapon != null and weapon.weapon_visual_handle != null, "runtime weapon visual"):
		return
	var ak_handle := static_snapshot.resolve_asset(&"wood_stock_assault_rifle", &"world_sprite")
	if not _require(ak_handle != null, "AK candidate handle"):
		return
	var orbit_offsets: Array[Vector2] = []
	for index in 6:
		var orbit_weapon := weapon_orbit.get_child(index) as GogoWeaponInstance
		if not _require(
			orbit_weapon != null and orbit_weapon.weapon_visual_handle != null
			and orbit_weapon.weapon_visual_handle.texture == ak_handle.texture,
			"AK candidate mapped to orbit weapon %d" % index
		):
			return
		var expected_offset := world.player_actor.weapon_orbit_offset(index, 6)
		if not _require(orbit_weapon.position.is_equal_approx(expected_offset), "orbit slot %d" % index):
			return
		orbit_offsets.append(orbit_weapon.position)

	for index in 6:
		world.call("_spawn_enemy", TARGET_ENEMY_ID)
		var markers := world.effect_layer.find_children(
			"SpawnMarker_*", "GogoStaticSpawnMarker", false, false
		)
		if not markers.is_empty():
			(markers.back() as GogoStaticSpawnMarker).complete_now()
		await process_frame
		var enemy := world.active_enemy_at(index)
		if not _require(enemy != null, "controlled enemy %d spawned" % index):
			return
		enemy.global_position = (
			world.player_actor.global_position
			+ Vector2.RIGHT.rotated(TAU * float(index) / 6.0) * 270.0
		)
		enemy.set_physics_process(false)

	_add_runtime_caption(root_window, "NIKO · AK AUTO FIRE · BROTATO ORBIT PREVIEW")
	if not await _wait_for_counter(&"shot", 6, 120):
		_fail("weapon did not auto-fire")
		return
	await process_frame
	if not await _save_capture(FIRE_CAPTURE_URI):
		return

	if not await _wait_for_counter(&"impact", 6, 120):
		_fail("projectile did not hit from the weapon muzzle")
		return
	await process_frame
	if not await _save_capture(IMPACT_CAPTURE_URI):
		return

	var report_path := ProjectSettings.globalize_path(REPORT_URI)
	var report := {
		"schema": "gogobro.static_candidate_preview_combat.v1",
		"capture_size": [CAPTURE_SIZE.x, CAPTURE_SIZE.y],
		"character_count": kernel.content_snapshot.all(&"character").size(),
		"character_id": String(ValidationContentFactory.CHARACTER_ID),
		"weapon_content_id": String(ValidationContentFactory.RANGED_ID),
		"weapon_asset_id": "wood_stock_assault_rifle",
		"weapon_count": weapon_orbit.get_child_count(),
		"weapon_orbit_offsets": orbit_offsets.map(func(offset: Vector2) -> Array: return [offset.x, offset.y]),
		"weapon_texture_size": [ak_handle.texture.get_width(), ak_handle.texture.get_height()],
		"weapon_pivot": [ak_handle.pivot_px.x, ak_handle.pivot_px.y],
		"weapon_muzzle_anchor": [
			(ak_handle.anchors_px.get("muzzle") as Vector2i).x,
			(ak_handle.anchors_px.get("muzzle") as Vector2i).y,
		],
		"shots_observed": _shot_count,
		"impacts_observed": _impact_count,
		"last_muzzle_global": [_last_muzzle.x, _last_muzzle.y],
		"last_contact_global": [_last_contact.x, _last_contact.y],
		"fire_capture": ProjectSettings.globalize_path(FIRE_CAPTURE_URI),
		"impact_capture": ProjectSettings.globalize_path(IMPACT_CAPTURE_URI),
		"fire_capture_sha256": FileAccess.get_sha256(ProjectSettings.globalize_path(FIRE_CAPTURE_URI)),
		"impact_capture_sha256": FileAccess.get_sha256(ProjectSettings.globalize_path(IMPACT_CAPTURE_URI)),
	}
	var report_file := FileAccess.open(report_path, FileAccess.WRITE)
	if not _require(report_file != null, "open combat preview report"):
		return
	report_file.store_string(JSON.stringify(report, "\t") + "\n")
	report_file.close()
	print("STATIC_CANDIDATE_PREVIEW_COMBAT_V1_OK report=%s" % report_path)
	quit(0)


func _wait_for_counter(kind: StringName, minimum: int, maximum_physics_frames: int) -> bool:
	for _frame in maximum_physics_frames:
		if (kind == &"shot" and _shot_count >= minimum) or (kind == &"impact" and _impact_count >= minimum):
			return true
		await physics_frame
	return false


func _save_capture(uri: String) -> bool:
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path(uri)
	if DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK:
		_fail("could not create capture directory")
		return false
	var image := get_root().get_texture().get_image()
	if image == null or image.get_size() != CAPTURE_SIZE:
		_fail("capture size mismatch")
		return false
	if image.save_png(path) != OK:
		_fail("could not save capture")
		return false
	return true


func _add_runtime_caption(root_window: Window, value: String) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	root_window.add_child(layer)
	var panel := ColorRect.new()
	panel.position = Vector2(24.0, 22.0)
	panel.size = Vector2(540.0, 46.0)
	panel.color = Color("111722d9")
	layer.add_child(panel)
	var label := Label.new()
	label.position = Vector2(16.0, 9.0)
	label.text = value
	label.add_theme_font_size_override(&"font_size", 18)
	label.add_theme_color_override(&"font_color", Color("f0c76b"))
	panel.add_child(label)


func _on_weapon_fired(
	_weapon_instance_id: int,
	_feedback_profile_id: StringName,
	integer_muzzle_global_position: Vector2i,
	_shot_direction: Vector2,
	_projectile_count: int,
	_shot_sequence: int
) -> void:
	_shot_count += 1
	_last_muzzle = integer_muzzle_global_position


func _on_projectile_contact(
	_projectile_instance_id: int,
	_target_instance_id: int,
	_feedback_profile_id: StringName,
	integer_contact_global_position: Vector2i,
	_contact_normal: Vector2,
	_damage_kind: StringName,
	_impact_kind: StringName,
	_contact_sequence: int
) -> void:
	_impact_count += 1
	_last_contact = integer_contact_global_position


func _require(condition: bool, label: String) -> bool:
	if condition:
		return true
	_fail(label)
	return false


func _fail(message: String) -> void:
	push_error("STATIC_CANDIDATE_PREVIEW_COMBAT_V1_FAILED: " + message)
	quit(1)
