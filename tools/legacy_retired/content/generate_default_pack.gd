extends Node


const OUTPUT_PATH := "res://content_packs/default/pack.tres"
const CHARACTER_IDS := ["brawler", "bunny", "crazy", "knight", "well_rounded"]
const ENEMY_IDS := ["charger", "chaser_fast", "chaser_mid", "chaser_slow", "shooter"]
const WAVE_DURATIONS := [
	30, 35, 40, 45, 50, 55, 60, 65, 70, 60,
	70, 70, 75, 75, 65, 80, 80, 85, 85, 90,
]
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
const EXTRA_CHARACTERS := [
	{"id": "ember_sage", "base": "bunny", "tags": [&"elemental", &"burn"], "health": -2, "speed": 10, "luck": 5},
	{"id": "scrapwright", "base": "well_rounded", "tags": [&"engineering", &"building"], "health": 3, "speed": -10, "luck": 0},
	{"id": "dash_raider", "base": "crazy", "tags": [&"dash", &"dodge"], "health": -3, "speed": 35, "luck": 0},
	{"id": "bloodbound", "base": "brawler", "tags": [&"sustain", &"life_steal"], "health": 5, "speed": 0, "luck": -5},
	{"id": "scrap_broker", "base": "well_rounded", "tags": [&"economy", &"luck"], "health": -2, "speed": 0, "luck": 30},
	{"id": "glass_cannon", "base": "crazy", "tags": [&"critical", &"glass"], "health": -8, "speed": 20, "luck": 10},
]
const EXTRA_WEAPONS := [
	{"id": "spear", "base": "sword", "tags": [&"melee", &"precise"], "damage": 1.10, "cooldown": 1.05, "range": 1.30},
	{"id": "cleaver", "base": "axe", "tags": [&"melee", &"heavy"], "damage": 1.25, "cooldown": 1.15, "range": 0.90},
	{"id": "carbine", "base": "pistol", "tags": [&"ranged", &"rapid"], "damage": 0.90, "cooldown": 0.80, "range": 1.15},
	{"id": "railbow", "base": "laser", "tags": [&"ranged", &"pierce"], "damage": 1.35, "cooldown": 1.25, "range": 1.35},
	{"id": "shrapnel_launcher", "base": "shotgun", "tags": [&"ranged", &"explosion"], "damage": 1.15, "cooldown": 1.15, "range": 1.00},
	{"id": "needler", "base": "smg", "tags": [&"ranged", &"rapid"], "damage": 0.75, "cooldown": 0.68, "range": 1.05},
	{"id": "boomerang", "base": "revolver", "tags": [&"ranged", &"bounce"], "damage": 1.05, "cooldown": 1.05, "range": 1.15},
	{"id": "ember_staff", "base": "wand", "tags": [&"elemental", &"burn"], "damage": 1.05, "cooldown": 1.00, "range": 1.15},
	{"id": "frost_orb", "base": "laser", "tags": [&"elemental", &"slow"], "damage": 0.90, "cooldown": 1.10, "range": 1.20},
	{"id": "storm_coil", "base": "smg", "tags": [&"elemental", &"chain"], "damage": 0.82, "cooldown": 0.90, "range": 1.10},
	{"id": "void_prism", "base": "revolver", "tags": [&"elemental", &"bounce"], "damage": 1.20, "cooldown": 1.18, "range": 1.25},
	{"id": "turret_kit", "base": "pistol", "tags": [&"engineering", &"building"], "damage": 0.85, "cooldown": 1.25, "range": 1.30},
	{"id": "drone_beacon", "base": "laser", "tags": [&"engineering", &"summon"], "damage": 0.80, "cooldown": 1.20, "range": 1.35},
]
const EXTRA_NORMAL_ENEMIES := [
	{"id": "swarm_mite", "base": "chaser_fast", "role": &"swarm", "health": 7, "damage": 1.0, "speed": 235, "gold": 1},
	{"id": "bulwark", "base": "chaser_slow", "role": &"tank", "health": 55, "damage": 5.0, "speed": 85, "gold": 4},
	{"id": "medic_spore", "base": "shooter", "role": &"healer", "health": 22, "damage": 1.0, "speed": 120, "gold": 3},
	{"id": "war_drummer", "base": "shooter", "role": &"buffer", "health": 26, "damage": 1.5, "speed": 110, "gold": 3},
	{"id": "brood_pod", "base": "chaser_slow", "role": &"spawner", "health": 38, "damage": 2.0, "speed": 70, "gold": 4},
	{"id": "flanker", "base": "charger", "role": &"flanker", "health": 18, "damage": 4.0, "speed": 205, "gold": 3},
	{"id": "hazard_weaver", "base": "shooter", "role": &"hazard", "health": 30, "damage": 3.0, "speed": 105, "gold": 4},
	{"id": "scrap_thief", "base": "chaser_fast", "role": &"resource_disrupt", "health": 16, "damage": 2.0, "speed": 220, "gold": 1},
	{"id": "shellback", "base": "chaser_mid", "role": &"armored", "health": 44, "damage": 4.0, "speed": 95, "gold": 4},
	{"id": "blink_rat", "base": "charger", "role": &"ambusher", "health": 20, "damage": 5.0, "speed": 190, "gold": 3},
	{"id": "hex_slinger", "base": "shooter", "role": &"debuffer", "health": 24, "damage": 4.0, "speed": 115, "gold": 4},
]


