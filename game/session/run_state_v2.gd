class_name GogoRunState
extends Resource

const SCHEMA_VERSION := 2

@export var schema_version: int = SCHEMA_VERSION
@export var run_seed: int = 1
@export var current_wave: int = 1
@export var total_waves: int = 20
@export var phase: StringName = &"selection"
@export var zone_id: StringName = &""
@export var difficulty_id: StringName = &""
@export var won: bool = false
@export var ended: bool = false
@export var endless: bool = false
@export var players: Array[SessionPlayerState] = []
@export var locked_shop_offer_ids: Array[StringName] = []
@export var shop_offer_wave: int = 0
@export var shop_offer_ids: Array[StringName] = []
@export var shop_offer_initialized: bool = false
@export var shop_offer_initialization_id: int = 0
@export var reroll_count: int = 0
@export var upgrade_reroll_count: int = 0
@export var pending_upgrade_count: int = 0
@export var elapsed_seconds: float = 0.0


func player(index: int = 0) -> SessionPlayerState:
	if index < 0 or index >= players.size():
		return null
	return players[index]


func advance_wave() -> bool:
	if ended or phase != &"shop" or pending_upgrade_count != 0 or current_wave < 1 or total_waves < 1:
		return false
	if (not endless and current_wave >= total_waves) or (endless and current_wave < total_waves):
		return false
	if current_wave == 9223372036854775807:
		return false
	current_wave += 1
	phase = &"combat"
	reroll_count = 0
	return true


func to_dictionary() -> Dictionary:
	var serialized_players: Array = []
	for value in players:
		# Preserve invalid candidates as rejectable data for the pure codec/profile
		# barrier; serialization must not dereference null or invent a new player.
		if value == null:
			serialized_players.append(null)
			continue
		var weapons: Variant = null
		if value.weapon_inventory != null:
			weapons = value.weapon_inventory.records()
			for record: Dictionary in weapons:
				if record.get("content_id") is StringName:
					record["content_id"] = String(record["content_id"])
		serialized_players.append({
			"player_index": value.player_index,
			"character_id": String(value.character_id),
			"level": value.level,
			"xp": value.xp,
			"xp_to_next_level": value.xp_to_next_level,
			"materials": value.materials,
			"economy_material_remainder": value.economy_material_remainder,
			"current_health": value.current_health,
			"max_health": value.max_health,
			"base_stats": value.base_stats.duplicate(true),
			"final_stats": value.final_stats.duplicate(true),
			"weapons": weapons,
			"next_weapon_instance_id": value.next_weapon_instance_id,
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
		"endless": endless,
		"players": serialized_players,
		"locked_shop_offer_ids": locked_shop_offer_ids.map(func(id: StringName) -> String: return String(id)),
		"shop_offer_wave": shop_offer_wave,
		"shop_offer_ids": shop_offer_ids.map(func(id: StringName) -> String: return String(id)),
		"shop_offer_initialized": shop_offer_initialized,
		"shop_offer_initialization_id": shop_offer_initialization_id,
		"reroll_count": reroll_count,
		"upgrade_reroll_count": upgrade_reroll_count,
		"pending_upgrade_count": pending_upgrade_count,
		"elapsed_seconds": elapsed_seconds,
	}


static func parse_dictionary(data: Variant, snapshot: ContentSnapshot) -> Dictionary:
	return load("res://game/session/run_state_codec.gd").parse(data, snapshot)


static func from_dictionary(data: Dictionary, snapshot: ContentSnapshot) -> GogoRunState:
	return parse_dictionary(data, snapshot).state as GogoRunState
