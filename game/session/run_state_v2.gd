class_name GogoRunState
extends Resource

const SCHEMA_VERSION := 1

@export var schema_version: int = SCHEMA_VERSION
@export var run_seed: int = 1
@export var current_wave: int = 1
@export var total_waves: int = 5
@export var phase: StringName = &"selection"
@export var zone_id: StringName = &""
@export var difficulty_id: StringName = &""
@export var won: bool = false
@export var ended: bool = false
@export var players: Array[SessionPlayerState] = []
@export var locked_shop_offer_ids: Array[StringName] = []
@export var reroll_count: int = 0
@export var upgrade_reroll_count: int = 0
@export var pending_upgrade_count: int = 0
@export var elapsed_seconds: float = 0.0


func player(index: int = 0) -> SessionPlayerState:
	if index < 0 or index >= players.size():
		return null
	return players[index]


func advance_wave() -> bool:
	if current_wave >= total_waves:
		won = true
		ended = true
		phase = &"settlement"
		return false
	current_wave += 1
	phase = &"combat"
	reroll_count = 0
	locked_shop_offer_ids.clear()
	return true


func to_dictionary() -> Dictionary:
	var serialized_players: Array[Dictionary] = []
	for value in players:
		serialized_players.append({
			"player_index": value.player_index,
			"character_id": String(value.character_id),
			"level": value.level,
			"xp": value.xp,
			"xp_to_next_level": value.xp_to_next_level,
			"materials": value.materials,
			"current_health": value.current_health,
			"max_health": value.max_health,
			"base_stats": value.base_stats.duplicate(true),
			"final_stats": value.final_stats.duplicate(true),
			"weapon_ids": value.weapon_ids.map(func(id: StringName) -> String: return String(id)),
			"weapon_levels": value.weapon_levels.duplicate(true),
			"item_ids": value.item_ids.map(func(id: StringName) -> String: return String(id)),
			"upgrade_ids": value.upgrade_ids.map(func(id: StringName) -> String: return String(id)),
		})
	return {
		"schema_version": schema_version,
		"run_seed": run_seed,
		"current_wave": current_wave,
		"total_waves": total_waves,
		"phase": String(phase),
		"zone_id": String(zone_id),
		"difficulty_id": String(difficulty_id),
		"won": won,
		"ended": ended,
		"players": serialized_players,
		"locked_shop_offer_ids": locked_shop_offer_ids.map(func(id: StringName) -> String: return String(id)),
		"reroll_count": reroll_count,
		"upgrade_reroll_count": upgrade_reroll_count,
		"pending_upgrade_count": pending_upgrade_count,
		"elapsed_seconds": elapsed_seconds,
	}


static func from_dictionary(data: Dictionary) -> GogoRunState:
	if int(data.get("schema_version", -1)) != SCHEMA_VERSION:
		return null
	var state := GogoRunState.new()
	state.run_seed = int(data.get("run_seed", 1))
	state.current_wave = int(data.get("current_wave", 1))
	state.total_waves = int(data.get("total_waves", 5))
	state.phase = StringName(data.get("phase", "selection"))
	state.zone_id = StringName(data.get("zone_id", ""))
	state.difficulty_id = StringName(data.get("difficulty_id", ""))
	state.won = bool(data.get("won", false))
	state.ended = bool(data.get("ended", false))
	state.reroll_count = int(data.get("reroll_count", 0))
	state.upgrade_reroll_count = int(data.get("upgrade_reroll_count", 0))
	state.pending_upgrade_count = int(data.get("pending_upgrade_count", 0))
	state.elapsed_seconds = float(data.get("elapsed_seconds", 0.0))
	for raw: Dictionary in data.get("players", []):
		var next_player := SessionPlayerState.new()
		next_player.player_index = int(raw.get("player_index", 0))
		next_player.character_id = StringName(raw.get("character_id", ""))
		next_player.level = int(raw.get("level", 1))
		next_player.xp = int(raw.get("xp", 0))
		next_player.xp_to_next_level = int(raw.get("xp_to_next_level", 20))
		next_player.materials = int(raw.get("materials", 35))
		next_player.current_health = float(raw.get("current_health", 10.0))
		next_player.max_health = float(raw.get("max_health", 10.0))
		next_player.base_stats = Dictionary(raw.get("base_stats", {})).duplicate(true)
		next_player.final_stats = Dictionary(raw.get("final_stats", {})).duplicate(true)
		next_player.weapon_levels = Dictionary(raw.get("weapon_levels", {})).duplicate(true)
		for id in raw.get("weapon_ids", []): next_player.weapon_ids.append(StringName(id))
		for id in raw.get("item_ids", []): next_player.item_ids.append(StringName(id))
		for id in raw.get("upgrade_ids", []): next_player.upgrade_ids.append(StringName(id))
		state.players.append(next_player)
	for id in data.get("locked_shop_offer_ids", []): state.locked_shop_offer_ids.append(StringName(id))
	return state
