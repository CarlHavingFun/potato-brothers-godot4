class_name EffectConditionDef
extends Resource


enum Kind {
	ALWAYS,
	EVENT_HAS_TAG,
	SOURCE_HAS_TAG,
	TARGET_HAS_TAG,
	VALUE_AT_LEAST,
	CHANCE,
}

@export var kind: Kind = Kind.ALWAYS
@export var tag: StringName = &""
@export var value_key: StringName = &""
@export var threshold: float = 0.0
@export_range(0.0, 1.0) var chance: float = 1.0
@export var inverted := false


func matches(context: GameplayEventContext, rng: RandomNumberGenerator) -> bool:
	if context == null:
		return false
	var matched := false
	match kind:
		Kind.ALWAYS:
			matched = true
		Kind.EVENT_HAS_TAG:
			matched = tag in context.tags
		Kind.SOURCE_HAS_TAG:
			matched = tag in context.source_tags
		Kind.TARGET_HAS_TAG:
			matched = tag in context.target_tags
		Kind.VALUE_AT_LEAST:
			matched = float(context.values.get(value_key, 0.0)) >= threshold
		Kind.CHANCE:
			matched = rng != null and rng.randf() < clampf(chance, 0.0, 1.0)
	return not matched if inverted else matched


static func event_has_tag(required_tag: StringName) -> EffectConditionDef:
	var result := EffectConditionDef.new()
	result.kind = Kind.EVENT_HAS_TAG
	result.tag = required_tag
	return result


static func source_has_tag(required_tag: StringName) -> EffectConditionDef:
	var result := EffectConditionDef.new()
	result.kind = Kind.SOURCE_HAS_TAG
	result.tag = required_tag
	return result


static func target_has_tag(required_tag: StringName) -> EffectConditionDef:
	var result := EffectConditionDef.new()
	result.kind = Kind.TARGET_HAS_TAG
	result.tag = required_tag
	return result


static func value_at_least(key: StringName, minimum: float) -> EffectConditionDef:
	var result := EffectConditionDef.new()
	result.kind = Kind.VALUE_AT_LEAST
	result.value_key = key
	result.threshold = minimum
	return result


static func roll(probability: float) -> EffectConditionDef:
	var result := EffectConditionDef.new()
	result.kind = Kind.CHANCE
	result.chance = clampf(probability, 0.0, 1.0)
	return result
