class_name FrontendViewModel
extends RefCounted

const POSITIVE_COLOR := "#9ed66f"
const NEGATIVE_COLOR := "#e46d58"
const HIGHLIGHT_COLOR := "#f4d35e"


static func character_name(definition: CharacterDef) -> String:
	return ItemDescriptionFormatter.character_display_name(definition)


static func character_traits(definition: CharacterDef) -> String:
	if definition == null:
		return LocalizedTextService.resolve(&"ui.character.hint")
	var rules := definition.rules
	if rules == null:
		return LocalizedTextService.resolve(&"ui.character.hint")
	var lines: Array[String] = []
	_append_starting_stats(lines, rules.starting_stat_modifiers)
	_append_stat_gain_multipliers(lines, rules.stat_modification_multipliers)
	_append_weapon_rules(lines, rules)
	_append_forced_starting_weapon(lines, definition, rules)
	if rules.starting_material_bonus != 0:
		lines.append(LocalizedTextService.resolve(
			&"ui.character.starting_materials", [
				_positive_or_negative_color(float(rules.starting_material_bonus)),
				rules.starting_material_bonus,
			]
		))
	if rules.weapon_slot_limit != InventoryState.MAX_WEAPON_SLOTS:
		lines.append(LocalizedTextService.resolve(
			&"ui.character.weapon_slots", [
				_multiplier_color(
					float(rules.weapon_slot_limit) / InventoryState.MAX_WEAPON_SLOTS
				),
				rules.weapon_slot_limit,
			]
		))
	if rules.pickup_healing_multiplier != 1.0:
		lines.append(LocalizedTextService.resolve(
			&"ui.character.pickup_healing", [
				_multiplier_color(rules.pickup_healing_multiplier),
				rules.pickup_healing_multiplier,
			]
		))
	if not is_equal_approx(rules.experience_gain_multiplier, 1.0):
		lines.append(LocalizedTextService.resolve(
			&"ui.character.experience_gain", [
				_multiplier_color(rules.experience_gain_multiplier),
				rules.experience_gain_multiplier,
			]
		))
	if rules.dodge_cap_override >= 0.0:
		var default_cap := StatRulesDef.baseline().maximum_dodge_chance * 100.0
		lines.append(LocalizedTextService.resolve(
			&"ui.character.dodge_cap", [
				_positive_or_negative_color(rules.dodge_cap_override - default_cap),
				rules.dodge_cap_override,
			]
		))
	if not is_zero_approx(rules.consumable_healing_bonus):
		lines.append(LocalizedTextService.resolve(
			&"ui.character.consumable_healing_bonus", [
				_positive_or_negative_color(rules.consumable_healing_bonus),
				rules.consumable_healing_bonus,
			]
		))
	if not is_equal_approx(rules.shop_price_multiplier, 1.0):
		lines.append(LocalizedTextService.resolve(
			&"ui.character.shop_price", [
				_multiplier_color(rules.shop_price_multiplier, true),
				rules.shop_price_multiplier,
			]
		))
	if not is_equal_approx(rules.recycle_value_multiplier, 1.0):
		lines.append(LocalizedTextService.resolve(
			&"ui.character.recycle_value", [
				_multiplier_color(rules.recycle_value_multiplier),
				rules.recycle_value_multiplier,
			]
		))
	if rules.materials_reset_on_wave_start:
		lines.append(LocalizedTextService.resolve(
			&"ui.character.materials_reset_on_wave_start", [NEGATIVE_COLOR]
		))
	if rules.dash_charges != 1:
		lines.append(LocalizedTextService.resolve(
			&"ui.character.dash_charges", [
				_positive_or_negative_color(float(rules.dash_charges - 1)),
				rules.dash_charges,
			]
		))
	if not is_equal_approx(rules.dash_cooldown_multiplier, 1.0):
		lines.append(LocalizedTextService.resolve(
			&"ui.character.dash_cooldown", [
				_multiplier_color(rules.dash_cooldown_multiplier, true),
				rules.dash_cooldown_multiplier,
			]
		))
	if not is_equal_approx(rules.dash_duration_multiplier, 1.0):
		lines.append(LocalizedTextService.resolve(
			&"ui.character.dash_duration", [
				_multiplier_color(rules.dash_duration_multiplier),
				rules.dash_duration_multiplier,
			]
		))
	if not rules.shop_bias_tags.is_empty():
		lines.append(LocalizedTextService.resolve(
			&"ui.character.shop_bias", [
				POSITIVE_COLOR,
				_localized_tags(rules.shop_bias_tags),
			]
		))
	return "\n".join(lines) if not lines.is_empty() else LocalizedTextService.resolve(
		&"ui.character.no_modifiers"
	)


