class_name BalanceParityManifest
extends Resource


const EXPECTED_CHARACTERS := 12
const EXPECTED_WEAPON_FAMILIES := 24
const EXPECTED_WEAPON_TIERS := 4
const EXPECTED_PASSIVES := 60
const EXPECTED_UPGRADES := 64
const EXPECTED_REGULAR_ENEMIES := 18
const EXPECTED_ELITES := 2
const EXPECTED_BOSSES := 2
const EXPECTED_WAVES := 20

@export var character_ids: Array[StringName] = []
@export var weapon_ids: Array[StringName] = []
@export var weapon_tier_counts: Dictionary = {}
@export var passive_ids: Array[StringName] = []
@export var upgrade_ids: Array[StringName] = []
@export var regular_enemy_ids: Array[StringName] = []
@export var elite_enemy_ids: Array[StringName] = []
@export var boss_enemy_ids: Array[StringName] = []
@export var wave_ids: Array[StringName] = []
@export var wave_numbers := PackedInt32Array()


func bind_content(pack: ContentPackDef) -> BalanceParityManifest:
	_clear()
	if pack == null:
		return self
	for character: CharacterDef in pack.characters:
		if character != null:
			character_ids.append(character.get_balance_id(pack.pack_id))
	for weapon: WeaponDef in pack.weapons:
		if weapon == null:
			continue
		var balance_id := weapon.get_balance_id(pack.pack_id)
		weapon_ids.append(balance_id)
		weapon_tier_counts[String(balance_id)] = weapon.tiers.size()
	for passive: PassiveItemDef in pack.passives:
		if passive != null:
			passive_ids.append(passive.get_balance_id(pack.pack_id))
	for upgrade: UpgradeDef in pack.upgrades:
		if upgrade != null:
			upgrade_ids.append(upgrade.get_balance_id(pack.pack_id))
	for enemy: EnemyDef in pack.enemies:
		if enemy == null:
			continue
		var balance_id := enemy.get_balance_id(pack.pack_id)
		if &"boss" in enemy.tags:
			boss_enemy_ids.append(balance_id)
		elif &"elite" in enemy.tags:
			elite_enemy_ids.append(balance_id)
		elif &"normal" in enemy.tags:
			regular_enemy_ids.append(balance_id)
	for wave: WaveDef in pack.waves:
		if wave != null:
			wave_ids.append(wave.get_balance_id(pack.pack_id))
			wave_numbers.append(wave.wave_number)
	return self


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	_validate_unique_count(character_ids, EXPECTED_CHARACTERS, "characters", errors)
	_validate_unique_count(weapon_ids, EXPECTED_WEAPON_FAMILIES, "weapon families", errors)
	_validate_unique_count(passive_ids, EXPECTED_PASSIVES, "passives", errors)
	_validate_unique_count(upgrade_ids, EXPECTED_UPGRADES, "upgrades", errors)
	_validate_unique_count(
		regular_enemy_ids, EXPECTED_REGULAR_ENEMIES, "regular enemies", errors
	)
	_validate_unique_count(elite_enemy_ids, EXPECTED_ELITES, "elites", errors)
	_validate_unique_count(boss_enemy_ids, EXPECTED_BOSSES, "bosses", errors)
	_validate_unique_count(wave_ids, EXPECTED_WAVES, "waves", errors)
	for weapon_id: StringName in weapon_ids:
		var tier_count := int(weapon_tier_counts.get(String(weapon_id), 0))
		if tier_count != EXPECTED_WEAPON_TIERS:
			errors.append("balance weapon %s requires %d tiers, got %d" % [
				weapon_id, EXPECTED_WEAPON_TIERS, tier_count
			])
	var unique_wave_numbers := {}
	for wave_number: int in wave_numbers:
		unique_wave_numbers[wave_number] = true
	for expected_wave in range(1, EXPECTED_WAVES + 1):
		if not unique_wave_numbers.has(expected_wave):
			errors.append("balance wave %d is missing" % expected_wave)
	var all_seen := {}
	for balance_id: StringName in all_balance_ids():
		if all_seen.has(balance_id):
			errors.append("balance_id %s is reused across content categories" % balance_id)
		else:
			all_seen[balance_id] = true
	return errors


func all_balance_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	result.append_array(character_ids)
	result.append_array(weapon_ids)
	result.append_array(passive_ids)
	result.append_array(upgrade_ids)
	result.append_array(regular_enemy_ids)
	result.append_array(elite_enemy_ids)
	result.append_array(boss_enemy_ids)
	result.append_array(wave_ids)
	return result


func _clear() -> void:
	character_ids.clear()
	weapon_ids.clear()
	weapon_tier_counts.clear()
	passive_ids.clear()
	upgrade_ids.clear()
	regular_enemy_ids.clear()
	elite_enemy_ids.clear()
	boss_enemy_ids.clear()
	wave_ids.clear()
	wave_numbers.clear()


func _validate_unique_count(
	ids: Array[StringName], expected_count: int, label: String, errors: PackedStringArray
) -> void:
	if ids.size() != expected_count:
		errors.append("balance %s requires %d entries, got %d" % [
			label, expected_count, ids.size()
		])
	var seen := {}
	for balance_id: StringName in ids:
		if balance_id.is_empty():
			errors.append("balance %s contains an empty id" % label)
		elif seen.has(balance_id):
			errors.append("duplicate balance_id %s" % balance_id)
		else:
			seen[balance_id] = true
