extends Node


const OUTPUT_PATH := "res://content_packs/default/pack.tres"
const CHARACTER_IDS := ["brawler", "bunny", "crazy", "knight", "well_rounded"]
const ENEMY_IDS := ["charger", "chaser_fast", "chaser_mid", "chaser_slow", "shooter"]
const WEAPON_PATHS := {
	"axe": "melee/axe",
	"chainsaw": "melee/chainsaw",
	"mace": "melee/mace",
	"punch": "melee/punch",
	"sword": "melee/sword",
	"wand": "melee/wand",
	"laser": "range/laser",
	"pistol": "range/pistol",
	"revolver": "range/revolver",
	"shotgun": "range/shotgun",
	"smg": "range/smg",
}


func _ready() -> void:
	var pack := ContentPackDef.new()
	pack.pack_id = &"potato_default"
	pack.pack_version = "0.1.0"
	pack.characters = _build_characters()
	pack.weapons = _build_weapons()
	pack.passives = _build_passives()
	pack.upgrades = _build_upgrades()
	pack.enemies = _build_enemies()
	pack.waves = _build_waves()
	pack.difficulties = _build_difficulties()

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_PATH.get_base_dir()))
	var result := ResourceSaver.save(pack, OUTPUT_PATH)
	if result != OK:
		push_error("Failed to save default content pack: %s" % error_string(result))
		get_tree().quit(result)
		return
	print("Generated %s" % OUTPUT_PATH)
	get_tree().quit(OK)


func _build_characters() -> Array[CharacterDef]:
	var result: Array[CharacterDef] = []
	for character_id: String in CHARACTER_IDS:
		var definition := CharacterDef.new()
		definition.content_id = StringName("character/%s" % character_id)
		definition.display_name_key = StringName("character.%s.name" % character_id)
		definition.description_key = StringName("character.%s.description" % character_id)
		definition.stats = load("res://resources/units/players/stats_player_%s.tres" % character_id)
		definition.scene = load("res://scenes/unit/players/player_%s.tscn" % character_id)
		result.append(definition)
	return result


func _build_weapons() -> Array[WeaponDef]:
	var result: Array[WeaponDef] = []
	for weapon_id: String in WEAPON_PATHS:
		var definition := WeaponDef.new()
		definition.content_id = StringName("weapon/%s" % weapon_id)
		definition.display_name_key = StringName("weapon.%s.name" % weapon_id)
		definition.description_key = StringName("weapon.%s.description" % weapon_id)
		var tiers: Array[ItemWeapon] = []
		for tier: int in range(1, 5):
			tiers.append(load(
				"res://resources/items/weapons/%s/item_%s_%d.tres"
				% [WEAPON_PATHS[weapon_id], weapon_id, tier]
			))
		definition.tiers = tiers
		result.append(definition)
	return result


func _build_passives() -> Array[PassiveItemDef]:
	var result: Array[PassiveItemDef] = []
	var root := "res://resources/items/passives/data"
	var files := Array(DirAccess.get_files_at(root))
	files.sort()
	for file_name: String in files:
		if file_name.get_extension() != "tres":
			continue
		var local_id := file_name.get_basename().trim_prefix("passive_")
		var definition := PassiveItemDef.new()
		definition.content_id = StringName("passive/%s" % local_id)
		definition.display_name_key = StringName("passive.%s.name" % local_id)
		definition.description_key = StringName("passive.%s.description" % local_id)
		definition.item = load(root.path_join(file_name))
		result.append(definition)
	return result


func _build_upgrades() -> Array[UpgradeDef]:
	var result: Array[UpgradeDef] = []
	var root := "res://resources/items/upgrades/data"
	var paths: Array[String] = []
	_collect_resources(root, paths)
	paths.sort()
	for resource_path: String in paths:
		var item: ItemUpgrade = load(resource_path)
		var relative_id := resource_path.trim_prefix(root + "/").trim_suffix(".tres")
		var definition := UpgradeDef.new()
		definition.content_id = StringName("upgrade/legacy/%s" % relative_id)
		definition.display_name_key = StringName("upgrade.legacy.%s.name" % relative_id.replace("/", "."))
		definition.description_key = StringName("upgrade.legacy.%s.description" % relative_id.replace("/", "."))
		definition.quality = int(item.item_tier)
		definition.stat_id = TutorialStatsAdapter.stat_id_for_property(item.stat_id)
		definition.item = item
		result.append(definition)
	return result


func _build_enemies() -> Array[EnemyDef]:
	var result: Array[EnemyDef] = []
	for enemy_id: String in ENEMY_IDS:
		var definition := EnemyDef.new()
		definition.content_id = StringName("enemy/%s" % enemy_id)
		definition.display_name_key = StringName("enemy.%s.name" % enemy_id)
		definition.description_key = StringName("enemy.%s.description" % enemy_id)
		definition.stats = load("res://resources/units/enemies/stats_enemy_%s.tres" % enemy_id)
		definition.scene = load("res://scenes/unit/enemy/enemy_%s.tscn" % enemy_id)
		result.append(definition)
	return result


func _build_waves() -> Array[WaveDef]:
	var definition := WaveDef.new()
	definition.content_id = &"wave/legacy_1_to_5"
	definition.wave_number = 1
	definition.data = load("res://resources/waves/data/wave_1_to_5.tres")
	definition.duration = definition.data.wave_time
	return [definition]


func _build_difficulties() -> Array[DifficultyDef]:
	var result: Array[DifficultyDef] = []
	for level: int in range(1, 6):
		result.append(DifficultyDef.for_level(level))
	return result


func _collect_resources(root: String, output: Array[String]) -> void:
	var directory := DirAccess.open(root)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var path := root.path_join(entry)
			if directory.current_is_dir():
				_collect_resources(path, output)
			elif entry.get_extension() == "tres":
				output.append(path)
		entry = directory.get_next()
	directory.list_dir_end()
