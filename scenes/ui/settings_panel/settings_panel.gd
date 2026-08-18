extends Panel
class_name SettingsPanel


signal closed

const DISPLAY_MODE_WINDOWED := 0
const DISPLAY_MODE_BORDERLESS := 1
const DISPLAY_MODE_EXCLUSIVE := 2
const DISPLAY_CONFIRM_SECONDS := 10.0
const TAB_KEYS: Array[StringName] = [
	&"ui.settings.tab.audio",
	&"ui.settings.tab.display",
	&"ui.settings.tab.gameplay",
	&"ui.settings.tab.accessibility",
	&"ui.settings.tab.controls",
]
const TAB_FALLBACKS: Array[String] = ["Audio", "Display", "Gameplay", "Accessibility", "Controls"]

@onready var tabs_container: HBoxContainer = %Tabs
@onready var audio_content: VBoxContainer = %AudioPage.get_node("Margin/Content")
@onready var display_content: VBoxContainer = %DisplayPage.get_node("Margin/Content")
@onready var gameplay_content: VBoxContainer = %GameplayPage.get_node("Margin/Content")
@onready var accessibility_content: VBoxContainer = %AccessibilityPage.get_node("Margin/Content")
@onready var controls_content: VBoxContainer = %ControlsPage.get_node("Margin/Content")
@onready var status_label: Label = %StatusLabel
@onready var conflict_dialog: ConfirmationDialog = %ConflictDialog
@onready var display_confirm_dialog: ConfirmationDialog = %DisplayConfirmDialog
@onready var display_confirm_timer: Timer = %DisplayConfirmTimer

var master_slider: HSlider
var music_slider: HSlider
var sfx_slider: HSlider
var mute_on_focus_check: CheckButton
var display_mode_option: OptionButton
var resolution_option: OptionButton
var vsync_check: CheckButton
var fps_cap_option: OptionButton
var aim_option: OptionButton
var pause_on_focus_check: CheckButton
var damage_numbers_check: CheckButton
var player_health_bar_check: CheckButton
var boss_health_bar_check: CheckButton
var locale_option: OptionButton
var enemy_health_slider: HSlider
var enemy_damage_slider: HSlider
var enemy_speed_slider: HSlider
var ui_scale_slider: HSlider
var screen_shake_slider: HSlider
var rumble_slider: HSlider
var reduced_flashes_check: CheckButton
var high_contrast_projectiles_check: CheckButton
var deadzone_slider: HSlider
var keybind_grid: GridContainer

var remap_service := InputRemapService.new()
var awaiting_action: StringName = &""
var awaiting_gamepad := false
var binding_buttons: Dictionary = {}
var binding_labels: Dictionary = {}
var keyboard_binding_buttons: Dictionary = {}
var gamepad_binding_buttons: Dictionary = {}
var value_labels: Dictionary = {}
var tab_buttons: Array[Button] = []
var page_containers: Array[ScrollContainer] = []
var active_tab := 0
var resolution_provider := Callable()

var _binding_snapshot: Dictionary = {}
var _deadzone_snapshot := InputRemapService.DEFAULT_GAMEPAD_DEADZONE
var _settings_snapshot: ProductSettings
var _pending_settings: ProductSettings
var _pending_event: InputEvent
var _pending_action: StringName = &""
var _translated_controls: Array[Control] = []
var _display_confirmation_active := false
var _built := false


func _ready() -> void:
	page_containers = [%AudioPage, %DisplayPage, %GameplayPage, %AccessibilityPage, %ControlsPage]
	_build_tabs()
	_build_pages()
	_configure_dialogs()
	_connect_preview_signals()
	load_settings()
	_select_tab(0)
	visibility_changed.connect(_on_visibility_changed)
	if not Input.joy_connection_changed.is_connected(_on_joy_connection_changed):
		Input.joy_connection_changed.connect(_on_joy_connection_changed)
	set_process_input(true)
	set_process(false)


func _configure_dialogs() -> void:
	for dialog: ConfirmationDialog in [conflict_dialog, display_confirm_dialog]:
		var message_label := dialog.get_label()
		if message_label != null:
			message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			message_label.add_theme_font_size_override(&"font_size", 18)
		for button: Button in [dialog.get_ok_button(), dialog.get_cancel_button()]:
			if button == null:
				continue
			button.custom_minimum_size = Vector2(150, 48)
			button.add_theme_font_size_override(&"font_size", 18)


