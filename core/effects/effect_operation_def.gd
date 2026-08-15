class_name EffectOperationDef
extends Resource


enum Kind {
	ADD_STAT,
	HEAL,
	EXTRA_DAMAGE,
	APPLY_STATUS,
	ADD_PIERCE,
	ADD_BOUNCE,
	EXPLOSION,
	BURN,
	CHAIN,
	SPAWN_PROJECTILE,
	SUMMON,
	BUILD,
	EMIT_EVENT,
}

@export var kind: Kind = Kind.ADD_STAT
@export var stat_id: int = -1
@export var amount: float = 0.0
@export var count: int = 0
@export var radius: float = 0.0
@export var scale: float = 1.0
@export var duration: float = 0.0
@export var content_id: StringName = &""
@export var status_id: StringName = &""
@export var emitted_event_type: int = -1


func apply(context: GameplayEventContext, result: EffectResult) -> void:
	match kind:
		Kind.ADD_STAT:
			if StatId.is_valid(stat_id):
				result.stat_changes[stat_id] = float(result.stat_changes.get(stat_id, 0.0)) + amount
		Kind.HEAL:
			result.healing += maxf(0.0, amount)
		Kind.EXTRA_DAMAGE:
			result.extra_damage += maxf(0.0, amount)
		Kind.APPLY_STATUS, Kind.BURN:
			result.status_commands.append({
				"kind": kind,
				"status_id": String(status_id if not status_id.is_empty() else &"burn"),
				"duration": maxf(0.0, duration),
				"stacks": maxi(1, count),
				"amount": amount,
			})
		Kind.ADD_PIERCE:
			result.pierce += maxi(0, count)
		Kind.ADD_BOUNCE:
			result.bounce += maxi(0, count)
		Kind.EXPLOSION, Kind.CHAIN:
			result.area_commands.append({
				"kind": kind,
				"radius": maxf(0.0, radius),
				"scale": maxf(0.0, scale),
				"targets": maxi(0, count),
			})
		Kind.SPAWN_PROJECTILE:
			result.projectile_commands.append({"content_id": String(content_id), "count": maxi(1, count)})
		Kind.SUMMON:
			result.summon_commands.append({"content_id": String(content_id), "count": maxi(1, count)})
		Kind.BUILD:
			result.building_commands.append({"content_id": String(content_id), "count": maxi(1, count)})
		Kind.EMIT_EVENT:
			if GameplayEvent.is_valid(emitted_event_type):
				result.emitted_events.append(context.child(emitted_event_type))


static func add_stat(target_stat_id: int, value: float) -> EffectOperationDef:
	var result := EffectOperationDef.new()
	result.kind = Kind.ADD_STAT
	result.stat_id = target_stat_id
	result.amount = value
	return result


static func heal(value: float) -> EffectOperationDef:
	var result := EffectOperationDef.new()
	result.kind = Kind.HEAL
	result.amount = value
	return result


static func extra_damage(value: float) -> EffectOperationDef:
	var result := EffectOperationDef.new()
	result.kind = Kind.EXTRA_DAMAGE
	result.amount = value
	return result


static func apply_status(target_status_id: StringName, seconds: float, stacks: int = 1) -> EffectOperationDef:
	var result := EffectOperationDef.new()
	result.kind = Kind.APPLY_STATUS
	result.status_id = target_status_id
	result.duration = seconds
	result.count = stacks
	return result


static func add_pierce(value: int) -> EffectOperationDef:
	var result := EffectOperationDef.new()
	result.kind = Kind.ADD_PIERCE
	result.count = value
	return result


static func add_bounce(value: int) -> EffectOperationDef:
	var result := EffectOperationDef.new()
	result.kind = Kind.ADD_BOUNCE
	result.count = value
	return result


static func explosion(area_radius: float, damage_scale: float) -> EffectOperationDef:
	var result := EffectOperationDef.new()
	result.kind = Kind.EXPLOSION
	result.radius = area_radius
	result.scale = damage_scale
	return result


static func burn(damage_per_tick: float, seconds: float, stacks: int = 1) -> EffectOperationDef:
	var result := EffectOperationDef.new()
	result.kind = Kind.BURN
	result.status_id = &"burn"
	result.amount = damage_per_tick
	result.duration = seconds
	result.count = stacks
	return result


static func chain(target_count: int, chain_radius: float) -> EffectOperationDef:
	var result := EffectOperationDef.new()
	result.kind = Kind.CHAIN
	result.count = target_count
	result.radius = chain_radius
	return result


static func spawn_projectile(projectile_id: StringName, projectile_count: int = 1) -> EffectOperationDef:
	var result := EffectOperationDef.new()
	result.kind = Kind.SPAWN_PROJECTILE
	result.content_id = projectile_id
	result.count = projectile_count
	return result


static func summon(summon_id: StringName, summon_count: int = 1) -> EffectOperationDef:
	var result := EffectOperationDef.new()
	result.kind = Kind.SUMMON
	result.content_id = summon_id
	result.count = summon_count
	return result


static func build(building_id: StringName, building_count: int = 1) -> EffectOperationDef:
	var result := EffectOperationDef.new()
	result.kind = Kind.BUILD
	result.content_id = building_id
	result.count = building_count
	return result


static func emit_event(event_type: int) -> EffectOperationDef:
	var result := EffectOperationDef.new()
	result.kind = Kind.EMIT_EVENT
	result.emitted_event_type = event_type
	return result
