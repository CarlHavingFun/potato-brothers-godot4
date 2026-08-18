class_name DifficultyDef
extends Resource


const _DEFAULT_MULTIPLIERS: Dictionary = {
	1: [1.00, 1.00, 1.00, 1.00, 1.00, 1.00, 1.00, []],
	2: [1.10, 1.05, 1.00, 1.10, 1.08, 1.06, 0.95, [&"mixed_waves"]],
	3: [1.25, 1.15, 1.03, 1.20, 1.18, 1.12, 0.90, [&"mixed_waves", &"extra_specialists"]],
	4: [1.45, 1.25, 1.06, 1.30, 1.32, 1.22, 0.85, [&"hazard_pressure", &"economy_pressure"]],
	5: [1.70, 1.40, 1.10, 1.40, 1.50, 1.35, 0.80, [&"elite_frenzy", &"economy_pressure", &"boss_enrage"]],
}

@export_range(1, 5, 1) var level: int = 1
@export var health_multiplier: float = 1.0
@export var damage_multiplier: float = 1.0
@export var speed_multiplier: float = 1.0
@export var spawn_density_multiplier: float = 1.0
@export var elite_health_multiplier: float = 1.0
@export var shop_price_multiplier: float = 1.0
@export var material_drop_multiplier: float = 1.0
@export var rule_tags: Array[StringName] = []
@export var mutator: DifficultyMutatorDef


func _init(
	level_value: int = 1,
	health_value: float = 1.0,
	damage_value: float = 1.0,
	speed_value: float = 1.0,
	spawn_density_value: float = 1.0,
	elite_health_value: float = 1.0,
	shop_price_value: float = 1.0,
	material_drop_value: float = 1.0,
	rule_tag_values: Array[StringName] = []
) -> void:
	level = level_value
	health_multiplier = health_value
	damage_multiplier = damage_value
	speed_multiplier = speed_value
	spawn_density_multiplier = spawn_density_value
	elite_health_multiplier = elite_health_value
	shop_price_multiplier = shop_price_value
	material_drop_multiplier = material_drop_value
	rule_tags = rule_tag_values.duplicate()
	mutator = _mutator_for_level(level)


static func for_level(level_value: int) -> DifficultyDef:
	if not _DEFAULT_MULTIPLIERS.has(level_value):
		return null
	var values: Array = _DEFAULT_MULTIPLIERS[level_value]
	var tags: Array[StringName] = []
	tags.assign(values[7])
	return DifficultyDef.new(
		level_value, values[0], values[1], values[2], values[3],
		values[4], values[5], values[6], tags
	)


func scale_health(base_health: int) -> int:
	return roundi(base_health * health_multiplier)


func scale_damage(base_damage: float) -> float:
	return base_damage * damage_multiplier


func scale_speed(base_speed: float) -> float:
	return base_speed * speed_multiplier


func scale_spawn_count(base_count: int) -> int:
	return roundi(base_count * spawn_density_multiplier)


func scale_elite_health(base_health: int) -> int:
	return roundi(scale_health(base_health) * elite_health_multiplier)


func scale_shop_price(base_price: int) -> int:
	return maxi(1, ceili(base_price * shop_price_multiplier))


func scale_material_drop(base_drop: int) -> int:
	return maxi(1, floori(base_drop * material_drop_multiplier))


func final_boss_count() -> int:
	# Level is authoritative so content packs created before the new mutator
	# fields still receive the difficulty-five encounter rule.
	return 2 if level >= 5 else 1


func uses_randomized_encounters() -> bool:
	return level >= 2 or (mutator != null and mutator.randomized_encounters)


func horde_events_per_run() -> int:
	if mutator != null and mutator.horde_event_count > 0:
		return mutator.horde_event_count
	match level:
		2:
			return 1
		3:
			return 2
		4, 5:
			return 3
	return 0


static func _mutator_for_level(difficulty_level: int) -> DifficultyMutatorDef:
	var result := DifficultyMutatorDef.new()
	result.level = clampi(difficulty_level, 1, 5)
	result.mutator_id = StringName("difficulty/%d" % result.level)
	result.mixed_enemy_groups = result.level >= 2
	result.specialist_weight = maxf(0.0, float(result.level - 1) * 0.18)
	result.hazards_enabled = result.level >= 4
	result.hazard_interval_multiplier = 0.82 if result.level >= 4 else 1.0
	result.hazard_radius_multiplier = 1.15 if result.level >= 4 else 1.0
	result.economy_pressure = maxf(0.0, float(result.level - 2) * 0.12)
	result.elite_frenzy = result.level >= 5
	result.boss_extra_phase = result.level >= 5
	result.randomized_encounters = result.level >= 2
	result.horde_event_count = [0, 0, 1, 2, 3, 3][result.level]
	result.double_final_boss = result.level >= 5
	return result
