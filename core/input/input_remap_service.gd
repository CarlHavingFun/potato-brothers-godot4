class_name InputRemapService
extends RefCounted


const REMAPPABLE_ACTIONS: Array[StringName] = [
	&"move_up", &"move_down", &"move_left", &"move_right", &"dash", &"pause",
]
const GAMEPAD_DEADZONE_ACTIONS: Array[StringName] = [
	&"move_up", &"move_down", &"move_left", &"move_right",
	&"aim_up", &"aim_down", &"aim_left", &"aim_right",
]
const DEFAULT_GAMEPAD_DEADZONE := 0.25


func rebind(action: StringName, event: InputEvent, replace_conflicts: bool = false) -> bool:
	if action not in REMAPPABLE_ACTIONS:
		return false
	_ensure_action(action)
	if not _is_supported_event(event):
		return false
	var normalized := _normalized_copy(event)
	var conflicts := find_conflicts(action, normalized)
	if not conflicts.is_empty() and not replace_conflicts:
		return false
	if replace_conflicts:
		for conflicting_action: StringName in conflicts:
			_erase_matching_event(conflicting_action, normalized)
	_erase_device_bindings(action, normalized)
	InputMap.action_add_event(action, normalized)
	return true


func find_conflicts(action: StringName, event: InputEvent) -> Array[StringName]:
	var result: Array[StringName] = []
	if not _is_supported_event(event):
		return result
	for candidate: StringName in REMAPPABLE_ACTIONS:
		if candidate == action or not InputMap.has_action(candidate):
			continue
		for existing: InputEvent in InputMap.action_get_events(candidate):
			if events_equivalent(existing, event):
				result.append(candidate)
				break
	return result


func events_equivalent(first: InputEvent, second: InputEvent) -> bool:
	if first is InputEventKey and second is InputEventKey:
		var first_key := first as InputEventKey
		var second_key := second as InputEventKey
		return _effective_keycode(first_key) == _effective_keycode(second_key) \
			and first_key.alt_pressed == second_key.alt_pressed \
			and first_key.shift_pressed == second_key.shift_pressed \
			and first_key.ctrl_pressed == second_key.ctrl_pressed \
			and first_key.meta_pressed == second_key.meta_pressed
	if first is InputEventJoypadButton and second is InputEventJoypadButton:
		return (
			(first as InputEventJoypadButton).button_index
			== (second as InputEventJoypadButton).button_index
		)
	if first is InputEventJoypadMotion and second is InputEventJoypadMotion:
		var first_motion := first as InputEventJoypadMotion
		var second_motion := second as InputEventJoypadMotion
		return first_motion.axis == second_motion.axis \
			and signf(first_motion.axis_value) == signf(second_motion.axis_value)
	if first is InputEventMouseButton and second is InputEventMouseButton:
		var first_mouse := first as InputEventMouseButton
		var second_mouse := second as InputEventMouseButton
		return first_mouse.button_index == second_mouse.button_index \
			and first_mouse.alt_pressed == second_mouse.alt_pressed \
			and first_mouse.shift_pressed == second_mouse.shift_pressed \
			and first_mouse.ctrl_pressed == second_mouse.ctrl_pressed \
			and first_mouse.meta_pressed == second_mouse.meta_pressed
	return false


func serialize_actions(actions: Array[StringName] = REMAPPABLE_ACTIONS) -> Dictionary:
	var result := {}
	for action: StringName in actions:
		if not InputMap.has_action(action):
			continue
		var serialized: Array[Dictionary] = []
		for event: InputEvent in InputMap.action_get_events(action):
			var data := event_to_data(event)
			if not data.is_empty():
				serialized.append(data)
		result[String(action)] = serialized
	return result


func apply_actions(bindings: Dictionary) -> void:
	for raw_action: Variant in bindings:
		var action := StringName(str(raw_action))
		if action not in REMAPPABLE_ACTIONS:
			continue
		_ensure_action(action)
		var raw_value: Variant = bindings[raw_action]
		var events := events_from_data(raw_value if raw_value is Array else [])
		if events.is_empty():
			continue
		InputMap.action_erase_events(action)
		for event: InputEvent in events:
			InputMap.action_add_event(action, event)


func restore_defaults(actions: Array[StringName] = REMAPPABLE_ACTIONS) -> void:
	var defaults := default_bindings()
	for action: StringName in actions:
		if action not in REMAPPABLE_ACTIONS:
			continue
		_ensure_action(action)
		InputMap.action_erase_events(action)
		var raw_events: Variant = defaults.get(String(action), [])
		for event: InputEvent in events_from_data(raw_events if raw_events is Array else []):
			InputMap.action_add_event(action, event)
	set_gamepad_deadzone(DEFAULT_GAMEPAD_DEADZONE)