func _ready() -> void:
	var pack := ContentPackDef.new()
	pack.pack_id = &"core"
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
	_assign_presentation_ids(pack)
	_assign_typed_rules(pack)
	_strip_legacy_presentation_assets(pack)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_PATH.get_base_dir()))
	var result := ResourceSaver.save(pack, OUTPUT_PATH)
	if result != OK:
		push_error("Failed to save default content pack: %s" % error_string(result))
		get_tree().quit(result)
		return
	print("Generated %s" % OUTPUT_PATH)
	get_tree().quit(OK)


func _strip_legacy_presentation_assets(pack: ContentPackDef) -> void:
	for definition: ContentDef in (
		pack.characters + pack.weapons + pack.passives + pack.upgrades + pack.enemies + pack.waves
	):
		if definition != null:
			definition.icon = null
	for character: CharacterDef in pack.characters:
		if character != null and character.stats != null:
			character.stats.icon = null
	for weapon: WeaponDef in pack.weapons:
		if weapon == null:
			continue
		for tier: ItemWeapon in weapon.tiers:
			if tier != null:
				tier.item_icon = null
	for passive: PassiveItemDef in pack.passives:
		if passive != null and passive.item != null:
			passive.item.item_icon = null
	for upgrade: UpgradeDef in pack.upgrades:
		if upgrade != null and upgrade.item != null:
			upgrade.item.item_icon = null
	for enemy: EnemyDef in pack.enemies:
		if enemy != null and enemy.stats != null:
			enemy.stats.icon = null


func _assign_presentation_ids(pack: ContentPackDef) -> void:
	var collections: Array = [
		pack.characters, pack.weapons, pack.passives, pack.upgrades, pack.enemies, pack.waves,
	]
	for collection: Array in collections:
		for definition: ContentDef in collection:
			if definition != null and definition.presentation_id.is_empty():
				definition.presentation_id = StringName(String(definition.content_id).replace("/", "."))


func _assign_typed_rules(pack: ContentPackDef) -> void:
	for character: CharacterDef in pack.characters:
		character.rules = _character_rule_for(String(character.content_id).get_file())
	for weapon: WeaponDef in pack.weapons:
		var weapon_id := String(weapon.content_id).get_file()
		weapon.attack_pattern = _attack_pattern_for(weapon_id)
		var pattern_tag := weapon.attack_pattern.kind_key()
		if pattern_tag not in weapon.tags:
			weapon.tags.append(pattern_tag)
		for mechanic_tag: StringName in [
			&"pierce" if weapon.attack_pattern.pierce > 0 else &"",
			&"bounce" if weapon.attack_pattern.bounce > 0 else &"",
			&"explosion" if weapon.attack_pattern.explosion_radius > 0.0 else &"",
			weapon.attack_pattern.status_id,
		]:
			if not mechanic_tag.is_empty() and mechanic_tag not in weapon.tags:
				weapon.tags.append(mechanic_tag)
		if weapon.effects.is_empty():
			weapon.effects = _weapon_effects(weapon_id, weapon.tags)
	for enemy: EnemyDef in pack.enemies:
		enemy.behavior = _enemy_behavior_for(String(enemy.content_id).get_file())


