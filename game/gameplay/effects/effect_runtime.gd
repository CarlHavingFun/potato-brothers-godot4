class_name EffectRuntime
extends RefCounted

signal effect_dispatched(event_id: StringName, applied_count: int)

var _subscriptions: Dictionary = {}


func register(definition: GogoEffectDefinition) -> Error:
	if definition == null or definition.event_id.is_empty():
		return ERR_INVALID_PARAMETER
	var entries: Array = _subscriptions.get(definition.event_id, [])
	entries.append(definition)
	entries.sort_custom(func(a: GogoEffectDefinition, b: GogoEffectDefinition) -> bool: return a.stage < b.stage)
	_subscriptions[definition.event_id] = entries
	return OK


func dispatch(event_id: StringName, context: Dictionary) -> int:
	var applied := 0
	for definition: GogoEffectDefinition in _subscriptions.get(event_id, []):
		for operation: Dictionary in definition.operations:
			if _apply(operation, context):
				applied += 1
	effect_dispatched.emit(event_id, applied)
	return applied


func _apply(operation: Dictionary, context: Dictionary) -> bool:
	var target: Dictionary = context.get(operation.get("target", "stats"), {})
	var key := StringName(operation.get("key", ""))
	if key.is_empty() or target.is_empty():
		return false
	match String(operation.get("op", "add")):
		"add": target[key] = float(target.get(key, 0.0)) + float(operation.get("value", 0.0))
		"multiply": target[key] = float(target.get(key, 0.0)) * float(operation.get("value", 1.0))
		"set": target[key] = operation.get("value")
		_: return false
	return true
