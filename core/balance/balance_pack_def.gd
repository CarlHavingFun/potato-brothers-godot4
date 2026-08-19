class_name BalancePackDef
extends Resource


const BASELINE_ID: StringName = &"baseline_parity_1_1_15_4"
const BASELINE_VERSION := "1.1.15.4-baseline.3"

@export var balance_pack_id: StringName = BASELINE_ID
@export var balance_pack_version := BASELINE_VERSION
@export var stat_rules: StatRulesDef
@export var manifest: BalanceParityManifest
@export var wave_durations: Array[float] = [
	20.0, 25.0, 30.0, 35.0, 40.0, 45.0, 50.0, 55.0,
	60.0, 60.0, 60.0, 60.0, 60.0, 60.0, 60.0, 60.0,
	60.0, 60.0, 60.0, 90.0,
]
@export var maximum_active_enemies := 100
@export var material_drop_decay_start_wave := 5
@export var material_drop_decay_per_wave := 0.015
@export var minimum_material_drop_multiplier := 0.50
@export var final_boss_wave := 20
@export var difficulty_five_boss_count := 2
@export var difficulty_five_boss_base_health_multiplier := 0.75
@export var endless_harvesting_growth_cutoff_wave := 20
@export var special_event_wave_windows: Dictionary = {
	2: [Vector2i(11, 12)],
	3: [Vector2i(11, 12)],
	4: [Vector2i(11, 12), Vector2i(14, 15), Vector2i(17, 18)],
	5: [Vector2i(11, 12), Vector2i(14, 15), Vector2i(17, 18)],
}
@export var economy_values: Dictionary = {
	"material_drop_base_multiplier": 1.0,
	"material_drop_decay_start_wave": 5,
	"material_drop_decay_per_wave": 0.015,
	"minimum_material_drop_multiplier": 0.50,
	"harvesting_growth_rate": 0.05,
	"harvesting_grants_experience": true,
	"negative_harvesting_removes_resources": true,
}
@export var character_values: Dictionary = {}
@export var weapon_values: Dictionary = {}
@export var passive_values: Dictionary = {}
@export var upgrade_values: Dictionary = {}
@export var enemy_values: Dictionary = {}
@export var wave_values: Dictionary = {}


func bind_content(pack: ContentPackDef) -> BalancePackDef:
	manifest = BalanceParityManifest.new().bind_content(pack)
	character_values.clear()
	weapon_values.clear()
	passive_values.clear()
	upgrade_values.clear()
	enemy_values.clear()
	wave_values.clear()
	if pack == null:
		return self
	var baseline_character_rules := _baseline_character_rule_contracts()
	for character: CharacterDef in pack.characters:
		if character == null:
			continue
		var balance_id := String(character.get_balance_id(pack.pack_id))
		var captured := _capture_character(character)
		if baseline_character_rules.has(balance_id):
			captured["base_stats"] = _baseline_player_base_stats()
			captured["rule_contract"] = baseline_character_rules[balance_id].duplicate(true)
		character_values[balance_id] = captured
	for weapon: WeaponDef in pack.weapons:
		if weapon != null:
			weapon_values[String(weapon.get_balance_id(pack.pack_id))] = _capture_weapon(weapon)
	for passive: PassiveItemDef in pack.passives:
		if passive != null:
			passive_values[String(passive.get_balance_id(pack.pack_id))] = _capture_passive(passive)
	for upgrade: UpgradeDef in pack.upgrades:
		if upgrade != null:
			upgrade_values[String(upgrade.get_balance_id(pack.pack_id))] = {
				"stat_id": upgrade.stat_id,
				"value": upgrade.value,
				"quality": upgrade.quality,
			}
	for enemy: EnemyDef in pack.enemies:
		if enemy != null:
			enemy_values[String(enemy.get_balance_id(pack.pack_id))] = _capture_enemy(enemy)
	for wave: WaveDef in pack.waves:
		if wave == null:
			continue
		var duration := wave_duration(wave.wave_number, wave.duration)
		wave_values[String(wave.get_balance_id(pack.pack_id))] = {
			"wave_number": wave.wave_number,
			"duration": duration,
			"spawn_density_multiplier": wave.spawn_density_multiplier,
			"priority_spawn_count": wave.priority_spawn_count,
		}
	return self


