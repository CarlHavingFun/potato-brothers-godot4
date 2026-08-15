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
