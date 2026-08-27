class_name GogoCombatHudSnapshot
extends RefCounted


var health: float = 0.0
var maximum_health: float = 0.0
var seconds: float = 0.0
var wave_elapsed: float = 0.0
var wave: int = 0
var level: int = 1
var experience: int = 0
var next_level_requirement: int = 1
var materials: int = 0
var weapon_ids: Array[StringName] = []
var item_ids: Array[StringName] = []


static func create(
	player: SessionPlayerState,
	remaining_seconds: float,
	current_wave: int,
	elapsed_seconds: float = 0.0
) -> GogoCombatHudSnapshot:
	var snapshot := GogoCombatHudSnapshot.new()
	snapshot.seconds = maxf(remaining_seconds, 0.0)
	snapshot.wave_elapsed = maxf(elapsed_seconds, 0.0)
	snapshot.wave = maxi(current_wave, 0)
	if player == null:
		return snapshot
	snapshot.health = player.current_health
	snapshot.maximum_health = player.max_health
	snapshot.level = player.level
	snapshot.experience = player.xp
	snapshot.next_level_requirement = player.xp_to_next_level
	snapshot.materials = player.materials
	snapshot.weapon_ids.assign(player.weapon_ids)
	snapshot.item_ids.assign(player.item_ids)
	return snapshot
