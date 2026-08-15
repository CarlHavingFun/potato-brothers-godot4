extends Node
class_name InputDeviceManager

signal device_changed(device: int)
signal controller_disconnected(device_id: int)

enum Device { KEYBOARD_MOUSE, GAMEPAD }

var active_device: int = Device.KEYBOARD_MOUSE


func _ready() -> void:
	Input.joy_connection_changed.connect(on_joy_connection_changed)


func _input(event: InputEvent) -> void:
	observe_event(event)


func observe_event(event: InputEvent) -> void:
	if event == null:
		return
	var next_device := active_device
	if event is InputEventJoypadButton:
		next_device = Device.GAMEPAD
	elif event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.35:
		next_device = Device.GAMEPAD
	elif event is InputEventKey or event is InputEventMouseButton:
		next_device = Device.KEYBOARD_MOUSE
	elif event is InputEventMouseMotion and (event as InputEventMouseMotion).relative.length_squared() > 4.0:
		next_device = Device.KEYBOARD_MOUSE
	_set_active_device(next_device)


func on_joy_connection_changed(device_id: int, connected: bool) -> void:
	if connected:
		return
	if active_device == Device.GAMEPAD:
		_set_active_device(Device.KEYBOARD_MOUSE)
	controller_disconnected.emit(device_id)


func confirm_prompt() -> String:
	return "A" if active_device == Device.GAMEPAD else "Enter"


func back_prompt() -> String:
	return "B" if active_device == Device.GAMEPAD else "Esc"


func dash_prompt() -> String:
	return "X" if active_device == Device.GAMEPAD else "Space"


func _set_active_device(value: int) -> void:
	if active_device == value:
		return
	active_device = value
	device_changed.emit(active_device)
