extends GdUnitTestSuite


func test_device_manager_switches_prompts_between_keyboard_and_gamepad() -> void:
	var manager := auto_free(InputDeviceManager.new()) as InputDeviceManager
	add_child(manager)
	manager.observe_event(InputEventKey.new())
	assert_int(manager.active_device).is_equal(InputDeviceManager.Device.KEYBOARD_MOUSE)
	assert_str(manager.confirm_prompt()).is_equal("Enter")

	var gamepad_event := InputEventJoypadButton.new()
	gamepad_event.button_index = JOY_BUTTON_A
	manager.observe_event(gamepad_event)
	assert_int(manager.active_device).is_equal(InputDeviceManager.Device.GAMEPAD)
	assert_str(manager.confirm_prompt()).is_equal("A")


func test_disconnect_falls_back_to_keyboard_without_losing_navigation() -> void:
	var manager := auto_free(InputDeviceManager.new()) as InputDeviceManager
	add_child(manager)
	var gamepad_event := InputEventJoypadButton.new()
	manager.observe_event(gamepad_event)

	manager.on_joy_connection_changed(0, false)

	assert_int(manager.active_device).is_equal(InputDeviceManager.Device.KEYBOARD_MOUSE)


func test_input_remapping_round_trips_keyboard_and_gamepad_bindings() -> void:
	var service := InputRemapService.new()
	var original_events: Array[InputEvent] = []
	for original: InputEvent in InputMap.action_get_events(&"dash"):
		original_events.append(original.duplicate(true) as InputEvent)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_SHIFT
	var button := InputEventJoypadButton.new()
	button.button_index = JOY_BUTTON_RIGHT_SHOULDER

	assert_bool(service.rebind(&"dash", key)).is_true()
	assert_bool(service.rebind(&"dash", button)).is_true()
	var serialized := service.serialize_actions([&"dash"])
	var restored_events := service.events_from_data(serialized.get("dash", []))

	assert_int(restored_events.size()).is_equal(2)
	assert_bool(restored_events.any(func(event: InputEvent): return event is InputEventKey)).is_true()
	assert_bool(restored_events.any(func(event: InputEvent): return event is InputEventJoypadButton)).is_true()
	InputMap.action_erase_events(&"dash")
	for original: InputEvent in original_events:
		InputMap.action_add_event(&"dash", original)


func test_input_remapping_reports_conflicts_and_can_replace_them() -> void:
	var service := InputRemapService.new()
	var original := service.serialize_actions()
	var key := InputEventKey.new()
	key.physical_keycode = KEY_W

	var conflicts := service.find_conflicts(&"dash", key)

	assert_array(conflicts).contains([&"move_up"])
	assert_bool(service.rebind(&"dash", key)).is_false()
	assert_bool(service.rebind(&"dash", key, true)).is_true()
	assert_bool(service.find_conflicts(&"dash", key).is_empty()).is_true()
	var move_up_still_uses_w := false
	for event: InputEvent in InputMap.action_get_events(&"move_up"):
		if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_W:
			move_up_still_uses_w = true
	assert_bool(move_up_still_uses_w).is_false()
	service.apply_actions(original)


func test_input_remapping_supports_axes_defaults_and_transactional_deadzone() -> void:
	var service := InputRemapService.new()
	var original := service.serialize_actions()
	var original_deadzone := service.gamepad_deadzone()
	var axis := InputEventJoypadMotion.new()
	axis.axis = JOY_AXIS_RIGHT_X
	axis.axis_value = -1.0

	assert_bool(service.rebind(&"move_left", axis, true)).is_true()
	var has_axis := false
	for event: InputEvent in InputMap.action_get_events(&"move_left"):
		if event is InputEventJoypadMotion:
			has_axis = true
	assert_bool(has_axis).is_true()
	service.set_gamepad_deadzone(0.55)
	assert_float(service.gamepad_deadzone()).is_equal_approx(0.55, 0.001)
	service.restore_defaults([&"move_left", &"dash", &"pause"])
	assert_bool(InputMap.has_action(&"pause")).is_true()
	var default_dash: Array = service.serialize_actions([&"dash"]).get("dash", [])
	assert_bool(default_dash.any(func(data: Dictionary): return int(data.get("physical_keycode", 0)) == KEY_SPACE)).is_true()
	assert_bool(default_dash.any(func(data: Dictionary): return int(data.get("button_index", -1)) == JOY_BUTTON_X)).is_true()
	var default_pause: Array = service.serialize_actions([&"pause"]).get("pause", [])
	assert_bool(default_pause.any(func(data: Dictionary): return int(data.get("physical_keycode", 0)) == KEY_ESCAPE)).is_true()
	service.apply_actions(original)
	service.set_gamepad_deadzone(original_deadzone)
