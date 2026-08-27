class_name GogoCombatCamera
extends Camera2D

const MAX_VISUAL_IMPULSE := 4.0
const VISUAL_IMPULSE_DECAY := 58.0

var target: Node2D
var world_bounds := Rect2()
var _visual_impulse := Vector2.ZERO
var _visual_impulse_remaining := 0.0
var _visual_impulse_phase := 0
var _current_visual_offset := Vector2.ZERO


func configure(next_target: Node2D, next_world_bounds: Rect2) -> void:
	target = next_target
	world_bounds = next_world_bounds
	enabled = true
	clear_visual_impulses()
	_snap_to_target()


func _physics_process(delta: float) -> void:
	_advance_visual_impulse(delta)
	_snap_to_target()


func add_visual_impulse(direction: Vector2, strength: float) -> bool:
	if not direction.is_finite() or direction.is_zero_approx() or not is_finite(strength) or strength <= 0.0:
		return false
	_visual_impulse += direction.normalized() * minf(strength, MAX_VISUAL_IMPULSE)
	if _visual_impulse.length() > MAX_VISUAL_IMPULSE:
		_visual_impulse = _visual_impulse.normalized() * MAX_VISUAL_IMPULSE
	_visual_impulse_remaining = maxf(_visual_impulse_remaining, 0.075 + minf(strength, 4.0) * 0.012)
	return true


func clear_visual_impulses() -> void:
	_visual_impulse = Vector2.ZERO
	_visual_impulse_remaining = 0.0
	_visual_impulse_phase = 0
	_current_visual_offset = Vector2.ZERO
	offset = Vector2.ZERO


func visual_impulse_magnitude() -> float:
	return _visual_impulse.length()


func _snap_to_target() -> void:
	if target == null or world_bounds.size.x <= 0.0 or world_bounds.size.y <= 0.0:
		return
	global_position = _clamp_center(target.global_position).round()
	offset = _current_visual_offset.round()


func _advance_visual_impulse(delta: float) -> void:
	if _visual_impulse_remaining <= 0.0 or _visual_impulse.is_zero_approx():
		clear_visual_impulses()
		return
	var safe_delta := maxf(delta, 1.0 / 120.0)
	_visual_impulse_phase += 1
	var polarity := 1.0 if _visual_impulse_phase % 2 == 0 else -0.65
	_current_visual_offset = (_visual_impulse * polarity).round()
	_visual_impulse = _visual_impulse.move_toward(Vector2.ZERO, VISUAL_IMPULSE_DECAY * safe_delta)
	_visual_impulse_remaining = maxf(_visual_impulse_remaining - safe_delta, 0.0)


func _clamp_center(desired: Vector2) -> Vector2:
	var visible_size := get_viewport_rect().size / zoom
	var half_size := visible_size * 0.5
	return Vector2(
		_axis_center(desired.x, world_bounds.position.x, world_bounds.end.x, half_size.x),
		_axis_center(desired.y, world_bounds.position.y, world_bounds.end.y, half_size.y)
	)


func _axis_center(desired: float, minimum: float, maximum: float, half_visible: float) -> float:
	if maximum - minimum <= half_visible * 2.0:
		return (minimum + maximum) * 0.5
	return clampf(desired, minimum + half_visible, maximum - half_visible)
