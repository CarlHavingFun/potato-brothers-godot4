class_name EffectDef
extends Resource


@export var effect_id: StringName = &""
@export var priority: int = 0
@export_range(1, 99, 1) var max_stacks: int = 99
@export var trigger_events: Array[int] = []
@export var conditions: Array[EffectConditionDef] = []
@export var operations: Array[EffectOperationDef] = []
@export var tags: Array[StringName] = []


func triggers(event_type: int) -> bool:
	return event_type in trigger_events


func matches(context: GameplayEventContext, rng: RandomNumberGenerator) -> bool:
	if context == null or not triggers(context.event_type):
		return false
	for condition: EffectConditionDef in conditions:
		if condition == null or not condition.matches(context, rng):
			return false
	return true