func default_bindings() -> Dictionary:
	return {
		"move_up": [_key_data(KEY_W), _axis_data(JOY_AXIS_LEFT_Y, -1.0)],
		"move_down": [_key_data(KEY_S), _axis_data(JOY_AXIS_LEFT_Y, 1.0)],
		"move_left": [_key_data(KEY_A), _axis_data(JOY_AXIS_LEFT_X, -1.0)],
		"move_right": [_key_data(KEY_D), _axis_data(JOY_AXIS_LEFT_X, 1.0)],
		"dash": [_key_data(KEY_SPACE), _button_data(JOY_BUTTON_X)],
		"pause": [_key_data(KEY_ESCAPE), _button_data(JOY_BUTTON_START)],
	}


func set_gamepad_deadzone(value: float) -> void:
	var sanitized := clampf(value, 0.05, 0.95)
	for action: StringName in GAMEPAD_DEADZONE_ACTIONS:
		if InputMap.has_action(action):
			InputMap.action_set_deadzone(action, sanitized)


func gamepad_deadzone() -> float:
	for action: StringName in GAMEPAD_DEADZONE_ACTIONS:
		if InputMap.has_action(action):
			return InputMap.action_get_deadzone(action)
	return DEFAULT_GAMEPAD_DEADZONE


func binding_text(action: StringName, gamepad: bool) -> String:
	return InputPromptFormatter.format_binding_tokens(binding_tokens(action, gamepad))


func binding_tokens(action: StringName, gamepad: bool) -> Array[Dictionary]:
	if not InputMap.has_action(action):
		return []
	var result: Array[Dictionary] = []
	for event: InputEvent in InputMap.action_get_events(action):
		if gamepad != (event is InputEventJoypadButton or event is InputEventJoypadMotion):
			continue
		result.append(event_token(event))
	return result