func apply_to_content(pack: ContentPackDef) -> Error:
	if pack == null:
		return ERR_INVALID_PARAMETER
	for character: CharacterDef in pack.characters:
		if character == null:
			continue
		var character_entry: Variant = character_values.get(
			String(character.get_balance_id(pack.pack_id)), {}
		)
		if character_entry is Dictionary:
			var base_stats: Variant = character_entry.get("base_stats", {})
			if base_stats is Dictionary:
				_apply_character_base_stats(character.stats, base_stats)
			var rule_contract: Variant = character_entry.get("rule_contract", {})
			if rule_contract is Dictionary:
				_apply_character_rule_contract(character.rules, rule_contract)
				if rule_contract.has("starter_weapon_ids"):
					character.starter_weapon_ids = _string_name_array(
						rule_contract.get("starter_weapon_ids", [])
					)
	for weapon: WeaponDef in pack.weapons:
		if weapon == null:
			continue
		var weapon_entry: Variant = weapon_values.get(
			String(weapon.get_balance_id(pack.pack_id)), {}
		)
		if not weapon_entry is Dictionary:
			continue
		var tier_values: Variant = weapon_entry.get("tiers", [])
		if tier_values is Array:
			for tier_index in mini(weapon.tiers.size(), tier_values.size()):
				if tier_values[tier_index] is Dictionary:
					_apply_weapon_tier(weapon.tiers[tier_index], tier_values[tier_index])
					if &"engineering" in weapon.tags and weapon.tiers[tier_index] != null:
						weapon.tiers[tier_index].stats.is_engineering_structure = true
		var pattern_values: Variant = weapon_entry.get("attack_pattern", {})
		if pattern_values is Dictionary:
			_apply_known_properties(weapon.attack_pattern, pattern_values)
	for passive: PassiveItemDef in pack.passives:
		if passive == null:
			continue
		var passive_entry: Variant = passive_values.get(
			String(passive.get_balance_id(pack.pack_id)), {}
		)
		if passive_entry is Dictionary:
			passive.stat_modifiers = passive_entry.get("stat_modifiers", {}).duplicate(true)
			passive.max_stack = maxi(1, int(passive_entry.get("max_stack", passive.max_stack)))
			if passive.item != null:
				passive.item.item_cost = maxi(0, int(passive_entry.get("cost", passive.item.item_cost)))
				passive.item.item_tier = clampi(int(passive_entry.get(
					"quality", passive.item.item_tier
				)), Global.UpgradeTier.COMMON, Global.UpgradeTier.LEGENDARY)
	for enemy: EnemyDef in pack.enemies:
		if enemy == null or enemy.stats == null:
			continue
		var enemy_entry: Variant = enemy_values.get(
			String(enemy.get_balance_id(pack.pack_id)), {}
		)
		if enemy_entry is Dictionary:
			enemy.stats.health = maxi(1, int(enemy_entry.get("health", enemy.stats.health)))
			enemy.stats.health_increase_per_wave = float(enemy_entry.get(
				"health_per_wave", enemy.stats.health_increase_per_wave
			))
			enemy.stats.damage = float(enemy_entry.get("damage", enemy.stats.damage))
			enemy.stats.damage_increase_per_wave = float(enemy_entry.get(
				"damage_per_wave", enemy.stats.damage_increase_per_wave
			))
			enemy.stats.speed = maxi(0, int(enemy_entry.get("speed", enemy.stats.speed)))
			enemy.stats.gold_drop = maxi(0, int(enemy_entry.get(
				"material_drop", enemy.stats.gold_drop
			)))
			var behavior_values: Variant = enemy_entry.get("behavior_values", {})
			if behavior_values is Dictionary:
				_apply_known_properties(enemy.behavior, behavior_values)
	for wave: WaveDef in pack.waves:
		if wave != null:
			wave.duration = wave_duration(wave.wave_number, wave.duration)
			if wave.data != null:
				wave.data.wave_time = wave.duration
	return OK


func merge_weapon_values(overrides: Dictionary) -> void:
	for raw_balance_id: Variant in overrides:
		var value: Variant = overrides[raw_balance_id]
		if value is Array:
			weapon_values[str(raw_balance_id)] = {"tiers": value.duplicate(true)}
		elif value is Dictionary:
			weapon_values[str(raw_balance_id)] = value.duplicate(true)


