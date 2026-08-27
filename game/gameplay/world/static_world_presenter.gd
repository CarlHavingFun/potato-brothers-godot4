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
	&"experience_pickup",
	&"supply_pickup",
	&"medical_pickup",
]
const DECOR_SELECTORS: Array[StringName] = [
	&"decor_variant_01",
	&"decor_variant_02",
	&"decor_variant_03",
	&"decor_variant_04",
	&"decor_variant_05",
	&"decor_variant_06",
]
const GRID_SIZE := 64
const PLAYER_CLEAR_RADIUS := 240.0
const CAPTURE_SOCKET_STEP := 96.0
const CAPTURE_SIDE_INSET := 64.0
const CAPTURE_TOP_INSET := 112.0
const CAPTURE_CENTER_HALF_SIZE := Vector2(176.0, 112.0)

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
	_build_props(run_seed, development_preview)
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
	var tile_size := Vector2(handle.display_size_px)
	if tile_size.x <= 0.0 or tile_size.y <= 0.0:
		_issue(&"community_server_floor")
		return
	var instance := MultiMeshInstance2D.new()
	instance.name = "community_server_floor"
	instance.texture = handle.texture
	instance.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var columns := ceili(_arena_rect.size.x / tile_size.x)
	var rows := ceili(_arena_rect.size.y / tile_size.y)
	var mesh := QuadMesh.new()
	mesh.size = tile_size
	var multi_mesh := MultiMesh.new()
	multi_mesh.transform_format = MultiMesh.TRANSFORM_2D
	multi_mesh.mesh = mesh
	multi_mesh.instance_count = columns * rows
	var index := 0
	for row in rows:
		for column in columns:
			var tile_center := _arena_rect.position + Vector2(
				(float(column) + 0.5) * tile_size.x,
				(float(row) + 0.5) * tile_size.y
			)
			multi_mesh.set_instance_transform_2d(index, Transform2D(0.0, tile_center.round()))
			index += 1
	instance.multimesh = multi_mesh
	_floor_layer.add_child(instance)
	_record(handle, instance, Vector2i(_arena_rect.position))


func _build_boundary() -> void:
	var handle := _handle(&"arena_boundary_border")
	if handle == null:
		_issue(&"arena_boundary_border")
		return
	var segment_size := Vector2(handle.display_size_px)
	_build_boundary_edge(
		handle,
		"arena_boundary_border_top",
		ceili(_arena_rect.size.x / segment_size.x),
		Vector2(_arena_rect.position.x + segment_size.x * 0.5, _arena_rect.position.y + segment_size.y * 0.5),
		Vector2(segment_size.x, 0.0),
		0.0
	)
	_build_boundary_edge(
		handle,
		"arena_boundary_border_bottom",
		ceili(_arena_rect.size.x / segment_size.x),
		Vector2(_arena_rect.position.x + segment_size.x * 0.5, _arena_rect.end.y - segment_size.y * 0.5),
		Vector2(segment_size.x, 0.0),
		PI
	)
	_build_boundary_edge(
		handle,
		"arena_boundary_border_left",
		ceili(_arena_rect.size.y / segment_size.x),
		Vector2(_arena_rect.position.x + segment_size.y * 0.5, _arena_rect.position.y + segment_size.x * 0.5),
		Vector2(0.0, segment_size.x),
		-PI * 0.5
	)
	_build_boundary_edge(
		handle,
		"arena_boundary_border_right",
		ceili(_arena_rect.size.y / segment_size.x),
		Vector2(_arena_rect.end.x - segment_size.y * 0.5, _arena_rect.position.y + segment_size.x * 0.5),
		Vector2(0.0, segment_size.x),
		PI * 0.5
	)
	_record(handle, _boundary_layer.get_child(0), Vector2i(_arena_rect.position))


func _build_boundary_edge(
	handle: GogoStaticAssetHandle,
	node_name: String,
	count: int,
	first_center: Vector2,
	step: Vector2,
	rotation: float
) -> void:
	var instance := MultiMeshInstance2D.new()
	instance.name = node_name
	instance.texture = handle.texture
	instance.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var mesh := QuadMesh.new()
	mesh.size = Vector2(handle.display_size_px)
	var multi_mesh := MultiMesh.new()
	multi_mesh.transform_format = MultiMesh.TRANSFORM_2D
	multi_mesh.mesh = mesh
	multi_mesh.instance_count = count
	for index in count:
		multi_mesh.set_instance_transform_2d(
			index,
			Transform2D(rotation, (first_center + step * float(index)).round())
		)
	instance.multimesh = multi_mesh
	_boundary_layer.add_child(instance)


