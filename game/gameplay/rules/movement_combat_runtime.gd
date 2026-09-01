class_name GogoMovementCombatRuntime
extends RefCounted


const SPEED_REFERENCE := 235.0
const MOVE_ACCELERATION := 1600.0
const RELEASE_BRAKE_ACCELERATION := 900.0
const REVERSE_BRAKE_ACCELERATION := 1800.0
const MAX_COUNTER_STRAFE_BRAKE_PERCENT := 200.0
const MAX_MOVING_RECOIL_CONTROL_PERCENT := 80.0
const MOVEMENT_SPREAD_DEGREES_AT_REFERENCE := 6.0
const MOVEMENT_RECOIL_MULTIPLIER_AT_REFERENCE := 0.32
const MAX_ASYMPTOTIC_SPEED_RATIO := 2.0


static func move_toward_velocity(
	current_velocity: Vector2,
	direction: Vector2,
	maximum_speed: float,
	delta: float,
	counter_strafe_brake_percent: float
) -> Vector2:
	var safe_delta := maxf(delta, 0.0)
	var safe_maximum_speed := maximum_speed if is_finite(maximum_speed) else 0.0
	safe_maximum_speed = maxf(safe_maximum_speed, 0.0)
	var desired_velocity := direction.limit_length(1.0) * safe_maximum_speed
	var brake_multiplier := 1.0 + clampf(
		counter_strafe_brake_percent,
		0.0,
		MAX_COUNTER_STRAFE_BRAKE_PERCENT
	) / 100.0
	# Braking was approved at the original 235 px/s reference. Scaling only the
	# braking acceleration keeps those release/reverse time windows intact when
	# a character or build has a higher movement cap; it does not increase forward
	# acceleration. The 1.0 floor preserves safe braking for slowed/zero-speed
	# states instead of letting a zero cap strand carried velocity.
	var brake_speed_scale := maxf(safe_maximum_speed / SPEED_REFERENCE, 1.0)
	if direction.is_zero_approx():
		return current_velocity.move_toward(
			Vector2.ZERO,
			RELEASE_BRAKE_ACCELERATION * brake_multiplier * brake_speed_scale * safe_delta
		)
	var acceleration := MOVE_ACCELERATION
	if current_velocity.dot(direction) < 0.0:
		# Reversal is deliberately two-phase: an opposing input may consume an
		# entire long frame reaching zero, but it never crosses zero in that same
		# update. The next update can accelerate toward the newly held direction.
		return current_velocity.move_toward(
			Vector2.ZERO,
			REVERSE_BRAKE_ACCELERATION * brake_multiplier * brake_speed_scale * safe_delta
		)
	return current_velocity.move_toward(desired_velocity, acceleration * safe_delta)


static func ranged_movement_penalty(
	actual_velocity: Vector2,
	moving_recoil_control_percent: float
) -> Dictionary:
	var actual_speed := actual_velocity.length()
	if not is_finite(actual_speed):
		actual_speed = 0.0
	actual_speed = maxf(actual_speed, 0.0)
	# This grows at every finite speed while asymptotically approaching a bounded
	# 2x reference ratio: 235→1, 470→4/3, 705→3/2. It avoids both a hard plateau
	# and unbounded visual kick at extreme speeds.
	var speed_ratio := (
		MAX_ASYMPTOTIC_SPEED_RATIO * actual_speed
		/ (SPEED_REFERENCE + actual_speed)
	)
	var mitigation := 1.0 - clampf(
		moving_recoil_control_percent,
		0.0,
		MAX_MOVING_RECOIL_CONTROL_PERCENT
	) / 100.0
	return {
		&"spread_degrees": MOVEMENT_SPREAD_DEGREES_AT_REFERENCE * speed_ratio * mitigation,
		&"recoil_multiplier": 1.0 + MOVEMENT_RECOIL_MULTIPLIER_AT_REFERENCE * speed_ratio * mitigation,
	}
