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
	if not InputMap.has_action(action):
		return ""
	var parts: Array[String] = []
	for event: InputEvent in InputMap.action_get_events(action):
		if gamepad != (event is InputEventJoypadButton or event is InputEventJoypadMotion):
			continue
		parts.append(_event_text(event))
	return " / ".join(parts)


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
	return copy


func _is_supported_event(event: InputEvent) -> bool:
	return event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion


func _effective_keycode(event: InputEventKey) -> Key:
	return event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode


func _event_text(event: InputEvent) -> String:
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		var axis_names: Array[String] = ["Left X", "Left Y", "Right X", "Right Y", "Trigger L", "Trigger R"]
		var axis_name: String = axis_names[motion.axis] if motion.axis >= 0 and motion.axis < axis_names.size() else "Axis %d" % motion.axis
		return "%s %s" % [axis_name, "-" if motion.axis_value < 0.0 else "+"]
	return event.as_text()


func _key_data(keycode: Key) -> Dictionary:
	return {"type": "key", "physical_keycode": keycode, "keycode": 0}


func _button_data(button_index: JoyButton) -> Dictionary:
	return {"type": "joy_button", "button_index": button_index}


func _axis_data(axis: JoyAxis, value: float) -> Dictionary:
	return {"type": "joy_axis", "axis": axis, "axis_value": value}