func _attack_pattern_for(weapon_id: String) -> AttackPatternDef:
	var order := [
		"axe", "chainsaw", "mace", "punch", "sword", "wand", "spear", "cleaver",
		"laser", "pistol", "revolver", "shotgun", "smg", "carbine", "railbow",
		"shrapnel_launcher", "needler", "boomerang", "ember_staff", "frost_orb",
		"storm_coil", "void_prism", "turret_kit", "drone_beacon",
	]
	var index := maxi(0, order.find(weapon_id))
	var pattern := AttackPatternDef.new()
	pattern.pattern_id = StringName("attack/%s" % weapon_id)
	# A small per-family cadence offset remains part of the mechanics signature and
	# prevents reskinned clones from silently collapsing to identical behavior.
	pattern.cooldown_multiplier = 0.88 + float(index) * 0.012
	match weapon_id:
		"axe":
			pattern.kind = AttackPatternDef.Kind.ARC
			pattern.swing_degrees = 125.0
			pattern.melee_reach_multiplier = 1.05
			pattern.damage_multiplier = 1.12
		"chainsaw":
			pattern.kind = AttackPatternDef.Kind.CONTINUOUS
			pattern.active_duration_multiplier = 1.9
			pattern.melee_reach_multiplier = 0.72
			pattern.damage_multiplier = 0.72
		"mace":
			pattern.kind = AttackPatternDef.Kind.AREA
			pattern.swing_degrees = 75.0
			pattern.explosion_radius = 88.0
			pattern.damage_multiplier = 1.28
		"punch":
			pattern.kind = AttackPatternDef.Kind.BURST
			pattern.burst_count = 2
			pattern.melee_reach_multiplier = 0.68
			pattern.active_duration_multiplier = 0.62
		"sword":
			pattern.kind = AttackPatternDef.Kind.ARC
			pattern.swing_degrees = 82.0
			pattern.melee_reach_multiplier = 1.18
		"wand":
			pattern.kind = AttackPatternDef.Kind.ORBIT
			pattern.swing_degrees = 220.0
			pattern.melee_reach_multiplier = 1.12
		"spear":
			pattern.kind = AttackPatternDef.Kind.THRUST
			pattern.melee_reach_multiplier = 1.62
			pattern.pierce = 1
		"cleaver":
			pattern.kind = AttackPatternDef.Kind.ARC
			pattern.swing_degrees = 155.0
			pattern.melee_reach_multiplier = 0.92
			pattern.damage_multiplier = 1.38
		"laser":
			pattern.kind = AttackPatternDef.Kind.BEAM
			pattern.pierce = 2
			pattern.projectile_speed_multiplier = 1.45
		"pistol":
			pattern.kind = AttackPatternDef.Kind.BURST
			pattern.projectile_speed_multiplier = 1.08
		"revolver":
			pattern.kind = AttackPatternDef.Kind.CHARGED
			pattern.pierce = 1
			pattern.damage_multiplier = 1.22
		"shotgun":
			pattern.kind = AttackPatternDef.Kind.SCATTER
			pattern.projectile_count = 5
			pattern.spread_degrees = 8.0
			pattern.damage_multiplier = 0.58
		"smg":
			pattern.kind = AttackPatternDef.Kind.BURST
			pattern.burst_count = 3
			pattern.damage_multiplier = 0.78
		"carbine":
			pattern.kind = AttackPatternDef.Kind.BURST
			pattern.burst_count = 2
			pattern.pierce = 1
		"railbow":
			pattern.kind = AttackPatternDef.Kind.CHARGED
			pattern.pierce = 3
			pattern.projectile_speed_multiplier = 1.25
			pattern.damage_multiplier = 1.35
		"shrapnel_launcher":
			pattern.kind = AttackPatternDef.Kind.SCATTER
			pattern.projectile_count = 3
			pattern.spread_degrees = 11.0
			pattern.explosion_radius = 96.0
		"needler":
			pattern.kind = AttackPatternDef.Kind.BURST
			pattern.burst_count = 4
			pattern.status_id = &"mark"
			pattern.damage_multiplier = 0.62
		"boomerang":
			pattern.kind = AttackPatternDef.Kind.BOOMERANG
			pattern.bounce = 2
			pattern.projectile_speed_multiplier = 0.82
		"ember_staff":
			pattern.kind = AttackPatternDef.Kind.AREA
			pattern.explosion_radius = 72.0
			pattern.status_id = &"burn"
		"frost_orb":
			pattern.kind = AttackPatternDef.Kind.SCATTER
			pattern.projectile_count = 2
			pattern.spread_degrees = 6.0
			pattern.status_id = &"slow"
		"storm_coil":
			pattern.kind = AttackPatternDef.Kind.BEAM
			pattern.bounce = 3
			pattern.status_id = &"shock"
		"void_prism":
			pattern.kind = AttackPatternDef.Kind.BOOMERANG
			pattern.bounce = 4
			pattern.pierce = 1
			pattern.damage_multiplier = 1.18
		"turret_kit":
			pattern.kind = AttackPatternDef.Kind.BUILDING
			pattern.summon_count = 1
			pattern.projectile_speed_multiplier = 0.9
		"drone_beacon":
			pattern.kind = AttackPatternDef.Kind.SUMMON
			pattern.summon_count = 2
			pattern.bounce = 1
	return pattern