func _build_props(run_seed: int, development_preview: bool) -> void:
	var sockets := _prop_sockets(run_seed)
	var socket_index := 0
	for handle in _decor_handles():
		if socket_index >= sockets.size():
			break
		var decor_sprite := _sprite_for_handle(handle)
		decor_sprite.name = _prop_node_name(handle)
		decor_sprite.position = sockets[socket_index]
		socket_index += 1
		_prop_layer.add_child(decor_sprite)
		_record(handle, decor_sprite, Vector2i(decor_sprite.position))
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
		_prop_layer.add_child(pickup)
		_record(handle, pickup, Vector2i(pickup.position))
	if development_preview:
		_build_preview_turret()


func _build_preview_turret() -> void:
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
	turret.position = Vector2(
		floorf((_arena_rect.end.x - 256.0) / GRID_SIZE) * GRID_SIZE,
		ceilf((_arena_rect.position.y + 256.0) / GRID_SIZE) * GRID_SIZE
	)
	_prop_layer.add_child(turret)
	_record(handle, turret, Vector2i(turret.position))


func _prop_sockets(run_seed: int) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var center := _arena_rect.get_center()
	var start_x := ceili((_arena_rect.position.x + 128.0) / GRID_SIZE) * GRID_SIZE
	var end_x := floori((_arena_rect.end.x - 128.0) / GRID_SIZE) * GRID_SIZE
	var start_y := ceili((_arena_rect.position.y + 128.0) / GRID_SIZE) * GRID_SIZE
	var end_y := floori((_arena_rect.end.y - 128.0) / GRID_SIZE) * GRID_SIZE
	for y in range(start_y, end_y + 1, GRID_SIZE):
		for x in range(start_x, end_x + 1, GRID_SIZE):
			var socket := Vector2(x, y)
			if socket.distance_to(center) >= PLAYER_CLEAR_RADIUS:
				result.append(socket)
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed
	for index in range(result.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var held := result[index]
		result[index] = result[swap_index]
		result[swap_index] = held
	return result


func _sprite_for_handle(handle: GogoStaticAssetHandle) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.centered = false
	sprite.texture = handle.texture
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.offset = -Vector2(handle.pivot_px)
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


func _prop_node_name(handle: GogoStaticAssetHandle) -> String:
	if handle.selector.is_empty():
		return String(handle.asset_id)
	return "%s_%s" % [handle.asset_id, handle.selector]


func _handle(asset_id: StringName, selector: StringName = &"") -> GogoStaticAssetHandle:
	if _snapshot == null:
		return null
	return _snapshot.resolve_asset(asset_id, &"world_sprite", selector)


func _record(handle: GogoStaticAssetHandle, node: Node, at: Vector2i) -> void:
	GogoStaticConsumerRegistry.observe_handle(
		handle,
		"res://game/gameplay/world/static_world_presenter.gd",
		String(get_path_to(node))
	)
	_records.append({
		"asset_id": handle.asset_id,
		"selector": handle.selector,
		"node": String(get_path_to(node)),
		"position": at,
		"display_size_px": handle.display_size_px,
		"pivot_px": handle.pivot_px,
	})


func _capture_candidate_centers(visible_rect: Rect2) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var left_x := visible_rect.position.x + CAPTURE_SIDE_INSET
	var right_x := visible_rect.end.x - CAPTURE_SIDE_INSET
	var center_x := visible_rect.get_center().x
	var columns: Array[float] = []
	while left_x <= center_x - PLAYER_CLEAR_RADIUS:
		columns.append(left_x)
		left_x += CAPTURE_SOCKET_STEP
	while right_x >= center_x + PLAYER_CLEAR_RADIUS:
		columns.append(right_x)
		right_x -= CAPTURE_SOCKET_STEP
	columns.sort()
	var y := visible_rect.position.y + CAPTURE_TOP_INSET
	while y <= visible_rect.end.y - CAPTURE_SIDE_INSET:
		for x in columns:
			result.append(Vector2(x, y).round())
		y += CAPTURE_SOCKET_STEP
	return result


func _floor_evidence_rect(
	visible_rect: Rect2,
	exclusions: Array[Rect2],
	occupied: Array[Rect2],
	tile_size: Vector2
) -> Rect2:
	var inset := Vector2(GRID_SIZE, GRID_SIZE)
	var interior := Rect2(
		visible_rect.position + inset,
		visible_rect.size - inset * 2.0
	)
	return _find_safe_rect(tile_size, interior, exclusions, occupied, GRID_SIZE)


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
