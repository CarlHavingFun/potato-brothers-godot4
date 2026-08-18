class_name RunState
extends RefCounted

const SHOP_SLOT_COUNT := 4
const CURRENT_STAT_RULES_VERSION := StatRulesDef.CURRENT_VERSION
const CURRENT_BALANCE_PACK_VERSION := BalancePackDef.BASELINE_VERSION
const LEGACY_STAT_RULES_VERSION := "legacy_v3"
const LEGACY_BALANCE_PACK_VERSION := "legacy_v3"

var character_id: StringName = &""
var starting_weapon_id: StringName = &""
var random_seed: int = 0
var phase: int = RunPhase.SELECTION
var wave: int = 1
var difficulty: int = 1
var run_mode: int = RunMode.STANDARD
var standard_victory_recorded := false
var endless_cycle: int = 0
var highest_wave_reached: int = 1
var kill_count: int = 0
var boss_kill_count: int = 0
var character_rule_id: StringName = &""
var character_rule_applied := false
var pickup_healing_multiplier := 1.0
var shop_price_multiplier := 1.0
var recycle_value_multiplier := 1.0
var experience_gain_multiplier := 1.0
var experience_gain_remainder := 0.0
var dodge_cap_override := -1.0
var consumable_healing_bonus := 0.0
var materials_reset_on_wave_start := false
var allowed_weapon_tags: Array[StringName] = []
var forbidden_weapon_tags: Array[StringName] = []
var shop_bias_tags: Array[StringName] = []
var dash_charges := 1
var dash_cooldown_multiplier := 1.0
var dash_duration_multiplier := 1.0
var level: int = 1
var experience: int = 0
var materials: int = 0
var material_bag: int = 0
var queued_level_ups: int = 0
var queued_rewards: int = 0
var queued_reward_floors: Array[int] = []
var elapsed_seconds: float = 0.0
var player_health_ratio := 1.0
var shop_refresh_count: int = 0
var upgrade_refresh_count: int = 0
var shop_locked: bool = false
var shop_offer_ids: Array[Dictionary] = []
var shop_slots: Array[ShopSlotState] = []
var rng_states: Dictionary = {}
var stat_rules_version := CURRENT_STAT_RULES_VERSION
var balance_pack_version := CURRENT_BALANCE_PACK_VERSION
var stat_rebuild_source: Dictionary = {}
var applied_upgrades: Array[Dictionary] = []
var player_stats: PlayerStats
var inventory: InventoryState


func _init(seed_value: int = 0, stats_template: PlayerStats = null) -> void:
	random_seed = seed_value
	player_stats = stats_template.copy() if stats_template != null else PlayerStats.new()
	inventory = InventoryState.new()
	for slot_index in SHOP_SLOT_COUNT:
		shop_slots.append(ShopSlotState.new())


func try_transition(next_phase: int) -> bool:
	if not RunPhase.can_transition(phase, next_phase):
		return false
	phase = next_phase
	return true


func is_resumable_checkpoint() -> bool:
	return (
		not character_id.is_empty()
		and not starting_weapon_id.is_empty()
		and phase in [RunPhase.COMBAT, RunPhase.UPGRADE, RunPhase.CHEST, RunPhase.SHOP]
		and wave >= 1
	)


func to_dict() -> Dictionary:
	return {
		"character_id": String(character_id),
		"starting_weapon_id": String(starting_weapon_id),
		"random_seed": random_seed,
		"phase": phase,
		"wave": wave,
		"difficulty": difficulty,
		"run_mode": run_mode,
		"standard_victory_recorded": standard_victory_recorded,
		"endless_cycle": endless_cycle,
		"highest_wave_reached": highest_wave_reached,
		"kill_count": kill_count,
		"boss_kill_count": boss_kill_count,
		"character_rule_id": String(character_rule_id),
		"character_rule_applied": character_rule_applied,
		"pickup_healing_multiplier": pickup_healing_multiplier,
		"shop_price_multiplier": shop_price_multiplier,
		"recycle_value_multiplier": recycle_value_multiplier,
		"experience_gain_multiplier": experience_gain_multiplier,
		"experience_gain_remainder": experience_gain_remainder,
		"dodge_cap_override": dodge_cap_override,
		"consumable_healing_bonus": consumable_healing_bonus,
		"materials_reset_on_wave_start": materials_reset_on_wave_start,
		"allowed_weapon_tags": allowed_weapon_tags.map(func(tag: StringName): return String(tag)),
		"forbidden_weapon_tags": forbidden_weapon_tags.map(func(tag: StringName): return String(tag)),
		"shop_bias_tags": shop_bias_tags.map(func(tag: StringName): return String(tag)),
		"dash_charges": dash_charges,
		"dash_cooldown_multiplier": dash_cooldown_multiplier,
		"dash_duration_multiplier": dash_duration_multiplier,
		"level": level,
		"experience": experience,
		"materials": materials,
		"material_bag": material_bag,
		"queued_level_ups": queued_level_ups,
		"queued_rewards": queued_rewards,
		"queued_reward_floors": queued_reward_floors.duplicate(),
		"elapsed_seconds": elapsed_seconds,
		"player_health_ratio": player_health_ratio,
		"shop_refresh_count": shop_refresh_count,
		"upgrade_refresh_count": upgrade_refresh_count,
		"shop_locked": shop_locked,
		"shop_offer_ids": shop_offer_ids.duplicate(true),
		"shop_slots": shop_slots.map(func(slot: ShopSlotState): return slot.to_dict()),
		"rng_states": _serialized_rng_states(),
		"stat_rules_version": stat_rules_version,
		"balance_pack_version": balance_pack_version,
		"stat_rebuild_source": stat_rebuild_source.duplicate(true),
		"applied_upgrades": applied_upgrades.duplicate(true),
		"player_stats": player_stats.to_dict(),
		"inventory": inventory.to_dict(),
	}