func _character_rule_for(character_id: String) -> CharacterRuleDef:
	var rule := CharacterRuleDef.new()
	rule.rule_id = StringName("character_rule/%s" % character_id)
	rule.core_ability_id = StringName("ability/%s" % character_id)
	match character_id:
		"brawler":
			rule.allowed_weapon_tags = [&"melee"]
			rule.starting_stat_modifiers = {"melee_damage": 4.0, "range": -12.0}
		"bunny":
			rule.shop_bias_tags = [&"rapid"]
			rule.starting_stat_modifiers = {"attack_speed": 8.0}
		"crazy":
			rule.shop_bias_tags = [&"critical", &"precise"]
			rule.starting_stat_modifiers = {"critical_chance": 7.0}
		"knight":
			rule.starting_stat_modifiers = {"armor": 3.0, "move_speed": -8.0}
			rule.weapon_slot_limit = 5
		"well_rounded":
			rule.starting_stat_modifiers = {"max_health": 2.0, "damage": 2.0}
		"almighty":
			rule.starting_stat_modifiers = {"damage": 3.0, "luck": 3.0, "harvesting": 3.0}
		"ember_sage":
			rule.allowed_weapon_tags = [&"elemental"]
			rule.shop_bias_tags = [&"burn", &"slow", &"chain"]
			rule.starting_stat_modifiers = {"elemental_damage": 6.0}
		"scrapwright":
			rule.allowed_weapon_tags = [&"engineering"]
			rule.shop_bias_tags = [&"building", &"summon"]
			rule.starting_stat_modifiers = {"engineering": 7.0}
		"dash_raider":
			rule.dash_charges = 2
			rule.dash_cooldown_multiplier = 0.72
			rule.dash_duration_multiplier = 1.15
			rule.starting_stat_modifiers = {"dodge": 8.0}
		"bloodbound":
			rule.pickup_healing_multiplier = 1.3
			rule.starting_stat_modifiers = {"life_steal": 8.0, "recovery": 2.0}
		"scrap_broker":
			rule.starting_material_bonus = 25
			rule.shop_bias_tags = [&"economy", &"luck"]
			rule.starting_stat_modifiers = {"harvesting": 8.0}
		"glass_cannon":
			rule.starting_stat_modifiers = {"damage": 16.0, "max_health": -6.0}
			rule.dash_cooldown_multiplier = 1.15
	return rule


