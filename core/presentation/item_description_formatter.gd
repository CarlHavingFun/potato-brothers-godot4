class_name ItemDescriptionFormatter
extends RefCounted


const POSITIVE_COLOR := "#9ed66f"
const NEGATIVE_COLOR := "#e46d58"
const ACCENT_COLOR := "#f4d35e"
const TAG_COLOR := "#d4a5ff"


static func item_display_name(item: ItemBase) -> String:
	if item == null:
		return ""
	var definition := Content.catalog.get_item_definition(item)
	if definition != null and not definition.display_name_key.is_empty():
		return LocalizedTextService.resolve(
			definition.display_name_key, [], item.item_name
		)
	return _safe_content_fallback(item.item_name, true)


static func character_display_name(definition: CharacterDef) -> String:
	if definition == null or definition.stats == null:
		return ""
	if not definition.display_name_key.is_empty():
		return LocalizedTextService.resolve(
			definition.display_name_key, [], definition.stats.name
		)
	return _safe_content_fallback(definition.stats.name, true)


static func definition_display_name(definition: ContentDef, english_fallback := "") -> String:
	if definition == null:
		return ""
	if not definition.display_name_key.is_empty():
		return LocalizedTextService.resolve(definition.display_name_key, [], english_fallback)
	return _safe_content_fallback(english_fallback, true)


static func item_type_display_name(item_type: int) -> String:
	match item_type:
		ItemBase.ItemType.WEAPON:
			return LocalizedTextService.resolve(&"item_type.weapon", [], "Weapon")
		ItemBase.ItemType.UPGRADE:
			return LocalizedTextService.resolve(&"item_type.upgrade", [], "Upgrade")
		ItemBase.ItemType.PASSIVE:
			return LocalizedTextService.resolve(&"item_type.passive", [], "Passive Item")
	return ""


static func upgrade_display_name(item: ItemUpgrade) -> String:
	if item == null:
		return ""
	var definition := Content.catalog.get_upgrade_definition_for_item(item)
	if definition == null or not StatId.is_valid(definition.stat_id):
		return _safe_content_fallback(item.item_name, true)
	var quality_keys: Array[StringName] = [
		&"quality.common", &"quality.rare", &"quality.epic", &"quality.legendary",
	]
	var quality_key := quality_keys[clampi(definition.quality, 0, quality_keys.size() - 1)]
	return LocalizedTextService.resolve(&"ui.upgrade.name", [
		LocalizedTextService.resolve(quality_key),
		LocalizedTextService.resolve(StringName("stat.%s" % StatId.key(definition.stat_id))),
	])


static func format_item(item: ItemBase, player_stats: PlayerStats = null) -> String:
	if item == null:
		return ""
	if item is ItemWeapon:
		return format_weapon(item as ItemWeapon, player_stats)
	if item is ItemPassive:
		return format_passive(item as ItemPassive)
	if item is ItemUpgrade:
		return format_upgrade(item as ItemUpgrade)
	return LocalizedTextService.resolve(&"ui.item.no_description")


static func format_weapon(item: ItemWeapon, player_stats: PlayerStats = null) -> String:
	if item == null or item.stats == null:
		return LocalizedTextService.resolve(&"ui.item.no_description")
	var stats := item.stats
	var resolved_damage := stats.damage
	var resolved_cooldown := stats.cooldown
	var resolved_range := stats.max_range
	var resolved_crit := stats.crit_chance
	var active_stats := player_stats
	if active_stats == null and Global.current_run != null:
		active_stats = Global.current_run.player_stats
	if active_stats != null and Global.combat_resolver != null:
		var coefficients: Dictionary = stats.scaling_coefficients
		resolved_damage = Global.combat_resolver.weapon_damage_with_coefficients(
			stats.damage,
			active_stats,
			coefficients if not coefficients.is_empty() else {_scaling_stat_id(item): 1.0},
			stats.is_engineering_structure
		)
		resolved_cooldown = Global.combat_resolver.attack_cooldown(stats.cooldown, active_stats)
		resolved_range = Global.combat_resolver.attack_range(stats.max_range, active_stats)
		resolved_crit = Global.combat_resolver.critical_chance(stats.crit_chance, active_stats)
	var definition := Content.catalog.get_item_definition(item)
	var lines: Array[String] = [LocalizedTextService.resolve(
		&"ui.item.weapon_values",
		[
			resolved_damage,
			resolved_cooldown,
			resolved_crit * 100.0,
			stats.crit_damage,
			resolved_range,
			stats.knockback,
		]
	)]
	_append_content_description(lines, definition)
	_append_effects(lines, definition)
	_append_tags(lines, definition)
	return "\n".join(lines)


