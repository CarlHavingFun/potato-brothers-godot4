class_name CharacterRuleDef
extends Resource


@export var rule_id: StringName
@export var core_ability_id: StringName
@export var allowed_weapon_tags: Array[StringName] = []
@export var forbidden_weapon_tags: Array[StringName] = []
@export var shop_bias_tags: Array[StringName] = []
@export var starting_stat_modifiers: Dictionary = {}
@export var stat_conversions: Dictionary = {}
@export var stat_modification_multipliers: Dictionary = {}
@export var starting_material_bonus := 0
@export var pickup_healing_multiplier := 1.0
@export var shop_price_multiplier := 1.0
@export var recycle_value_multiplier := 1.0
@export var experience_gain_multiplier := 1.0
@export var dodge_cap_override := -1.0
@export var consumable_healing_bonus := 0.0
@export var materials_reset_on_wave_start := false
@export var semantic_rules: Dictionary = {}
@export var runtime_support: Dictionary = {}
@export_range(1, 6, 1) var weapon_slot_limit := 6
@export_range(1, 3, 1) var dash_charges := 1
@export var dash_cooldown_multiplier := 1.0
@export var dash_duration_multiplier := 1.0
@export var permanent_effects: Array[EffectDef] = []


func allows_weapon(weapon_tags: Array[StringName]) -> bool:
	for tag: StringName in forbidden_weapon_tags:
		if tag in weapon_tags:
			return false
	if allowed_weapon_tags.is_empty():
		return true
	for tag: StringName in allowed_weapon_tags:
		if tag in weapon_tags:
			return true
	return false


func unsupported_runtime_rules() -> Array[StringName]:
	var result: Array[StringName] = []
	for raw_rule_id: Variant in runtime_support:
		if not bool(runtime_support[raw_rule_id]):
			result.append(StringName(str(raw_rule_id)))
	return result


func apply_to_run(run_state: RunState) -> bool:
	if run_state == null or run_state.character_rule_applied:
		return false
	for raw_stat: Variant in starting_stat_modifiers:
		var stat_id := StatId.from_key(str(raw_stat))
		if StatId.is_valid(stat_id):
			run_state.player_stats.add_stat(stat_id, float(starting_stat_modifiers[raw_stat]))
	for raw_source: Variant in stat_conversions:
		var conversion: Variant = stat_conversions[raw_source]
		if not conversion is Dictionary:
			continue
		var source_id := StatId.from_key(str(raw_source))
		var target_id := StatId.from_key(str(conversion.get("target", "")))
		if StatId.is_valid(source_id) and StatId.is_valid(target_id):
			run_state.player_stats.add_stat(
				target_id,
				run_state.player_stats.get_stat(source_id) * float(conversion.get("ratio", 0.0))
			)
	run_state.materials += maxi(0, starting_material_bonus)
	run_state.inventory.weapon_slot_limit = clampi(weapon_slot_limit, 1, InventoryState.MAX_WEAPON_SLOTS)
	run_state.character_rule_id = rule_id
	hydrate_runtime_rules(run_state)
	run_state.character_rule_applied = true
	return true


func hydrate_runtime_rules(run_state: RunState) -> bool:
	if run_state == null:
		return false
	run_state.pickup_healing_multiplier = maxf(0.0, pickup_healing_multiplier)
	run_state.shop_price_multiplier = maxf(0.0, shop_price_multiplier)
	run_state.recycle_value_multiplier = maxf(0.0, recycle_value_multiplier)
	run_state.experience_gain_multiplier = maxf(0.0, experience_gain_multiplier)
	run_state.dodge_cap_override = clampf(dodge_cap_override, -1.0, 100.0)
	run_state.consumable_healing_bonus = consumable_healing_bonus
	run_state.materials_reset_on_wave_start = materials_reset_on_wave_start
	run_state.allowed_weapon_tags = allowed_weapon_tags.duplicate()
	run_state.forbidden_weapon_tags = forbidden_weapon_tags.duplicate()
	run_state.shop_bias_tags = shop_bias_tags.duplicate()
	run_state.dash_charges = maxi(1, dash_charges)
	run_state.dash_cooldown_multiplier = maxf(0.1, dash_cooldown_multiplier)
	run_state.dash_duration_multiplier = maxf(0.1, dash_duration_multiplier)
	return true
