class_name SkinResolver
extends Node


signal skin_loaded(skin_id: StringName)

const DEFAULT_MANIFEST_PATH := "res://content_packs/skins/dev_placeholder/skin.tres"
const ASSET_MANIFEST_FILE := "asset_manifest.json"
const LOGICAL_ANCHOR_SUFFIX := "_logical"

var active_skin: SkinPackDef
var manifest_path := ""
var notices := PackedStringArray()
var _logical_anchor_tables: Dictionary = {}


func _ready() -> void:
	if active_skin == null:
		load_manifest(str(ProjectSettings.get_setting(
			"presentation/skin_manifest", DEFAULT_MANIFEST_PATH
		)))


func load_manifest(path: String) -> int:
	notices.clear()
	if not ResourceLoader.exists(path):
		notices.append("skin manifest not found: %s" % path)
		return ERR_FILE_NOT_FOUND
	# Validate the attached script after loading; exported binary resources do
	# not advertise script class names as native ResourceLoader type hints.
	var candidate := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
	if not candidate is SkinPackDef:
		notices.append("skin manifest is not a SkinPackDef: %s" % path)
		return ERR_INVALID_DATA
	var errors := (candidate as SkinPackDef).validate()
	if not errors.is_empty():
		notices.append_array(errors)
		return ERR_INVALID_DATA
	# ResourceLoader may update `candidate` in place when any tooling reloads the
	# same manifest with CACHE_MODE_REPLACE. The running presentation must own a
	# deep copy so a background validation/import cannot change the active skin.
	active_skin = (candidate as SkinPackDef).duplicate(true) as SkinPackDef
	manifest_path = path
	_load_logical_anchor_manifest(path.get_base_dir().path_join(ASSET_MANIFEST_FILE))
	_register_translations(active_skin)
	skin_loaded.emit(active_skin.skin_id)
	return OK


func resolve_path(
	category: StringName,
	presentation_id: StringName,
	variant: StringName = &""
) -> String:
	if active_skin == null:
		return ""
	var path := active_skin.asset_path(category, presentation_id, variant)
	if path.is_empty():
		var qualified := SkinPackDef.qualified_category(category, variant)
		notices.append("missing presentation asset: %s/%s" % [qualified, presentation_id])
	return path


func resolve_resource(
	category: StringName,
	presentation_id: StringName,
	mechanical_fallback: Resource = null,
	variant: StringName = &""
) -> Resource:
	if active_skin != null:
		var skin_fallback_path := resolve_path(category, presentation_id, variant)
		if not skin_fallback_path.is_empty():
			return load(skin_fallback_path)
	return mechanical_fallback


func resolve_texture(
	category: StringName,
	presentation_id: StringName,
	mechanical_fallback: Texture2D = null,
	variant: StringName = &""
) -> Texture2D:
	return resolve_resource(category, presentation_id, mechanical_fallback, variant) as Texture2D


func resolve_scene(
	category: StringName,
	presentation_id: StringName,
	mechanical_fallback: PackedScene = null,
	variant: StringName = &""
) -> PackedScene:
	return resolve_resource(category, presentation_id, mechanical_fallback, variant) as PackedScene


func resolve_content_texture(
	definition: ContentDef,
	mechanical_fallback: Texture2D = null,
	variant: StringName = &"icon",
	pack_id: StringName = &""
) -> Texture2D:
	if definition == null:
		return mechanical_fallback
	var category := category_for_content(definition)
	if category.is_empty():
		return mechanical_fallback
	return resolve_texture(
		category,
		definition.get_presentation_id(pack_id),
		mechanical_fallback,
		variant
	)


## Returns the position anchors declared by the skin's optional
## asset_manifest.json. Keys omit the schema's `_logical` suffix (for example,
## `pivot`, `muzzle`, `throw_origin`), and values remain in the logical 64x64
## coordinate space. Missing manifests and entries intentionally return `{}`.
func resolve_logical_anchors(
	category: StringName,
	presentation_id: StringName,
	variant: StringName = &""
) -> Dictionary:
	var qualified := SkinPackDef.qualified_category(category, variant)
	var category_table: Variant = _logical_anchor_tables.get(
		qualified, _logical_anchor_tables.get(String(qualified), {})
	)
	if category_table is not Dictionary:
		return {}
	var anchors: Variant = (category_table as Dictionary).get(
		presentation_id,
		(category_table as Dictionary).get(String(presentation_id), {})
	)
	return (anchors as Dictionary).duplicate(true) if anchors is Dictionary else {}


## Resolves one logical-64 anchor. `anchor_name` accepts either `muzzle` or the
## manifest spelling `muzzle_logical`. Null is returned when no valid anchor is
## available so callers can retain their scene-authored fallback.
func resolve_logical_anchor(
	category: StringName,
	presentation_id: StringName,
	anchor_name: StringName,
	variant: StringName = &""
) -> Variant:
	var normalized_name := String(anchor_name).trim_suffix(LOGICAL_ANCHOR_SUFFIX)
	return resolve_logical_anchors(category, presentation_id, variant).get(
		StringName(normalized_name), null
	)


