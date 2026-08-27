class_name ValidationContentFactory
extends RefCounted

const NIKO_CONTENT_FACTORY := preload("res://game/content/packs/characters/niko/niko_content_factory.gd")
const STATIC_PREVIEW_CONTENT_FACTORY := preload(
	"res://game/content/assets/gogobro_static_preview_content_factory.gd"
)
const CHARACTER_ID: StringName = &"character.niko:character/niko"
const MELEE_ID: StringName = &"weapon.training_blade:weapon/training_blade"
const RANGED_ID: StringName = &"weapon.training_blaster:weapon/training_blaster"
const DIFFICULTY_ID: StringName = &"gogobro.core:difficulty/standard"
const ZONE_ID: StringName = &"gogobro.core:zone/training_ground"


static func create_packs(include_development_preview: bool = true) -> Array[GogoContentPackDefinition]:
	var packs: Array[GogoContentPackDefinition] = [
		_core_pack(),
		_weapon_pack(MELEE_ID, true),
		_weapon_pack(RANGED_ID, false),
		NIKO_CONTENT_FACTORY.create_pack(),
	]
	if include_development_preview:
		packs.append(STATIC_PREVIEW_CONTENT_FACTORY.create_pack())
	return packs


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
	var item_asset_ids := [
		&"ballistic_liner",
		&"silent_step_insoles",
		&"crosshair_shim",
		&"supply_radar",
		&"trade_guard",
		&"tactical_med_patch",
	]
	var upgrade_asset_ids := [
		&"one_more_round",
		&"trade_step_drills",
		&"pre_aim_drills",
		&"economy_sense",
		&"kevlar_reinforcement",
		&"medical_timeout",
	]
	for index in 6:
		var item := GogoItemDefinition.new()
		item.content_id = StringName("gogobro.core:item/training_%d" % (index + 1))
		item.display_name = ["防弹内衬", "轻鞋", "磨刀石", "采集袋", "护腕", "急救贴"][index]
		item.icon_asset_id = item_asset_ids[index]
		item.price = 10 + index * 2
		var item_stats := [&"max_health", &"movement_speed", &"damage_multiplier", &"pickup_range", &"armor", &"health_regen"]
		item.stat_modifiers[item_stats[index]] = [2.0, 18.0, 0.08, 24.0, 1.0, 0.6][index]
		pack.definitions.append(item)
		var upgrade := GogoUpgradeDefinition.new()
		upgrade.content_id = StringName("gogobro.core:upgrade/training_%d" % (index + 1))
		upgrade.display_name = ["多活一回合", "步伐", "力量", "磁力", "护甲", "恢复"][index]
		upgrade.icon_asset_id = upgrade_asset_ids[index]
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


static func _weapon_pack(id: StringName, melee: bool) -> GogoContentPackDefinition:
	var pack := GogoContentPackDefinition.new()
	pack.pack_id = &"weapon.training_blade" if melee else &"weapon.training_blaster"
	pack.pack_kind = &"weapon"
	var weapon := GogoWeaponDefinition.new()
	weapon.content_id = id
	weapon.display_name = "蝴蝶刀" if melee else "Glock-18"
	weapon.icon_asset_id = &"warmup_shiv" if melee else &"service_pistol"
	weapon.mode = GogoWeaponDefinition.Mode.MELEE if melee else GogoWeaponDefinition.Mode.RANGED
	weapon.damage = 7.0 if melee else 4.0
	weapon.cooldown_seconds = 0.55 if melee else 0.42
	weapon.attack_range = 92.0 if melee else 520.0
	weapon.projectile_speed = 620.0
	weapon.knockback = 46.0 if melee else 22.0
	weapon.feedback_profile_id = &"heavy" if melee else &"rifle"
	weapon.damage_kind = &"melee" if melee else &"ballistic"
	weapon.impact_kind = &"normal"
	weapon.tags.append(&"melee" if melee else &"ranged")
	pack.definitions.append(weapon)
	return pack
