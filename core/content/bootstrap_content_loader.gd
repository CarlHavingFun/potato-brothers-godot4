class_name BootstrapContentLoader
extends Node


const DEFAULT_MANIFEST_PATH := "res://content_packs/default/pack.tres"
const DEFAULT_PACK_FILENAME := "default_content.pck"
const OPTIONAL_CHARACTER_PATHS: Array[String] = [
	"res://content_packs/default/assets/sprites/players/niko_v3/character_niko_v3.tres",
]


var catalog := ContentCatalog.new()
var last_errors := PackedStringArray()


func _init() -> void:
	var result := OK
	if ResourceLoader.exists(DEFAULT_MANIFEST_PATH):
		result = load_manifest(DEFAULT_MANIFEST_PATH, DEFAULT_MANIFEST_PATH.get_base_dir())
	else:
		result = mount_and_load(default_export_pack_path())
	if result != OK:
		push_error("Default content pack failed to load: %s" % "\n".join(last_errors))


func load_manifest(manifest_path: String, source_root := "") -> int:
	last_errors.clear()
	if not ResourceLoader.exists(manifest_path):
		last_errors.append("content manifest not found: %s" % manifest_path)
		return ERR_FILE_NOT_FOUND

	var resource := ResourceLoader.load(manifest_path, "ContentPackDef", ResourceLoader.CACHE_MODE_REPLACE)
	if not resource is ContentPackDef:
		last_errors.append("content manifest is not a ContentPackDef: %s" % manifest_path)
		return ERR_INVALID_DATA

	var runtime_pack := resource as ContentPackDef
	if manifest_path == DEFAULT_MANIFEST_PATH:
		runtime_pack = _with_optional_characters(runtime_pack)

	var validator := ContentValidator.new()
	last_errors = validator.validate_pack(runtime_pack, source_root)
	if not last_errors.is_empty():
		return ERR_INVALID_DATA

	var candidate_catalog := ContentCatalog.new()
	var result := candidate_catalog.register_pack(runtime_pack)
	if result != OK:
		last_errors.append("content catalog registration failed: %s" % error_string(result))
		return result
	catalog = candidate_catalog
	_register_translations(runtime_pack)
	return OK


func _with_optional_characters(source: ContentPackDef) -> ContentPackDef:
	var result := source.duplicate(false) as ContentPackDef
	result.characters = source.characters.duplicate()
	var known_ids := {}
	for character: CharacterDef in result.characters:
		if character != null:
			known_ids[character.content_id] = true
	for path: String in OPTIONAL_CHARACTER_PATHS:
		if not ResourceLoader.exists(path):
			continue
		var character := ResourceLoader.load(
			path, "CharacterDef", ResourceLoader.CACHE_MODE_REPLACE
		) as CharacterDef
		if character == null or character.content_id.is_empty() or known_ids.has(character.content_id):
			continue
		result.characters.append(character)
		known_ids[character.content_id] = true
	return result


func _register_translations(pack: ContentPackDef) -> void:
	for translation_path: String in pack.translation_paths:
		if not ResourceLoader.exists(translation_path):
			push_warning("Content translation not found: %s" % translation_path)
			continue
		var translation := load(translation_path) as Translation
		if translation != null:
			TranslationServer.add_translation(translation)


func mount_and_load(pack_path: String, manifest_path := DEFAULT_MANIFEST_PATH) -> int:
	last_errors.clear()
	if not FileAccess.file_exists(pack_path):
		last_errors.append("content pack not found: %s" % pack_path)
		return ERR_FILE_NOT_FOUND
	if not ProjectSettings.load_resource_pack(pack_path, false):
		last_errors.append("content pack could not be mounted: %s" % pack_path)
		return ERR_CANT_OPEN
	return load_manifest(manifest_path)


func default_export_pack_path() -> String:
	return OS.get_executable_path().get_base_dir().path_join(DEFAULT_PACK_FILENAME)