func merge_weapon_tier_overrides(overrides: Dictionary) -> void:
	# Identity overlays are intentionally partial. They correct only tier fields
	# that changed semantic meaning while preserving the copied reference row's
	# economy and compatible combat values.
	for raw_balance_id: Variant in overrides:
		var balance_id := str(raw_balance_id)
		var tier_overrides: Variant = overrides[raw_balance_id]
		if not tier_overrides is Array:
			continue
		var weapon_entry: Variant = weapon_values.get(balance_id, {})
		if not weapon_entry is Dictionary:
			continue
		var tiers: Variant = weapon_entry.get("tiers", [])
		if not tiers is Array:
			continue
		for tier_index: int in mini(tiers.size(), tier_overrides.size()):
			var base_tier: Variant = tiers[tier_index]
			var identity_tier: Variant = tier_overrides[tier_index]
			if base_tier is Dictionary and identity_tier is Dictionary:
				(base_tier as Dictionary).merge(identity_tier as Dictionary, true)


func merge_passive_values(overrides: Dictionary) -> void:
	for raw_balance_id: Variant in overrides:
		if overrides[raw_balance_id] is Dictionary:
			passive_values[str(raw_balance_id)] = overrides[raw_balance_id].duplicate(true)


func merge_enemy_values(overrides: Dictionary) -> void:
	for raw_balance_id: Variant in overrides:
		if overrides[raw_balance_id] is Dictionary:
			enemy_values[str(raw_balance_id)] = overrides[raw_balance_id].duplicate(true)


func wave_duration(wave_number: int, fallback: float = 60.0) -> float:
	if wave_number >= 1 and wave_number <= wave_durations.size():
		return wave_durations[wave_number - 1]
	return 60.0 if wave_number > final_boss_wave else maxf(0.1, fallback)


func material_drop_multiplier(wave_number: int) -> float:
	if wave_number < material_drop_decay_start_wave:
		return 1.0
	return maxf(
		minimum_material_drop_multiplier,
		1.0 - material_drop_decay_per_wave * float(maxi(0, wave_number))
	)