static func category_for_content(definition: ContentDef) -> StringName:
	if definition is CharacterDef:
		return &"character"
	if definition is WeaponDef:
		return &"weapon"
	if definition is PassiveItemDef:
		return &"passive"
	if definition is UpgradeDef:
		return &"upgrade"
	if definition is EnemyDef:
		return &"enemy"
	if definition is WaveDef:
		return &"scene"
	return &""


func resolve_cue(cue_id: StringName) -> Dictionary:
	return active_skin.cue_definition(cue_id) if active_skin != null else {}


func resolve_music(track_id: StringName) -> AudioStream:
	if active_skin == null:
		return null
	var path := active_skin.music_path(track_id)
	return load(path) as AudioStream if not path.is_empty() else null


func resolve_animation_map(category: StringName, presentation_id: StringName) -> Dictionary:
	if active_skin == null:
		return {}
	var category_map: Variant = active_skin.animation_maps.get(
		category, active_skin.animation_maps.get(String(category), {})
	)
	if category_map is not Dictionary:
		return {}
	var mappings := category_map as Dictionary
	var exact: Variant = mappings.get(presentation_id, mappings.get(String(presentation_id), null))
	if exact is Dictionary:
		return (exact as Dictionary).duplicate(true)
	var fallback: Variant = mappings.get(&"default", mappings.get("default", null))
	return (fallback as Dictionary).duplicate(true) if fallback is Dictionary else {}


func _load_logical_anchor_manifest(path: String) -> void:
	_logical_anchor_tables.clear()
	if not FileAccess.file_exists(path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is not Dictionary:
		notices.append("invalid skin asset manifest: %s" % path)
		return
	var raw_assets: Variant = (parsed as Dictionary).get("assets", [])
	if raw_assets is not Array:
		notices.append("invalid skin asset list: %s" % path)
		return
	for raw_entry: Variant in raw_assets:
		if raw_entry is not Dictionary:
			continue
		_index_logical_anchor_entry(raw_entry as Dictionary)


func _index_logical_anchor_entry(entry: Dictionary) -> void:
	var presentation_id := StringName(str(entry.get("presentation_id", "")).strip_edges())
	var raw_anchors: Variant = entry.get("anchors", {})
	if presentation_id.is_empty() or raw_anchors is not Dictionary:
		return
	var anchor_metadata := raw_anchors as Dictionary
	if str(anchor_metadata.get("coordinate_space", "")) != "logical_64":
		return
	var anchors: Dictionary = {}
	for raw_key: Variant in anchor_metadata:
		var schema_key := str(raw_key)
		if not schema_key.ends_with(LOGICAL_ANCHOR_SUFFIX):
			continue
		var raw_position: Variant = anchor_metadata[raw_key]
		if raw_position is not Array or (raw_position as Array).size() != 2:
			continue
		var position_values := raw_position as Array
		if position_values[0] is not float and position_values[0] is not int:
			continue
		if position_values[1] is not float and position_values[1] is not int:
			continue
		anchors[StringName(schema_key.trim_suffix(LOGICAL_ANCHOR_SUFFIX))] = Vector2(
			float(position_values[0]), float(position_values[1])
		)
	var raw_world_scale: Variant = anchor_metadata.get("world_scale", null)
	if raw_world_scale is float or raw_world_scale is int:
		anchors[&"world_scale"] = float(raw_world_scale)
	var raw_mount_position: Variant = anchor_metadata.get("mount_position_world", null)
	if raw_mount_position is Array and (raw_mount_position as Array).size() == 2:
		var mount_values := raw_mount_position as Array
		if (
			(mount_values[0] is float or mount_values[0] is int)
			and (mount_values[1] is float or mount_values[1] is int)
		):
			anchors[&"mount_position"] = Vector2(
				float(mount_values[0]), float(mount_values[1])
			)
	if anchors.is_empty():
		return
	var raw_uses: Variant = entry.get("uses", [])
	if raw_uses is not Array:
		return
	for raw_use: Variant in raw_uses:
		var qualified := _qualified_category_from_manifest_use(str(raw_use))
		if qualified.is_empty():
			continue
		if not _logical_anchor_tables.has(qualified):
			_logical_anchor_tables[qualified] = {}
		var category_table := _logical_anchor_tables[qualified] as Dictionary
		category_table[presentation_id] = anchors.duplicate(true)


static func _qualified_category_from_manifest_use(use_id: String) -> StringName:
	var separator := use_id.find(".")
	if separator <= 0 or separator >= use_id.length() - 1:
		return StringName(use_id.strip_edges())
	return StringName("%s/%s" % [
		use_id.left(separator).strip_edges(),
		use_id.substr(separator + 1).strip_edges(),
	])


func _register_translations(skin: SkinPackDef) -> void:
	# Only the resolver mounted as the active presentation service may change
	# process-wide visible copy. Validators and comparison tests use detached
	# resolver instances and must not leak their skin into the live UI.
	if not is_inside_tree():
		return
	LocalizedTextService.configure_skin_paths(skin.translation_paths)
	for path: String in skin.translation_paths:
		if ResourceLoader.exists(path):
			var translation := load(path) as Translation
			if translation != null:
				TranslationServer.add_translation(translation)
