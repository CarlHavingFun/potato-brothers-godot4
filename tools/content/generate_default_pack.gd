extends Node


const OUTPUT_PATH := "res://content_packs/default/pack.tres"
const CHARACTER_IDS := ["brawler", "bunny", "crazy", "knight", "well_rounded"]
const ENEMY_IDS := ["charger", "chaser_fast", "chaser_mid", "chaser_slow", "shooter"]
const WAVE_DURATIONS := [30, 35, 40, 45, 50, 55, 60, 65, 70, 90]
const QUALITY_NAMES := ["common", "rare", "epic", "legendary"]
const STAT_TIER_VALUES := {
	"max_health": [3.0, 6.0, 9.0, 12.0],
	"recovery": [1.0, 2.0, 3.0, 4.0],
	"life_steal": [2.0, 4.0, 6.0, 8.0],
	"damage": [3.0, 6.0, 9.0, 12.0],
	"melee_damage": [2.0, 4.0, 6.0, 8.0],
	"ranged_damage": [2.0, 4.0, 6.0, 8.0],
	"elemental_damage": [2.0, 4.0, 6.0, 8.0],
	"attack_speed": [5.0, 10.0, 15.0, 20.0],
	"critical_chance": [3.0, 6.0, 9.0, 12.0],
	"engineering": [2.0, 4.0, 6.0, 8.0],
	"range": [10.0, 20.0, 30.0, 40.0],
	"armor": [1.0, 2.0, 3.0, 4.0],
	"dodge": [3.0, 6.0, 9.0, 12.0],
	"move_speed": [3.0, 6.0, 9.0, 12.0],
	"luck": [5.0, 10.0, 15.0, 20.0],
	"harvesting": [5.0, 10.0, 15.0, 20.0],
}
const MIGRATED_PASSIVES := [
	{"id": "coffee", "level": 1, "mods": {"damage": -2.0, "attack_speed": 10.0}},
	{"id": "crack", "level": 1, "mods": {"max_health": 5.0, "recovery": -1.0}},
	{"id": "helmet", "level": 1, "mods": {"damage": -3.0, "armor": 2.0}},
	{"id": "toxic_sludge", "level": 1, "mods": {"dodge": 2.0}},
	{"id": "butterfly", "level": 1, "mods": {"life_steal": 2.0, "luck": -1.0}},
	{"id": "flag", "level": 2, "mods": {"range": 20.0, "attack_speed": 10.0}},
	{"id": "knight_helmet", "level": 4, "mods": {"max_health": 5.0, "armor": 1.0, "move_speed": 5.0}},
	{"id": "leech", "level": 3, "mods": {"recovery": 1.0, "life_steal": 1.0, "harvesting": -2.0}},
	{"id": "missile", "level": 4, "mods": {"damage": 10.0, "attack_speed": -4.0}},
	{"id": "muscle", "level": 4, "mods": {"max_health": 5.0, "melee_damage": 3.0, "range": -15.0}},
	{"id": "plant", "level": 2, "mods": {"recovery": 3.0, "life_steal": -1.0}},
	{"id": "round_hat", "level": 4, "mods": {"luck": 15.0, "harvesting": 18.0}},
	{"id": "telescope", "level": 2, "mods": {"range": 20.0, "ranged_damage": 2.0}},
	{"id": "vest", "level": 3, "mods": {"armor": 1.0, "dodge": 2.0}},
	{"id": "map", "level": 4, "mods": {"range": 20.0, "move_speed": 5.0}},
	{"id": "magazine", "level": 4, "mods": {"attack_speed": 10.0, "ranged_damage": 3.0}},
]
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
	pack.translation_paths = [
		"res://content_packs/default/i18n/game.zh_CN.po",
		"res://content_packs/default/i18n/game.en.po",
	]

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
	var almighty := CharacterDef.new()
	almighty.content_id = &"character/almighty"
	almighty.display_name_key = &"character.almighty.name"
	almighty.description_key = &"character.almighty.description"
	almighty.stats = load(
		"res://resources/units/players/stats_player_well_rounded.tres"
	).duplicate(true)
	almighty.stats.name = "Almighty"
	almighty.stats.health += 5
	almighty.stats.hp_regen += 1.0
	almighty.stats.luck += 10.0
	almighty.scene = load("res://scenes/unit/players/player_well_rounded.tscn")
	result.append(almighty)
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
		definition.stat_modifiers = _legacy_passive_modifiers(definition.item)
		definition.max_stack = definition.item.max_stack
		result.append(definition)
	var icon_index := 0
	for source: Dictionary in MIGRATED_PASSIVES:
		var definition := PassiveItemDef.new()
		var passive_id := str(source["id"])
		var level := int(source["level"])
		var item := ItemPassive.new()
		item.item_name = passive_id.replace("_", " ").capitalize()
		item.item_icon = result[icon_index % result.size()].item.item_icon
		item.item_tier = clampi(level - 1, 0, 3) as Global.UpgradeTier
		item.item_type = ItemBase.ItemType.PASSIVE
		item.item_cost = 15 + level * 5
		definition.content_id = StringName("passive/%s" % passive_id)
		definition.display_name_key = StringName("passive.%s.name" % passive_id)
		definition.description_key = StringName("passive.%s.description" % passive_id)
		definition.item = item
		definition.stat_modifiers = source["mods"].duplicate(true)
		definition.max_stack = 99
		result.append(definition)
		icon_index += 1
	return result


