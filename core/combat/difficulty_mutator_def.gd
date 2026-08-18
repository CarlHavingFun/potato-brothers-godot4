class_name DifficultyMutatorDef
extends Resource


@export_range(1, 5, 1) var level := 1
@export var mutator_id: StringName
@export var mixed_enemy_groups := false
@export var specialist_weight := 0.0
@export var hazards_enabled := false
@export var hazard_interval_multiplier := 1.0
@export var hazard_radius_multiplier := 1.0
@export var economy_pressure := 0.0
@export var elite_frenzy := false
@export var boss_extra_phase := false
@export var randomized_encounters := false
@export_range(0, 4, 1) var horde_event_count := 0
@export var double_final_boss := false


func pressure_score() -> float:
	return (
		float(level)
		+ specialist_weight
		+ (0.4 if mixed_enemy_groups else 0.0)
		+ (0.8 if hazards_enabled else 0.0)
		+ economy_pressure
		+ (1.0 if elite_frenzy else 0.0)
		+ (1.2 if boss_extra_phase else 0.0)
		+ float(horde_event_count) * 0.25
		+ (0.8 if double_final_boss else 0.0)
	)
