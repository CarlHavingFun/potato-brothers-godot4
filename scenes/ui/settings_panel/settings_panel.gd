extends Panel
class_name SettingsPanel

signal closed

const RESOLUTIONS := ["1280x720", "1600x900", "1920x1080"]

@onready var music_slider: HSlider = %MusicSlider
@onready var sfx_slider: HSlider = %SfxSlider
@onready var fullscreen_check: CheckButton = %FullscreenCheck
@onready var resolution_option: OptionButton = %ResolutionOption
@onready var aim_option: OptionButton = %AimOption
@onready var locale_option: OptionButton = %LocaleOption


func _ready() -> void:
	for resolution: String in RESOLUTIONS:
		resolution_option.add_item(resolution)
	aim_option.add_item(tr("ui.settings.auto_aim"), AimMode.AUTO_TARGET)
	aim_option.add_item(tr("ui.settings.manual_aim"), AimMode.MANUAL_MOUSE)
	locale_option.add_item("简体中文")
	locale_option.add_item("English")
	load_settings()


func _notification(what: int) -> void:
	if what != NOTIFICATION_TRANSLATION_CHANGED or not is_node_ready():
		return
	aim_option.set_item_text(0, tr("ui.settings.auto_aim"))
	aim_option.set_item_text(1, tr("ui.settings.manual_aim"))


func load_settings() -> void:
	var settings := Global.meta_progress
	music_slider.value = settings.music_volume * 100.0
	sfx_slider.value = settings.sfx_volume * 100.0
	fullscreen_check.button_pressed = settings.fullscreen
	resolution_option.select(maxi(0, RESOLUTIONS.find(settings.resolution)))
	aim_option.select(settings.aim_mode)
	locale_option.select(0 if settings.locale == "zh_CN" else 1)


func _on_apply_button_pressed() -> void:
	Global.update_product_settings(
		music_slider.value / 100.0,
		sfx_slider.value / 100.0,
		fullscreen_check.button_pressed,
		RESOLUTIONS[resolution_option.selected],
		aim_option.get_item_id(aim_option.selected),
		"zh_CN" if locale_option.selected == 0 else "en"
	)
	closed.emit()
	hide()


func _on_cancel_button_pressed() -> void:
	load_settings()
	closed.emit()
	hide()