static func format_passive(item: ItemPassive) -> String:
	if item == null:
		return ""
	var definition := Content.catalog.get_passive_definition_for_item(item)
	var lines: Array[String] = []
	if definition != null:
		var modifiers: Array[Dictionary] = []
		for raw_stat: Variant in definition.stat_modifiers:
			var stat_id := StatId.from_key(str(raw_stat))
			if StatId.is_valid(stat_id):
				modifiers.append({
					"id": stat_id,
					"value": float(definition.stat_modifiers[raw_stat]),
				})
		modifiers.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.id) < int(b.id))
		for modifier: Dictionary in modifiers:
			lines.append(_stat_line(int(modifier.id), float(modifier.value)))
		_append_content_description(lines, definition)
		_append_effects(lines, definition)
		_append_tags(lines, definition)
	if lines.is_empty():
		return LocalizedTextService.resolve(&"ui.item.no_description")
	return "\n".join(lines)


static func format_upgrade(item: ItemUpgrade) -> String:
	if item == null:
		return ""
	var definition := Content.catalog.get_upgrade_definition_for_item(item)
	if definition != null and StatId.is_valid(definition.stat_id):
		return _stat_line(definition.stat_id, definition.value)
	return LocalizedTextService.resolve(&"ui.item.no_description")


static func tags_text(item: ItemBase) -> String:
	if item == null:
		return ""
	var names: Array[String] = []
	for tag: StringName in Content.catalog.get_tags_for_item(item):
		names.append(LocalizedTextService.resolve(
			StringName("tag.%s" % String(tag).replace("/", "."))
		))
	return " / ".join(names)


static func _append_content_description(lines: Array[String], definition: ContentDef) -> void:
	if (
		definition != null
		and not definition.description_key.is_empty()
		and LocalizedTextService.has_message(definition.description_key)
	):
		lines.append(LocalizedTextService.resolve(definition.description_key))


static func _append_effects(lines: Array[String], definition: ContentDef) -> void:
	if definition == null:
		return
	for effect: EffectDef in definition.effects:
		var effect_line := _format_effect(effect)
		if not effect_line.is_empty():
			lines.append(effect_line)


static func _format_effect(effect: EffectDef) -> String:
	if effect == null:
		return ""
	var event_names: Array[String] = []
	for event_type: int in effect.trigger_events:
		var event_name := _event_name(event_type)
		if not event_name.is_empty():
			event_names.append(event_name)
	if event_names.is_empty():
		return ""
	var operation_names: Array[String] = []
	for operation: EffectOperationDef in effect.operations:
		var operation_name := _operation_name(operation)
		if not operation_name.is_empty():
			operation_names.append(operation_name)
	if operation_names.is_empty():
		return ""
	var trigger := LocalizedTextService.resolve(&"ui.effect.trigger", [
		LocalizedTextService.resolve(&"ui.effect.event_separator").join(event_names),
	])
	var condition_names: Array[String] = []
	for condition: EffectConditionDef in effect.conditions:
		var condition_name := _condition_name(condition)
		if not condition_name.is_empty():
			condition_names.append(condition_name)
	if not condition_names.is_empty():
		trigger = LocalizedTextService.resolve(&"ui.effect.trigger_with_conditions", [
			trigger,
			LocalizedTextService.resolve(&"ui.effect.condition_separator").join(condition_names),
		])
	return LocalizedTextService.resolve(&"ui.effect.rule", [
		ACCENT_COLOR,
		trigger,
		LocalizedTextService.resolve(&"ui.effect.operation_separator").join(operation_names),
	])