func _notification(what: int) -> void:
	if what != NOTIFICATION_TRANSLATION_CHANGED or not is_node_ready() or not _built:
		return
	_refresh_translations()


func _build_tabs() -> void:
	for index: int in TAB_KEYS.size():
		var button := Button.new()
		button.name = "Tab%d" % index
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(150, 44)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override(&"font_size", 20)
		button.pressed.connect(_select_tab.bind(index))
		tabs_container.add_child(button)
		tab_buttons.append(button)


func _build_pages() -> void:
	_add_section_title(audio_content, &"ui.settings.section.volume", "Volume")
	master_slider = _add_slider_row(audio_content, "MasterSlider", &"ui.settings.master", "Master volume", 0.0, 100.0, 1.0, 100.0)
	music_slider = _add_slider_row(audio_content, "MusicSlider", &"ui.settings.music", "Music volume", 0.0, 100.0, 1.0, 70.0)
	sfx_slider = _add_slider_row(audio_content, "SfxSlider", &"ui.settings.sfx", "Sound effects", 0.0, 100.0, 1.0, 80.0)
	mute_on_focus_check = _add_check(audio_content, "MuteOnFocusCheck", &"ui.settings.mute_on_focus_lost", "Mute when unfocused")

	_add_section_title(display_content, &"ui.settings.section.window", "Window")
	display_mode_option = _add_option_row(display_content, "DisplayModeOption", &"ui.settings.display_mode", "Display mode")
	display_mode_option.add_item(_text(&"ui.settings.display.windowed", "Windowed"), DISPLAY_MODE_WINDOWED)
	display_mode_option.add_item(_text(&"ui.settings.display.borderless", "Borderless fullscreen"), DISPLAY_MODE_BORDERLESS)
	display_mode_option.add_item(_text(&"ui.settings.display.exclusive", "Exclusive fullscreen"), DISPLAY_MODE_EXCLUSIVE)
	display_mode_option.item_selected.connect(_on_display_mode_selected)
	resolution_option = _add_option_row(display_content, "ResolutionOption", &"ui.settings.resolution", "Resolution")
	vsync_check = _add_check(display_content, "VsyncCheck", &"ui.settings.vsync", "Vertical sync")
	fps_cap_option = _add_option_row(display_content, "FpsCapOption", &"ui.settings.fps_cap", "Frame-rate limit")
	for cap: int in [0, 60, 120, 144, 240]:
		fps_cap_option.add_item(_text(&"ui.settings.unlimited", "Unlimited") if cap == 0 else str(cap), cap)

	_add_section_title(gameplay_content, &"ui.settings.section.aiming", "Aiming and interface")
	aim_option = _add_option_row(gameplay_content, "AimOption", &"ui.settings.aim", "Aim mode")
	aim_option.add_item(_text(&"ui.settings.auto_aim", "Automatic aim"), AimMode.AUTO_TARGET)
	aim_option.add_item(_text(&"ui.settings.manual_aim", "Manual aim"), AimMode.MANUAL_MOUSE)
	pause_on_focus_check = _add_check(gameplay_content, "PauseOnFocusCheck", &"ui.settings.pause_on_focus_lost", "Pause when unfocused")
	damage_numbers_check = _add_check(gameplay_content, "DamageNumbersCheck", &"ui.settings.show_damage_numbers", "Show damage numbers")
	player_health_bar_check = _add_check(gameplay_content, "PlayerHealthBarCheck", &"ui.settings.show_player_health_bar", "Show player health bar")
	boss_health_bar_check = _add_check(gameplay_content, "BossHealthBarCheck", &"ui.settings.show_boss_health_bar", "Show boss health bar")
	locale_option = _add_option_row(gameplay_content, "LocaleOption", &"ui.settings.language", "Language")
	locale_option.add_item(_text(&"ui.language.zh_cn", "Chinese (Simplified)"))
	locale_option.add_item(_text(&"ui.language.en", "English"))
	locale_option.item_selected.connect(_on_locale_selected)

	_add_section_title(accessibility_content, &"ui.settings.section.enemy_assists", "Enemy assistance")
	enemy_health_slider = _add_slider_row(accessibility_content, "EnemyHealthSlider", &"ui.settings.enemy_health", "Enemy health", 25.0, 200.0, 5.0, 100.0)
	enemy_damage_slider = _add_slider_row(accessibility_content, "EnemyDamageSlider", &"ui.settings.enemy_damage", "Enemy damage", 25.0, 200.0, 5.0, 100.0)
	enemy_speed_slider = _add_slider_row(accessibility_content, "EnemySpeedSlider", &"ui.settings.enemy_speed", "Enemy speed", 25.0, 200.0, 5.0, 100.0)
	_add_section_title(accessibility_content, &"ui.settings.section.presentation", "Presentation")
	ui_scale_slider = _add_slider_row(accessibility_content, "UiScaleSlider", &"ui.settings.ui_scale", "UI and text scale", 75.0, 150.0, 5.0, 100.0)
	screen_shake_slider = _add_slider_row(accessibility_content, "ScreenShakeSlider", &"ui.settings.screen_shake", "Screen shake", 0.0, 100.0, 5.0, 100.0)
	rumble_slider = _add_slider_row(accessibility_content, "RumbleSlider", &"ui.settings.rumble", "Controller vibration", 0.0, 100.0, 5.0, 100.0)
	reduced_flashes_check = _add_check(accessibility_content, "ReducedFlashesCheck", &"ui.settings.reduce_flashes", "Reduce flashes")
	high_contrast_projectiles_check = _add_check(accessibility_content, "HighContrastProjectilesCheck", &"ui.settings.high_contrast_projectiles", "High-contrast projectiles")

	_build_controls_page()
	_built = true
	_refresh_translations()


