class_name StatRulesDef
extends Resource


const CURRENT_VERSION := "baseline_parity_1_1_15_4"

@export var rules_version := CURRENT_VERSION
@export var minimum_final_damage := 1.0
@export var armor_half_damage_point := 15.0
@export_range(0.0, 1.0, 0.01) var maximum_dodge_chance := 0.60
@export var base_move_speed := 450.0
@export var minimum_move_speed_multiplier := 0.0
@export var maximum_attacks_per_second := 12.0
@export var regeneration_first_point_per_second := 0.20
@export var regeneration_additional_point_per_second := 0.089
@export var regeneration_tick_seconds := 3.0
@export var life_steal_heal_amount := 1.0
@export var life_steal_minimum_interval_seconds := 0.10
@export_range(0.0, 1.0, 0.01) var harvesting_growth_rate := 0.05


static func baseline() -> StatRulesDef:
	return StatRulesDef.new()