static func _event_name(event_type: int) -> String:
	var key := &""
	match event_type:
		GameplayEvent.Type.RUN_STARTED:
			key = &"ui.effect.event.run_started"
		GameplayEvent.Type.WAVE_STARTED:
			key = &"ui.effect.event.wave_started"
		GameplayEvent.Type.WAVE_ENDED:
			key = &"ui.effect.event.wave_ended"
		GameplayEvent.Type.ATTACKED:
			key = &"ui.effect.event.attacked"
		GameplayEvent.Type.HIT:
			key = &"ui.effect.event.hit"
		GameplayEvent.Type.CRITICAL_HIT:
			key = &"ui.effect.event.critical_hit"
		GameplayEvent.Type.KILLED:
			key = &"ui.effect.event.killed"
		GameplayEvent.Type.DAMAGED:
			key = &"ui.effect.event.damaged"
		GameplayEvent.Type.DODGED:
			key = &"ui.effect.event.dodged"
		GameplayEvent.Type.PICKED_UP:
			key = &"ui.effect.event.picked_up"
		GameplayEvent.Type.PURCHASED:
			key = &"ui.effect.event.purchased"
		GameplayEvent.Type.SHOP_REFRESHED:
			key = &"ui.effect.event.shop_refreshed"
		GameplayEvent.Type.DASHED:
			key = &"ui.effect.event.dashed"
	return LocalizedTextService.resolve(key) if not key.is_empty() else ""


static func _operation_name(operation: EffectOperationDef) -> String:
	if operation == null:
		return ""
	match operation.kind:
		EffectOperationDef.Kind.ADD_STAT:
			if not StatId.is_valid(operation.stat_id):
				return ""
			return LocalizedTextService.resolve(&"ui.effect.operation.add_stat", [
				_number(operation.amount),
				LocalizedTextService.resolve(StringName("stat.%s" % StatId.key(operation.stat_id))),
			])
		EffectOperationDef.Kind.HEAL:
			return LocalizedTextService.resolve(
				&"ui.effect.operation.heal", [_number(operation.amount)]
			)
		EffectOperationDef.Kind.EXTRA_DAMAGE:
			return LocalizedTextService.resolve(
				&"ui.effect.operation.extra_damage", [_number(operation.amount)]
			)
		EffectOperationDef.Kind.APPLY_STATUS:
			return LocalizedTextService.resolve(&"ui.effect.operation.apply_status", [
				maxi(1, operation.count), _number(maxf(0.0, operation.duration)),
			])
		EffectOperationDef.Kind.ADD_PIERCE:
			return LocalizedTextService.resolve(
				&"ui.effect.operation.add_pierce", [maxi(0, operation.count)]
			)
		EffectOperationDef.Kind.ADD_BOUNCE:
			return LocalizedTextService.resolve(
				&"ui.effect.operation.add_bounce", [maxi(0, operation.count)]
			)
		EffectOperationDef.Kind.EXPLOSION:
			return LocalizedTextService.resolve(&"ui.effect.operation.explosion", [
				_number(maxf(0.0, operation.radius)),
				_number(maxf(0.0, operation.scale) * 100.0),
			])
		EffectOperationDef.Kind.BURN:
			return LocalizedTextService.resolve(&"ui.effect.operation.burn", [
				maxi(1, operation.count),
				_number(operation.amount),
				_number(maxf(0.0, operation.duration)),
			])
		EffectOperationDef.Kind.CHAIN:
			return LocalizedTextService.resolve(&"ui.effect.operation.chain", [
				maxi(0, operation.count), _number(maxf(0.0, operation.radius)),
			])
		EffectOperationDef.Kind.SPAWN_PROJECTILE:
			return LocalizedTextService.resolve(
				&"ui.effect.operation.spawn_projectile", [maxi(1, operation.count)]
			)
		EffectOperationDef.Kind.SUMMON:
			return LocalizedTextService.resolve(
				&"ui.effect.operation.summon", [maxi(1, operation.count)]
			)
		EffectOperationDef.Kind.BUILD:
			return LocalizedTextService.resolve(
				&"ui.effect.operation.build", [maxi(1, operation.count)]
			)
		EffectOperationDef.Kind.EMIT_EVENT:
			return LocalizedTextService.resolve(&"ui.effect.operation.emit_event")
	return ""


