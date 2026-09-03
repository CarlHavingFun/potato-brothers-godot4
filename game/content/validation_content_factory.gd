class_name ValidationContentFactory
extends RefCounted

const NIKO_CONTENT_FACTORY := preload("res://game/content/packs/characters/niko/niko_content_factory.gd")
const FALCONS_ITEM_FACTORY := preload(
	"res://game/content/packs/items/falcons/falcons_item_factory.gd"
)
const STATIC_PREVIEW_CONTENT_FACTORY := preload(
	"res://game/content/assets/gogobro_static_preview_content_factory.gd"
)
const DRIFTER_TEXTURE := preload("res://game/assets/enemies/drifter.png")
const SPARK_TEXTURE := preload("res://game/assets/enemies/spark.png")
const RAMMER_TEXTURE := preload("res://game/assets/enemies/rammer.png")
const CHARACTER_ID: StringName = &"character.niko:character/niko"
const MELEE_ID: StringName = &"weapon.training_blade:weapon/training_blade"
const RANGED_ID: StringName = &"weapon.training_blaster:weapon/training_blaster"
const DIFFICULTY_ID: StringName = &"gogobro.core:difficulty/standard"
const ZONE_ID: StringName = &"gogobro.core:zone/training_ground"
const ELITE_RAMMER_ID: StringName = &"gogobro.core:enemy/b_site_elite"


