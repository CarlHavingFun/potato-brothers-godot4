class_name GogoStaticWorldPresenter
extends Node2D


const PICKUP_VISUAL := preload("res://game/gameplay/world/static_pickup_visual.gd")
const PROP_ASSET_IDS: Array[StringName] = [
	&"community_server_decor_pack",
	&"hazard_beacon",
	&"supply_crate",
	&"weapon_rack",
]
const PICKUP_ASSET_IDS: Array[StringName] = [
	&"medical_pickup",
]
# Mount only visually unambiguous, noninteractive decorations. The remaining
# approved selector handles stay available in the snapshot but are not world props.
const DECOR_SELECTORS: Array[StringName] = [
	&"decor_variant_01",
	&"decor_variant_02",
	&"decor_variant_03",
	&"decor_variant_04",
	&"decor_variant_05",
	&"decor_variant_06",
]
const DECOR_RUNTIME_NAMES := {
	&"decor_variant_01": &"decor_visual_gauge_barrel",
	&"decor_variant_02": &"decor_visual_variant_02",
	&"decor_variant_03": &"decor_visual_button_panel_device",
	&"decor_variant_04": &"decor_visual_variant_04",
	&"decor_variant_05": &"decor_visual_headset",
	&"decor_variant_06": &"decor_visual_variant_06",
}
const GRID_SIZE := 64
const ARENA_BACKGROUND_SIZE := Vector2i(2048, 1536)
const PLAYER_CLEAR_RADIUS := 240.0
const CAPTURE_CENTER_HALF_SIZE := Vector2(176.0, 112.0)
const PROP_EDGE_INSET := 96.0
const PROP_MINIMUM_SEPARATION := 128.0
const FLOOR_MODULATE := Color.WHITE
const BOUNDARY_MODULATE := Color(1.0, 1.0, 1.0, 0.0)
const PERMANENT_PROP_MODULATE := Color(0.90, 0.92, 0.88, 0.76)
# The opening camera is centered on the 2048x1536 arena and shows 1280x720.
# Keep the first six purely visual props inside that view, outside the player
# clear radius and away from the left/top HUD. Later sockets remain seed-shuffled.
const OPENING_PROP_ANCHOR_FACTORS: Array[Vector2] = [
	Vector2(0.31, 0.52), Vector2(0.69, 0.52),
	Vector2(0.70, 0.32),
	Vector2(0.31, 0.70), Vector2(0.69, 0.70),
	Vector2(0.50, 0.68),
]
const PROP_ANCHOR_FACTORS: Array[Vector2] = [
	Vector2(0.08, 0.13), Vector2(0.22, 0.09), Vector2(0.38, 0.14),
	Vector2(0.55, 0.08), Vector2(0.72, 0.15), Vector2(0.88, 0.10),
	Vector2(0.93, 0.29), Vector2(0.89, 0.48), Vector2(0.94, 0.68),
	Vector2(0.86, 0.88), Vector2(0.68, 0.92), Vector2(0.51, 0.86),
	Vector2(0.32, 0.93), Vector2(0.14, 0.86), Vector2(0.07, 0.70),
	Vector2(0.12, 0.48), Vector2(0.06, 0.31), Vector2(0.27, 0.29),
	Vector2(0.76, 0.34), Vector2(0.25, 0.70), Vector2(0.73, 0.73),
]
const CAPTURE_ANCHOR_FACTORS: Array[Vector2] = [
	Vector2(0.72, 0.14), Vector2(0.87, 0.10), Vector2(0.95, 0.25),
	Vector2(0.07, 0.45), Vector2(0.20, 0.55), Vector2(0.34, 0.38),
	Vector2(0.09, 0.75), Vector2(0.27, 0.84), Vector2(0.72, 0.74),
	Vector2(0.86, 0.57), Vector2(0.94, 0.81), Vector2(0.42, 0.90),
	Vector2(0.63, 0.91), Vector2(0.82, 0.91), Vector2(0.34, 0.68),
	Vector2(0.95, 0.48), Vector2(0.55, 0.84), Vector2(0.18, 0.36),
]