static func from_dict(data: Dictionary) -> RunState:
	var stats_data: Variant = data.get("player_stats", {})
	var stats := PlayerStats.from_dict(stats_data if stats_data is Dictionary else {})
	var result := RunState.new(int(data.get("random_seed", 0)), stats)
	result.character_id = StringName(str(data.get("character_id", "")))
	result.starting_weapon_id = StringName(str(data.get("starting_weapon_id", "")))
	var restored_phase := int(data.get("phase", RunPhase.SELECTION))
	result.phase = restored_phase if RunPhase.is_valid(restored_phase) else RunPhase.SELECTION
	result.wave = maxi(1, int(data.get("wave", 1)))
	result.difficulty = clampi(int(data.get("difficulty", 1)), 1, 5)
	var restored_run_mode := int(data.get("run_mode", RunMode.STANDARD))
	result.run_mode = restored_run_mode if RunMode.is_valid(restored_run_mode) else RunMode.STANDARD
	result.standard_victory_recorded = bool(data.get("standard_victory_recorded", false))
	result.endless_cycle = maxi(0, int(data.get("endless_cycle", 0)))
	result.highest_wave_reached = maxi(result.wave, int(data.get("highest_wave_reached", result.wave)))
	result.kill_count = maxi(0, int(data.get("kill_count", 0)))
	result.boss_kill_count = maxi(0, int(data.get("boss_kill_count", 0)))
	result.character_rule_id = StringName(str(data.get("character_rule_id", "")))
	result.character_rule_applied = bool(data.get("character_rule_applied", false))
	result.pickup_healing_multiplier = maxf(0.0, float(data.get("pickup_healing_multiplier", 1.0)))
	result.shop_price_multiplier = maxf(0.0, float(data.get("shop_price_multiplier", 1.0)))
	result.recycle_value_multiplier = maxf(0.0, float(data.get("recycle_value_multiplier", 1.0)))
	result.experience_gain_multiplier = maxf(0.0, float(data.get("experience_gain_multiplier", 1.0)))
	result.experience_gain_remainder = clampf(
		float(data.get("experience_gain_remainder", 0.0)), 0.0, 0.999999
	)
	result.dodge_cap_override = clampf(float(data.get("dodge_cap_override", -1.0)), -1.0, 100.0)
	result.consumable_healing_bonus = float(data.get("consumable_healing_bonus", 0.0))
	result.materials_reset_on_wave_start = bool(data.get("materials_reset_on_wave_start", false))
	result.allowed_weapon_tags = _deserialize_tags(data.get("allowed_weapon_tags", []))
	result.forbidden_weapon_tags = _deserialize_tags(data.get("forbidden_weapon_tags", []))
	var raw_shop_bias: Variant = data.get("shop_bias_tags", [])
	if raw_shop_bias is Array:
		for tag: Variant in raw_shop_bias:
			result.shop_bias_tags.append(StringName(str(tag)))
	result.dash_charges = maxi(1, int(data.get("dash_charges", 1)))
	result.dash_cooldown_multiplier = maxf(0.1, float(data.get("dash_cooldown_multiplier", 1.0)))
	result.dash_duration_multiplier = maxf(0.1, float(data.get("dash_duration_multiplier", 1.0)))
	result.level = maxi(1, int(data.get("level", 1)))
	result.experience = maxi(0, int(data.get("experience", 0)))
	result.materials = maxi(0, int(data.get("materials", 0)))
	result.material_bag = maxi(0, int(data.get("material_bag", 0)))
	result.queued_level_ups = maxi(0, int(data.get("queued_level_ups", 0)))
	result.queued_rewards = maxi(0, int(data.get("queued_rewards", 0)))
	var stored_reward_floors: Variant = data.get("queued_reward_floors", [])
	if stored_reward_floors is Array:
		for floor_value: Variant in stored_reward_floors:
			if result.queued_reward_floors.size() >= result.queued_rewards:
				break
			result.queued_reward_floors.append(clampi(
				int(floor_value), Global.UpgradeTier.COMMON, Global.UpgradeTier.LEGENDARY
			))
	result.elapsed_seconds = maxf(0.0, float(data.get("elapsed_seconds", 0.0)))
	result.player_health_ratio = clampf(float(data.get("player_health_ratio", 1.0)), 0.0, 1.0)
	result.shop_refresh_count = maxi(0, int(data.get("shop_refresh_count", 0)))
	result.upgrade_refresh_count = maxi(0, int(data.get("upgrade_refresh_count", 0)))
	result.shop_locked = bool(data.get("shop_locked", false))
	var stored_offers: Variant = data.get("shop_offer_ids", [])
	if stored_offers is Array:
		for entry: Variant in stored_offers:
			if entry is Dictionary:
				result.shop_offer_ids.append((entry as Dictionary).duplicate(true))
	result.shop_slots.clear()
	var stored_slots: Variant = data.get("shop_slots", [])
	if stored_slots is Array:
		for entry: Variant in stored_slots:
			if entry is Dictionary and result.shop_slots.size() < SHOP_SLOT_COUNT:
				result.shop_slots.append(ShopSlotState.from_dict(entry))
	if result.shop_slots.is_empty():
		for entry: Dictionary in result.shop_offer_ids.slice(0, SHOP_SLOT_COUNT):
			var migrated := ShopSlotState.from_dict(entry)
			migrated.locked = result.shop_locked
			result.shop_slots.append(migrated)
	while result.shop_slots.size() < SHOP_SLOT_COUNT:
		result.shop_slots.append(ShopSlotState.new())
	var stored_rng_states: Variant = data.get("rng_states", {})
	result.rng_states = {}
	if stored_rng_states is Dictionary:
		for raw_stream: Variant in stored_rng_states:
			result.rng_states[str(raw_stream)] = int(str(stored_rng_states[raw_stream]))
	var inventory_data: Variant = data.get("inventory", {})
	result.inventory = InventoryState.from_dict(inventory_data if inventory_data is Dictionary else {})
	var has_versioned_stats := data.has("stat_rules_version")
	result.stat_rules_version = str(data.get(
		"stat_rules_version",
		LEGACY_STAT_RULES_VERSION
	))
	result.balance_pack_version = str(data.get(
		"balance_pack_version",
		LEGACY_BALANCE_PACK_VERSION
	))
	var raw_rebuild_source: Variant = data.get("stat_rebuild_source", {})
	result.stat_rebuild_source = (
		raw_rebuild_source.duplicate(true) if raw_rebuild_source is Dictionary else {}
	)
	var raw_applied_upgrades: Variant = data.get("applied_upgrades", [])
	if raw_applied_upgrades is Array:
		for raw_upgrade: Variant in raw_applied_upgrades:
			if raw_upgrade is Dictionary:
				result.applied_upgrades.append(raw_upgrade.duplicate(true))
	if not has_versioned_stats and result.stat_rebuild_source.is_empty():
		result.stat_rebuild_source = {
			"character_id": String(result.character_id),
			"starting_weapon_id": String(result.starting_weapon_id),
			"inventory": result.inventory.to_dict(),
			"applied_upgrades": result.applied_upgrades.duplicate(true),
			"legacy_player_stats": result.player_stats.to_dict(),
		}
	return result


