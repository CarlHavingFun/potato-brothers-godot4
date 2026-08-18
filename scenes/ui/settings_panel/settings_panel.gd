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
@onready var keybind_grid: GridContainer = %KeybindGrid

var remap_service := InputRemapService.new()
var awaiting_action: StringName = &""
var binding_buttons: Dictionary = {}
var binding_labels: Dictionary = {}
var _binding_snapshot: Dictionary = {}


func _ready() -> void:
	for resolution: String in RESOLUTIONS:
		resolution_option.add_item(resolution)
	aim_option.add_item(tr("ui.settings.auto_aim"), AimMode.AUTO_TARGET)
	aim_option.add_item(tr("ui.settings.manual_aim"), AimMode.MANUAL_MOUSE)
	locale_option.add_item(tr("ui.language.zh_cn"))
	locale_option.add_item(tr("ui.language.en"))
	_build_keybind_rows()
	load_settings()
	set_process_input(true)


func _notification(what: int) -> void:
	if what != NOTIFICATION_TRANSLATION_CHANGED or not is_node_ready():
		return
	aim_option.set_item_text(0, tr("ui.settings.auto_aim"))
	aim_option.set_item_text(1, tr("ui.settings.manual_aim"))
	locale_option.set_item_text(0, tr("ui.language.zh_cn"))
	locale_option.set_item_text(1, tr("ui.language.en"))
	_refresh_action_labels()
	_refresh_binding_labels()


func load_settings() -> void:
	var settings := Global.meta_progress
	music_slider.value = settings.music_volume * 100.0
	sfx_slider.value = settings.sfx_volume * 100.0
	fullscreen_check.button_pressed = settings.fullscreen
	resolution_option.select(maxi(0, RESOLUTIONS.find(settings.resolution)))
	aim_option.select(settings.aim_mode)
	locale_option.select(0 if settings.locale == "zh_CN" else 1)
	_binding_snapshot = remap_service.serialize_actions()
	_refresh_binding_labels()


func _build_keybind_rows() -> void:
	for action: StringName in InputRemapService.REMAPPABLE_ACTIONS:
		var label := Label.new()
		label.text = tr("ui.settings.action.%s" % action)
		label.add_theme_font_size_override(&"font_size", 20)
		keybind_grid.add_child(label)
		binding_labels[action] = label
		var button := Button.new()
		button.custom_minimum_size = Vector2(300, 40)
		button.pressed.connect(_begin_rebind.bind(action))
		keybind_grid.add_child(button)
		binding_buttons[action] = button


func _begin_rebind(action: StringName) -> void:
	awaiting_action = action
	var button := binding_buttons.get(action) as Button
	if button != null:
		button.text = tr("ui.settings.press_binding")


func _input(event: InputEvent) -> void:
	if awaiting_action.is_empty() or not visible:
		return
	if event is InputEventKey and (event as InputEventKey).pressed:
		if (event as InputEventKey).keycode == KEY_ESCAPE:
			awaiting_action = &""
			_refresh_binding_labels()
			get_viewport().set_input_as_handled()
			return
		_commit_rebind(event)
	elif event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
		_commit_rebind(event)


func _commit_rebind(event: InputEvent) -> void:
	remap_service.rebind(awaiting_action, event)
	awaiting_action = &""
	_refresh_binding_labels()
	get_viewport().set_input_as_handled()


func _refresh_binding_labels() -> void:
	for action: StringName in binding_buttons:
		var parts: Array[String] = []
		for event: InputEvent in InputMap.action_get_events(action):
			if event is InputEventKey or event is InputEventJoypadButton:
				parts.append(event.as_text())
		var button := binding_buttons[action] as Button
		button.text = " / ".join(parts) if not parts.is_empty() else tr("ui.settings.unbound")


func _refresh_action_labels() -> void:
	for action: StringName in binding_labels:
		var label := binding_labels[action] as Label
		label.text = tr("ui.settings.action.%s" % action)


func _on_apply_button_pressed() -> void:
	Global.meta_progress.input_bindings = remap_service.serialize_actions()
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
	awaiting_action = &""
	remap_service.apply_actions(_binding_snapshot)
	load_settings()
	closed.emit()
	hide()
