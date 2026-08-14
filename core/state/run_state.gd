class_name RunState
extends RefCounted


var character_id: StringName = &""
var starting_weapon_id: StringName = &""
var random_seed: int = 0
var phase: int = RunPhase.SELECTION
var wave: int = 1
var difficulty: int = 1
var level: int = 1
var experience: int = 0
var materials: int = 0
var queued_level_ups: int = 0
var queued_rewards: int = 0
var player_stats: PlayerStats
var inventory: InventoryState


func _init(seed_value: int = 0, stats_template: PlayerStats = null) -> void:
	random_seed = seed_value
	player_stats = stats_template.copy() if stats_template != null else PlayerStats.new()
	inventory = InventoryState.new()


func try_transition(next_phase: int) -> bool:
	if not RunPhase.can_transition(phase, next_phase):
		return false
	phase = next_phase
	return true


func to_dict() -> Dictionary:
	return {
		"character_id": String(character_id),
		"starting_weapon_id": String(starting_weapon_id),
		"random_seed": random_seed,
		"phase": phase,
		"wave": wave,
		"difficulty": difficulty,
		"level": level,
		"experience": experience,
		"materials": materials,
		"queued_level_ups": queued_level_ups,
		"queued_rewards": queued_rewards,
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
	result.level = maxi(1, int(data.get("level", 1)))
	result.experience = maxi(0, int(data.get("experience", 0)))
	result.materials = maxi(0, int(data.get("materials", 0)))
	result.queued_level_ups = maxi(0, int(data.get("queued_level_ups", 0)))
	result.queued_rewards = maxi(0, int(data.get("queued_rewards", 0)))
	var inventory_data: Variant = data.get("inventory", {})
	result.inventory = InventoryState.from_dict(inventory_data if inventory_data is Dictionary else {})
	return result
