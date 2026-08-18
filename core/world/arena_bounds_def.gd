class_name ArenaBoundsDef
extends Resource


@export var playable_rect := Rect2(-1000.0, -500.0, 2000.0, 1000.0)
@export var visual_padding := Vector2(280.0, 160.0)
@export var spawn_margin := Vector2(80.0, 80.0)
@export_range(0.0, 256.0, 1.0) var player_radius := 34.0


func playable_rect_for_radius(radius: float = 0.0) -> Rect2:
	return _inset_rect(playable_rect, Vector2.ONE * maxf(0.0, radius))


func spawn_rect() -> Rect2:
	return _inset_rect(playable_rect, Vector2(
		maxf(0.0, spawn_margin.x), maxf(0.0, spawn_margin.y)
	))


func visual_rect() -> Rect2:
	var padding := Vector2(maxf(0.0, visual_padding.x), maxf(0.0, visual_padding.y))
	return Rect2(playable_rect.position - padding, playable_rect.size + padding * 2.0)


func clamp_player_position(world_position: Vector2, radius: float = -1.0) -> Vector2:
	var effective_radius := player_radius if radius < 0.0 else radius
	return _clamp_point_to_rect(world_position, playable_rect_for_radius(effective_radius))


func clamp_spawn_position(world_position: Vector2) -> Vector2:
	return _clamp_point_to_rect(world_position, spawn_rect())


func random_spawn_position(rng: RandomNumberGenerator) -> Vector2:
	if rng == null:
		return spawn_rect().get_center()
	var bounds := spawn_rect()
	return Vector2(
		rng.randf_range(bounds.position.x, bounds.end.x),
		rng.randf_range(bounds.position.y, bounds.end.y)
	)


func clamp_camera_center(
	target: Vector2,
	viewport_size: Vector2,
	shake_padding: Vector2 = Vector2.ZERO
) -> Vector2:
	var bounds := visual_rect()
	var half_view := Vector2(maxf(0.0, viewport_size.x), maxf(0.0, viewport_size.y)) * 0.5
	var padding := Vector2(maxf(0.0, shake_padding.x), maxf(0.0, shake_padding.y))
	var minimum := bounds.position + half_view + padding
	var maximum := bounds.end - half_view - padding
	var center := bounds.get_center()
	return Vector2(
		center.x if minimum.x > maximum.x else clampf(target.x, minimum.x, maximum.x),
		center.y if minimum.y > maximum.y else clampf(target.y, minimum.y, maximum.y)
	)


func _inset_rect(source: Rect2, margin: Vector2) -> Rect2:
	var safe_margin := Vector2(
		minf(maxf(0.0, margin.x), source.size.x * 0.5),
		minf(maxf(0.0, margin.y), source.size.y * 0.5)
	)
	return Rect2(source.position + safe_margin, source.size - safe_margin * 2.0)


func _clamp_point_to_rect(point: Vector2, bounds: Rect2) -> Vector2:
	return Vector2(
		clampf(point.x, bounds.position.x, bounds.end.x),
		clampf(point.y, bounds.position.y, bounds.end.y)
	)