static func _condition_name(condition: EffectConditionDef) -> String:
	if condition == null or condition.kind == EffectConditionDef.Kind.ALWAYS:
		return ""
	var result := ""
	match condition.kind:
		EffectConditionDef.Kind.EVENT_HAS_TAG:
			result = LocalizedTextService.resolve(
				&"ui.effect.condition.event_tag", [_tag_name(condition.tag)]
			)
		EffectConditionDef.Kind.SOURCE_HAS_TAG:
			result = LocalizedTextService.resolve(
				&"ui.effect.condition.source_tag", [_tag_name(condition.tag)]
			)
		EffectConditionDef.Kind.TARGET_HAS_TAG:
			result = LocalizedTextService.resolve(
				&"ui.effect.condition.target_tag", [_tag_name(condition.tag)]
			)
		EffectConditionDef.Kind.VALUE_AT_LEAST:
			result = LocalizedTextService.resolve(
				&"ui.effect.condition.value_at_least", [_number(condition.threshold)]
			)
		EffectConditionDef.Kind.CHANCE:
			result = LocalizedTextService.resolve(
				&"ui.effect.condition.chance", [_number(clampf(condition.chance, 0.0, 1.0) * 100.0)]
			)
	if result.is_empty():
		return ""
	return LocalizedTextService.resolve(&"ui.effect.condition.inverted", [result]) \
		if condition.inverted else result


static func _tag_name(tag: StringName) -> String:
	var key := StringName("tag.%s" % String(tag).replace("/", "."))
	if LocalizedTextService.has_message(key):
		return LocalizedTextService.resolve(key)
	return LocalizedTextService.resolve(&"ui.effect.condition.unknown_tag")


static func _number(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return ("%.2f" % value).trim_suffix("0").trim_suffix(".")


static func _append_tags(lines: Array[String], definition: ContentDef) -> void:
	if definition == null or definition.tags.is_empty():
		return
	var names: Array[String] = []
	for tag: StringName in definition.tags:
		names.append(LocalizedTextService.resolve(
			StringName("tag.%s" % String(tag).replace("/", "."))
		))
	lines.append(LocalizedTextService.resolve(&"ui.item.tags", [" / ".join(names)]))


static func _stat_line(stat_id: int, value: float) -> String:
	var stat_name := LocalizedTextService.resolve(
		StringName("stat.%s" % StatId.key(stat_id))
	)
	var color := POSITIVE_COLOR if value >= 0.0 else NEGATIVE_COLOR
	return LocalizedTextService.resolve(
		&"ui.item.stat_line",
		[color, value, stat_name]
	)


static func _scaling_stat_id(item: ItemWeapon) -> int:
	var stable_id := String(Content.catalog.get_item_stable_id(item))
	if stable_id.contains("wand") or &"elemental" in Content.catalog.get_tags_for_item(item):
		return StatId.ELEMENTAL_DAMAGE
	return StatId.RANGED_DAMAGE if item.type == ItemWeapon.WeaponType.RANGE else StatId.MELEE_DAMAGE


static func _safe_content_fallback(english_fallback: String, name: bool) -> String:
	if TranslationServer.get_locale().begins_with("zh"):
		return (
			LocalizedTextService.DEFAULT_ZH_MISSING_NAME
			if name
			else LocalizedTextService.DEFAULT_ZH_MISSING_DESCRIPTION
		)
	return english_fallback if not english_fallback.is_empty() else (
		"Unnamed content" if name else "No description"
	)
