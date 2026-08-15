class_name GameplayEventContext
extends RefCounted


var event_type: int = GameplayEvent.Type.RUN_STARTED
var root_event_id: int = 0
var recursion_depth: int = 0
var source: Object
var target: Object
var actor_id: StringName = &""
var weapon_id: StringName = &""
var tags: Array[StringName] = []
var source_tags: Array[StringName] = []
var target_tags: Array[StringName] = []
var values: Dictionary = {}


func _init(type_value: int = GameplayEvent.Type.RUN_STARTED, root_id: int = 0, depth: int = 0) -> void:
	event_type = type_value
	root_event_id = root_id
	recursion_depth = depth


func child(next_type: int) -> GameplayEventContext:
	var result := GameplayEventContext.new(next_type, root_event_id, recursion_depth + 1)
	result.source = source
	result.target = target
	result.actor_id = actor_id
	result.weapon_id = weapon_id
	result.tags = tags.duplicate()
	result.source_tags = source_tags.duplicate()
	result.target_tags = target_tags.duplicate()
	result.values = values.duplicate(true)
	return result
