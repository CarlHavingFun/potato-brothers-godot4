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
var _difficulties: Dictionary = {}
var _item_ids: Dictionary = {}
var _item_paths: Dictionary = {}
var _shop_items: Array[ItemBase] = []
var _upgrade_items: Array[ItemUpgrade] = []
var _passive_defs_by_item: Dictionary = {}
var _upgrade_defs_by_item: Dictionary = {}
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
	var candidate_difficulties: Dictionary = {}
	var candidate_item_ids: Dictionary = {}
	var candidate_item_paths: Dictionary = {}
	var candidate_shop_items: Array[ItemBase] = []
	var candidate_upgrade_items: Array[ItemUpgrade] = []
	var candidate_passive_defs_by_item: Dictionary = {}
	var candidate_upgrade_defs_by_item: Dictionary = {}
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
	for weapon: WeaponDef in pack.weapons:
		var stable_id := weapon.get_stable_id(pack.pack_id)
		for item: ItemWeapon in weapon.tiers:
			if item == null:
				return ERR_INVALID_DATA
			candidate_item_ids[item.get_instance_id()] = stable_id
			if not item.resource_path.is_empty():
				candidate_item_paths[item.resource_path] = stable_id
			candidate_shop_items.append(item)
	for passive: PassiveItemDef in pack.passives:
		if passive.item == null:
			return ERR_INVALID_DATA
		var stable_id := passive.get_stable_id(pack.pack_id)
		candidate_item_ids[passive.item.get_instance_id()] = stable_id
		candidate_passive_defs_by_item[passive.item.get_instance_id()] = passive
		if not passive.item.resource_path.is_empty():
			candidate_item_paths[passive.item.resource_path] = stable_id
		candidate_shop_items.append(passive.item)
	for upgrade: UpgradeDef in pack.upgrades:
		if upgrade.item == null:
			return ERR_INVALID_DATA
		var stable_id := upgrade.get_stable_id(pack.pack_id)
		candidate_item_ids[upgrade.item.get_instance_id()] = stable_id
		candidate_upgrade_defs_by_item[upgrade.item.get_instance_id()] = upgrade
		if not upgrade.item.resource_path.is_empty():
			candidate_item_paths[upgrade.item.resource_path] = stable_id
		candidate_upgrade_items.append(upgrade.item)
	for difficulty: DifficultyDef in pack.difficulties:
		if difficulty == null or candidate_difficulties.has(difficulty.level):
			return ERR_INVALID_DATA
		candidate_difficulties[difficulty.level] = difficulty

	pack_id = pack.pack_id
	_pack = pack
	_all = candidate_all
	_characters = candidate_characters
	_weapons = candidate_weapons
	_passives = candidate_passives
	_upgrades = candidate_upgrades
	_enemies = candidate_enemies
	_waves = candidate_waves
	_difficulties = candidate_difficulties
	_item_ids = candidate_item_ids
	_item_paths = candidate_item_paths
	_shop_items = candidate_shop_items
	_upgrade_items = candidate_upgrade_items
	_passive_defs_by_item = candidate_passive_defs_by_item
	_upgrade_defs_by_item = candidate_upgrade_defs_by_item
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


func get_difficulties() -> Array[DifficultyDef]:
	return _pack.difficulties.duplicate() if _pack != null else []


func get_difficulty(level: int) -> DifficultyDef:
	return _difficulties.get(level) as DifficultyDef


func get_shop_items() -> Array[ItemBase]:
	return _shop_items.duplicate()


func get_upgrade_items() -> Array[ItemUpgrade]:
	return _upgrade_items.duplicate()


func get_passive_definition_for_item(item: ItemPassive) -> PassiveItemDef:
	if item == null:
		return null
	return _passive_defs_by_item.get(item.get_instance_id()) as PassiveItemDef


func get_upgrade_definition_for_item(item: ItemUpgrade) -> UpgradeDef:
	if item == null:
		return null
	return _upgrade_defs_by_item.get(item.get_instance_id()) as UpgradeDef