static func create_packs(include_development_preview: bool = true) -> Array[GogoContentPackDefinition]:
	var packs: Array[GogoContentPackDefinition] = [
		_core_pack(),
		_weapon_pack(MELEE_ID, true),
		_weapon_pack(RANGED_ID, false),
		NIKO_CONTENT_FACTORY.create_pack(),
		FALCONS_ITEM_FACTORY.create_pack(),
	]
	# Stable gogobro.preview:* IDs are now part of the release content surface.
	# The flag controls only the debug candidate tag/overlay, never definition presence.
	packs.append(STATIC_PREVIEW_CONTENT_FACTORY.create_pack(include_development_preview))
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
		[&"gogobro.core:enemy/drifter", "游荡体", GogoEnemyDefinition.Role.CHASER, 7.0, 82.0, 2.0, 3, 1, false, DRIFTER_TEXTURE],
		[&"gogobro.core:enemy/spark", "火花体", GogoEnemyDefinition.Role.SHOOTER, 10.0, 65.0, 2.0, 4, 1, false, SPARK_TEXTURE],
		[&"gogobro.core:enemy/rammer", "冲撞体", GogoEnemyDefinition.Role.CHARGER, 16.0, 110.0, 3.0, 5, 2, false, RAMMER_TEXTURE],
		[ELITE_RAMMER_ID, "B 点突破精英", GogoEnemyDefinition.Role.CHARGER, 45.0, 96.0, 5.0, 12, 2, true, RAMMER_TEXTURE],
	]
	for spec in enemy_specs:
		var enemy := GogoEnemyDefinition.new()
		enemy.content_id = spec[0]
		enemy.display_name = spec[1]
		enemy.role = spec[2]
		enemy.max_health = spec[3]
		enemy.movement_speed = spec[4]
		enemy.touch_damage = spec[5]
		enemy.xp_value = spec[6]
		enemy.material_value = spec[7]
		enemy.is_boss = spec[8]
		enemy.visual_texture = spec[9]
		pack.definitions.append(enemy)
	var item_asset_ids := [
		&"ballistic_liner",
		&"silent_step_insoles",
		&"crosshair_shim",
		&"supply_radar",
		&"trade_guard",
		&"tactical_med_patch",
	]
	var item_descriptions := [
		"一块可塞进战术背心的硬质防弹插板。",
		"一双吸震凝胶战术鞋垫，能压低落脚声。",
		"用于微调瞄具高度的金属校准垫片。",
		"带折叠天线和绿屏的手持补给雷达。",
		"带厚衬垫的战术前臂护具。",
		"装在密封小袋里的止血急救贴。",
	]
	var item_flavors := [
		"边角满是跳弹擦痕，中心仍牢牢护住胸口。",
		"塞进跑鞋后，B点木门也听不见脚步。",
		"薄得像贴纸，却能把偏掉的瞄线扶正。",
		"亮点出现时，总有人先喊“我的箱子”。",
		"它替补枪手挡住门框，也挡住第一颗流弹。",
		"撕开、按住，再回去补那一枪。",
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
		item.display_name = ["防弹内衬", "静步鞋垫", "准星校片", "补给雷达", "补枪护腕", "战术急救贴"][index]
		item.icon_asset_id = item_asset_ids[index]
		item.price = 10 + index * 2
		item.set_meta(&"description", item_descriptions[index])
		item.set_meta(&"flavor", item_flavors[index])
		var item_stats := [&"max_health", &"movement_speed", &"damage_multiplier", &"pickup_range", &"armor", &"health_regen"]
		item.stat_modifiers[item_stats[index]] = [2.0, 18.0, 0.08, 24.0, 1.0, 0.6][index]
		pack.definitions.append(item)
		var upgrade := GogoUpgradeDefinition.new()
		upgrade.content_id = StringName("gogobro.core:upgrade/training_%d" % (index + 1))
		upgrade.display_name = ["重甲头盔", "轻量战术靴", "爆头靶纸", "经济局硬币弹匣", "凯夫拉插板组", "医疗针"][index]
		upgrade.icon_asset_id = upgrade_asset_ids[index]
		upgrade.stat_modifiers = item.stat_modifiers.duplicate(true)
		pack.definitions.append(upgrade)
	var additional_upgrade_specs: Array[Dictionary] = [
		{
			"id": &"gogobro.core:upgrade/economy_readout",
			"title": "经济训练",
			"icon": &"economy_sense",
			"modifiers": {&"economy": 8.0},
		},
		{
			"id": &"gogobro.core:upgrade/reticle_breathing",
			"title": "暴击训练",
			"icon": &"pre_aim_drills",
			"modifiers": {&"critical_chance": 0.05},
		},
		{
			"id": &"gogobro.core:upgrade/firing_cadence",
			"title": "射击节奏",
			"icon": &"pre_aim_drills",
			"modifiers": {&"attack_speed_multiplier": 0.08},
		},
		{
			"id": &"gogobro.core:upgrade/ranged_drill",
			"title": "远程训练",
			"icon": &"pre_aim_drills",
			"modifiers": {&"ranged_damage": 1.0},
		},
		{
			"id": &"gogobro.core:upgrade/melee_drill",
			"title": "近战训练",
			"icon": &"trade_step_drills",
			"modifiers": {&"melee_damage": 1.0},
		},
		{
			"id": &"gogobro.core:upgrade/range_gauge",
			"title": "射程训练",
			"icon": &"pre_aim_drills",
			"modifiers": {&"attack_range_bonus": 24.0},
		},
		{
			"id": &"gogobro.core:upgrade/evasive_peek",
			"title": "闪避训练",
			"icon": &"trade_step_drills",
			"modifiers": {&"dodge": 0.04},
		},
		{
			"id": &"gogobro.core:upgrade/counter_strafe_drill",
			"title": "急停训练",
			"icon": &"trade_step_drills",
			"modifiers": {&"counter_strafe_brake": 25.0},
		},
		{
			"id": &"gogobro.core:upgrade/running_recoil_control",
			"title": "跑打控枪",
			"icon": &"pre_aim_drills",
			"modifiers": {&"moving_recoil_control": 15.0},
		},
		{
			"id": &"gogobro.core:upgrade/field_sutures",
			"title": "战地恢复",
			"icon": &"medical_timeout",
			"modifiers": {&"health_regen": 1.0},
		},
		{
			"id": &"gogobro.core:upgrade/breacher_plate",
			"title": "突破防护",
			"icon": &"kevlar_reinforcement",
			"modifiers": {&"max_health": 1.0, &"armor": 1.0},
		},
		{
			"id": &"gogobro.core:upgrade/scavenge_route",
			"title": "回收路线",
			"icon": &"trade_step_drills",
			"modifiers": {&"movement_speed_multiplier": 0.04, &"pickup_range": 12.0},
		},
	]
	for spec: Dictionary in additional_upgrade_specs:
		var upgrade := GogoUpgradeDefinition.new()
		upgrade.content_id = StringName(spec["id"])
		upgrade.display_name = String(spec["title"])
		upgrade.icon_asset_id = StringName(spec["icon"])
		upgrade.stat_modifiers = (spec["modifiers"] as Dictionary).duplicate(true)
		pack.definitions.append(upgrade)
	var zone := GogoZoneDefinition.new()
	zone.content_id = ZONE_ID
	zone.display_name = "训练场"
	zone.icon_asset_id = &"zone_thumbnail"
	var wave_specs := [
		{
			"number": 1,
			"duration": 20.0,
			"groups": [
				{"enemy_id": &"gogobro.core:enemy/drifter", "count": 28, "batch_size": 4, "interval_seconds": 3.0, "start": 1.0, "end": 19.1, "phase": &"warmup"},
			],
		},
		{
			"number": 2,
			"duration": 25.0,
			"groups": [
				{"enemy_id": &"gogobro.core:enemy/drifter", "count": 32, "batch_size": 4, "interval_seconds": 3.0, "start": 1.0, "end": 22.1, "phase": &"baseline"},
				{"enemy_id": &"gogobro.core:enemy/spark", "count": 12, "batch_size": 4, "interval_seconds": 5.0, "start": 10.0, "end": 20.1, "phase": &"ranged_pressure"},
			],
		},
		{
			"number": 3,
			"duration": 30.0,
			"groups": [
				{"enemy_id": &"gogobro.core:enemy/drifter", "count": 50, "batch_size": 5, "interval_seconds": 3.0, "start": 1.0, "end": 28.1, "phase": &"baseline"},
				{"enemy_id": &"gogobro.core:enemy/spark", "count": 16, "batch_size": 4, "interval_seconds": 6.0, "start": 10.0, "end": 28.1, "phase": &"ranged_pressure"},
				{"enemy_id": &"gogobro.core:enemy/rammer", "count": 2, "start": 18.0, "end": 28.0, "phase": &"charge_preview"},
			],
		},
		{
			"number": 4,
			"duration": 35.0,
			"groups": [
				{"enemy_id": &"gogobro.core:enemy/drifter", "count": 60, "batch_size": 5, "interval_seconds": 3.0, "start": 1.0, "end": 34.1, "phase": &"baseline"},
				{"enemy_id": &"gogobro.core:enemy/spark", "count": 20, "batch_size": 4, "interval_seconds": 6.0, "start": 8.0, "end": 32.1, "phase": &"ranged_pressure"},
				{"enemy_id": &"gogobro.core:enemy/rammer", "count": 5, "start": 13.0, "end": 33.0, "phase": &"charge_pressure"},
			],
		},
		{
			"number": 5,
			"duration": 40.0,
			"groups": [
				{"enemy_id": &"gogobro.core:enemy/drifter", "count": 70, "batch_size": 5, "interval_seconds": 2.8, "start": 1.0, "end": 37.5, "phase": &"baseline"},
				{"enemy_id": &"gogobro.core:enemy/spark", "count": 24, "batch_size": 4, "interval_seconds": 5.5, "start": 8.0, "end": 35.6, "phase": &"ranged_pressure"},
				{"enemy_id": &"gogobro.core:enemy/rammer", "count": 10, "batch_size": 2, "interval_seconds": 5.0, "start": 13.0, "end": 33.1, "phase": &"charge_pressure"},
				{"enemy_id": ELITE_RAMMER_ID, "count": 1, "start": 29.0, "end": 29.1, "phase": &"boss_event", "event": &"b_site_push"},
			],
		},
	]
	# Provisional post-calibration curve: duration, drifters, sparks, rammers, elites.
	# W1–5 above remain the Task3 baseline. Counts are scheduled, not simultaneous.
	var late_specs := [
		[42, 76, 28, 12, 1], [44, 82, 28, 14, 2], [46, 88, 32, 16, 2],
		[48, 94, 32, 18, 3], [50, 100, 36, 20, 3], [52, 106, 36, 24, 4],
		[54, 112, 40, 26, 4], [56, 118, 40, 28, 5], [58, 124, 44, 32, 5],
		[60, 130, 44, 34, 6], [60, 136, 48, 38, 6], [60, 142, 48, 40, 7],
		[60, 148, 52, 44, 7], [60, 154, 56, 48, 8], [60, 160, 60, 52, 8],
	]
	for index in late_specs.size():
		var spec: Array = late_specs[index]
		var duration := float(spec[0])
		wave_specs.append({
			"number": index + 6, "duration": duration,
			"groups": [
				{"enemy_id": &"gogobro.core:enemy/drifter", "count": spec[1], "start": 1.0, "end": duration - 1.0, "phase": &"baseline"},
				{"enemy_id": &"gogobro.core:enemy/spark", "count": spec[2], "start": 6.0, "end": duration - 1.0, "phase": &"ranged_pressure"},
				{"enemy_id": &"gogobro.core:enemy/rammer", "count": spec[3], "start": 10.0, "end": duration - 1.0, "phase": &"charge_pressure"},
				{"enemy_id": ELITE_RAMMER_ID, "count": spec[4], "start": duration * 0.55, "end": duration - 2.0, "phase": &"late_elites"},
			],
		})
	for raw_wave: Dictionary in wave_specs:
		var wave_number := int(raw_wave.get("number", 1))
		var wave := GogoWaveDefinition.new()
		wave.content_id = StringName("gogobro.core:wave/training_%d" % wave_number)
		wave.display_name = "第 %d 波" % wave_number
		wave.wave_number = wave_number
		wave.duration_seconds = float(raw_wave.get("duration", 15.0))
		var pressure_step := maxi(wave_number - 5, 0)
		wave.enemy_health_multiplier = 1.0 + 0.10 * pressure_step
		wave.enemy_damage_multiplier = 1.0 + 0.05 * pressure_step
		wave.enemy_speed_multiplier = 1.0 + 0.01 * pressure_step
		for group: Dictionary in raw_wave.get("groups", []):
			wave.spawn_groups.append(group.duplicate(true))
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
	weapon.set_meta(
		&"description",
		"一把配重灵活的训练蝴蝶刀。"
		if melee
		else "一把用于经济局和近距离自卫的制式手枪。"
	)
	weapon.set_meta(
		&"flavor",
		"翻腕出刀，近身那一步要比犹豫更快。"
		if melee
		else "经济局的第一声枪响，通常从这里开始。"
	)
	pack.definitions.append(weapon)
	return pack
