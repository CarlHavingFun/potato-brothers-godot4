class_name RunState
extends RefCounted

const SHOP_SLOT_COUNT := 4

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
var shop_refresh_count: int = 0
var upgrade_refresh_count: int = 0
var shop_locked: bool = false
var shop_offer_ids: Array[Dictionary] = []
var shop_slots: Array[ShopSlotState] = []
var rng_states: Dictionary = {}
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
		"shop_refresh_count": shop_refresh_count,
		"upgrade_refresh_count": upgrade_refresh_count,
		"shop_locked": shop_locked,
		"shop_offer_ids": shop_offer_ids.duplicate(true),
		"shop_slots": shop_slots.map(func(slot: ShopSlotState): return slot.to_dict()),
		"rng_states": _serialized_rng_states(),
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
	return result


func _serialized_rng_states() -> Dictionary:
	var result := {}
	for raw_stream: Variant in rng_states:
		result[str(raw_stream)] = str(int(rng_states[raw_stream]))
	return result
