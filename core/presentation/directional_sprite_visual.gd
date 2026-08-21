class_name DirectionalSpriteVisual
extends AnimatedSprite2D


signal action_changed(action: StringName)
signal facing_changed(direction: StringName)


const DIRECTIONS: Array[StringName] = [
	&"down",
	&"down_right",
	&"right",
	&"up_right",
	&"up",
	&"up_left",
	&"left",
	&"down_left",
]
const ACTION_PRIORITY: Array[StringName] = [
	&"death", &"victory", &"hit", &"dash", &"walk", &"idle",
]
const TRANSIENT_ACTIONS: Array[StringName] = [&"hit", &"dash"]


@export var default_facing: StringName = &"down"


var last_facing: StringName = &"down"
var current_action: StringName = &"idle"
var _active_actions := {
	&"death": false,
	&"victory": false,
	&"hit": false,
	&"dash": false,
	&"walk": false,
	&"idle": true,
}


func _ready() -> void:
	last_facing = default_facing if default_facing in DIRECTIONS else &"down"
	if not animation_finished.is_connected(_on_animation_finished):
		animation_finished.connect(_on_animation_finished)
	_refresh_animation()


func update_motion(direction: Vector2) -> void:
	if direction.length_squared() > 0.0001:
		set_facing(direction_from_vector(direction))
	set_action_active(&"walk", direction.length_squared() > 0.0001)


func set_facing(direction: StringName) -> bool:
	if direction not in DIRECTIONS:
		return false
	if last_facing == direction:
		return true
	last_facing = direction
	facing_changed.emit(direction)
	_refresh_animation()
	return true


func set_action_active(action: StringName, active: bool) -> bool:
	if action not in ACTION_PRIORITY or action == &"idle":
		return false
	if bool(_active_actions.get(action, false)) == active:
		return true
	_active_actions[action] = active
	_refresh_animation()
	return true


func trigger_action(action: StringName) -> bool:
	if action not in ACTION_PRIORITY or action == &"idle":
		return false
	if not has_action_animation(action):
		return false
	_active_actions[action] = true
	_refresh_animation(true)
	return true


func clear_action(action: StringName) -> bool:
	return set_action_active(action, false)


func set_semantic_state(state: StringName) -> bool:
	match state:
		&"idle":
			return set_action_active(&"walk", false)
		&"move", &"walk":
			return set_action_active(&"walk", true)
		&"dash", &"hit", &"death", &"victory":
			return trigger_action(state)
	return false


func is_facing_right() -> bool:
	return last_facing in [&"right", &"down_right", &"up_right"]


func animation_name_for(action: StringName, direction: StringName = last_facing) -> StringName:
	if sprite_frames == null:
		return &""
	var requested := StringName("%s_%s" % [action, direction])
	if sprite_frames.has_animation(requested):
		return requested
	var down_fallback := StringName("%s_down" % action)
	if sprite_frames.has_animation(down_fallback):
		return down_fallback
	var idle_facing := StringName("idle_%s" % direction)
	if sprite_frames.has_animation(idle_facing):
		return idle_facing
	return &"idle_down" if sprite_frames.has_animation(&"idle_down") else &""


func has_action_animation(action: StringName, direction: StringName = last_facing) -> bool:
	if sprite_frames == null:
		return false
	return (
		sprite_frames.has_animation(StringName("%s_%s" % [action, direction]))
		or sprite_frames.has_animation(StringName("%s_down" % action))
	)


func animation_duration(action: StringName, direction: StringName = last_facing) -> float:
	var animation_name := animation_name_for(action, direction)
	if animation_name.is_empty():
		return 0.0
	var speed := sprite_frames.get_animation_speed(animation_name)
	if speed <= 0.0:
		return 0.0
	var duration := 0.0
	for frame_index in sprite_frames.get_frame_count(animation_name):
		duration += sprite_frames.get_frame_duration(animation_name, frame_index) / speed
	return duration


static func direction_from_vector(direction: Vector2) -> StringName:
	if direction.length_squared() <= 0.0001:
		return &"down"
	var octant: int = wrapi(int(round(direction.angle() / (PI / 4.0))), 0, 8)
	match octant:
		0:
			return &"right"
		1:
			return &"down_right"
		2:
			return &"down"
		3:
			return &"down_left"
		4:
			return &"left"
		5:
			return &"up_left"
		6:
			return &"up"
		_:
			return &"up_right"


func _refresh_animation(restart: bool = false) -> void:
	var next_action := _highest_priority_action()
	var next_animation := animation_name_for(next_action)
	if current_action != next_action:
		current_action = next_action
		action_changed.emit(current_action)
	if next_animation.is_empty():
		stop()
		return
	if restart or animation != next_animation or not is_playing():
		play(next_animation)


func _highest_priority_action() -> StringName:
	for action: StringName in ACTION_PRIORITY:
		if bool(_active_actions.get(action, false)):
			return action
	return &"idle"


func _on_animation_finished() -> void:
	if current_action not in TRANSIENT_ACTIONS:
		return
	_active_actions[current_action] = false
	_refresh_animation()
