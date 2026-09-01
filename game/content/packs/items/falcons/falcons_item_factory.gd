class_name FalconsItemFactory
extends RefCounted


const PACK_ID: StringName = &"gogobro.falcons.items"
const CATALOG_PATH := "res://game/content/packs/items/falcons/falcons_item_catalog_v1.json"
const ICON_ROOT := "res://game/assets/falcons/items"

const NIKO_CHARACTER_ID: StringName = &"character.niko:character/niko"
const M0NESY_CHARACTER_ID: StringName = &"character.falcons_m0nesy:character/m0nesy"
const KYOUSUKE_CHARACTER_ID: StringName = &"character.falcons_kyousuke:character/kyousuke"
const TESES_CHARACTER_ID: StringName = &"character.falcons_teses:character/teses"
const KARRIGAN_CHARACTER_ID: StringName = &"character.falcons_karrigan:character/karrigan"

const OWNER_CHARACTER_IDS := {
	"niko": NIKO_CHARACTER_ID,
	"m0nesy": M0NESY_CHARACTER_ID,
	"kyousuke": KYOUSUKE_CHARACTER_ID,
	"teses": TESES_CHARACTER_ID,
	"karrigan": KARRIGAN_CHARACTER_ID,
}
const PRICE_BY_TIER := {
	1: 12,
	2: 20,
	3: 30,
	4: 45,
}


static func create_pack() -> GogoContentPackDefinition:
	var pack := GogoContentPackDefinition.new()
	pack.pack_id = PACK_ID
	pack.pack_kind = &"core"
	var catalog := _load_catalog()
	var records: Array = catalog.get("items", []) as Array
	for value: Variant in records:
		if not value is Dictionary:
			push_error("Falcons item catalog contains a non-dictionary record")
			continue
		var definition := _definition_from_record(value as Dictionary)
		if definition != null:
			pack.definitions.append(definition)
	return pack


static func content_id_for_asset(asset_id: String) -> StringName:
	return StringName("gogobro.falcons:item/%s" % asset_id)


static func _load_catalog() -> Dictionary:
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	if file == null:
		push_error("Unable to open Falcons item catalog: %s" % CATALOG_PATH)
		return {}
	var parser := JSON.new()
	var error := parser.parse(file.get_as_text())
	if error != OK:
		push_error(
			"Unable to parse Falcons item catalog at line %d: %s"
			% [parser.get_error_line(), parser.get_error_message()]
		)
		return {}
	if not parser.data is Dictionary:
		push_error("Falcons item catalog root must be a dictionary")
		return {}
	return parser.data as Dictionary


static func _definition_from_record(record: Dictionary) -> GogoItemDefinition:
	var asset_id := String(record.get("id", "")).strip_edges()
	var owner_slug := String(record.get("owner", "")).strip_edges()
	var owner_character_id: StringName = OWNER_CHARACTER_IDS.get(owner_slug, &"")
	if asset_id.is_empty() or owner_character_id.is_empty():
		push_error("Invalid Falcons item record: id=%s owner=%s" % [asset_id, owner_slug])
		return null
	var tier := clampi(int(record.get("tier", 1)), 1, 4)
	var icon_path := "%s/%s.png" % [ICON_ROOT, asset_id]
	var icon := load(icon_path) as Texture2D
	if icon == null:
		push_error("Unable to load Falcons item icon: %s" % icon_path)
		return null

	var definition := GogoItemDefinition.new()
	definition.content_id = content_id_for_asset(asset_id)
	definition.display_name = String(record.get("zh_name", asset_id))
	definition.tags.assign([&"falcons", StringName(owner_slug), &"character_owned"])
	definition.icon_asset_id = StringName(asset_id)
	definition.direct_icon_texture = icon
	definition.tier = tier
	definition.price = int(PRICE_BY_TIER[tier])
	definition.max_count = maxi(int(record.get("max_count", 1)), 1)
	definition.owner_character_ids.assign([owner_character_id])
	definition.stat_modifiers = _stat_modifiers(record.get("stat_modifiers", {}) as Dictionary)
	definition.set_meta(&"description", String(record.get("description", "")))
	definition.set_meta(&"flavor", String(record.get("flavor", "")))
	return definition


static func _stat_modifiers(raw_modifiers: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for raw_key: Variant in raw_modifiers.keys():
		var raw_value: Variant = raw_modifiers[raw_key]
		if not (raw_value is int or raw_value is float):
			push_error("Falcons item stat modifier must be numeric: %s" % String(raw_key))
			continue
		result[StringName(String(raw_key))] = float(raw_value)
	return result
