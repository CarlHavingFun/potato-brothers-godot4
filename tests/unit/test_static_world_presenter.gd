extends GdUnitTestSuite


const PRESENTER_PATH := "res://game/gameplay/world/static_world_presenter.gd"
const PICKUP_PATH := "res://game/gameplay/world/static_pickup_visual.gd"
const MARKER_PATH := "res://game/gameplay/world/static_spawn_marker.gd"
const WORLD_ASSET_IDS: Array[StringName] = [
	&"community_server_floor",
	&"arena_boundary_border",
	&"community_server_decor_pack",
	&"spawn_marker",
	&"experience_pickup",
	&"supply_pickup",
	&"medical_pickup",
	&"site_hold_turret",
	&"hazard_beacon",
	&"supply_crate",
	&"weapon_rack",
]
const DECOR_SELECTORS: Array[StringName] = [
	&"decor_variant_01",
	&"decor_variant_02",
	&"decor_variant_03",
	&"decor_variant_04",
	&"decor_variant_05",
	&"decor_variant_06",
]
const CAPTURE_VIEW_RECT := Rect2(0, 0, 1280, 720)
const CAPTURE_HUD_EXCLUSION_RECTS: Array[Rect2] = [
	Rect2(0, 0, 368, 244),
	Rect2(448, 0, 384, 112),
]


func test_static_world_runtime_presenters_exist() -> void:
	assert_bool(FileAccess.file_exists(PRESENTER_PATH)).is_true()
	assert_bool(FileAccess.file_exists(PICKUP_PATH)).is_true()
	assert_bool(FileAccess.file_exists(MARKER_PATH)).is_true()


func test_world_consumes_persistent_assets_at_deterministic_collision_free_nodes() -> void:
	if not FileAccess.file_exists(PRESENTER_PATH):
		return
	var first := _build_presenter(9137, true)
	var second := _build_presenter(9137, true)
	assert_array(first.call("consumer_records")).is_equal(second.call("consumer_records"))
	assert_object(first.get_node("Floor/community_server_floor")).is_not_null()
	assert_object(first.get_node("Boundary/arena_boundary_border_top")).is_not_null()
	for asset_id in [
		"community_server_decor_pack",
		"experience_pickup",
		"supply_pickup",
		"medical_pickup",
		"hazard_beacon",
		"supply_crate",
		"weapon_rack",
		"site_hold_turret",
	]:
		assert_bool(first.has_node("Props/%s" % asset_id)).is_true()
	assert_int(first.find_children("*", "CollisionShape2D", true, false).size()).is_equal(0)
	var foreground_rects: Array[Rect2] = []
	var off_grid_count := 0
	for record: Dictionary in first.call("consumer_records"):
		if not String(record.node).begins_with("Props/"):
			continue
		var position := record.position as Vector2i
		if position.x % 64 != 0 or position.y % 64 != 0:
			off_grid_count += 1
		assert_float(Vector2(position).distance_to(Vector2(1024, 768))).is_greater_equal(240.0)
		var rect := Rect2(
			Vector2(position - (record.pivot_px as Vector2i)),
			Vector2(record.display_size_px as Vector2i)
		)
		for prior in foreground_rects:
			assert_bool(rect.intersects(prior)).is_false()
		foreground_rects.append(rect)
	assert_int(off_grid_count).is_greater_equal(8)


func test_boundary_decoration_is_sparse_and_keeps_floor_and_corner_coverage() -> void:
	if not FileAccess.file_exists(PRESENTER_PATH):
		return
	var presenter := _build_presenter(9137, true, [], false, CAPTURE_VIEW_RECT)
	var floor := presenter.get_node("Floor/community_server_floor") as MultiMeshInstance2D
	var top := presenter.get_node("Boundary/arena_boundary_border_top") as MultiMeshInstance2D
	var bottom := presenter.get_node("Boundary/arena_boundary_border_bottom") as MultiMeshInstance2D
	var left := presenter.get_node("Boundary/arena_boundary_border_left") as MultiMeshInstance2D
	var right := presenter.get_node("Boundary/arena_boundary_border_right") as MultiMeshInstance2D
	assert_int(floor.multimesh.instance_count).is_equal(240)
	var boundary_count := (
		top.multimesh.instance_count
		+ bottom.multimesh.instance_count
		+ left.multimesh.instance_count
		+ right.multimesh.instance_count
	)
	assert_int(boundary_count).is_between(10, 14)
	assert_int(top.multimesh.instance_count).is_greater_equal(2)
	assert_int(bottom.multimesh.instance_count).is_greater_equal(2)
	assert_int(left.multimesh.instance_count).is_greater_equal(1)
	assert_int(right.multimesh.instance_count).is_greater_equal(1)
	var approximate_perimeter_coverage := (
		float(boundary_count) * 96.0
		/ (2.0 * (CAPTURE_VIEW_RECT.size.x + CAPTURE_VIEW_RECT.size.y))
	)
	assert_float(approximate_perimeter_coverage).is_between(0.24, 0.34)


