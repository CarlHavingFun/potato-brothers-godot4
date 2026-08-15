class_name GameplayEffectRuntime
extends RefCounted


var rng := RandomNumberGenerator.new()
var recursion_limit: int = 8
var _effects_by_event: Dictionary = {}
var _effect_ids: Dictionary = {}
var _effect_stack_counts: Dictionary = {}
var _next_root_id: int = 1


func _init(seed_value: int = 0, root_recursion_limit: int = 8) -> void:
	rng.seed = seed_value ^ 0x45464658
	recursion_limit = maxi(0, root_recursion_limit)


func register_effect(effect: EffectDef) -> bool:
	if effect == null or effect.effect_id.is_empty():
		return false
	if effect.trigger_events.is_empty():
		return false
	for event_type: int in effect.trigger_events:
		if not GameplayEvent.is_valid(event_type):
			return false
	if _effect_ids.has(effect.effect_id):
		var current_count := int(_effect_stack_counts.get(effect.effect_id, 1))
		var maximum_count := maxi(1, (effect as EffectDef).max_stacks)
		if current_count >= maximum_count:
			return false
		_effect_stack_counts[effect.effect_id] = current_count + 1
		return true
	_effect_ids[effect.effect_id] = effect
	_effect_stack_counts[effect.effect_id] = 1
	for event_type: int in effect.trigger_events:
		var bucket: Array = _effects_by_event.get(event_type, [])
		bucket.append(effect)
		bucket.sort_custom(_effect_before)
		_effects_by_event[event_type] = bucket
	return true


func register_effects(effects: Array[EffectDef], stack_count: int = 1) -> int:
	var registered := 0
	for effect: EffectDef in effects:
		for _stack_index in maxi(0, stack_count):
			if register_effect(effect):
				registered += 1
	return registered


func dispatch(context: GameplayEventContext) -> EffectResult:
	var result := EffectResult.new()
	if context == null or not GameplayEvent.is_valid(context.event_type):
		return result
	if context.root_event_id <= 0:
		context.root_event_id = _next_root_id
		_next_root_id += 1
	var queue: Array[GameplayEventContext] = [context]
	var stacks: Dictionary = {}
	while not queue.is_empty():
		var current := queue.pop_front() as GameplayEventContext
		if current.recursion_depth > recursion_limit:
			result.recursion_blocked = true
			continue
		result.processed_event_count += 1
		var effects: Array = _effects_by_event.get(current.event_type, [])
		for effect: EffectDef in effects:
			var registered_stacks := int(_effect_stack_counts.get(effect.effect_id, 1))
			for _copy_index in registered_stacks:
				var stack_count := int(stacks.get(effect.effect_id, 0))
				if stack_count >= effect.max_stacks:
					break
				if not effect.matches(current, rng):
					continue
				stacks[effect.effect_id] = stack_count + 1
				result.applied_effect_ids.append(effect.effect_id)
				var emitted_before := result.emitted_events.size()
				for operation: EffectOperationDef in effect.operations:
					if operation != null:
						operation.apply(current, result)
				for index in range(emitted_before, result.emitted_events.size()):
					var child := result.emitted_events[index]
					if child.recursion_depth > recursion_limit:
						result.recursion_blocked = true
					else:
						queue.append(child)
	return result


func _effect_before(first: EffectDef, second: EffectDef) -> bool:
	if first.priority != second.priority:
		return first.priority < second.priority
	return String(first.effect_id) < String(second.effect_id)