var _snapshot: GogoStaticAssetSnapshot
var _arena_rect := Rect2()
var _records: Array[Dictionary] = []
var _issues: Array[Dictionary] = []
var _floor_layer: Node2D
var _boundary_layer: Node2D
var _prop_layer: Node2D


func configure(
	next_snapshot: GogoStaticAssetSnapshot,
	next_arena_rect: Rect2,
	run_seed: int,
	development_preview: bool
) -> Array[Dictionary]:
	_clear()
	_snapshot = next_snapshot
	_arena_rect = next_arena_rect
	_build_layers()
	_build_floor()
	_build_boundary()
	# Keep gameplay space semantically clean. The world prop atlas contains
	# crates, racks, beacons and devices that read like pickups or objectives,
	# even though these presenter instances have no interaction. They remain
	# available to the explicit validation mount below, but never enter an
	# ordinary run (including debug/exported playtests).
	var _unused_run_seed := run_seed
	var _unused_development_preview := development_preview
	return consumer_records()


func mount_validation_props(run_seed: int, include_preview_turret: bool = false) -> Array[Dictionary]:
	# Validation-only opt-in for asset coverage fixtures. Production callers do
	# not invoke this method, so test/evidence silhouettes cannot leak into play.
	if _prop_layer == null or _prop_layer.get_child_count() > 0:
		return consumer_records()
	_build_props(run_seed, include_preview_turret)
	return consumer_records()


func consumer_records() -> Array[Dictionary]:
	return _records.duplicate(true)


func issues() -> Array[Dictionary]:
	return _issues.duplicate(true)


func apply_capture_safe_layout(
	visible_world_rect: Rect2,
	hud_exclusion_rects: Array[Rect2]
) -> Array[Dictionary]:
	var used_rects: Array[Rect2] = []
	var candidate_centers := _capture_candidate_centers(visible_world_rect)
	var candidate_index := 0
	var center_exclusion := Rect2(
		visible_world_rect.get_center() - CAPTURE_CENTER_HALF_SIZE,
		CAPTURE_CENTER_HALF_SIZE * 2.0
	)
	for index in _records.size():
		var record := _records[index] as Dictionary
		var node_path := NodePath(String(record.get("node", "")))
		if not String(node_path).begins_with("Props/") or not has_node(node_path):
			continue
		var size := Vector2(record.get("display_size_px", Vector2i.ZERO))
		var pivot := Vector2(record.get("pivot_px", Vector2i.ZERO))
		var placed := false
		while candidate_index < candidate_centers.size():
			var center := candidate_centers[candidate_index]
			candidate_index += 1
			var candidate_rect := Rect2(center - pivot, size)
			if (
				not visible_world_rect.encloses(candidate_rect)
				or candidate_rect.intersects(center_exclusion)
				or _intersects_any(candidate_rect, hud_exclusion_rects)
				or _intersects_any(candidate_rect, used_rects)
			):
				continue
			var node := get_node(node_path) as Node2D
			node.position = center.round()
			record["position"] = Vector2i(node.position)
			record["world_rect"] = Rect2(node.position - pivot, size)
			_records[index] = record
			used_rects.append(record.world_rect as Rect2)
			placed = true
			break
		if not placed:
			record["world_rect"] = Rect2()
			_records[index] = record

	var evidence: Array[Dictionary] = []
	for raw_record: Dictionary in _records:
		var record := raw_record.duplicate(true)
		match StringName(record.get("asset_id", &"")):
			&"community_server_floor":
				record["world_rect"] = _floor_evidence_rect(
					visible_world_rect,
					hud_exclusion_rects,
					used_rects,
					Vector2(record.get("display_size_px", Vector2i.ZERO))
				)
				record["position"] = Vector2i((record.world_rect as Rect2).get_center())
				var floor_evidence := record.world_rect as Rect2
				if floor_evidence.has_area():
					used_rects.append(floor_evidence)
			&"arena_boundary_border":
				record["world_rect"] = _boundary_evidence_rect(
					visible_world_rect,
					hud_exclusion_rects,
					used_rects,
					Vector2(record.get("display_size_px", Vector2i.ZERO))
				)
				record["position"] = Vector2i((record.world_rect as Rect2).get_center())
		evidence.append(record)
	return evidence