func test_release_world_omits_neutral_preview_turret() -> void:
	if not FileAccess.file_exists(PRESENTER_PATH):
		return
	var presenter := _build_presenter(9137, false)
	assert_bool(presenter.has_node("Props/site_hold_turret")).is_false()
	for record: Dictionary in presenter.call("consumer_records"):
		assert_bool(record.asset_id != &"site_hold_turret").is_true()


func test_capture_safe_layout_exposes_every_real_world_node_without_hud_overlap() -> void:
	if not FileAccess.file_exists(PRESENTER_PATH):
		return
	var presenter := _build_presenter(9137, true, [], true, CAPTURE_VIEW_RECT)
	var records: Array = presenter.call(
		"apply_capture_safe_layout",
		CAPTURE_VIEW_RECT,
		CAPTURE_HUD_EXCLUSION_RECTS
	)
	assert_int(records.size()).is_equal(15)
	var expected_counts := {
		&"community_server_floor": 1,
		&"arena_boundary_border": 1,
		&"community_server_decor_pack": 6,
		&"hazard_beacon": 1,
		&"supply_crate": 1,
		&"weapon_rack": 1,
		&"experience_pickup": 1,
		&"supply_pickup": 1,
		&"medical_pickup": 1,
		&"site_hold_turret": 1,
	}
	var actual_counts: Dictionary = {}
	var foreground_rects: Array[Rect2] = []
	var actual_decor_selectors: Array[StringName] = []
	var floor_evidence_rect := Rect2()
	var boundary_evidence_rect := Rect2()
	var off_grid_count := 0
	var capture_lattice_residues: Dictionary = {}
	for raw_record: Variant in records:
		var record := raw_record as Dictionary
		var asset_id := StringName(record.get("asset_id", &""))
		actual_counts[asset_id] = int(actual_counts.get(asset_id, 0)) + 1
		var node_path := NodePath(String(record.get("node", "")))
		assert_bool(presenter.has_node(node_path)).is_true()
		var node := presenter.get_node(node_path) as CanvasItem
		assert_object(node).is_not_null()
		assert_bool(node.is_visible_in_tree()).is_true()
		var world_rect := record.get("world_rect", Rect2()) as Rect2
		assert_bool(world_rect.has_area()).is_true()
		assert_bool(CAPTURE_VIEW_RECT.encloses(world_rect)).is_true()
		for exclusion in CAPTURE_HUD_EXCLUSION_RECTS:
			assert_bool(world_rect.intersects(exclusion)).is_false()
		if asset_id == &"community_server_decor_pack":
			actual_decor_selectors.append(StringName(record.get("selector", &"")))
		elif asset_id == &"community_server_floor":
			floor_evidence_rect = world_rect
		elif asset_id == &"arena_boundary_border":
			boundary_evidence_rect = world_rect
		if asset_id not in [&"community_server_floor", &"arena_boundary_border"]:
			var position := record.get("position", Vector2i.ZERO) as Vector2i
			if position.x % 64 != 0 or position.y % 64 != 0:
				off_grid_count += 1
			capture_lattice_residues[Vector2i(position.x % 96, position.y % 96)] = true
			for prior_rect in foreground_rects:
				assert_bool(world_rect.intersects(prior_rect)).is_false()
			foreground_rects.append(world_rect)
	assert_dict(actual_counts).is_equal(expected_counts)
	assert_bool(floor_evidence_rect.intersects(boundary_evidence_rect)).is_false()
	assert_int(actual_decor_selectors.size()).is_equal(DECOR_SELECTORS.size())
	assert_int(off_grid_count).is_greater_equal(8)
	assert_int(capture_lattice_residues.size()).is_greater_equal(4)
	for selector in DECOR_SELECTORS:
		assert_bool(actual_decor_selectors.has(selector)).is_true()