func allows_weapon_tags(weapon_tags: Array[StringName]) -> bool:
	for tag: StringName in forbidden_weapon_tags:
		if tag in weapon_tags:
			return false
	if allowed_weapon_tags.is_empty():
		return true
	for tag: StringName in allowed_weapon_tags:
		if tag in weapon_tags:
			return true
	return false


func apply_wave_start_character_rules() -> int:
	if not materials_reset_on_wave_start or materials <= 0:
		return 0
	var removed := materials
	materials = 0
	return removed


func requires_stat_rebuild(
	target_stat_rules_version: String = CURRENT_STAT_RULES_VERSION,
	target_balance_pack_version: String = CURRENT_BALANCE_PACK_VERSION
) -> bool:
	return (
		stat_rules_version != target_stat_rules_version
		or balance_pack_version != target_balance_pack_version
	)


func mark_stats_rebuilt(
	rebuilt_stats: PlayerStats,
	target_stat_rules_version: String = CURRENT_STAT_RULES_VERSION,
	target_balance_pack_version: String = CURRENT_BALANCE_PACK_VERSION
) -> bool:
	if rebuilt_stats == null:
		return false
	player_stats = rebuilt_stats.copy()
	stat_rules_version = target_stat_rules_version
	balance_pack_version = target_balance_pack_version
	stat_rebuild_source.clear()
	return true


func record_applied_upgrade(upgrade_id: StringName, stat_id: int, value: float) -> bool:
	if upgrade_id.is_empty() or not StatId.is_valid(stat_id):
		return false
	applied_upgrades.append({
		"upgrade_id": String(upgrade_id),
		"stat_id": stat_id,
		"value": value,
	})
	return true


func _serialized_rng_states() -> Dictionary:
	var result := {}
	for raw_stream: Variant in rng_states:
		result[str(raw_stream)] = str(int(rng_states[raw_stream]))
	return result


static func _deserialize_tags(raw_tags: Variant) -> Array[StringName]:
	var result: Array[StringName] = []
	if not raw_tags is Array:
		return result
	for raw_tag: Variant in raw_tags:
		var tag := StringName(str(raw_tag))
		if not tag.is_empty() and tag not in result:
			result.append(tag)
	return result
