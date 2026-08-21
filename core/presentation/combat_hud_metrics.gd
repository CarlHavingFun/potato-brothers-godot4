class_name CombatHudMetrics
extends RefCounted


# Source of truth for the measured 1280x720 reference layout.  The game canvas
# is 1920x1080, so scene coordinates are these values multiplied by 1.5.
const REFERENCE_SIZE := Vector2(1280.0, 720.0)
const LOGICAL_SCALE := 1.5
const HEALTH_REFERENCE_RECT := Rect2(20.0, 16.0, 205.0, 23.0)
const EXPERIENCE_REFERENCE_RECT := Rect2(20.0, 50.0, 205.0, 23.0)
const MATERIALS_REFERENCE_RECT := Rect2(20.0, 85.0, 205.0, 30.666667)
const MATERIAL_BAG_REFERENCE_RECT := Rect2(20.0, 116.0, 205.0, 28.0)
const WAVE_REFERENCE_RECT := Rect2(500.0, 12.0, 280.0, 36.944447)
const COUNTDOWN_REFERENCE_RECT := Rect2(570.0, 49.0, 140.0, 54.444447)
const BOSS_REFERENCE_RECT := Rect2(420.0, 94.0, 440.0, 28.0)
const NOTICE_REFERENCE_RECT := Rect2(400.0, 128.0, 480.0, 34.0)


static func logical_rect(reference_rect: Rect2) -> Rect2:
	return Rect2(reference_rect.position * LOGICAL_SCALE, reference_rect.size * LOGICAL_SCALE)


static func layout_for_output(physical_size: Vector2) -> Dictionary:
	var scale := physical_size.x / REFERENCE_SIZE.x
	return {
		"health": _scaled(HEALTH_REFERENCE_RECT, scale),
		"experience": _scaled(EXPERIENCE_REFERENCE_RECT, scale),
		"materials": _scaled(MATERIALS_REFERENCE_RECT, scale),
		"material_bag": _scaled(MATERIAL_BAG_REFERENCE_RECT, scale),
		"wave": _scaled(WAVE_REFERENCE_RECT, scale),
		"countdown": _scaled(COUNTDOWN_REFERENCE_RECT, scale),
		"boss": _scaled(BOSS_REFERENCE_RECT, scale),
		"notice": _scaled(NOTICE_REFERENCE_RECT, scale),
	}


static func _scaled(rect: Rect2, scale: float) -> Rect2:
	return Rect2(rect.position * scale, rect.size * scale)