func _build_upgrades() -> Array[UpgradeDef]:
	var result: Array[UpgradeDef] = []
	var root := "res://resources/items/upgrades/data"
	var paths: Array[String] = []
	_collect_resources(root, paths)
	paths.sort()
	for stat_key: String in STAT_TIER_VALUES:
		var stat_id := StatId.from_key(stat_key)
		for quality: int in range(4):
			var value := float(STAT_TIER_VALUES[stat_key][quality])
			var item := ItemUpgrade.new()
			var icon_source: ItemUpgrade = load(paths[(stat_id * 4 + quality) % paths.size()])
			item.item_name = stat_key.replace("_", " ").capitalize()
			item.item_icon = icon_source.item_icon
			item.item_tier = quality as Global.UpgradeTier
			item.item_type = ItemBase.ItemType.UPGRADE
			item.value = value
			item.description = "+%s" % value
			item.stat_id = stat_key
			var definition := UpgradeDef.new()
			definition.content_id = StringName(
				"upgrade/%s/%s" % [stat_key, QUALITY_NAMES[quality]]
			)
			definition.display_name_key = StringName("upgrade.%s.name" % stat_key)
			definition.description_key = StringName(
				"upgrade.%s.%s.description" % [stat_key, QUALITY_NAMES[quality]]
			)
			definition.quality = quality
			definition.stat_id = stat_id
			definition.value = value
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
	result.append(_build_adapted_enemy(
		"xiami", "chaser_mid", 15, 3.0, 180, 2, []
	))
	result.append(_build_adapted_enemy(
		"dapan", "shooter", 10, 2.0, 140, 3, [&"ranged"]
	))
	result.append(_build_adapted_enemy(
		"mouse_dog", "charger", 1000, 5.0, 160, 50, [&"boss"]
	))
	return result


