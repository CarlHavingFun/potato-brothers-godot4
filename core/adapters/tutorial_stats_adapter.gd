class_name TutorialStatsAdapter
extends RefCounted


const UNIT_PROPERTY_TO_STAT_ID := {
	"health": StatId.MAX_HEALTH,
	"hp_regen": StatId.RECOVERY,
	"life_steal": StatId.LIFE_STEAL,
	"damage": StatId.DAMAGE,
	"block_chance": StatId.DODGE,
	"move_speed_percent": StatId.MOVE_SPEED,
	"luck": StatId.LUCK,
	"harvesting": StatId.HARVESTING,
}

const LEGACY_PROPERTY_ALIASES := {
	"speed": StatId.MOVE_SPEED,
}


static func to_player_stats(source: UnitStats) -> PlayerStats:
	var result := PlayerStats.new()
	if source == null:
		return result
	for property_name: String in UNIT_PROPERTY_TO_STAT_ID:
		result.set_stat(UNIT_PROPERTY_TO_STAT_ID[property_name], float(source.get(property_name)))
	return result


static func apply_to_unit_stats(source: PlayerStats, target: UnitStats) -> bool:
	if source == null or target == null:
		return false
	for property_name: String in UNIT_PROPERTY_TO_STAT_ID:
		apply_stat_to_unit(source, target, UNIT_PROPERTY_TO_STAT_ID[property_name])
	return true


static func stat_id_for_property(property_name: String) -> int:
	return int(UNIT_PROPERTY_TO_STAT_ID.get(
		property_name,
		LEGACY_PROPERTY_ALIASES.get(property_name, -1)
	))


static func apply_stat_to_unit(source: PlayerStats, target: UnitStats, stat_id: int) -> bool:
	if source == null or target == null or not StatId.is_valid(stat_id):
		return false
	var property_name := property_for_stat_id(stat_id)
	if property_name.is_empty():
		return false
	var value := source.get_stat(stat_id)
	match property_name:
		"health":
			target.health = roundi(value)
		"move_speed_percent":
			target.move_speed_percent = value
			target.speed = roundi(StatCalculator.new().movement_speed(value))
		_:
			target.set(property_name, value)
	return true


static func property_for_stat_id(stat_id: int) -> String:
	for property_name: String in UNIT_PROPERTY_TO_STAT_ID:
		if int(UNIT_PROPERTY_TO_STAT_ID[property_name]) == stat_id:
			return property_name
	return ""
