extends Control
class_name CombatHud

const METRICS := preload("res://core/presentation/combat_hud_metrics.gd")

@onready var health_bar: ProgressBar = $TopLeft/HealthBar
@onready var health_value: Label = $TopLeft/HealthBar/Value
@onready var experience_bar: ProgressBar = $TopLeft/ExperienceBar
@onready var level_label: Label = $TopLeft/ExperienceBar/Level
@onready var materials_value: Label = $TopLeft/Materials/Value
@onready var material_bag: Control = $TopLeft/MaterialBag
@onready var material_bag_value: Label = $TopLeft/MaterialBag/Value
@onready var wave_label: Label = $TopCenter/Wave
@onready var countdown_label: Label = $TopCenter/Countdown
@onready var boss_status: Label = $BossStatus
@onready var notice: Label = $Notice


func _ready() -> void:
	apply_metric_layout()
	var material_icon := $TopLeft/Materials/Icon as TextureRect
	var bag_icon := $TopLeft/MaterialBag/Icon as TextureRect
	var texture := Presentation.resolve_texture(&"pickup", &"pickup.material")
	material_icon.texture = texture
	bag_icon.texture = texture


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready():
		apply_metric_layout()


func apply_metric_layout() -> void:
	_apply_region_rect(health_bar, METRICS.logical_rect(METRICS.HEALTH_REFERENCE_RECT))
	_apply_region_rect(experience_bar, METRICS.logical_rect(METRICS.EXPERIENCE_REFERENCE_RECT))
	_apply_region_rect($TopLeft/Materials as Control, METRICS.logical_rect(METRICS.MATERIALS_REFERENCE_RECT))
	_apply_region_rect(material_bag, METRICS.logical_rect(METRICS.MATERIAL_BAG_REFERENCE_RECT))
	_apply_region_rect(wave_label, METRICS.logical_rect(METRICS.WAVE_REFERENCE_RECT))
	_apply_region_rect(countdown_label, METRICS.logical_rect(METRICS.COUNTDOWN_REFERENCE_RECT))
	_apply_region_rect(boss_status, METRICS.logical_rect(METRICS.BOSS_REFERENCE_RECT))
	_apply_region_rect(notice, METRICS.logical_rect(METRICS.NOTICE_REFERENCE_RECT))


func _apply_region_rect(control: Control, rect: Rect2) -> void:
	control.position = rect.position
	control.size = rect.size


# This is intentionally the only full-state render entry. Arena owns capture;
# the HUD only projects the immutable state it receives.
func apply_state(state: HudState) -> void:
	if state == null:
		return
	health_bar.max_value = maxf(1.0, float(state.max_health))
	health_bar.value = clampf(float(state.health), 0.0, health_bar.max_value)
	health_value.text = "%d / %d" % [state.health, state.max_health]
	experience_bar.max_value = maxi(1, state.experience_required)
	experience_bar.value = clampi(state.experience, 0, int(experience_bar.max_value))
	level_label.text = "LV.%d" % state.level
	materials_value.text = str(state.materials)
	material_bag.visible = state.material_bag > 0
	material_bag_value.text = str(state.material_bag)
	wave_label.text = LocalizedTextService.resolve(
		&"ui.hud.wave.endless" if state.endless else &"ui.hud.wave.standard", [state.wave]
	)
	countdown_label.text = str(state.seconds_remaining)


func update_boss_status(text: String) -> void:
	boss_status.text = text
	boss_status.visible = not text.is_empty()


func show_notice(text: String, important := false) -> void:
	notice.text = text
	notice.visible = not text.is_empty()
	notice.add_theme_color_override(
		&"font_color", Color(1.0, 0.84, 0.34) if important else Color.WHITE
	)


func clear_notice() -> void:
	notice.text = ""
	notice.hide()
