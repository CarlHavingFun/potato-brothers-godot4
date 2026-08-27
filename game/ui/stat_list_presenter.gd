class_name GogoStatListPresenter
extends RefCounted


const POSITIVE_COLOR := Color("72d572")
const NEGATIVE_COLOR := Color("ef6a67")
const NEUTRAL_COLOR := Color("f3edd7")
const STAT_SPECS := [
	[&"max_health", "MaxHealth", "最大生命", &"number"],
	[&"health_regen", "HealthRegen", "生命恢复", &"number"],
	[&"damage_multiplier", "DamageMultiplier", "伤害", &"ratio_percent"],
	[&"melee_damage", "MeleeDamage", "近战伤害", &"number"],
	[&"ranged_damage", "RangedDamage", "远程伤害", &"number"],
	[&"attack_speed", "AttackSpeed", "攻击速度", &"multiplier"],
	[&"attack_speed_multiplier", "AttackSpeedMultiplier", "攻击速度加成", &"delta_percent"],
	[&"critical_chance", "CriticalChance", "暴击率", &"ratio_percent"],
	[&"attack_range_bonus", "AttackRange", "射程", &"number"],
	[&"armor", "Armor", "护甲", &"number"],
	[&"dodge", "Dodge", "闪避", &"ratio_percent"],
	[&"movement_speed", "MovementSpeed", "移动速度", &"number"],
	[&"movement_speed_multiplier", "MovementSpeedMultiplier", "移动速度加成", &"delta_percent"],
	[&"pickup_range", "PickupRange", "拾取范围", &"number"],
	[&"economy", "Economy", "经济", &"number"],
	[&"explosion_damage_multiplier", "ExplosionDamage", "爆炸伤害", &"delta_percent"],
]


static func build(
	player: SessionPlayerState,
	_content: ContentSnapshot,
	layout_variant: StringName = &"default"
) -> VBoxContainer:
	var values: Dictionary = {}
	if player != null:
		values = player.final_stats if not player.final_stats.is_empty() else player.base_stats
	var visible_stat_count := 0
	for spec: Array in STAT_SPECS:
		if values.has(spec[0] as StringName):
			visible_stat_count += 1
	var compact := layout_variant == &"shop_compact" and visible_stat_count > 12
	var list := VBoxContainer.new()
	list.name = "StatList"
	list.add_theme_constant_override(&"separation", 1 if compact else 4)
	if player == null:
		return list
	for spec: Array in STAT_SPECS:
		var key := spec[0] as StringName
		if not values.has(key):
			continue
		var row := HBoxContainer.new()
		row.name = String(spec[1])
		row.custom_minimum_size = Vector2(220, 20 if compact else 24)
		row.add_theme_constant_override(&"separation", 8 if compact else 12)
		var name_label := Label.new()
		name_label.name = "Name"
		name_label.text = String(spec[2])
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.add_theme_font_size_override(&"font_size", 14 if compact else 17)
		name_label.add_theme_color_override(&"font_color", Color("c9c3b1"))
		row.add_child(name_label)
		var value_label := Label.new()
		value_label.name = "Value"
		value_label.text = _format_value(float(values[key]), spec[3] as StringName)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value_label.custom_minimum_size.x = 68 if compact else 76
		value_label.add_theme_font_size_override(&"font_size", 14 if compact else 17)
		var base_value := _baseline_value(key, player.base_stats)
		value_label.add_theme_color_override(
			&"font_color",
			_delta_color(float(values[key]), base_value)
		)
		row.add_child(value_label)
		list.add_child(row)
	return list


static func _format_value(value: float, format_kind: StringName) -> String:
	match format_kind:
		&"ratio_percent":
			return "%s%%" % _number(value * 100.0)
		&"delta_percent":
			return "%s%s%%" % ["+" if value > 0.0 else "", _number(value * 100.0)]
		&"multiplier":
			return "%.2f×" % value
		_:
			return _number(value)


static func _number(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return "%.1f" % value


static func _delta_color(value: float, base_value: float) -> Color:
	if value > base_value + 0.0001:
		return POSITIVE_COLOR
	if value < base_value - 0.0001:
		return NEGATIVE_COLOR
	return NEUTRAL_COLOR


static func _baseline_value(key: StringName, base_stats: Dictionary) -> float:
	if base_stats.has(key):
		return float(base_stats[key])
	if key == &"damage_multiplier" or key == &"attack_speed":
		return 1.0
	return 0.0
