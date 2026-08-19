class_name BootstrapContentLoader
extends Node


const DEFAULT_MANIFEST_PATH := "res://content_packs/default/pack.tres"
const DEFAULT_PACK_FILENAME := "default_content.pck"
const EXPECTED_DEFAULT_WEAPON_COUNT := 24
const EXPECTED_DEFAULT_PASSIVE_COUNT := 60
const EXPECTED_DEFAULT_UPGRADE_COUNT := 64
const DEFAULT_CONTENT_READY_MARKER := (
	"MECHANICS_CONTENT_READY weapons=24 passives=60 upgrades=64 presentation_icons=0"
)
const OPTIONAL_CHARACTER_PATHS: Array[String] = [
	"res://content_packs/default/assets/sprites/players/niko_v3/character_niko_v3.tres",
]


var catalog := ContentCatalog.new()
var active_balance_pack: BalancePackDef
var last_errors := PackedStringArray()
var _translation_paths: Array[String] = []


func _init() -> void:
	var result := OK
	if ResourceLoader.exists(DEFAULT_MANIFEST_PATH):
		result = load_manifest(DEFAULT_MANIFEST_PATH, DEFAULT_MANIFEST_PATH.get_base_dir())
	else:
		result = mount_and_load(default_export_pack_path())
	if result != OK:
		push_error("Default content pack failed to load: %s" % "\n".join(last_errors))


func _ready() -> void:
	_apply_registered_translations()


func load_manifest(manifest_path: String, source_root := "") -> int:
	last_errors.clear()
	if not ResourceLoader.exists(manifest_path):
		last_errors.append("content manifest not found: %s" % manifest_path)
		return ERR_FILE_NOT_FOUND

	# Exported .tres files are remapped to binary resources. A class_name string
	# is not a native runtime type hint, so validate the script type after load.
	var resource := ResourceLoader.load(manifest_path, "", ResourceLoader.CACHE_MODE_REPLACE)
	if not resource is ContentPackDef:
		last_errors.append("content manifest is not a ContentPackDef: %s" % manifest_path)
		return ERR_INVALID_DATA

	# Runtime catalogs must not keep ResourceLoader's cached manifest objects.
	# Tests, import tools, and optional pack validation may reload a manifest with
	# CACHE_MODE_REPLACE; sharing those instances would silently revert the live
	# balance overlay midway through a run. Own a deep runtime copy instead.
	var runtime_pack := (resource as ContentPackDef).duplicate(true) as ContentPackDef
	if manifest_path == DEFAULT_MANIFEST_PATH:
		runtime_pack = _with_optional_characters(runtime_pack)

	var validator := ContentValidator.new()
	last_errors = validator.validate_pack(runtime_pack, source_root)
	var candidate_balance_pack: BalancePackDef
	if manifest_path == DEFAULT_MANIFEST_PATH:
		last_errors.append_array(_validate_default_mechanics_contract(runtime_pack))
		candidate_balance_pack = BalanceProfileRegistry.load_active(runtime_pack)
		last_errors.append_array(
			validator.validate_balance_parity(runtime_pack, candidate_balance_pack)
		)
	if not last_errors.is_empty():
		return ERR_INVALID_DATA

	var candidate_catalog := ContentCatalog.new()
	var result := candidate_catalog.register_pack(runtime_pack, candidate_balance_pack)
	if result != OK:
		last_errors.append("content catalog registration failed: %s" % error_string(result))
		return result
	catalog = candidate_catalog
	active_balance_pack = candidate_balance_pack
	_register_translations(runtime_pack)
	if manifest_path == DEFAULT_MANIFEST_PATH:
		print(DEFAULT_CONTENT_READY_MARKER)
	return OK


func _validate_default_mechanics_contract(pack: ContentPackDef) -> PackedStringArray:
	var errors := PackedStringArray()
	if pack.weapons.size() != EXPECTED_DEFAULT_WEAPON_COUNT:
		errors.append(
			"default mechanics must contain %d weapons" % EXPECTED_DEFAULT_WEAPON_COUNT
		)
	if pack.passives.size() != EXPECTED_DEFAULT_PASSIVE_COUNT:
		errors.append(
			"default mechanics must contain %d passives" % EXPECTED_DEFAULT_PASSIVE_COUNT
		)
	if pack.upgrades.size() != EXPECTED_DEFAULT_UPGRADE_COUNT:
		errors.append(
			"default mechanics must contain %d upgrades" % EXPECTED_DEFAULT_UPGRADE_COUNT
		)
	for definition: WeaponDef in pack.weapons:
		if definition == null:
			continue
		if definition.tiers.size() != 4:
			errors.append(
				"default weapon %s must contain four tiers" % definition.content_id
			)
		for item: ItemWeapon in definition.tiers:
			if item != null and item.item_icon != null:
				errors.append(
					"default weapon %s embeds presentation art" % definition.content_id
				)
	for definition: PassiveItemDef in pack.passives:
		if definition != null and definition.item != null \
				and definition.item.item_icon != null:
			errors.append(
				"default passive %s embeds presentation art" % definition.content_id
			)
	for definition: UpgradeDef in pack.upgrades:
		if definition != null and definition.item != null \
				and definition.item.item_icon != null:
			errors.append(
				"default upgrade %s embeds presentation art" % definition.content_id
			)
	return errors


func _with_optional_characters(
	source: ContentPackDef,
	optional_paths: Array[String] = OPTIONAL_CHARACTER_PATHS
) -> ContentPackDef:
	var result := source.duplicate(false) as ContentPackDef
	result.characters = source.characters.duplicate()
	var known_ids := {}
	for character: CharacterDef in result.characters:
		if character != null:
			known_ids[character.content_id] = true
	for path: String in optional_paths:
		if not ResourceLoader.exists(path):
			continue
		var cached_character := ResourceLoader.load(
			path, "", ResourceLoader.CACHE_MODE_REPLACE
		) as CharacterDef
		if (
			cached_character == null
			or cached_character.content_id.is_empty()
			or known_ids.has(cached_character.content_id)
		):
			continue
		# Optional resources are reloaded with CACHE_MODE_REPLACE by import tools.
		# Never expose that cached instance to the active runtime catalog: a later
		# reload of the same path mutates the cached object in place.
		var character := cached_character.duplicate(true) as CharacterDef
		result.characters.append(character)
		known_ids[character.content_id] = true
	return result


func _register_translations(pack: ContentPackDef) -> void:
	_translation_paths.assign(pack.translation_paths)
	# The autoload performs its initial manifest load from `_init`, before it is
	# inside the tree. Defer the process-wide registration to `_ready`; detached
	# validation/import loaders never reach that callback and cannot clobber it.
	if not is_inside_tree():
		return
	_apply_registered_translations()


func _apply_registered_translations() -> void:
	LocalizedTextService.configure_core_paths(_translation_paths)
	for translation_path: String in _translation_paths:
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