func test_missing_floor_is_reported_without_blocking_other_props() -> void:
	if not FileAccess.file_exists(PRESENTER_PATH):
		return
	var presenter := _build_presenter(9137, true, [&"community_server_floor"])
	assert_bool(presenter.has_node("Floor/community_server_floor")).is_false()
	assert_bool(presenter.has_node("Props/supply_crate")).is_true()
	var issues: Array = presenter.call("issues")
	assert_int(issues.size()).is_equal(1)
	assert_str(String((issues[0] as Dictionary).code)).is_equal("missing_world_asset")
	assert_str(String((issues[0] as Dictionary).asset_id)).is_equal("community_server_floor")


func test_spawn_marker_completes_once_before_enemy_activation_callback() -> void:
	if not FileAccess.file_exists(MARKER_PATH):
		return
	var marker_script := load(MARKER_PATH) as GDScript
	var marker := auto_free(marker_script.new()) as Node2D
	add_child(marker)
	marker.call("configure_visual", _handle(&"spawn_marker", Vector2i(96, 64)))
	var state := {"activations": 0}
	marker.call("play", Vector2(129.4, 64.4), func() -> void: state.activations += 1)
	assert_int(state.activations).is_equal(0)
	assert_vector(marker.position).is_equal(Vector2(129, 64))
	marker.call("complete_now")
	marker.call("complete_now")
	assert_int(state.activations).is_equal(1)


func test_spawn_marker_without_texture_activates_immediately() -> void:
	if not FileAccess.file_exists(MARKER_PATH):
		return
	var marker_script := load(MARKER_PATH) as GDScript
	var marker := auto_free(marker_script.new()) as Node2D
	add_child(marker)
	var state := {"activated": false}
	marker.call("play", Vector2(64, 64), func() -> void: state.activated = true)
	assert_bool(state.activated).is_true()


func test_structure_actor_uses_static_texture_and_keeps_draw_fallback() -> void:
	var structure := auto_free(GogoStructureActor.new()) as GogoStructureActor
	structure.configure_visual(_handle(&"site_hold_turret", Vector2i(96, 64)))
	var sprite := structure.get_node("StaticVisual") as Sprite2D
	assert_object(sprite.texture).is_not_null()
	assert_int(sprite.texture_filter).is_equal(CanvasItem.TEXTURE_FILTER_NEAREST)


func _build_presenter(
	seed: int,
	development_preview: bool,
	missing: Array[StringName] = [],
	include_decor_selectors: bool = false,
	arena_rect: Rect2 = Rect2(Vector2.ZERO, Vector2(2048, 1536))
) -> Node2D:
	var presenter_script := load(PRESENTER_PATH) as GDScript
	var presenter := auto_free(presenter_script.new()) as Node2D
	add_child(presenter)
	presenter.call(
		"configure",
		_snapshot(missing, include_decor_selectors),
		arena_rect,
		seed,
		development_preview
	)
	return presenter


func _snapshot(
	missing: Array[StringName],
	include_decor_selectors: bool = false
) -> GogoStaticAssetSnapshot:
	var handles: Dictionary = {}
	for asset_id in WORLD_ASSET_IDS:
		if missing.has(asset_id):
			continue
		var size := Vector2i(64, 64)
		if asset_id in [
			&"arena_boundary_border",
			&"spawn_marker",
			&"experience_pickup",
			&"supply_pickup",
			&"site_hold_turret",
			&"weapon_rack",
		]:
			size = Vector2i(96, 64)
		var handle := _handle(asset_id, size)
		handles[String(handle.binding_key)] = handle
	if include_decor_selectors and not missing.has(&"community_server_decor_pack"):
		for selector in DECOR_SELECTORS:
			var selector_handle := _handle(
				&"community_server_decor_pack",
				Vector2i(64, 64),
				selector
			)
			handles[String(selector_handle.binding_key)] = selector_handle
	var snapshot := GogoStaticAssetSnapshot.new()
	snapshot._configure(1, "fixture", 70, {}, handles, {}, {}, {}, [])
	return snapshot


func _handle(
	asset_id: StringName,
	size: Vector2i,
	selector: StringName = &""
) -> GogoStaticAssetHandle:
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color8(67, 82, 76, 255))
	var handle := GogoStaticAssetHandle.new()
	var key := "%s|world_sprite|%s" % [asset_id, selector]
	handle._configure({
		"binding_key": StringName(key),
		"asset_id": asset_id,
		"role": &"world_sprite",
		"selector": selector,
		"display_size_px": size,
		"display_scale": Vector2.ONE,
		"pivot_px": Vector2i(size / 2),
		"anchors_px": {},
		"atlas_rect_px": Rect2i(Vector2i.ZERO, size),
	}, ImageTexture.create_from_image(image))
	return handle