func _build_waves() -> Array[WaveDef]:
	var result: Array[WaveDef] = []
	var compositions := [
		{"chaser_slow": 10.0},
		{"chaser_slow": 7.0, "chaser_mid": 3.0},
		{"chaser_mid": 6.0, "chaser_fast": 2.0, "xiami": 2.0},
		{"chaser_mid": 5.0, "shooter": 2.0, "xiami": 3.0},
		{"charger": 2.0, "chaser_slow": 4.0, "shooter": 2.0, "dapan": 2.0},
		{"chaser_fast": 4.0, "charger": 2.0, "xiami": 2.0, "dapan": 2.0},
		{"chaser_slow": 2.0, "chaser_mid": 2.0, "chaser_fast": 2.0, "shooter": 2.0, "charger": 2.0},
		{"xiami": 4.0, "dapan": 3.0, "charger": 3.0},
		{"chaser_fast": 3.0, "shooter": 3.0, "xiami": 2.0, "dapan": 2.0},
		{"mouse_dog": 1.0, "chaser_slow": 3.0, "shooter": 2.0},
	]
	for index: int in range(10):
		var wave_number := index + 1
		var definition := WaveDef.new()
		definition.content_id = StringName("wave/%02d" % wave_number)
		definition.wave_number = wave_number
		definition.duration = float(WAVE_DURATIONS[index])
		definition.fixed_spawn_time = maxf(0.55, 1.1 - index * 0.06)
		var data := WaveData.new()
		data.from = wave_number
		data.to = wave_number
		data.wave_time = definition.duration
		data.spawn_type = WaveData.SpawnType.FIXED
		data.fixed_spawn_time = definition.fixed_spawn_time
		var units: Array[WaveUnitData] = []
		var spawns: Array[WaveSpawnDef] = []
		for enemy_id: String in compositions[index]:
			var weight := float(compositions[index][enemy_id])
			var spawn := WaveSpawnDef.new()
			spawn.enemy_id = StringName("enemy/%s" % enemy_id)
			spawn.weight = weight
			spawn.is_boss = enemy_id == "mouse_dog"
			spawns.append(spawn)
			var enemy_scene := _enemy_scene_for_id(enemy_id)
			var unit := WaveUnitData.new()
			unit.unit_scene = enemy_scene
			unit.weight = weight
			units.append(unit)
		definition.spawns = spawns
		data.units = units
		definition.data = data
		result.append(definition)
	return result


func _legacy_passive_modifiers(item: ItemPassive) -> Dictionary:
	var result := {}
	var add_stat := TutorialStatsAdapter.stat_id_for_property(item.add_stats)
	if item.add_value != 0.0 and StatId.is_valid(add_stat):
		result[StatId.key(add_stat)] = item.add_value
	var remove_stat := TutorialStatsAdapter.stat_id_for_property(item.remove_stats)
	if item.remove_value != 0.0 and StatId.is_valid(remove_stat):
		var key := StatId.key(remove_stat)
		result[key] = float(result.get(key, 0.0)) - item.remove_value
	return result


func _build_adapted_enemy(
	enemy_id: String,
	base_id: String,
	health: int,
	damage: float,
	speed: int,
	gold: int,
	tags: Array[StringName]
) -> EnemyDef:
	var definition := EnemyDef.new()
	definition.content_id = StringName("enemy/%s" % enemy_id)
	definition.display_name_key = StringName("enemy.%s.name" % enemy_id)
	definition.description_key = StringName("enemy.%s.description" % enemy_id)
	definition.stats = load(
		"res://resources/units/enemies/stats_enemy_%s.tres" % base_id
	).duplicate(true)
	definition.stats.name = enemy_id.replace("_", " ").capitalize()
	definition.stats.health = health
	definition.stats.damage = damage
	definition.stats.speed = speed
	definition.stats.gold_drop = gold
	definition.scene = _enemy_scene_for_id(enemy_id)
	definition.tags = tags
	return definition


func _enemy_scene_for_id(enemy_id: String) -> PackedScene:
	match enemy_id:
		"xiami":
			return load("res://scenes/unit/enemy/enemy_chaser_mid.tscn")
		"dapan":
			return load("res://scenes/unit/enemy/enemy_shooter.tscn")
		"mouse_dog":
			return load("res://scenes/unit/enemy/boss/mouse_dog.tscn")
		_:
			return load("res://scenes/unit/enemy/enemy_%s.tscn" % enemy_id)


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
