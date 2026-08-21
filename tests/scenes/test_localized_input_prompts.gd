extends GdUnitTestSuite


const SETTINGS_SCENE := "res://scenes/ui/settings_panel/settings_panel.tscn"

var _original_locale := ""
var _original_bindings: Dictionary
var _original_device := InputDeviceManager.Device.KEYBOARD_MOUSE
var _original_product_settings: ProductSettings


func before_test() -> void:
	_original_locale = TranslationServer.get_locale()
	_original_bindings = InputRemapService.new().serialize_actions()
	_original_device = InputDevices.active_device
	_original_product_settings = Global.product_settings.copy()
	InputRemapService.new().restore_defaults()


func after_test() -> void:
	InputRemapService.new().apply_actions(_original_bindings)
	InputDevices.active_device = _original_device
	TranslationServer.set_locale(_original_locale)
	Global.product_settings = _original_product_settings


func test_settings_binding_buttons_render_localized_tokens_in_both_locales() -> void:
	TranslationServer.set_locale("zh_CN")
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	assert_bool(InputRemapService.new().rebind(&"move_up", mouse, true)).is_true()
	Global.product_settings = Global.product_settings.copy()
	Global.product_settings.input_bindings = InputRemapService.new().serialize_actions()
	var panel: SettingsPanel = auto_free(load(SETTINGS_SCENE).instantiate())
	add_child(panel)
	await await_idle_frame()

	var keyboard_buttons := panel.keyboard_binding_buttons
	var gamepad_buttons := panel.gamepad_binding_buttons
	var dash_keyboard := keyboard_buttons.get(&"dash") as Button
	var move_up_keyboard := keyboard_buttons.get(&"move_up") as Button
	var move_left_gamepad := gamepad_buttons.get(&"move_left") as Button
	var pause_gamepad := gamepad_buttons.get(&"pause") as Button
	assert_object(dash_keyboard).is_not_null()
	assert_object(move_up_keyboard).is_not_null()
	assert_object(move_left_gamepad).is_not_null()
	assert_object(pause_gamepad).is_not_null()
	assert_str(dash_keyboard.text).is_equal("空格键")
	assert_str(move_up_keyboard.text).is_equal("鼠标左键")
	assert_str(move_left_gamepad.text).contains("左摇杆横轴")
	assert_str(move_left_gamepad.text).contains("负向")
	assert_str(pause_gamepad.text).is_equal("手柄开始键")
	_assert_no_english_input_words(panel)

	TranslationServer.set_locale("en")
	await await_idle_frame()
	assert_str(dash_keyboard.text).is_equal("Space")
	assert_str(move_up_keyboard.text).is_equal("Left Mouse Button")
	assert_str(move_left_gamepad.text).contains("Left Stick X")
	assert_str(move_left_gamepad.text).contains("Negative")
	assert_str(pause_gamepad.text).is_equal("Start Button")


func test_frontend_device_hint_uses_the_same_localized_prompt_tokens() -> void:
	TranslationServer.set_locale("zh_CN")
	InputDevices.active_device = InputDeviceManager.Device.KEYBOARD_MOUSE
	var frontend: Control = auto_free(load(
		"res://scenes/ui/frontend/frontend_shell.tscn"
	).instantiate())
	add_child(frontend)
	await await_idle_frame()
	var hint := frontend.get_node("DeviceHint") as Label
	assert_object(hint).is_not_null()
	assert_str(hint.text).contains("回车键")
	assert_str(hint.text).contains("退出键")
	assert_str(hint.text).not_contains("Enter")
	assert_str(hint.text).not_contains("Esc")


func _assert_no_english_input_words(panel: SettingsPanel) -> void:
	var leaked_words: Array[String] = [
		"Enter", "Escape", "Space", "Left", "Right", "Mouse", "Trigger", "Button", "Axis",
	]
	for button: Variant in panel.keyboard_binding_buttons.values() + panel.gamepad_binding_buttons.values():
		var rendered := (button as Button).text
		for word: String in leaked_words:
			assert_str(rendered).not_contains(word)