func _enemy_behavior_for(enemy_id: String) -> EnemyBehaviorDef:
	var behavior := EnemyBehaviorDef.new()
	behavior.behavior_id = StringName("enemy_behavior/%s" % enemy_id)
	var role_by_id := {
		"chaser_slow": "swarm", "chaser_mid": "chaser", "chaser_fast": "flanker",
		"charger": "charger", "shooter": "ranged", "xiami": "swarm", "dapan": "ranged",
		"swarm_mite": "swarm", "bulwark": "tank", "medic_spore": "healer",
		"war_drummer": "buffer", "brood_pod": "spawner", "flanker": "flanker",
		"hazard_weaver": "hazard", "scrap_thief": "resource_disrupt", "shellback": "tank",
		"blink_rat": "ambusher", "hex_slinger": "debuffer", "iron_maw": "charger",
		"volt_stalker": "ranged", "mouse_dog": "charger", "scrap_titan": "tank",
	}
	behavior.role_id = StringName(str(role_by_id.get(enemy_id, "chaser")))
	behavior.skill_states = [&"approach", &"attack", &"recover"]
	match behavior.role_id:
		&"charger":
			behavior.movement_mode = &"charge"
			behavior.telegraph_seconds = 0.6
		&"ranged":
			behavior.movement_mode = &"keep_distance"
			behavior.telegraph_seconds = 0.35
		&"tank":
			behavior.damage_taken_multiplier = 0.72
			behavior.status_immunities = [&"slow"]
		&"healer":
			behavior.heal_amount = 8.0
			behavior.effect_radius = 180.0
		&"buffer":
			behavior.ally_speed_bonus = 0.18
		&"spawner":
			behavior.spawn_reinforcements = true
			behavior.pulse_interval = 6.0
		&"flanker":
			behavior.flank_angle_degrees = 32.0
		&"hazard":
			behavior.hazard_damage = 5.0
			behavior.effect_radius = 150.0
		&"resource_disrupt":
			behavior.material_steal = 1
			behavior.effect_radius = 125.0
		&"ambusher":
			behavior.ambush_distance = 260.0
			behavior.pulse_interval = 4.5
		&"debuffer":
			behavior.slow_multiplier = 0.72
			behavior.effect_radius = 165.0
	if enemy_id in ["mouse_dog", "scrap_titan"]:
		behavior.status_immunities = [&"slow", &"burn"]
	return behavior


