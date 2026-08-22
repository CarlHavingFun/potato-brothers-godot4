class_name ValidationContentFactory
extends RefCounted

const CHARACTER_ID: StringName = &"character.placeholder:character/runner"
const MELEE_ID: StringName = &"weapon.training_blade:weapon/training_blade"
const RANGED_ID: StringName = &"weapon.training_blaster:weapon/training_blaster"
const DIFFICULTY_ID: StringName = &"gogobro.core:difficulty/standard"
const ZONE_ID: StringName = &"gogobro.core:zone/training_ground"


static func create_packs() -> Array[GogoContentPackDefinition]:
	return [_core_pack(), _character_pack(), _weapon_pack(MELEE_ID, true), _weapon_pack(RANGED_ID, false)]


static func _core_pack() -> GogoContentPackDefinition:
	var pack := GogoContentPackDefinition.new()
	pack.pack_id = &"gogobro.core"
	pack.pack_kind = &"core"
	var difficulty := GogoDifficultyDefinition.new()
	difficulty.content_id = DIFFICULTY_ID
	difficulty.display_name = "标准"
	pack.definitions.append(difficulty)
	var enemy_specs := [
		[&"gogobro.core:enemy/drifter", "游荡体", GogoEnemyDefinition.Role.CHASER, 7.0, 82.0],
		[&"gogobro.core:enemy/spark", "火花体", GogoEnemyDefinition.Role.SHOOTER, 10.0, 65.0],
		[&"gogobro.core:enemy/rammer", "冲撞体", GogoEnemyDefinition.Role.CHARGER, 16.0, 110.0],
	]
	for spec in enemy_specs:
		var enemy := GogoEnemyDefinition.new()
		enemy.content_id = spec[0]
		enemy.display_name = spec[1]
		enemy.role = spec[2]
		enemy.max_health = spec[3]
		enemy.movement_speed = spec[4]
		pack.definitions.append(enemy)
	for index in 6:
		var item := GogoItemDefinition.new()
		item.content_id = StringName("gogobro.core:item/training_%d" % (index + 1))
		item.display_name = ["坚果壳", "轻鞋", "磨刀石", "采集袋", "护腕", "急救贴"][index]
		item.price = 10 + index * 2
		var item_stats := [&"max_health", &"movement_speed", &"damage_multiplier", &"pickup_range", &"armor", &"health_regen"]
		item.stat_modifiers[item_stats[index]] = [2.0, 18.0, 0.08, 24.0, 1.0, 0.6][index]
		pack.definitions.append(item)
		var upgrade := GogoUpgradeDefinition.new()
		upgrade.content_id = StringName("gogobro.core:upgrade/training_%d" % (index + 1))
		upgrade.display_name = ["体魄", "步伐", "力量", "磁力", "护甲", "恢复"][index]
		upgrade.stat_modifiers = item.stat_modifiers.duplicate(true)
		pack.definitions.append(upgrade)
	var zone := GogoZoneDefinition.new()
	zone.content_id = ZONE_ID
	zone.display_name = "训练场"
	for wave_number in range(1, 6):
		var wave := GogoWaveDefinition.new()
		wave.content_id = StringName("gogobro.core:wave/training_%d" % wave_number)
		wave.display_name = "第 %d 波" % wave_number
		wave.wave_number = wave_number
		wave.duration_seconds = 12.0
		wave.spawn_groups.append({
			"enemy_id": &"gogobro.core:enemy/drifter",
			"count": 3 + wave_number * 2,
			"start": 0.0,
			"end": 10.0,
		})
		if wave_number >= 2:
			wave.spawn_groups.append({"enemy_id": &"gogobro.core:enemy/spark", "count": wave_number, "start": 2.0, "end": 10.0})
		if wave_number >= 4:
			wave.spawn_groups.append({"enemy_id": &"gogobro.core:enemy/rammer", "count": wave_number - 2, "start": 4.0, "end": 11.0})
		zone.wave_ids.append(wave.content_id)
		pack.definitions.append(wave)
	pack.definitions.append(zone)
	return pack


static func _character_pack() -> GogoContentPackDefinition:
	var pack := GogoContentPackDefinition.new()
	pack.pack_id = &"character.placeholder"
	pack.pack_kind = &"character"
	var character := CharacterDefinition.new()
	character.content_id = CHARACTER_ID
	character.display_name = "占位跑者"
	character.base_stats = {
		&"max_health": 20.0,
		&"movement_speed": 235.0,
		&"damage_multiplier": 1.0,
		&"attack_speed": 1.0,
		&"armor": 0.0,
		&"dodge": 0.0,
		&"pickup_range": 115.0,
		&"health_regen": 0.0,
	}
	pack.definitions.append(character)
	return pack


static func _weapon_pack(id: StringName, melee: bool) -> GogoContentPackDefinition:
	var pack := GogoContentPackDefinition.new()
	pack.pack_id = &"weapon.training_blade" if melee else &"weapon.training_blaster"
	pack.pack_kind = &"weapon"
	var weapon := GogoWeaponDefinition.new()
	weapon.content_id = id
	weapon.display_name = "训练短刃" if melee else "训练发射器"
	weapon.mode = GogoWeaponDefinition.Mode.MELEE if melee else GogoWeaponDefinition.Mode.RANGED
	weapon.damage = 7.0 if melee else 4.0
	weapon.cooldown_seconds = 0.55 if melee else 0.42
	weapon.attack_range = 92.0 if melee else 520.0
	weapon.projectile_speed = 620.0
	weapon.knockback = 46.0 if melee else 22.0
	weapon.tags.append(&"melee" if melee else &"ranged")
	pack.definitions.append(weapon)
	return pack