static func _append_starting_stats(lines: Array[String], modifiers: Dictionary) -> void:
	var entries: Array[Dictionary] = []
	for raw_stat: Variant in modifiers:
		var stat_id := StatId.from_key(str(raw_stat))
		if StatId.is_valid(stat_id):
			entries.append({"stat_id": stat_id, "value": float(modifiers[raw_stat])})
	entries.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.stat_id) < int(b.stat_id))
	for entry: Dictionary in entries:
		var value := float(entry.value)
		lines.append(LocalizedTextService.resolve(&"ui.character.stat_modifier", [
			_positive_or_negative_color(value),
			value,
			LocalizedTextService.resolve(StringName("stat.%s" % StatId.key(int(entry.stat_id)))),
		]))


static func _append_stat_gain_multipliers(lines: Array[String], multipliers: Dictionary) -> void:
	var entries: Array[Dictionary] = []
	for raw_stat: Variant in multipliers:
		var stat_id := StatId.from_key(str(raw_stat))
		if StatId.is_valid(stat_id):
			entries.append({"stat_id": stat_id, "value": float(multipliers[raw_stat])})
	entries.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.stat_id) < int(b.stat_id))
	for entry: Dictionary in entries:
		var percent := (float(entry.value) - 1.0) * 100.0
		lines.append(LocalizedTextService.resolve(&"ui.character.stat_gain_multiplier", [
			_positive_or_negative_color(percent),
			percent,
			LocalizedTextService.resolve(StringName("stat.%s" % StatId.key(int(entry.stat_id)))),
		]))


static func _append_weapon_rules(lines: Array[String], rules: CharacterRuleDef) -> void:
	if not rules.allowed_weapon_tags.is_empty():
		lines.append(LocalizedTextService.resolve(
			&"ui.character.allowed_weapons", [
				NEGATIVE_COLOR,
				_localized_tags(rules.allowed_weapon_tags),
			]
		))
	if not rules.forbidden_weapon_tags.is_empty():
		lines.append(LocalizedTextService.resolve(
			&"ui.character.forbidden_weapons", [
				NEGATIVE_COLOR,
				_localized_tags(rules.forbidden_weapon_tags),
			]
		))


static func _append_forced_starting_weapon(
	lines: Array[String],
	definition: CharacterDef,
	rules: CharacterRuleDef
) -> void:
	if not bool(rules.runtime_support.get("forced_starting_weapon", false)):
		return
	var names: Array[String] = []
	if Content.catalog != null:
		for weapon_id: StringName in definition.starter_weapon_ids:
			var weapon := Content.catalog.get_weapon(weapon_id)
			if weapon == null or weapon.tiers.is_empty() or weapon.tiers[0] == null:
				continue
			var display_name := weapon_name(weapon.tiers[0])
			if not display_name.is_empty() and display_name not in names:
				names.append(display_name)
	if names.is_empty():
		return
	names.sort()
	lines.append(LocalizedTextService.resolve(
		&"ui.character.forced_starting_weapon", [HIGHLIGHT_COLOR, " / ".join(names)]
	))


static func _localized_tags(tags: Array[StringName]) -> String:
	var names: Array[String] = []
	for tag: StringName in tags:
		names.append(LocalizedTextService.resolve(
			StringName("tag.%s" % String(tag).replace("/", "."))
		))
	names.sort()
	return " / ".join(names)


static func _positive_or_negative_color(delta: float) -> String:
	return POSITIVE_COLOR if delta >= 0.0 else NEGATIVE_COLOR


static func _multiplier_color(value: float, lower_is_better := false) -> String:
	var favorable := value >= 1.0
	if lower_is_better:
		favorable = value <= 1.0
	return POSITIVE_COLOR if favorable else NEGATIVE_COLOR


static func weapon_name(item: ItemWeapon) -> String:
	return ItemDescriptionFormatter.item_display_name(item)


static func weapon_details(item: ItemWeapon, stats: PlayerStats = null) -> String:
	return ItemDescriptionFormatter.format_weapon(item, stats)
