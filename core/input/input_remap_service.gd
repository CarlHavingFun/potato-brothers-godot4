class_name InputRemapService
extends RefCounted

const REMAPPABLE_ACTIONS: Array[StringName] = [
	&"move_up", &"move_down", &"move_left", &"move_right", &"dash",
]


func rebind(action: StringName, event: InputEvent) -> bool:
	if action not in REMAPPABLE_ACTIONS or not InputMap.has_action(action):
		return false
	if not event is InputEventKey and not event is InputEventJoypadButton:
		return false
	for existing: InputEvent in InputMap.action_get_events(action):
		if (
			(existing is InputEventKey and event is InputEventKey)
			or (existing is InputEventJoypadButton and event is InputEventJoypadButton)
		):
			InputMap.action_erase_event(action, existing)
	var copy := event.duplicate(true) as InputEvent
	if copy is InputEventKey:
		(copy as InputEventKey).pressed = false
	elif copy is InputEventJoypadButton:
		(copy as InputEventJoypadButton).pressed = false
	InputMap.action_add_event(action, copy)
	return true


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
		if action not in REMAPPABLE_ACTIONS or not InputMap.has_action(action):
			continue
		var events := events_from_data(bindings[raw_action] if bindings[raw_action] is Array else [])
		if events.is_empty():
			continue
		InputMap.action_erase_events(action)
		for event: InputEvent in events:
			InputMap.action_add_event(action, event)


func event_to_data(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		var key := event as InputEventKey
		return {
			"type": "key",
			"physical_keycode": key.physical_keycode,
			"keycode": key.keycode,
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
