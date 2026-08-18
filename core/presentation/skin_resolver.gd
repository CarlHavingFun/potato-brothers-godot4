class_name SkinResolver
extends Node


signal skin_loaded(skin_id: StringName)

const DEFAULT_MANIFEST_PATH := "res://content_packs/skins/dev_placeholder/skin.tres"

var active_skin: SkinPackDef
var manifest_path := ""
var notices := PackedStringArray()


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
	_register_translations(active_skin)
	skin_loaded.emit(active_skin.skin_id)
	return OK


func resolve_path(category: StringName, presentation_id: StringName) -> String:
	if active_skin == null:
		return ""
	var path := active_skin.asset_path(category, presentation_id)
	if path.is_empty():
		notices.append("missing presentation asset: %s/%s" % [category, presentation_id])
	return path


func resolve_resource(
	category: StringName,
	presentation_id: StringName,
	mechanical_fallback: Resource = null
) -> Resource:
	if active_skin != null:
		var table: Variant = active_skin.asset_tables.get(category, {})
		if table is Dictionary:
			var exact_path := str(table.get(presentation_id, table.get(String(presentation_id), "")))
			if not exact_path.is_empty() and ResourceLoader.exists(exact_path):
				return load(exact_path)
		var skin_fallback_path := resolve_path(category, presentation_id)
		if not skin_fallback_path.is_empty():
			return load(skin_fallback_path)
	return mechanical_fallback


func resolve_texture(
	category: StringName,
	presentation_id: StringName,
	mechanical_fallback: Texture2D = null
) -> Texture2D:
	return resolve_resource(category, presentation_id, mechanical_fallback) as Texture2D


func resolve_scene(
	category: StringName,
	presentation_id: StringName,
	mechanical_fallback: PackedScene = null
) -> PackedScene:
	return resolve_resource(category, presentation_id, mechanical_fallback) as PackedScene


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