func _build_controls_page() -> void:
	var help := Label.new()
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.add_theme_font_size_override(&"font_size", 17)
	_register_text(help, &"ui.settings.remap_help", "Select a binding, then press a key, mouse button, controller button, or move a stick.")
	controls_content.add_child(help)
	keybind_grid = GridContainer.new()
	keybind_grid.name = "KeybindGrid"
	keybind_grid.columns = 3
	keybind_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	keybind_grid.add_theme_constant_override(&"h_separation", 14)
	keybind_grid.add_theme_constant_override(&"v_separation", 8)
	controls_content.add_child(keybind_grid)
	_add_grid_header(&"ui.settings.action", "Action")
	_add_grid_header(&"ui.settings.keyboard", "Keyboard")
	_add_grid_header(&"ui.settings.gamepad", "Controller")
	for action: StringName in InputRemapService.REMAPPABLE_ACTIONS:
		var label := Label.new()
		label.custom_minimum_size = Vector2(210, 44)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override(&"font_size", 19)
		_register_text(label, StringName("ui.settings.action.%s" % action), String(action).capitalize())
		keybind_grid.add_child(label)
		binding_labels[action] = label
		var keyboard_button := _make_binding_button(action, false)
		keybind_grid.add_child(keyboard_button)
		keyboard_binding_buttons[action] = keyboard_button
		binding_buttons[action] = keyboard_button
		var gamepad_button := _make_binding_button(action, true)
		keybind_grid.add_child(gamepad_button)
		gamepad_binding_buttons[action] = gamepad_button
	deadzone_slider = _add_slider_row(controls_content, "DeadzoneSlider", &"ui.settings.gamepad_deadzone", "Stick deadzone", 5.0, 95.0, 5.0, 25.0)
	deadzone_slider.value_changed.connect(_on_deadzone_preview)
	var reset_controls := Button.new()
	reset_controls.name = "ResetControlsButton"
	reset_controls.custom_minimum_size = Vector2(300, 48)
	reset_controls.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	reset_controls.add_theme_font_size_override(&"font_size", 20)
	reset_controls.pressed.connect(_on_reset_controls_pressed)
	_register_text(reset_controls, &"ui.settings.reset_controls", "Restore control defaults")
	controls_content.add_child(reset_controls)


func _add_grid_header(key: StringName, fallback: String) -> void:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override(&"font_size", 18)
	_register_text(label, key, fallback)
	keybind_grid.add_child(label)


func _make_binding_button(action: StringName, gamepad: bool) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(250, 44)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override(&"font_size", 17)
	button.pressed.connect(_begin_rebind.bind(action, gamepad))
	return button


func _add_section_title(parent: VBoxContainer, key: StringName, fallback: String) -> void:
	var label := Label.new()
	label.add_theme_font_size_override(&"font_size", 25)
	label.add_theme_color_override(&"font_color", Color(0.93, 0.77, 0.35))
	_register_text(label, key, fallback)
	parent.add_child(label)