func _build_layers() -> void:
	_floor_layer = Node2D.new()
	_floor_layer.name = "Floor"
	add_child(_floor_layer)
	_boundary_layer = Node2D.new()
	_boundary_layer.name = "Boundary"
	add_child(_boundary_layer)
	_prop_layer = Node2D.new()
	_prop_layer.name = "Props"
	add_child(_prop_layer)


func _build_floor() -> void:
	var handle := _handle(&"community_server_floor")
	if handle == null:
		_issue(&"community_server_floor")
		return
	var display_size := Vector2(handle.display_size_px)
	if (
		display_size.x <= 0.0
		or display_size.y <= 0.0
		or handle.display_size_px != ARENA_BACKGROUND_SIZE
	):
		_issues.append({
			"code": &"invalid_world_asset_layout",
			"message": "Arena background must be the exact 2048x1536 single-sprite asset.",
			"asset_id": &"community_server_floor",
		})
		return
	var instance := Sprite2D.new()
	instance.name = "community_server_floor"
	instance.texture = handle.texture
	instance.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	instance.self_modulate = FLOOR_MODULATE
	instance.centered = true
	instance.position = _arena_rect.get_center().round()
	_floor_layer.add_child(instance)
	_record(handle, instance, Vector2i(instance.position))


func _build_boundary() -> void:
	var handle := _handle(&"arena_boundary_border")
	if handle == null:
		_issue(&"arena_boundary_border")
		return
	var segment_size := Vector2(handle.display_size_px)
	if segment_size.x <= 0.0 or segment_size.y <= 0.0:
		_issue(&"arena_boundary_border")
		return
	var instance := MultiMeshInstance2D.new()
	instance.name = "arena_boundary_border_corners"
	instance.texture = handle.texture
	instance.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	instance.self_modulate = BOUNDARY_MODULATE
	instance.visible = false
	var mesh := QuadMesh.new()
	mesh.size = segment_size
	var multi_mesh := MultiMesh.new()
	multi_mesh.transform_format = MultiMesh.TRANSFORM_2D
	multi_mesh.mesh = mesh
	multi_mesh.instance_count = 4
	var half_size := segment_size * 0.5
	var rotated_half_size := Vector2(half_size.y, half_size.x)
	var corner_transforms: Array[Transform2D] = [
		Transform2D(0.0, (_arena_rect.position + half_size).round()),
		Transform2D(
			PI * 0.5,
			Vector2(
				_arena_rect.end.x - rotated_half_size.x,
				_arena_rect.position.y + rotated_half_size.y
			).round()
		),
		Transform2D(PI, (_arena_rect.end - half_size).round()),
		Transform2D(
			-PI * 0.5,
			Vector2(
				_arena_rect.position.x + rotated_half_size.x,
				_arena_rect.end.y - rotated_half_size.y
			).round()
		),
	]
	for index in corner_transforms.size():
		multi_mesh.set_instance_transform_2d(index, corner_transforms[index])
	instance.multimesh = multi_mesh
	_boundary_layer.add_child(instance)
	_record(handle, instance, Vector2i(_arena_rect.position))


func _build_props(run_seed: int, development_preview: bool) -> void:
	var sockets := _prop_sockets(run_seed)
	var socket_index := 0
	var decor_handles := _decor_handles()
	for decor_index in decor_handles.size():
		if socket_index >= sockets.size():
			break
		var handle := decor_handles[decor_index]
		var decor_sprite := _sprite_for_handle(handle)
		var runtime_name := _decor_runtime_name(handle)
		decor_sprite.name = runtime_name
		decor_sprite.position = sockets[socket_index]
		socket_index += 1
		_prop_layer.add_child(decor_sprite)
		_record(
			handle,
			decor_sprite,
			Vector2i(decor_sprite.position),
			{
				"runtime_name": StringName(runtime_name),
				"runtime_role": &"noninteractive_visual_decor",
				"interaction": &"none",
			}
		)
	for asset_id in PROP_ASSET_IDS:
		if asset_id == &"community_server_decor_pack":
			continue
		if socket_index >= sockets.size():
			break
		var handle := _handle(asset_id)
		if handle == null:
			_issue(asset_id)
			continue
		var sprite := _sprite_for_handle(handle)
		sprite.name = String(asset_id)
		sprite.position = sockets[socket_index]
		socket_index += 1
		_prop_layer.add_child(sprite)
		_record(handle, sprite, Vector2i(sprite.position))
	for asset_id in PICKUP_ASSET_IDS:
		if socket_index >= sockets.size():
			break
		var handle := _handle(asset_id)
		if handle == null:
			_issue(asset_id)
			continue
		var pickup := PICKUP_VISUAL.new() as GogoStaticPickupVisual
		pickup.name = String(asset_id)
		pickup.position = sockets[socket_index]
		socket_index += 1
		pickup.configure(handle)
		pickup.modulate = PERMANENT_PROP_MODULATE
		# This branch is reached only through mount_validation_props(); expose the
		# texture there so the coverage fixture can inspect it. Ordinary gameplay
		# never mounts the node at all.
		pickup.visible = true
		_prop_layer.add_child(pickup)
		_record(handle, pickup, Vector2i(pickup.position))
	if development_preview and socket_index < sockets.size():
		_build_preview_turret(sockets[socket_index])


