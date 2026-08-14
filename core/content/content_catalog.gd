class_name ContentCatalog
extends RefCounted


var pack_id: StringName
var _all: Dictionary = {}
var _characters: Dictionary = {}
var _weapons: Dictionary = {}
var _passives: Dictionary = {}
var _upgrades: Dictionary = {}
var _enemies: Dictionary = {}
var _waves: Dictionary = {}
var _pack: ContentPackDef


func register_pack(pack: ContentPackDef) -> int:
	if pack == null or pack.pack_id.is_empty():
		return ERR_INVALID_DATA
	if not _all.is_empty():
		return ERR_ALREADY_EXISTS

	var candidate_all: Dictionary = {}
	var candidate_characters: Dictionary = {}
	var candidate_weapons: Dictionary = {}
	var candidate_passives: Dictionary = {}
	var candidate_upgrades: Dictionary = {}
	var candidate_enemies: Dictionary = {}
	var candidate_waves: Dictionary = {}
	var collections := [
		[pack.characters, candidate_characters],
		[pack.weapons, candidate_weapons],
		[pack.passives, candidate_passives],
		[pack.upgrades, candidate_upgrades],
		[pack.enemies, candidate_enemies],
		[pack.waves, candidate_waves],
	]
	for collection: Array in collections:
		var result := _index_definitions(collection[0], collection[1], candidate_all, pack.pack_id)
		if result != OK:
			return result

	pack_id = pack.pack_id
	_pack = pack
	_all = candidate_all
	_characters = candidate_characters
	_weapons = candidate_weapons
	_passives = candidate_passives
	_upgrades = candidate_upgrades
	_enemies = candidate_enemies
	_waves = candidate_waves
	return OK


func get_characters() -> Array[CharacterDef]:
	return _pack.characters.duplicate() if _pack != null else []


func get_weapons() -> Array[WeaponDef]:
	return _pack.weapons.duplicate() if _pack != null else []


func get_passives() -> Array[PassiveItemDef]:
	return _pack.passives.duplicate() if _pack != null else []


func get_upgrades() -> Array[UpgradeDef]:
	return _pack.upgrades.duplicate() if _pack != null else []


func get_enemies() -> Array[EnemyDef]:
	return _pack.enemies.duplicate() if _pack != null else []


func get_waves() -> Array[WaveDef]:
	return _pack.waves.duplicate() if _pack != null else []


func get_character(content_id: StringName) -> CharacterDef:
	return _characters.get(_normalize_query(content_id)) as CharacterDef


func get_weapon(content_id: StringName) -> WeaponDef:
	return _weapons.get(_normalize_query(content_id)) as WeaponDef


func get_passive(content_id: StringName) -> PassiveItemDef:
	return _passives.get(_normalize_query(content_id)) as PassiveItemDef


func get_upgrade(content_id: StringName) -> UpgradeDef:
	return _upgrades.get(_normalize_query(content_id)) as UpgradeDef


func get_enemy(content_id: StringName) -> EnemyDef:
	return _enemies.get(_normalize_query(content_id)) as EnemyDef


func get_wave(content_id: StringName) -> WaveDef:
	return _waves.get(_normalize_query(content_id)) as WaveDef


func has(content_id: StringName) -> bool:
	return _all.has(_normalize_query(content_id))


func _index_definitions(
	definitions: Array,
	bucket: Dictionary,
	all_entries: Dictionary,
	owner_pack_id: StringName
) -> int:
	for definition: Variant in definitions:
		if not definition is ContentDef:
			return ERR_INVALID_DATA
		var stable_id: StringName = definition.get_stable_id(owner_pack_id)
		if stable_id.is_empty():
			return ERR_INVALID_DATA
		if all_entries.has(stable_id):
			return ERR_ALREADY_EXISTS
		all_entries[stable_id] = definition
		bucket[stable_id] = definition
	return OK


func _normalize_query(content_id: StringName) -> StringName:
	var value := String(content_id)
	if value.is_empty() or value.contains(":") or pack_id.is_empty():
		return content_id
	return StringName("%s:%s" % [pack_id, value])