func _add_slider_row(
	parent: VBoxContainer,
	node_name: String,
	key: StringName,
	fallback: String,
	minimum: float,
	maximum: float,
	step_value: float,
	default_value: float
) -> HSlider:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 46)
	row.add_theme_constant_override(&"separation", 14)
	parent.add_child(row)
	var label := Label.new()
	label.custom_minimum_size = Vector2(270, 0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override(&"font_size", 19)
	_register_text(label, key, fallback)
	row.add_child(label)
	var slider := HSlider.new()
	slider.name = node_name
	slider.custom_minimum_size = Vector2(260, 36)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step_value
	slider.value = default_value
	row.add_child(slider)
	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(76, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_label.add_theme_font_size_override(&"font_size", 18)
	row.add_child(value_label)
	value_labels[slider] = value_label
	slider.value_changed.connect(_on_slider_value_changed.bind(slider))
	_refresh_slider_label(slider)
	return slider


func _add_check(parent: VBoxContainer, node_name: String, key: StringName, fallback: String) -> CheckButton:
	var check := CheckButton.new()
	check.name = node_name
	check.custom_minimum_size = Vector2(0, 44)
	check.add_theme_font_size_override(&"font_size", 19)
	_register_text(check, key, fallback)
	parent.add_child(check)
	return check


func _add_option_row(parent: VBoxContainer, node_name: String, key: StringName, fallback: String) -> OptionButton:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 46)
	row.add_theme_constant_override(&"separation", 14)
	parent.add_child(row)
	var label := Label.new()
	label.custom_minimum_size = Vector2(270, 0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override(&"font_size", 19)
	_register_text(label, key, fallback)
	row.add_child(label)
	var option := OptionButton.new()
	option.name = node_name
	option.custom_minimum_size = Vector2(360, 42)
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.add_theme_font_size_override(&"font_size", 18)
	row.add_child(option)
	return option


func _register_text(control: Control, key: StringName, fallback: String) -> void:
	control.set_meta(&"translation_key", key)
	control.set_meta(&"translation_fallback", fallback)
	_translated_controls.append(control)
	_set_control_text(control, _text(key, fallback))


func _set_control_text(control: Control, value: String) -> void:
	if control is Label:
		(control as Label).text = value
	elif control is BaseButton:
		(control as BaseButton).text = value


func _text(key: StringName, fallback: String) -> String:
	return LocalizedTextService.resolve(key, [], fallback)


func _refresh_translations() -> void:
	for control: Control in _translated_controls:
		if is_instance_valid(control):
			_set_control_text(control, _text(control.get_meta(&"translation_key"), control.get_meta(&"translation_fallback")))
	for index: int in tab_buttons.size():
		tab_buttons[index].text = _text(TAB_KEYS[index], TAB_FALLBACKS[index])
	if display_mode_option != null:
		display_mode_option.set_item_text(0, _text(&"ui.settings.display.windowed", "Windowed"))
		display_mode_option.set_item_text(1, _text(&"ui.settings.display.borderless", "Borderless fullscreen"))
		display_mode_option.set_item_text(2, _text(&"ui.settings.display.exclusive", "Exclusive fullscreen"))
	if fps_cap_option != null:
		fps_cap_option.set_item_text(0, _text(&"ui.settings.unlimited", "Unlimited"))
	if aim_option != null:
		aim_option.set_item_text(0, _text(&"ui.settings.auto_aim", "Automatic aim"))
		aim_option.set_item_text(1, _text(&"ui.settings.manual_aim", "Manual aim"))
	if locale_option != null:
		locale_option.set_item_text(0, _text(&"ui.language.zh_cn", "Chinese (Simplified)"))
		locale_option.set_item_text(1, _text(&"ui.language.en", "English"))
	_refresh_binding_labels()


func load_settings() -> void:
	if not is_node_ready() or not _built:
		return
	_settings_snapshot = Global.product_settings.copy()
	if not _settings_snapshot.input_bindings.is_empty():
		remap_service.apply_actions(_settings_snapshot.input_bindings)
	remap_service.set_gamepad_deadzone(_settings_snapshot.gamepad_deadzone)
	_binding_snapshot = remap_service.serialize_actions()
	_deadzone_snapshot = remap_service.gamepad_deadzone()
	_populate_controls(_settings_snapshot)
	_pending_settings = null
	status_label.text = ""
	_refresh_binding_labels()


func _populate_controls(settings: ProductSettings) -> void:
	master_slider.value = settings.master_volume * 100.0
	music_slider.value = settings.music_volume * 100.0
	sfx_slider.value = settings.sfx_volume * 100.0
	mute_on_focus_check.button_pressed = settings.mute_on_focus_lost
	_select_option_id(display_mode_option, settings.display_mode)
	_populate_resolutions(settings.resolution)
	vsync_check.button_pressed = settings.vsync_enabled
	_select_option_id(fps_cap_option, settings.fps_cap)
	_select_option_id(aim_option, settings.aim_mode)
	pause_on_focus_check.button_pressed = settings.pause_on_focus_lost
	damage_numbers_check.button_pressed = settings.show_damage_numbers
	player_health_bar_check.button_pressed = settings.show_player_health_bar
	boss_health_bar_check.button_pressed = settings.show_boss_health_bar
	locale_option.select(0 if settings.locale == "zh_CN" else 1)
	enemy_health_slider.value = settings.enemy_health_scale * 100.0
	enemy_damage_slider.value = settings.enemy_damage_scale * 100.0
	enemy_speed_slider.value = settings.enemy_speed_scale * 100.0
	ui_scale_slider.value = settings.ui_scale * 100.0
	screen_shake_slider.value = settings.screen_shake_intensity * 100.0
	rumble_slider.value = settings.gamepad_rumble_intensity * 100.0
	reduced_flashes_check.button_pressed = settings.reduce_flashes
	high_contrast_projectiles_check.button_pressed = settings.high_contrast_projectiles
	deadzone_slider.value = settings.gamepad_deadzone * 100.0
	_on_display_mode_selected(display_mode_option.selected)


func set_resolution_provider(provider: Callable) -> void:
	resolution_provider = provider
	if is_node_ready() and resolution_option != null:
		_populate_resolutions(_selected_resolution())


func _populate_resolutions(selected_resolution: Vector2i) -> void:
	resolution_option.clear()
	var resolutions := _available_resolutions()
	if selected_resolution not in resolutions:
		resolutions.append(selected_resolution)
	resolutions.sort_custom(func(first: Vector2i, second: Vector2i) -> bool: return first.x * first.y < second.x * second.y)
	for resolution: Vector2i in resolutions:
		resolution_option.add_item("%d × %d" % [resolution.x, resolution.y])
		resolution_option.set_item_metadata(resolution_option.item_count - 1, resolution)
		if resolution == selected_resolution:
			resolution_option.select(resolution_option.item_count - 1)


func _available_resolutions() -> Array[Vector2i]:
	var raw: Variant = resolution_provider.call() if resolution_provider.is_valid() else Global.available_resolutions()
	var result: Array[Vector2i] = []
	if raw is Array:
		for value: Variant in raw:
			var resolution := value as Vector2i
			if resolution.x >= 640 and resolution.y >= 360 and resolution not in result:
				result.append(resolution)
	if result.is_empty():
		result.assign([Vector2i(1280, 720), Vector2i(1920, 1080)])
	return result


func _selected_resolution() -> Vector2i:
	if resolution_option == null or resolution_option.item_count == 0 or resolution_option.selected < 0:
		return Vector2i(1920, 1080)
	var metadata: Variant = resolution_option.get_item_metadata(resolution_option.selected)
	return metadata as Vector2i if metadata is Vector2i else Vector2i(1920, 1080)


func _build_draft() -> ProductSettings:
	var draft := Global.product_settings.copy()
	draft.master_volume = master_slider.value / 100.0
	draft.music_volume = music_slider.value / 100.0
	draft.sfx_volume = sfx_slider.value / 100.0
	draft.mute_on_focus_lost = mute_on_focus_check.button_pressed
	draft.display_mode = display_mode_option.get_item_id(display_mode_option.selected)
	draft.resolution = _selected_resolution()
	draft.vsync_enabled = vsync_check.button_pressed
	draft.fps_cap = fps_cap_option.get_item_id(fps_cap_option.selected)
	draft.aim_mode = aim_option.get_item_id(aim_option.selected)
	draft.pause_on_focus_lost = pause_on_focus_check.button_pressed
	draft.show_damage_numbers = damage_numbers_check.button_pressed
	draft.show_player_health_bar = player_health_bar_check.button_pressed
	draft.show_boss_health_bar = boss_health_bar_check.button_pressed
	draft.locale = "zh_CN" if locale_option.selected == 0 else "en"
	draft.enemy_health_scale = enemy_health_slider.value / 100.0
	draft.enemy_damage_scale = enemy_damage_slider.value / 100.0
	draft.enemy_speed_scale = enemy_speed_slider.value / 100.0
	draft.ui_scale = ui_scale_slider.value / 100.0
	draft.screen_shake_intensity = screen_shake_slider.value / 100.0
	draft.gamepad_rumble_intensity = rumble_slider.value / 100.0
	draft.reduce_flashes = reduced_flashes_check.button_pressed
	draft.high_contrast_projectiles = high_contrast_projectiles_check.button_pressed
	draft.input_bindings = remap_service.serialize_actions()
	draft.gamepad_deadzone = deadzone_slider.value / 100.0
	return draft.sanitize()


func _on_apply_button_pressed() -> void:
	awaiting_action = &""
	_pending_settings = _build_draft()
	if _display_settings_changed(_settings_snapshot, _pending_settings):
		if not Global.preview_product_settings(_pending_settings):
			status_label.text = _text(&"ui.settings.apply_failed", "Could not apply settings.")
			return
		_display_confirmation_active = true
		display_confirm_timer.start(DISPLAY_CONFIRM_SECONDS)
		_update_display_confirmation_text()
		display_confirm_dialog.popup_centered(Vector2i(560, 220))
		set_process(true)
		return
	if not Global.apply_product_settings(_pending_settings, true):
		status_label.text = _text(&"ui.settings.apply_failed", "Could not save settings.")
		return
	_finish_and_close()


func _display_settings_changed(before: ProductSettings, after: ProductSettings) -> bool:
	return before != null and after != null and (
		before.display_mode != after.display_mode
		or before.resolution != after.resolution
		or before.vsync_enabled != after.vsync_enabled
	)


func _on_display_keep_confirmed() -> void:
	if not _display_confirmation_active:
		return
	_display_confirmation_active = false
	display_confirm_timer.stop()
	set_process(false)
	if _pending_settings == null or not Global.apply_product_settings(_pending_settings, true):
		Global.restore_product_settings(_settings_snapshot)
		status_label.text = _text(&"ui.settings.apply_failed", "Could not save settings; previous display restored.")
		return
	_finish_and_close()


func _on_display_revert_requested() -> void:
	if not _display_confirmation_active:
		return
	_display_confirmation_active = false
	display_confirm_timer.stop()
	set_process(false)
	display_confirm_dialog.hide()
	Global.restore_product_settings(_settings_snapshot)
	remap_service.apply_actions(_binding_snapshot)
	remap_service.set_gamepad_deadzone(_deadzone_snapshot)
	_populate_controls(_settings_snapshot)
	_refresh_binding_labels()
	status_label.text = _text(&"ui.settings.display_reverted", "Previous display settings restored.")


func _process(_delta: float) -> void:
	if _display_confirmation_active:
		_update_display_confirmation_text()


func _update_display_confirmation_text() -> void:
	var seconds := maxi(0, ceili(display_confirm_timer.time_left))
	display_confirm_dialog.dialog_text = _text(
		&"ui.settings.keep_display_countdown",
		"Keep these display settings? Reverting in %d seconds." % seconds
	).replace("{seconds}", str(seconds))


func _on_cancel_button_pressed() -> void:
	if _display_confirmation_active:
		_on_display_revert_requested()
		return
	awaiting_action = &""
	remap_service.apply_actions(_binding_snapshot)
	remap_service.set_gamepad_deadzone(_deadzone_snapshot)
	if _settings_snapshot != null:
		Global.restore_product_settings(_settings_snapshot)
	_finish_and_close()


func _on_reset_button_pressed() -> void:
	var defaults := ProductSettings.new()
	remap_service.restore_defaults()
	remap_service.set_gamepad_deadzone(defaults.gamepad_deadzone)
	_populate_controls(defaults)
	_refresh_binding_labels()
	status_label.text = _text(&"ui.settings.defaults_staged", "Defaults staged. Select Apply to save them.")


func _on_reset_controls_pressed() -> void:
	remap_service.restore_defaults()
	deadzone_slider.value = ProductSettings.new().gamepad_deadzone * 100.0
	_refresh_binding_labels()
	status_label.text = _text(&"ui.settings.control_defaults_staged", "Control defaults staged.")


func _finish_and_close() -> void:
	_pending_settings = null
	display_confirm_timer.stop()
	display_confirm_dialog.hide()
	conflict_dialog.hide()
	set_process(false)
	closed.emit()
	hide()


func _begin_rebind(action: StringName, gamepad: bool) -> void:
	awaiting_action = action
	awaiting_gamepad = gamepad
	status_label.text = _text(
		&"ui.settings.press_gamepad_binding" if gamepad else &"ui.settings.press_keyboard_binding",
		"Press a controller input…" if gamepad else "Press a key or mouse button…"
	)
	var button := gamepad_binding_buttons.get(action) as Button if gamepad else keyboard_binding_buttons.get(action) as Button
	if button != null:
		button.text = "…"


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if conflict_dialog.visible:
		if _is_capture_cancel(event):
			conflict_dialog.hide()
			_on_conflict_canceled()
			get_viewport().set_input_as_handled()
		return
	if _display_confirmation_active:
		if _is_capture_cancel(event):
			_on_display_revert_requested()
			get_viewport().set_input_as_handled()
		return
	if not awaiting_action.is_empty():
		if _is_capture_cancel(event):
			awaiting_action = &""
			status_label.text = ""
			_refresh_binding_labels()
			get_viewport().set_input_as_handled()
			return
		if _event_matches_capture_device(event):
			if _is_reserved_ui_event(event):
				status_label.text = _text(&"ui.settings.reserved_binding", "That input is reserved for menu navigation.")
				get_viewport().set_input_as_handled()
				return
			_commit_rebind(event)
		return
	var joy_button := event as InputEventJoypadButton
	if joy_button != null and joy_button.pressed:
		if joy_button.button_index == JOY_BUTTON_LEFT_SHOULDER:
			_switch_tab_relative(-1)
			get_viewport().set_input_as_handled()
		elif joy_button.button_index == JOY_BUTTON_RIGHT_SHOULDER:
			_switch_tab_relative(1)
			get_viewport().set_input_as_handled()
		elif joy_button.button_index == JOY_BUTTON_B:
			_on_cancel_button_pressed()
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_cancel"):
		_on_cancel_button_pressed()
		get_viewport().set_input_as_handled()


func _event_matches_capture_device(event: InputEvent) -> bool:
	if awaiting_gamepad:
		if event is InputEventJoypadButton:
			return (event as InputEventJoypadButton).pressed
		if event is InputEventJoypadMotion:
			return absf((event as InputEventJoypadMotion).axis_value) >= 0.65
		return false
	if event is InputEventKey:
		return (event as InputEventKey).pressed and not (event as InputEventKey).echo
	return event is InputEventMouseButton and (event as InputEventMouseButton).pressed


func _is_capture_cancel(event: InputEvent) -> bool:
	if event is InputEventKey:
		var key := event as InputEventKey
		return key.pressed and (key.keycode == KEY_ESCAPE or key.physical_keycode == KEY_ESCAPE)
	if event is InputEventJoypadButton:
		var button := event as InputEventJoypadButton
		return button.pressed and button.button_index == JOY_BUTTON_B
	return false


func _is_reserved_ui_event(event: InputEvent) -> bool:
	if event is InputEventKey:
		var key := event as InputEventKey
		var code := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		return code in [KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE]
	if event is InputEventJoypadButton:
		return (event as InputEventJoypadButton).button_index in [
			JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER,
		]
	return false


func _commit_rebind(event: InputEvent) -> void:
	var action := awaiting_action
	awaiting_action = &""
	var conflicts := remap_service.find_conflicts(action, event)
	if not conflicts.is_empty():
		_pending_action = action
		_pending_event = event.duplicate(true) as InputEvent
		var conflict_names: Array[String] = []
		for conflict: StringName in conflicts:
			conflict_names.append(_action_text(conflict))
		conflict_dialog.dialog_text = _text(
			&"ui.settings.binding_conflict",
			"This input is already used by {actions}. Replace it?"
		).replace("{actions}", ", ".join(conflict_names))
		conflict_dialog.popup_centered(Vector2i(560, 230))
		get_viewport().set_input_as_handled()
		return
	remap_service.rebind(action, event)
	status_label.text = ""
	_refresh_binding_labels()
	get_viewport().set_input_as_handled()


func _on_conflict_replace_confirmed() -> void:
	if _pending_event != null and not _pending_action.is_empty():
		remap_service.rebind(_pending_action, _pending_event, true)
	_pending_action = &""
	_pending_event = null
	status_label.text = ""
	_refresh_binding_labels()


func _on_conflict_canceled() -> void:
	_pending_action = &""
	_pending_event = null
	status_label.text = ""
	_refresh_binding_labels()


func _refresh_binding_labels() -> void:
	if not _built:
		return
	for action: StringName in InputRemapService.REMAPPABLE_ACTIONS:
		var keyboard_text := InputPromptFormatter.format_binding_tokens(
			remap_service.binding_tokens(action, false)
		)
		var gamepad_text := InputPromptFormatter.format_binding_tokens(
			remap_service.binding_tokens(action, true)
		)
		var keyboard_button := keyboard_binding_buttons.get(action) as Button
		var gamepad_button := gamepad_binding_buttons.get(action) as Button
		if keyboard_button != null:
			keyboard_button.text = keyboard_text if not keyboard_text.is_empty() else _text(&"ui.settings.unbound", "Unbound")
		if gamepad_button != null:
			gamepad_button.text = gamepad_text if not gamepad_text.is_empty() else _text(&"ui.settings.unbound", "Unbound")


func _refresh_action_labels() -> void:
	_refresh_translations()


func _action_text(action: StringName) -> String:
	return _text(StringName("ui.settings.action.%s" % action), String(action).capitalize())


func _select_tab(index: int) -> void:
	if tab_buttons.is_empty():
		return
	active_tab = posmod(index, tab_buttons.size())
	for page_index: int in page_containers.size():
		page_containers[page_index].visible = page_index == active_tab
		tab_buttons[page_index].button_pressed = page_index == active_tab
	page_containers[active_tab].scroll_vertical = 0
	if visible:
		tab_buttons[active_tab].grab_focus()


func _switch_tab_relative(direction: int) -> void:
	_select_tab(active_tab + direction)


func _on_visibility_changed() -> void:
	if visible and not tab_buttons.is_empty():
		call_deferred("_focus_active_tab")


func _on_joy_connection_changed(_device: int, _connected: bool) -> void:
	if visible and not tab_buttons.is_empty():
		call_deferred("_focus_active_tab")


func _focus_active_tab() -> void:
	if visible and active_tab >= 0 and active_tab < tab_buttons.size():
		tab_buttons[active_tab].grab_focus()


func _on_display_mode_selected(index: int) -> void:
	if display_mode_option == null or display_mode_option.item_count == 0:
		return
	var safe_index := clampi(index, 0, display_mode_option.item_count - 1)
	resolution_option.disabled = (
		display_mode_option.get_item_id(safe_index) != DISPLAY_MODE_WINDOWED
	)


func _select_option_id(option: OptionButton, item_id: int) -> void:
	for index: int in option.item_count:
		if option.get_item_id(index) == item_id:
			option.select(index)
			return
	option.select(0)


func _connect_preview_signals() -> void:
	for slider: HSlider in [master_slider, music_slider, sfx_slider]:
		slider.value_changed.connect(_preview_audio.bind(slider))


func _on_slider_value_changed(_value: float, slider: HSlider) -> void:
	_refresh_slider_label(slider)


func _refresh_slider_label(slider: HSlider) -> void:
	var label := value_labels.get(slider) as Label
	if label != null:
		label.text = "%d%%" % roundi(slider.value)


func _preview_audio(_value: float, _slider: HSlider) -> void:
	_set_bus_volume(&"Master", master_slider.value / 100.0)
	_set_bus_volume(&"Music", music_slider.value / 100.0)
	_set_bus_volume(&"SFX", sfx_slider.value / 100.0)


func _set_bus_volume(bus_name: StringName, value: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index < 0:
		return
	var linear := clampf(value, 0.0, 1.0)
	AudioServer.set_bus_mute(index, linear <= 0.0)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(linear, 0.0001)))


func _on_locale_selected(index: int) -> void:
	TranslationServer.set_locale("zh_CN" if index == 0 else "en")
	_refresh_translations()


func _on_deadzone_preview(value: float) -> void:
	remap_service.set_gamepad_deadzone(value / 100.0)