func get_item_stable_id(item: ItemBase) -> StringName:
	if item == null:
		return &""
	var stable_id: StringName = _item_ids.get(item.get_instance_id(), &"")
	if stable_id.is_empty() and not item.resource_path.is_empty():
		stable_id = _item_paths.get(item.resource_path, &"")
	return stable_id if not stable_id.is_empty() else item.get_stable_id()


func get_item_definition(item: ItemBase) -> ContentDef:
	return _all.get(get_item_stable_id(item)) as ContentDef if item != null else null


func get_item_display_name(item: ItemBase) -> String:
	if item == null:
		return ""
	var definition := _all.get(get_item_stable_id(item)) as ContentDef
	if definition != null and not definition.display_name_key.is_empty():
		return Global.translate_text(definition.display_name_key, item.item_name)
	return item.item_name


func get_character_display_name(definition: CharacterDef) -> String:
	if definition == null or definition.stats == null:
		return ""
	return Global.translate_text(definition.display_name_key, definition.stats.name)


func get_upgrade_display_name(item: ItemUpgrade) -> String:
	var definition := get_upgrade_definition_for_item(item)
	if definition == null or not StatId.is_valid(definition.stat_id):
		return item.item_name if item != null else ""
	var quality_key := _quality_translation_key(definition.quality)
	var quality_name := Global.translate_text(quality_key, _quality_fallback(definition.quality))
	var stat_key := StringName("stat.%s" % StatId.key(definition.stat_id))
	var stat_name := Global.translate_text(stat_key, StatId.key(definition.stat_id).capitalize())
	return Global.translate_text(&"ui.upgrade.name", "%s %s") % [quality_name, stat_name]


func get_upgrade_description(item: ItemUpgrade) -> String:
	var definition := get_upgrade_definition_for_item(item)
	if definition == null or not StatId.is_valid(definition.stat_id):
		return item.description if item != null else ""
	var stat_key := StringName("stat.%s" % StatId.key(definition.stat_id))
	var stat_name := Global.translate_text(stat_key, StatId.key(definition.stat_id).capitalize())
	return Global.translate_text(&"ui.upgrade.value", "%+.1f %s") % [definition.value, stat_name]


func get_item_type_display_name(item_type: ItemBase.ItemType) -> String:
	match item_type:
		ItemBase.ItemType.WEAPON:
			return Global.translate_text(&"item_type.weapon", "Weapon")
		ItemBase.ItemType.UPGRADE:
			return Global.translate_text(&"item_type.upgrade", "Upgrade")
		ItemBase.ItemType.PASSIVE:
			return Global.translate_text(&"item_type.passive", "Passive Item")
	return ""


func get_weapon_tier(content_id: StringName, tier: int) -> ItemWeapon:
	var definition := get_weapon(content_id)
	if definition == null or tier < 1 or tier > definition.tiers.size():
		return null
	return definition.tiers[tier - 1]


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


func get_definition(content_id: StringName) -> ContentDef:
	return _all.get(_normalize_query(content_id)) as ContentDef


func get_tags_for_item(item: ItemBase) -> Array[StringName]:
	var definition := get_definition(get_item_stable_id(item))
	return definition.tags.duplicate() if definition != null else []


func get_tag_display_name(tag: StringName) -> String:
	var raw := String(tag)
	var key := StringName("tag.%s" % raw.replace("/", "."))
	return Global.translate_text(key, raw.replace("_", " ").capitalize())


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


func _quality_translation_key(quality: int) -> StringName:
	var keys: Array[StringName] = [
		&"quality.common",
		&"quality.rare",
		&"quality.epic",
		&"quality.legendary",
	]
	return keys[clampi(quality, 0, keys.size() - 1)]


func _quality_fallback(quality: int) -> String:
	var names: Array[String] = ["Common", "Rare", "Epic", "Legendary"]
	return names[clampi(quality, 0, names.size() - 1)]