static func event_token(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		return key_token(event as InputEventKey)
	if event is InputEventJoypadButton:
		return joy_button_token((event as InputEventJoypadButton).button_index)
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		return joy_axis_token(motion.axis, motion.axis_value)
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		var token := mouse_button_token(mouse.button_index)
		token["modifier_ids"] = _modifier_ids(mouse)
		return token
	return {"text_id": &"input.unknown", "args": [], "modifier_ids": []}


static func key_token(event: InputEventKey) -> Dictionary:
	var keycode := event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
	var text_id := &"input.key.code"
	var args: Array = [int(keycode)]
	match keycode:
		KEY_ENTER:
			text_id = &"input.key.enter"
			args = []
		KEY_KP_ENTER:
			text_id = &"input.key.keypad_enter"
			args = []
		KEY_ESCAPE:
			text_id = &"input.key.escape"
			args = []
		KEY_SPACE:
			text_id = &"input.key.space"
			args = []
		KEY_TAB:
			text_id = &"input.key.tab"
			args = []
		KEY_BACKSPACE:
			text_id = &"input.key.backspace"
			args = []
		KEY_DELETE:
			text_id = &"input.key.delete"
			args = []
		KEY_INSERT:
			text_id = &"input.key.insert"
			args = []
		KEY_HOME:
			text_id = &"input.key.home"
			args = []
		KEY_END:
			text_id = &"input.key.end"
			args = []
		KEY_PAGEUP:
			text_id = &"input.key.page_up"
			args = []
		KEY_PAGEDOWN:
			text_id = &"input.key.page_down"
			args = []
		KEY_LEFT:
			text_id = &"input.key.left"
			args = []
		KEY_RIGHT:
			text_id = &"input.key.right"
			args = []
		KEY_UP:
			text_id = &"input.key.up"
			args = []
		KEY_DOWN:
			text_id = &"input.key.down"
			args = []
		KEY_SHIFT:
			text_id = &"input.key.shift"
			args = []
		KEY_CTRL:
			text_id = &"input.key.control"
			args = []
		KEY_ALT:
			text_id = &"input.key.alt"
			args = []
		KEY_META:
			text_id = &"input.key.meta"
			args = []
		_:
			var code := int(keycode)
			if code >= int(KEY_F1) and code <= int(KEY_F35):
				text_id = &"input.key.function"
				args = [code - int(KEY_F1) + 1]
			elif code >= 33 and code <= 126:
				text_id = &"input.key.glyph"
				args = [String.chr(code)]
	return {
		"text_id": text_id,
		"args": args,
		"modifier_ids": _modifier_ids(event, keycode),
	}


static func joy_button_token(button: JoyButton) -> Dictionary:
	var text_id := &"input.button.numbered"
	var args: Array = [int(button) + 1]
	match button:
		JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y:
			text_id = &"input.button.face"
			var face_glyphs: Array[String] = ["A", "B", "X", "Y"]
			args = [face_glyphs[int(button)]]
		JOY_BUTTON_BACK:
			text_id = &"input.button.back"
			args = []
		JOY_BUTTON_GUIDE:
			text_id = &"input.button.guide"
			args = []
		JOY_BUTTON_START:
			text_id = &"input.button.start"
			args = []
		JOY_BUTTON_LEFT_STICK:
			text_id = &"input.button.left_stick"
			args = []
		JOY_BUTTON_RIGHT_STICK:
			text_id = &"input.button.right_stick"
			args = []
		JOY_BUTTON_LEFT_SHOULDER:
			text_id = &"input.button.left_shoulder"
			args = []
		JOY_BUTTON_RIGHT_SHOULDER:
			text_id = &"input.button.right_shoulder"
			args = []
		JOY_BUTTON_DPAD_UP:
			text_id = &"input.button.dpad_up"
			args = []
		JOY_BUTTON_DPAD_DOWN:
			text_id = &"input.button.dpad_down"
			args = []
		JOY_BUTTON_DPAD_LEFT:
			text_id = &"input.button.dpad_left"
			args = []
		JOY_BUTTON_DPAD_RIGHT:
			text_id = &"input.button.dpad_right"
			args = []
	return {"text_id": text_id, "args": args, "modifier_ids": []}


static func joy_axis_token(axis: JoyAxis, value: float) -> Dictionary:
	var axis_ids: Array[StringName] = [
		&"input.axis.left_x", &"input.axis.left_y",
		&"input.axis.right_x", &"input.axis.right_y",
		&"input.axis.trigger_left", &"input.axis.trigger_right",
	]
	var axis_id := (
		axis_ids[int(axis)]
		if int(axis) >= 0 and int(axis) < axis_ids.size()
		else &"input.axis.numbered"
	)
	return {
		"text_id": &"input.axis.binding",
		"args": [int(axis) + 1] if axis_id == &"input.axis.numbered" else [],
		"axis_id": axis_id,
		"direction_id": &"input.axis.negative" if value < 0.0 else &"input.axis.positive",
		"modifier_ids": [],
	}


static func mouse_button_token(button: MouseButton) -> Dictionary:
	var text_id := &"input.mouse.numbered"
	var args: Array = [int(button)]
	match button:
		MOUSE_BUTTON_LEFT:
			text_id = &"input.mouse.left"
			args = []
		MOUSE_BUTTON_RIGHT:
			text_id = &"input.mouse.right"
			args = []
		MOUSE_BUTTON_MIDDLE:
			text_id = &"input.mouse.middle"
			args = []
		MOUSE_BUTTON_WHEEL_UP:
			text_id = &"input.mouse.wheel_up"
			args = []
		MOUSE_BUTTON_WHEEL_DOWN:
			text_id = &"input.mouse.wheel_down"
			args = []
		MOUSE_BUTTON_WHEEL_LEFT:
			text_id = &"input.mouse.wheel_left"
			args = []
		MOUSE_BUTTON_WHEEL_RIGHT:
			text_id = &"input.mouse.wheel_right"
			args = []
		MOUSE_BUTTON_XBUTTON1:
			text_id = &"input.mouse.extra_1"
			args = []
		MOUSE_BUTTON_XBUTTON2:
			text_id = &"input.mouse.extra_2"
			args = []
	return {"text_id": text_id, "args": args, "modifier_ids": []}


static func _modifier_ids(
	event: InputEventWithModifiers,
	keycode: Key = KEY_NONE
) -> Array[StringName]:
	var result: Array[StringName] = []
	if event.ctrl_pressed and keycode != KEY_CTRL:
		result.append(&"input.key.control")
	if event.alt_pressed and keycode != KEY_ALT:
		result.append(&"input.key.alt")
	if event.shift_pressed and keycode != KEY_SHIFT:
		result.append(&"input.key.shift")
	if event.meta_pressed and keycode != KEY_META:
		result.append(&"input.key.meta")
	return result


func event_to_data(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		var key := event as InputEventKey
		return {
			"type": "key",
			"physical_keycode": key.physical_keycode,
			"keycode": key.keycode,
			"alt": key.alt_pressed,
			"shift": key.shift_pressed,
			"ctrl": key.ctrl_pressed,
			"meta": key.meta_pressed,
		}
	if event is InputEventJoypadButton:
		return {"type": "joy_button", "button_index": (event as InputEventJoypadButton).button_index}
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		return {"type": "joy_axis", "axis": motion.axis, "axis_value": motion.axis_value}
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		return {
			"type": "mouse_button",
			"button_index": mouse.button_index,
			"alt": mouse.alt_pressed,
			"shift": mouse.shift_pressed,
			"ctrl": mouse.ctrl_pressed,
			"meta": mouse.meta_pressed,
		}
	return {}


func events_from_data(raw_events: Array) -> Array[InputEvent]:
	var result: Array[InputEvent] = []
	for raw_event: Variant in raw_events:
		if not raw_event is Dictionary:
			continue
		var data := raw_event as Dictionary
		match str(data.get("type", "")):
			"key":
				var key := InputEventKey.new()
				key.physical_keycode = int(data.get("physical_keycode", 0)) as Key
				key.keycode = int(data.get("keycode", 0)) as Key
				key.alt_pressed = bool(data.get("alt", false))
				key.shift_pressed = bool(data.get("shift", false))
				key.ctrl_pressed = bool(data.get("ctrl", false))
				key.meta_pressed = bool(data.get("meta", false))
				result.append(key)
			"joy_button":
				var button := InputEventJoypadButton.new()
				button.button_index = int(data.get("button_index", 0)) as JoyButton
				result.append(button)
			"joy_axis":
				var motion := InputEventJoypadMotion.new()
				motion.axis = int(data.get("axis", 0)) as JoyAxis
				motion.axis_value = clampf(float(data.get("axis_value", 0.0)), -1.0, 1.0)
				result.append(motion)
			"mouse_button":
				var mouse := InputEventMouseButton.new()
				mouse.button_index = int(data.get("button_index", MOUSE_BUTTON_LEFT)) as MouseButton
				mouse.alt_pressed = bool(data.get("alt", false))
				mouse.shift_pressed = bool(data.get("shift", false))
				mouse.ctrl_pressed = bool(data.get("ctrl", false))
				mouse.meta_pressed = bool(data.get("meta", false))
				result.append(mouse)
	return result


func _erase_device_bindings(action: StringName, replacement: InputEvent) -> void:
	var replacing_gamepad := replacement is InputEventJoypadButton or replacement is InputEventJoypadMotion
	for existing: InputEvent in InputMap.action_get_events(action):
		var existing_gamepad := existing is InputEventJoypadButton or existing is InputEventJoypadMotion
		if replacing_gamepad == existing_gamepad:
			InputMap.action_erase_event(action, existing)


func _erase_matching_event(action: StringName, event: InputEvent) -> void:
	for existing: InputEvent in InputMap.action_get_events(action):
		if events_equivalent(existing, event):
			InputMap.action_erase_event(action, existing)


func _ensure_action(action: StringName) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, DEFAULT_GAMEPAD_DEADZONE)


func _normalized_copy(event: InputEvent) -> InputEvent:
	var copy := event.duplicate(true) as InputEvent
	if copy is InputEventKey:
		(copy as InputEventKey).pressed = false
		(copy as InputEventKey).echo = false
	elif copy is InputEventJoypadButton:
		(copy as InputEventJoypadButton).pressed = false
	elif copy is InputEventJoypadMotion:
		var motion := copy as InputEventJoypadMotion
		motion.axis_value = -1.0 if motion.axis_value < 0.0 else 1.0
	elif copy is InputEventMouseButton:
		(copy as InputEventMouseButton).pressed = false
	return copy


func _is_supported_event(event: InputEvent) -> bool:
	return (
		event is InputEventKey
		or event is InputEventMouseButton
		or event is InputEventJoypadButton
		or event is InputEventJoypadMotion
	)


func _effective_keycode(event: InputEventKey) -> Key:
	return event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode


func _key_data(keycode: Key) -> Dictionary:
	return {"type": "key", "physical_keycode": keycode, "keycode": 0}


func _button_data(button_index: JoyButton) -> Dictionary:
	return {"type": "joy_button", "button_index": button_index}


func _axis_data(axis: JoyAxis, value: float) -> Dictionary:
	return {"type": "joy_axis", "axis": axis, "axis_value": value}
