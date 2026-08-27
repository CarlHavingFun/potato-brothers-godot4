class_name GogoStaticPreviewContentFactory
extends RefCounted

const CONTENT_PATH := "res://game/content/assets/gogobro_static_preview_content_v1.json"
const REGISTRY_PATH := "res://game/content/assets/gogobro_static_assets_v1.json"
const SMOKE_SHELL_HELMET_FACTORY := preload(
	"res://game/content/packs/items/smoke_shell_helmet/smoke_shell_helmet_preview_factory.gd"
)
const SCHEMA_VERSION := "gogobro-static-preview-content-v1"
const PACK_ID: StringName = &"gogobro.preview"
const EXISTING_ITEM_ASSET_IDS := {
	"ballistic_liner": true,
	"silent_step_insoles": true,
	"crosshair_shim": true,
	"supply_radar": true,
	"trade_guard": true,
	"tactical_med_patch": true,
}
const RARITY_TIER := {
	"common": 1,
	"uncommon": 2,
	"rare": 3,
	"legendary": 4,
}
const EFFECT_MAP := {
	"max_health": [&"max_health", 1.0],
	"move_speed_pct": [&"movement_speed_multiplier", 0.01],
	"damage_pct": [&"damage_multiplier", 0.01],
	"economy": [&"economy", 1.0],
	"armor": [&"armor", 1.0],
	"regeneration": [&"health_regen", 1.0],
	"explosion_damage_pct": [&"explosion_damage_multiplier", 0.01],
	"melee_damage": [&"melee_damage", 1.0],
	"ranged_damage": [&"ranged_damage", 1.0],
	"critical_chance": [&"critical_chance", 0.01],
	"dodge": [&"dodge", 0.01],
	"range": [&"attack_range_bonus", 1.0],
	"attack_speed_pct": [&"attack_speed_multiplier", 0.01],
}
const WEAPON_MODES := {
	"melee": GogoWeaponDefinition.Mode.MELEE,
	"ranged": GogoWeaponDefinition.Mode.RANGED,
}


static func create_pack(mark_candidate_preview: bool = true) -> GogoContentPackDefinition:
	var pack := GogoContentPackDefinition.new()
	pack.pack_id = PACK_ID
	pack.pack_kind = &"weapon"
	var content := _load_json(CONTENT_PATH)
	var registry := _load_json(REGISTRY_PATH)
	if String(content.get("schema_version", "")) != SCHEMA_VERSION:
		return pack
	for raw_weapon: Variant in content.get("weapons", []):
		if raw_weapon is Dictionary:
			var weapon := _weapon_definition(raw_weapon as Dictionary, mark_candidate_preview)
			if weapon != null:
				pack.definitions.append(weapon)
	for raw_unit: Variant in registry.get("units", []):
		if not raw_unit is Dictionary:
			continue
		var unit := raw_unit as Dictionary
		if String(unit.get("category", "")) != "item":
			continue
		var asset_id := String(unit.get("asset_id", ""))
		if EXISTING_ITEM_ASSET_IDS.has(asset_id):
			continue
		pack.definitions.append(_item_definition(unit, mark_candidate_preview))
	return pack


static func _weapon_definition(raw: Dictionary, mark_candidate_preview: bool) -> GogoWeaponDefinition:
	var asset_id := String(raw.get("asset_id", ""))
	var mode_name := String(raw.get("mode", ""))
	if asset_id.is_empty() or not WEAPON_MODES.has(mode_name):
		return null
	var definition := GogoWeaponDefinition.new()
	definition.content_id = StringName("gogobro.preview:weapon/%s" % asset_id)
	definition.display_name = String(raw.get("name", asset_id))
	definition.icon_asset_id = StringName(asset_id)
	definition.mode = int(WEAPON_MODES[mode_name]) as GogoWeaponDefinition.Mode
	definition.damage = float(raw.get("damage", 1.0))
	definition.cooldown_seconds = float(raw.get("cooldown", 1.0))
	definition.attack_range = float(raw.get("range", 120.0))
	definition.projectile_speed = float(raw.get("projectile_speed", 520.0))
	definition.knockback = float(raw.get("knockback", 0.0))
	definition.price = int(raw.get("price", 12))
	definition.feedback_profile_id = StringName(String(raw.get("profile", "rifle")))
	definition.damage_kind = &"melee" if definition.mode == GogoWeaponDefinition.Mode.MELEE else &"ballistic"
	definition.impact_kind = StringName(String(raw.get("impact_kind", "normal")))
	definition.tags = [&"melee" if definition.mode == GogoWeaponDefinition.Mode.MELEE else &"ranged"]
	if mark_candidate_preview:
		definition.tags.append(&"candidate_preview")
	return definition


static func _item_definition(unit: Dictionary, mark_candidate_preview: bool) -> GogoItemDefinition:
	var asset_id := String(unit.get("asset_id", ""))
	var localization := unit.get("localization", {}) as Dictionary
	var chinese := localization.get("zh_CN", {}) as Dictionary
	var definition := GogoItemDefinition.new()
	definition.content_id = StringName("gogobro.preview:item/%s" % asset_id)
	definition.display_name = String(chinese.get("name", asset_id))
	definition.icon_asset_id = StringName(asset_id)
	definition.tier = int(RARITY_TIER.get(String(unit.get("rarity", "common")), 1))
	definition.price = [0, 12, 20, 30, 45][definition.tier]
	var max_count_variant: Variant = unit.get("max_count")
	if max_count_variant is int or max_count_variant is float:
		definition.max_count = maxi(int(max_count_variant), 1)
	definition.stat_modifiers = _literal_stat_modifiers(unit.get("effects", []))
	if mark_candidate_preview:
		definition.tags = [&"candidate_preview"]
	if asset_id == "smoke_shell_helmet":
		SMOKE_SHELL_HELMET_FACTORY.configure_item(definition)
	return definition


static func _literal_stat_modifiers(effects: Variant) -> Dictionary:
	var result: Dictionary = {}
	if not effects is Array:
		return result
	for raw_effect: Variant in effects as Array:
		if not raw_effect is Dictionary:
			continue
		var effect := raw_effect as Dictionary
		if not effect.has("operation") or not effect.has("value"):
			continue
		var operation := String(effect.get("operation", ""))
		if not EFFECT_MAP.has(operation):
			continue
		var mapping := EFFECT_MAP[operation] as Array
		var key := mapping[0] as StringName
		var amount := float(effect.get("value", 0.0)) * float(mapping[1])
		result[key] = float(result.get(key, 0.0)) + amount
	return result


static func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if parsed is Dictionary else {}
