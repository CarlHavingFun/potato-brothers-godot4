class_name AimResolver
extends RefCounted


func rotation_to_aim(
	origin: Vector2,
	aim_mode: int,
	auto_target_position: Vector2,
	mouse_position: Vector2,
	has_auto_target: bool
) -> float:
	if aim_mode == AimMode.MANUAL_MOUSE:
		return origin.direction_to(mouse_position).angle()
	if has_auto_target:
		return origin.direction_to(auto_target_position).angle()
	return 0.0


func can_fire(aim_mode: int, has_auto_target: bool) -> bool:
	return AimMode.is_valid(aim_mode) and has_auto_target