func _build_characters() -> Array[CharacterDef]:
	var result: Array[CharacterDef] = []
	var role_tags := {
		"brawler": [&"melee", &"sustain"],
		"bunny": [&"ranged", &"rapid"],
		"crazy": [&"critical", &"precise"],
		"knight": [&"tank", &"armor"],
		"well_rounded": [&"balanced"],
	}
	for character_id: String in CHARACTER_IDS:
		var definition := CharacterDef.new()
		definition.content_id = StringName("character/%s" % character_id)
		definition.display_name_key = StringName("character.%s.name" % character_id)
		definition.description_key = StringName("character.%s.description" % character_id)
		definition.stats = load("res://resources/units/players/stats_player_%s.tres" % character_id)
		definition.scene = load("res://scenes/unit/players/player_%s.tscn" % character_id)
		definition.tags.assign(role_tags.get(character_id, []))
		definition.starter_weapon_ids = _starter_weapons_for_tags(definition.tags)
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
	almighty.tags = [&"balanced", &"power"]
	almighty.starter_weapon_ids = _starter_weapons_for_tags(almighty.tags)
	result.append(almighty)
	for source: Dictionary in EXTRA_CHARACTERS:
		var definition := CharacterDef.new()
		var character_id := str(source["id"])
		var base_id := str(source["base"])
		definition.content_id = StringName("character/%s" % character_id)
		definition.display_name_key = StringName("character.%s.name" % character_id)
		definition.description_key = StringName("character.%s.description" % character_id)
		definition.scene = load("res://scenes/unit/players/player_%s.tscn" % base_id)
		definition.stats = load(
			"res://resources/units/players/stats_player_%s.tres" % base_id
		).duplicate(true)
		definition.stats.name = character_id.replace("_", " ").capitalize()
		definition.stats.health = maxi(1, definition.stats.health + int(source["health"]))
		definition.stats.speed = maxi(80, definition.stats.speed + int(source["speed"]))
		definition.stats.luck += float(source["luck"])
		definition.tags.assign(source["tags"])
		definition.starter_weapon_ids = _starter_weapons_for_tags(definition.tags)
		definition.unlock_difficulty = 1 if result.size() < 8 else mini(5, result.size() - 6)
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
		definition.tags = _base_weapon_tags(weapon_id)
		result.append(definition)
	for source: Dictionary in EXTRA_WEAPONS:
		var definition := WeaponDef.new()
		var weapon_id := str(source["id"])
		var base_id := str(source["base"])
		var base_definition: WeaponDef = result.filter(
			func(candidate: WeaponDef): return String(candidate.content_id) == "weapon/%s" % base_id
		).front()
		definition.content_id = StringName("weapon/%s" % weapon_id)
		definition.display_name_key = StringName("weapon.%s.name" % weapon_id)
		definition.description_key = StringName("weapon.%s.description" % weapon_id)
		definition.tags.assign(source["tags"])
		var tiers: Array[ItemWeapon] = []
		for tier_index in 4:
			var item := base_definition.tiers[tier_index].duplicate(true) as ItemWeapon
			item.stats = base_definition.tiers[tier_index].stats.duplicate(true)
			item.item_name = weapon_id.replace("_", " ").capitalize()
			item.content_id = definition.content_id
			item.stats.damage *= float(source["damage"])
			item.stats.cooldown *= float(source["cooldown"])
			item.stats.max_range *= float(source["range"])
			item.upgrade_to = null
			tiers.append(item)
		for tier_index in 3:
			tiers[tier_index].upgrade_to = tiers[tier_index + 1]
		definition.tiers = tiers
		definition.effects = _weapon_effects(weapon_id, definition.tags)
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
		definition.tags = [&"base_stat"]
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
		definition.tags.assign([&"base_stat"] if result.size() < 16 else [&"synergy"])
		result.append(definition)
		icon_index += 1
	var synergy_names := [
		"close_quarters_manual", "rapid_loader", "sharpshooter_lens", "ember_reservoir",
		"frost_capacitor", "storm_conductor", "turret_gears", "drone_uplink",
		"dash_blades", "blood_vial", "merchant_badge", "fortune_charm",
	]
	var synergy_tags: Array[StringName] = [
		&"melee", &"rapid", &"precise", &"burn", &"slow", &"chain",
		&"building", &"summon", &"dash", &"life_steal", &"economy", &"luck",
	]
	for index in synergy_names.size():
		result.append(_build_generated_passive(
			synergy_names[index], [&"synergy", synergy_tags[index]],
			{"damage": 3.0 + float(index % 3)}, result[index % result.size()].item.item_icon
		))
	var trigger_names := [
		"echo_round", "volatile_core", "cinder_seed", "arc_lens",
		"hunter_mark", "panic_guard", "last_breath", "harvest_bell",
		"salvage_hook", "thorn_mesh", "dash_charge", "battle_rhythm",
	]
	for index in trigger_names.size():
		result.append(_build_trigger_passive(
			trigger_names[index], index, result[index % result.size()].item.item_icon
		))
	var economy_names := [
		"scrap_ledger", "lucky_token", "market_map", "recycler_stamp",
		"golden_seed", "bargain_chip", "prospector_eye", "interest_coil",
	]
	for index in economy_names.size():
		result.append(_build_generated_passive(
			economy_names[index], [&"economy", &"luck"],
			{"luck": 5.0 + index, "harvesting": 2.0 + index}, result[index % result.size()].item.item_icon
		))
	var defense_names := [
		"iron_bark", "medic_patch", "evasion_mesh", "blood_filter",
		"shock_padding", "second_skin", "repair_gel", "guardian_core",
	]
	for index in defense_names.size():
		var modifiers := {"max_health": 2.0 + index}
		if index % 2 == 0:
			modifiers["armor"] = 1.0
		else:
			modifiers["recovery"] = 1.0
		result.append(_build_generated_passive(
			defense_names[index], [&"defense", &"sustain"], modifiers,
			result[index % result.size()].item.item_icon
		))
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
		definition.tags = [&"normal", StringName(enemy_id)]
		result.append(definition)
	result.append(_build_adapted_enemy(
		"xiami", "chaser_mid", 15, 3.0, 180, 2, [&"normal", &"swarm"]
	))
	result.append(_build_adapted_enemy(
		"dapan", "shooter", 10, 2.0, 140, 3, [&"normal", &"ranged"]
	))
	for source: Dictionary in EXTRA_NORMAL_ENEMIES:
		result.append(_build_adapted_enemy(
			str(source["id"]), str(source["base"]), int(source["health"]),
			float(source["damage"]), int(source["speed"]), int(source["gold"]),
			[&"normal", StringName(str(source["role"]))]
		))
	result.append(_build_adapted_enemy(
		"iron_maw", "charger", 420, 8.0, 145, 18, [&"elite", &"charger"]
	))
	result.append(_build_adapted_enemy(
		"volt_stalker", "shooter", 520, 9.0, 155, 22, [&"elite", &"ranged"]
	))
	result.append(_build_adapted_enemy(
		"mouse_dog", "charger", 1000, 5.0, 160, 50, [&"boss"]
	))
	result.append(_build_adapted_enemy(
		"scrap_titan", "charger", 1250, 7.0, 125, 60, [&"boss", &"tank"]
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
		{"swarm_mite": 5.0, "charger": 2.0, "xiami": 2.0, "dapan": 1.0},
		{"chaser_fast": 3.0, "bulwark": 2.0, "shooter": 3.0, "medic_spore": 1.0},
		{"xiami": 3.0, "dapan": 2.0, "flanker": 3.0, "war_drummer": 1.0},
		{"chaser_fast": 2.0, "shellback": 2.0, "scrap_thief": 2.0, "shooter": 2.0},
		{"iron_maw": 1.0, "chaser_slow": 3.0, "shooter": 2.0},
		{"brood_pod": 2.0, "swarm_mite": 4.0, "hazard_weaver": 2.0},
		{"bulwark": 2.0, "flanker": 3.0, "hex_slinger": 2.0, "chaser_mid": 2.0},
		{"blink_rat": 3.0, "scrap_thief": 3.0, "dapan": 2.0, "shellback": 2.0},
		{"hazard_weaver": 3.0, "brood_pod": 2.0, "medic_spore": 2.0, "charger": 2.0},
		{"volt_stalker": 1.0, "flanker": 3.0, "shooter": 2.0},
		{"swarm_mite": 4.0, "war_drummer": 2.0, "shellback": 2.0, "hex_slinger": 2.0},
		{"blink_rat": 3.0, "bulwark": 2.0, "hazard_weaver": 3.0, "dapan": 2.0},
		{"brood_pod": 3.0, "medic_spore": 2.0, "flanker": 3.0, "scrap_thief": 2.0},
		{"shellback": 3.0, "hex_slinger": 3.0, "charger": 2.0, "swarm_mite": 2.0},
		{"mouse_dog": 1.0, "scrap_titan": 1.0, "chaser_slow": 3.0, "shooter": 2.0},
	]
	for index: int in range(20):
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
			spawn.is_boss = enemy_id in ["mouse_dog", "scrap_titan"]
			spawn.is_elite = enemy_id in ["iron_maw", "volt_stalker"]
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
		"scrap_titan":
			return load("res://scenes/unit/enemy/boss/scrap_titan.tscn")
		"iron_maw":
			return load("res://scenes/unit/enemy/enemy_charger.tscn")
		"volt_stalker":
			return load("res://scenes/unit/enemy/enemy_shooter.tscn")
	for source: Dictionary in EXTRA_NORMAL_ENEMIES:
		if str(source["id"]) == enemy_id:
			return load("res://scenes/unit/enemy/enemy_%s.tscn" % str(source["base"]))
	return load("res://scenes/unit/enemy/enemy_%s.tscn" % enemy_id)


func _starter_weapons_for_tags(character_tags: Array[StringName]) -> Array[StringName]:
	var result: Array[StringName] = []
	var all_weapon_ids := Array(WEAPON_PATHS.keys())
	for source: Dictionary in EXTRA_WEAPONS:
		all_weapon_ids.append(str(source["id"]))
	for raw_weapon_id: Variant in all_weapon_ids:
		var weapon_id := str(raw_weapon_id)
		var weapon_tags := _base_weapon_tags(weapon_id)
		for source: Dictionary in EXTRA_WEAPONS:
			if str(source["id"]) == weapon_id:
				weapon_tags.assign(source["tags"])
				break
		if &"balanced" in character_tags or &"power" in character_tags:
			result.append(StringName("core:weapon/%s" % weapon_id))
			continue
		for tag: StringName in character_tags:
			if tag in weapon_tags:
				result.append(StringName("core:weapon/%s" % weapon_id))
				break
	if result.is_empty():
		result = [&"core:weapon/pistol", &"core:weapon/axe"]
	return result


func _base_weapon_tags(weapon_id: String) -> Array[StringName]:
	if weapon_id in ["axe", "chainsaw", "mace", "punch", "sword", "wand"]:
		return [&"melee"]
	return [&"ranged"]


func _weapon_effects(weapon_id: String, weapon_tags: Array[StringName]) -> Array[EffectDef]:
	var operations: Array[EffectOperationDef] = []
	var trigger := GameplayEvent.Type.HIT
	var trigger_tag: StringName = &""
	if &"burn" in weapon_tags:
		operations.append(EffectOperationDef.burn(2.0, 2.5))
		trigger_tag = &"burn"
	elif &"slow" in weapon_tags:
		operations.append(EffectOperationDef.apply_status(&"slow", 1.5))
		trigger_tag = &"slow"
	elif &"chain" in weapon_tags:
		operations.append(EffectOperationDef.chain(2, 180.0))
		trigger_tag = &"chain"
	elif &"explosion" in weapon_tags:
		operations.append(EffectOperationDef.explosion(96.0, 0.55))
		trigger_tag = &"explosion"
	elif &"pierce" in weapon_tags:
		trigger = GameplayEvent.Type.ATTACKED
		operations.append(EffectOperationDef.add_pierce(1))
		trigger_tag = &"pierce"
	elif &"bounce" in weapon_tags:
		trigger = GameplayEvent.Type.ATTACKED
		operations.append(EffectOperationDef.add_bounce(1))
		trigger_tag = &"bounce"
	elif &"building" in weapon_tags:
		trigger = GameplayEvent.Type.WAVE_STARTED
		operations.append(EffectOperationDef.build(&"building/scrap_turret"))
	elif &"summon" in weapon_tags:
		trigger = GameplayEvent.Type.WAVE_STARTED
		operations.append(EffectOperationDef.summon(&"summon/scout_drone"))
	if operations.is_empty():
		return []
	var effect := EffectDef.new()
	effect.effect_id = StringName("effect/weapon/%s" % weapon_id)
	effect.priority = 50
	effect.max_stacks = InventoryState.MAX_WEAPON_SLOTS
	effect.trigger_events = [trigger]
	if not trigger_tag.is_empty():
		effect.conditions = [EffectConditionDef.event_has_tag(trigger_tag)]
	effect.operations = operations
	return [effect]


func _build_generated_passive(
	passive_id: String,
	tags: Array[StringName],
	modifiers: Dictionary,
	icon: Texture2D
) -> PassiveItemDef:
	var definition := PassiveItemDef.new()
	var item := ItemPassive.new()
	item.item_name = passive_id.replace("_", " ").capitalize()
	item.content_id = StringName("passive/%s" % passive_id)
	item.item_icon = icon
	item.item_tier = Global.UpgradeTier.RARE
	item.item_type = ItemBase.ItemType.PASSIVE
	item.item_cost = 28
	item.max_stack = 8
	if not modifiers.is_empty():
		var first_key := str(modifiers.keys().front())
		item.add_stats = first_key
		item.add_value = float(modifiers[first_key])
	definition.content_id = item.content_id
	definition.display_name_key = StringName("passive.%s.name" % passive_id)
	definition.description_key = StringName("passive.%s.description" % passive_id)
	definition.item = item
	definition.stat_modifiers = modifiers.duplicate(true)
	definition.max_stack = item.max_stack
	definition.tags = tags
	return definition


func _build_trigger_passive(passive_id: String, index: int, icon: Texture2D) -> PassiveItemDef:
	var definition := _build_generated_passive(passive_id, [&"trigger"], {}, icon)
	var events := [
		GameplayEvent.Type.HIT, GameplayEvent.Type.CRITICAL_HIT, GameplayEvent.Type.KILLED,
		GameplayEvent.Type.DAMAGED, GameplayEvent.Type.DODGED, GameplayEvent.Type.PICKED_UP,
		GameplayEvent.Type.PURCHASED, GameplayEvent.Type.SHOP_REFRESHED,
		GameplayEvent.Type.DASHED, GameplayEvent.Type.WAVE_STARTED,
		GameplayEvent.Type.WAVE_ENDED, GameplayEvent.Type.ATTACKED,
	]
	var effect := EffectDef.new()
	effect.effect_id = StringName("effect/passive/%s" % passive_id)
	effect.priority = 100 + index
	effect.trigger_events = [events[index]]
	effect.max_stacks = definition.max_stack
	if index % 3 == 0:
		effect.operations = [EffectOperationDef.heal(1.0 + index * 0.15)]
	elif index % 3 == 1 and events[index] in [
		GameplayEvent.Type.HIT,
		GameplayEvent.Type.CRITICAL_HIT,
		GameplayEvent.Type.ATTACKED,
	]:
		effect.operations = [EffectOperationDef.extra_damage(1.0 + index * 0.25)]
	elif index % 3 == 1:
		effect.operations = [EffectOperationDef.heal(1.0 + index * 0.15)]
	else:
		effect.operations = [EffectOperationDef.add_stat(StatId.DAMAGE, 1.0)]
	definition.effects = [effect]
	return definition


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