func _build_preview_turret(at: Vector2) -> void:
	var handle := _handle(&"site_hold_turret")
	if handle == null:
		_issue(&"site_hold_turret")
		return
	var turret := GogoStructureActor.new()
	turret.name = "site_hold_turret"
	turret.collision_layer = 0
	turret.collision_mask = 0
	turret.configure(20.0, -1)
	turret.configure_visual(handle)
	turret.position = at
	turret.modulate = PERMANENT_PROP_MODULATE
	_prop_layer.add_child(turret)
	_record(handle, turret, Vector2i(turret.position))


func _prop_sockets(run_seed: int) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var center := _arena_rect.get_center()
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed
	var shuffled_factors: Array[Vector2] = PROP_ANCHOR_FACTORS.duplicate()
	for index in range(shuffled_factors.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var held: Vector2 = shuffled_factors[index]
		shuffled_factors[index] = shuffled_factors[swap_index]
		shuffled_factors[swap_index] = held
	var factors: Array[Vector2] = OPENING_PROP_ANCHOR_FACTORS.duplicate()
	factors.append_array(shuffled_factors)
	for factor in factors:
		var socket := _arena_rect.position + Vector2(
			factor.x * _arena_rect.size.x,
			factor.y * _arena_rect.size.y
		)
		socket += Vector2(rng.randi_range(-23, 23), rng.randi_range(-19, 19))
		socket.x = clampf(
			socket.x,
			_arena_rect.position.x + PROP_EDGE_INSET,
			_arena_rect.end.x - PROP_EDGE_INSET
		)
		socket.y = clampf(
			socket.y,
			_arena_rect.position.y + PROP_EDGE_INSET,
			_arena_rect.end.y - PROP_EDGE_INSET
		)
		socket = socket.round()
		if int(socket.x) % GRID_SIZE == 0 and int(socket.y) % GRID_SIZE == 0:
			socket += Vector2(11.0, -7.0)
		if socket.distance_to(center) < PLAYER_CLEAR_RADIUS:
			continue
		var separated := true
		for existing in result:
			if socket.distance_to(existing) < PROP_MINIMUM_SEPARATION:
				separated = false
				break
		if separated:
			result.append(socket)
	return result


func _sprite_for_handle(handle: GogoStaticAssetHandle) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.centered = false
	sprite.texture = handle.texture
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.offset = -Vector2(handle.pivot_px)
	sprite.modulate = PERMANENT_PROP_MODULATE
	return sprite


func _decor_handles() -> Array[GogoStaticAssetHandle]:
	var result: Array[GogoStaticAssetHandle] = []
	for selector in DECOR_SELECTORS:
		var selector_handle := _handle(&"community_server_decor_pack", selector)
		if selector_handle != null:
			result.append(selector_handle)
	if result.is_empty():
		var fallback := _handle(&"community_server_decor_pack")
		if fallback != null:
			result.append(fallback)
	elif result.size() < DECOR_SELECTORS.size():
		for selector in DECOR_SELECTORS:
			if _handle(&"community_server_decor_pack", selector) == null:
				_issue(&"community_server_decor_pack")
				break
	return result


func _decor_runtime_name(handle: GogoStaticAssetHandle) -> String:
	if handle.selector.is_empty():
		return "decor_visual_marked_barrel"
	return String(DECOR_RUNTIME_NAMES.get(handle.selector, &"decor_visual_unmapped"))


func _handle(asset_id: StringName, selector: StringName = &"") -> GogoStaticAssetHandle:
	if _snapshot == null:
		return null
	return _snapshot.resolve_asset(asset_id, &"world_sprite", selector)


func _record(
	handle: GogoStaticAssetHandle,
	node: Node,
	at: Vector2i,
	metadata: Dictionary = {}
) -> void:
	GogoStaticConsumerRegistry.observe_handle(
		handle,
		"res://game/gameplay/world/static_world_presenter.gd",
		String(get_path_to(node))
	)
	var record := {
		"asset_id": handle.asset_id,
		"selector": handle.selector,
		"node": String(get_path_to(node)),
		"position": at,
		"display_size_px": handle.display_size_px,
		"pivot_px": handle.pivot_px,
	}
	for key: Variant in metadata:
		record[key] = metadata[key]
	_records.append(record)


func _capture_candidate_centers(visible_rect: Rect2) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for index in CAPTURE_ANCHOR_FACTORS.size():
		var factor := CAPTURE_ANCHOR_FACTORS[index]
		var center := visible_rect.position + Vector2(
			factor.x * visible_rect.size.x,
			factor.y * visible_rect.size.y
		)
		var phase := Vector2(
			float((index * 17) % 23) - 11.0,
			float((index * 13) % 19) - 9.0
		)
		result.append((center + phase).round())
	return result


func _floor_evidence_rect(
	visible_rect: Rect2,
	exclusions: Array[Rect2],
	occupied: Array[Rect2],
	_display_size: Vector2
) -> Rect2:
	var inset := Vector2(GRID_SIZE, GRID_SIZE)
	var interior := Rect2(
		visible_rect.position + inset,
		visible_rect.size - inset * 2.0
	)
	# The floor is one arena-sized Sprite2D. Evidence needs only a visible,
	# unobstructed sample of that texture; treating the whole sprite as a movable
	# tile would misrepresent the production mount and cannot fit a camera view.
	return _find_safe_rect(
		Vector2(GRID_SIZE, GRID_SIZE),
		interior,
		exclusions,
		occupied,
		GRID_SIZE
	)


func _boundary_evidence_rect(
	visible_rect: Rect2,
	exclusions: Array[Rect2],
	occupied: Array[Rect2],
	segment_size: Vector2
) -> Rect2:
	if segment_size.x <= 0.0 or segment_size.y <= 0.0:
		return Rect2()
	var x := visible_rect.position.x
	while x + segment_size.x <= visible_rect.end.x:
		var candidate := Rect2(
			Vector2(x, visible_rect.position.y),
			segment_size
		)
		if (
			not _intersects_any(candidate, exclusions)
			and not _intersects_any(candidate, occupied)
		):
			return candidate
		x += segment_size.x
	return Rect2()


func _find_safe_rect(
	size: Vector2,
	visible_rect: Rect2,
	exclusions: Array[Rect2],
	occupied: Array[Rect2],
	step: int
) -> Rect2:
	if size.x <= 0.0 or size.y <= 0.0:
		return Rect2()
	var y := visible_rect.position.y
	while y + size.y <= visible_rect.end.y:
		var x := visible_rect.position.x
		while x + size.x <= visible_rect.end.x:
			var candidate := Rect2(Vector2(x, y), size)
			if (
				not _intersects_any(candidate, exclusions)
				and not _intersects_any(candidate, occupied)
			):
				return candidate
			x += step
		y += step
	return Rect2()


func _intersects_any(rect: Rect2, others: Array[Rect2]) -> bool:
	for other in others:
		if rect.intersects(other):
			return true
	return false


func _issue(asset_id: StringName) -> void:
	_issues.append({
		"code": &"missing_world_asset",
		"message": "Static world asset is unavailable; the remaining world stays playable.",
		"asset_id": asset_id,
	})


func _clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_records.clear()
	_issues.clear()
