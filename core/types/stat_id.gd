class_name StatId
extends RefCounted


enum {
	MAX_HEALTH,
	RECOVERY,
	LIFE_STEAL,
	DAMAGE,
	MELEE_DAMAGE,
	RANGED_DAMAGE,
	ELEMENTAL_DAMAGE,
	ATTACK_SPEED,
	CRITICAL_CHANCE,
	ENGINEERING,
	RANGE,
	ARMOR,
	DODGE,
	MOVE_SPEED,
	LUCK,
	HARVESTING,
}

const _KEYS: Array[String] = [
	"max_health",
	"recovery",
	"life_steal",
	"damage",
	"melee_damage",
	"ranged_damage",
	"elemental_damage",
	"attack_speed",
	"critical_chance",
	"engineering",
	"range",
	"armor",
	"dodge",
	"move_speed",
	"luck",
	"harvesting",
]


static func size() -> int:
	return _KEYS.size()


static func is_valid(stat_id: int) -> bool:
	return stat_id >= 0 and stat_id < _KEYS.size()


static func key(stat_id: int) -> String:
	if not is_valid(stat_id):
		return ""
	return _KEYS[stat_id]


static func from_key(stat_key: String) -> int:
	return _KEYS.find(stat_key)