func event_windows_for_difficulty(difficulty: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var raw_windows: Variant = special_event_wave_windows.get(clampi(difficulty, 1, 5), [])
	if raw_windows is Array:
		for raw_window: Variant in raw_windows:
			if raw_window is Vector2i:
				result.append(raw_window)
	return result


func final_boss_count(difficulty: int) -> int:
	return difficulty_five_boss_count if difficulty >= 5 else 1


func validate_config() -> PackedStringArray:
	var errors := PackedStringArray()
	if balance_pack_id.is_empty():
		errors.append("balance_pack_id is required")
	if balance_pack_version.strip_edges().is_empty():
		errors.append("balance_pack_version is required")
	if stat_rules == null:
		errors.append("stat_rules is required")
	elif stat_rules.rules_version.strip_edges().is_empty():
		errors.append("stat_rules_version is required")
	if wave_durations.size() != BalanceParityManifest.EXPECTED_WAVES:
		errors.append("balance wave durations require exactly 20 values")
	if maximum_active_enemies != 100:
		errors.append("baseline maximum_active_enemies must be 100")
	for required_key: String in [
		"material_drop_base_multiplier",
		"material_drop_decay_start_wave",
		"material_drop_decay_per_wave",
		"minimum_material_drop_multiplier",
		"harvesting_growth_rate",
		"harvesting_grants_experience",
		"negative_harvesting_removes_resources",
	]:
		if not economy_values.has(required_key):
			errors.append("balance economy is missing %s" % required_key)
	return errors


func _capture_character(character: CharacterDef) -> Dictionary:
	var stats := character.stats
	return {
		"base_stats": {
			"max_health": stats.health if stats != null else 0,
			"recovery": stats.hp_regen if stats != null else 0.0,
			"life_steal": stats.life_steal if stats != null else 0.0,
			"damage": stats.damage if stats != null else 0.0,
			"move_speed": stats.move_speed_percent if stats != null else 0.0,
			"dodge": stats.block_chance if stats != null else 0.0,
			"luck": stats.luck if stats != null else 0.0,
			"harvesting": stats.harvesting if stats != null else 0.0,
		},
		"starter_weapon_ids": character.starter_weapon_ids.duplicate(),
		"unlock_difficulty": character.unlock_difficulty,
	}


func _capture_weapon(weapon: WeaponDef) -> Dictionary:
	var tiers: Array[Dictionary] = []
	for item: ItemWeapon in weapon.tiers:
		if item == null or item.stats == null:
			tiers.append({})
			continue
		tiers.append({
			"damage": item.stats.damage,
			"cooldown": item.stats.cooldown,
			"range": item.stats.max_range,
			"critical_chance": item.stats.crit_chance,
			"critical_damage": item.stats.crit_damage,
			"life_steal": item.stats.life_steal,
			"cost": item.item_cost,
			"scaling_coefficients": item.stats.scaling_coefficients.duplicate(true),
			"engineering_structure": item.stats.is_engineering_structure,
		})
	return {
		"tiers": tiers,
		"tags": weapon.tags.duplicate(),
		"attack_pattern": _capture_known_properties(weapon.attack_pattern),
	}


func _capture_passive(passive: PassiveItemDef) -> Dictionary:
	return {
		"stat_modifiers": passive.stat_modifiers.duplicate(true),
		"max_stack": passive.max_stack,
		"cost": passive.item.item_cost if passive.item != null else 0,
		"quality": passive.item.item_tier if passive.item != null else 0,
	}


func _capture_enemy(enemy: EnemyDef) -> Dictionary:
	var stats := enemy.stats
	return {
		"health": stats.health if stats != null else 0,
		"health_per_wave": stats.health_increase_per_wave if stats != null else 0.0,
		"damage": stats.damage if stats != null else 0.0,
		"damage_per_wave": stats.damage_increase_per_wave if stats != null else 0.0,
		"speed": stats.speed if stats != null else 0,
		"material_drop": stats.gold_drop if stats != null else 0,
		"role_id": enemy.behavior.role_id if enemy.behavior != null else &"",
		"behavior_values": _capture_known_properties(enemy.behavior),
		"tags": enemy.tags.duplicate(),
	}


func _apply_character_rule_contract(rule: CharacterRuleDef, contract: Dictionary) -> void:
	if rule == null:
		return
	rule.allowed_weapon_tags = _string_name_array(contract.get("allowed_weapon_tags", []))
	rule.forbidden_weapon_tags = _string_name_array(contract.get("forbidden_weapon_tags", []))
	rule.starting_stat_modifiers = contract.get("starting_stat_modifiers", {}).duplicate(true)
	rule.stat_modification_multipliers = contract.get(
		"stat_modification_multipliers", {}
	).duplicate(true)
	rule.shop_price_multiplier = float(contract.get("shop_price_multiplier", 1.0))
	rule.recycle_value_multiplier = float(contract.get("recycle_value_multiplier", 1.0))
	rule.experience_gain_multiplier = float(contract.get("experience_gain_multiplier", 1.0))
	rule.dodge_cap_override = float(contract.get("dodge_cap_override", -1.0))
	rule.consumable_healing_bonus = float(contract.get("consumable_healing_bonus", 0.0))
	rule.materials_reset_on_wave_start = bool(contract.get("materials_reset_on_wave_start", false))
	rule.weapon_slot_limit = clampi(
		int(contract.get("weapon_slot_limit", rule.weapon_slot_limit)),
		1,
		InventoryState.MAX_WEAPON_SLOTS
	)
	rule.semantic_rules = contract.get("semantic_rules", {}).duplicate(true)
	rule.runtime_support = contract.get("runtime_support", {}).duplicate(true)


func _string_name_array(raw_values: Variant) -> Array[StringName]:
	var result: Array[StringName] = []
	if not raw_values is Array:
		return result
	for raw_value: Variant in raw_values:
		var value := StringName(str(raw_value))
		if not value.is_empty() and value not in result:
			result.append(value)
	return result


func _apply_character_base_stats(stats: UnitStats, values: Dictionary) -> void:
	if stats == null:
		return
	stats.health = maxi(1, int(values.get("max_health", stats.health)))
	stats.health_increase_per_wave = 0.0
	stats.hp_regen = float(values.get("recovery", stats.hp_regen))
	stats.life_steal = float(values.get("life_steal", stats.life_steal))
	stats.damage = float(values.get("damage", stats.damage))
	stats.move_speed_percent = float(values.get("move_speed", stats.move_speed_percent))
	stats.speed = roundi(StatCalculator.new(stat_rules).movement_speed(stats.move_speed_percent))
	stats.block_chance = float(values.get("dodge", stats.block_chance))
	stats.luck = float(values.get("luck", stats.luck))
	stats.harvesting = float(values.get("harvesting", stats.harvesting))


func _apply_weapon_tier(item: ItemWeapon, values: Dictionary) -> void:
	if item == null or item.stats == null:
		return
	item.stats.damage = float(values.get("base_damage", values.get("damage", item.stats.damage)))
	item.stats.cooldown = float(values.get("cooldown", item.stats.cooldown))
	item.stats.max_range = float(values.get("range", item.stats.max_range))
	item.stats.crit_chance = float(values.get(
		"crit_chance", values.get("critical_chance", item.stats.crit_chance)
	))
	item.stats.crit_damage = float(values.get(
		"crit_damage", values.get("critical_damage", item.stats.crit_damage)
	))
	item.stats.knockback = float(values.get("knockback", item.stats.knockback))
	item.stats.life_steal = float(values.get("life_steal", item.stats.life_steal))
	item.stats.scaling_coefficients = values.get(
		"scaling_coefficients", item.stats.scaling_coefficients
	).duplicate(true)
	item.stats.is_engineering_structure = bool(values.get(
		"engineering_structure", item.stats.is_engineering_structure
	))
	item.stats.projectile_count = clampi(int(values.get(
		"projectile_count", item.stats.projectile_count
	)), 0, 16)
	item.item_cost = maxi(0, int(values.get("cost", item.item_cost)))


func _capture_known_properties(target: Object) -> Dictionary:
	var result := {}
	if target == null:
		return result
	for property: Dictionary in target.get_property_list():
		if int(property.get("usage", 0)) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var property_name := StringName(str(property.get("name", "")))
			result[String(property_name)] = target.get(property_name)
	return result


func _apply_known_properties(target: Object, values: Dictionary) -> void:
	if target == null:
		return
	var known := {}
	for property: Dictionary in target.get_property_list():
		known[String(property.get("name", ""))] = true
	for raw_name: Variant in values:
		var property_name := str(raw_name)
		if known.has(property_name):
			target.set(property_name, values[raw_name])


func _baseline_character_rule_contracts() -> Dictionary:
	return {
		"core:character/well_rounded": {
			"reference_slot": "balanced",
			"starting_stat_modifiers": {"max_health": 5.0, "move_speed": 5.0, "harvesting": 8.0},
			"runtime_support": {"starting_stats": true},
		},
		"core:character/brawler": {
			"reference_slot": "unarmed_melee",
			"starting_stat_modifiers": {"attack_speed": 50.0, "dodge": 15.0, "range": -50.0, "ranged_damage": -50.0},
			"allowed_weapon_tags": [&"close_quarters"],
			"forbidden_weapon_tags": [&"firearm", &"tactical"],
			"semantic_rules": {"preferred_weapon_family": "close_quarters"},
			"runtime_support": {"starting_stats": true, "unarmed_only": true},
		},
		"core:character/bunny": {
			"reference_slot": "rapid_ranged",
			"starting_stat_modifiers": {"range": 50.0},
			"stat_modification_multipliers": {"ranged_damage": 1.5, "melee_damage": 0.0, "max_health": 0.75},
			"allowed_weapon_tags": [&"firearm"],
			"forbidden_weapon_tags": [&"close_quarters", &"tactical"],
			"runtime_support": {"starting_stats": true, "stat_modification_multipliers": true, "no_melee_weapons": true},
		},
		"core:character/crazy": {
			"reference_slot": "precision",
			"starting_stat_modifiers": {"range": 100.0, "attack_speed": 25.0, "dodge": -30.0, "engineering": -10.0, "ranged_damage": -10.0},
			"allowed_weapon_tags": [&"precise"],
			"starter_weapon_ids": [&"core:weapon/spear"],
			"semantic_rules": {"starting_weapon_family": "precision"},
			"runtime_support": {"starting_stats": true, "forced_starting_weapon": true},
		},
		"core:character/knight": {
			"reference_slot": "maximum_health_tank",
			"starting_stat_modifiers": {"life_steal": -100.0},
			"stat_modification_multipliers": {"max_health": 1.25, "recovery": 0.5, "dodge": 0.5, "move_speed": 0.0},
			"consumable_healing_bonus": 3.0,
			"semantic_rules": {"damage_per_max_health": {"health": 3, "damage_percent": 1}, "life_steal_floor": -100},
			"runtime_support": {"stat_modification_multipliers": true, "health_damage_conversion": false, "consumable_healing_bonus": true, "life_steal_floor": true},
		},
		"core:character/almighty": {
			"reference_slot": "luck_drop",
			"starting_stat_modifiers": {"luck": 100.0, "attack_speed": -60.0},
			"stat_modification_multipliers": {"luck": 1.25},
			"experience_gain_multiplier": 0.5,
			"semantic_rules": {"material_pickup_damage": {"base": 1.0, "luck_scale": 0.15, "chance": 0.75}},
			"runtime_support": {"starting_stats": true, "stat_modification_multipliers": true, "experience_gain_multiplier": true, "material_pickup_damage": false},
		},
		"core:character/ember_sage": {
			"reference_slot": "elemental",
			"starting_stat_modifiers": {},
			"stat_modification_multipliers": {"elemental_damage": 1.25, "melee_damage": 0.0, "ranged_damage": 0.0, "engineering": 0.5},
			"allowed_weapon_tags": [&"tactical"],
			"runtime_support": {"stat_modification_multipliers": true},
		},
		"core:character/scrapwright": {
			"reference_slot": "engineering",
			"starting_stat_modifiers": {"engineering": 10.0},
			"stat_modification_multipliers": {"engineering": 1.25, "damage": 0.5},
			"allowed_weapon_tags": [&"sidearm"],
			"starter_weapon_ids": [&"core:weapon/wand", &"core:weapon/pistol", &"core:weapon/revolver", &"core:weapon/drone_beacon"],
			"semantic_rules": {"structures_spawn_close": true},
			"runtime_support": {"starting_stats": true, "stat_modification_multipliers": true, "structures_spawn_close": false},
		},
		"core:character/dash_raider": {
			"reference_slot": "ethereal_dodge",
			"starting_stat_modifiers": {"damage": 10.0, "dodge": 30.0, "armor": -100.0},
			"dodge_cap_override": 90.0,
			"allowed_weapon_tags": [&"mobility"],
			"forbidden_weapon_tags": [&"tactical"],
			"starter_weapon_ids": [&"core:weapon/chainsaw", &"core:weapon/punch", &"core:weapon/sword", &"core:weapon/boomerang"],
			"semantic_rules": {"preferred_weapon_family": "mobility"},
			"runtime_support": {"starting_stats": true, "dodge_cap_override": true, "ethereal_only": true},
		},
		"core:character/bloodbound": {
			"reference_slot": "healing_trigger",
			"starting_stat_modifiers": {"recovery": 10.0, "life_steal": 10.0},
			"stat_modification_multipliers": {"damage": 0.5},
			"semantic_rules": {"heal_damage_trigger": {"base": 10.0, "random_enemy": true}},
			"runtime_support": {"starting_stats": true, "stat_modification_multipliers": true, "heal_damage_trigger": false},
		},
		"core:character/scrap_broker": {
			"reference_slot": "economy",
			"starting_stat_modifiers": {},
			"stat_modification_multipliers": {"harvesting": 1.5, "damage": 0.5},
			"shop_price_multiplier": 0.75,
			"recycle_value_multiplier": 1.25,
			"materials_reset_on_wave_start": true,
			"runtime_support": {"stat_modification_multipliers": true, "shop_price_multiplier": true, "recycle_value_multiplier": true, "materials_reset_on_wave_start": true},
		},
		"core:character/glass_cannon": {
			"reference_slot": "single_weapon",
			"starting_stat_modifiers": {"attack_speed": 200.0},
			"stat_modification_multipliers": {"damage": 2.0},
			"weapon_slot_limit": 1,
			"runtime_support": {"starting_stats": true, "weapon_slot_limit": true, "stat_modification_multipliers": true},
		},
	}


func _baseline_player_base_stats() -> Dictionary:
	return {
		"max_health": 10,
		"recovery": 0.0,
		"life_steal": 0.0,
		"damage": 0.0,
		"move_speed": 0.0,
		"dodge": 0.0,
		"luck": 0.0,
		"harvesting": 0.0,
	}
