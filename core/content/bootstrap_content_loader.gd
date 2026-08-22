class_name BootstrapContentLoader
extends Node


signal catalog_changed(catalog: ContentCatalog)

const RegistryScript := preload("res://core/content/content_pack_registry.gd")
const StateStoreScript := preload("res://core/content/content_pack_state_store.gd")
const InstallerScript := preload("res://core/content/content_pack_installer.gd")
const DEFAULT_MANIFEST_PATH := "res://content_packs/default/pack.tres"
const BUILTIN_PACK_INDEX_PATH := "res://content_packs/builtin_packs.json"
const DEFAULT_PACK_FILENAME := "default_content.pck"
const EXPECTED_DEFAULT_WEAPON_COUNT := 24
const EXPECTED_DEFAULT_PASSIVE_COUNT := 60
const EXPECTED_DEFAULT_UPGRADE_COUNT := 64
const DEFAULT_CONTENT_READY_MARKER := (
	"MECHANICS_CONTENT_READY weapons=24 passives=60 upgrades=64 presentation_icons=0"
)
const OPTIONAL_CHARACTER_PATHS: Array[String] = []


var catalog := ContentCatalog.new()
var active_balance_pack: BalancePackDef
var last_errors := PackedStringArray()
var _translation_paths: Array[String] = []
var _core_pack: ContentPackDef
var _optional_packs: Array[ContentPackDef] = []
var _active_pack_ids := PackedStringArray(["core"])
var _pending_pack_ids := PackedStringArray()
var _state_store := StateStoreScript.new()
var _installer := InstallerScript.new()
var _builtin_pack_ids := {}


func _init() -> void:
	var result := OK
	if ResourceLoader.exists(DEFAULT_MANIFEST_PATH):
		result = load_manifest(DEFAULT_MANIFEST_PATH, DEFAULT_MANIFEST_PATH.get_base_dir())
	else:
		result = mount_and_load(default_export_pack_path())
	if result != OK:
		push_error("Default content pack failed to load: %s" % "\n".join(last_errors))
	else:
		_initialize_optional_packs()


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
	if manifest_path == DEFAULT_MANIFEST_PATH:
		_core_pack = runtime_pack
	_register_translations(runtime_pack)
	if manifest_path == DEFAULT_MANIFEST_PATH:
		print(DEFAULT_CONTENT_READY_MARKER)
	return OK


func queue_enabled_pack_ids(ids: PackedStringArray) -> Dictionary:
	var known := {}
	for pack: ContentPackDef in _optional_packs:
		known[pack.pack_id] = true
	var normalized := PackedStringArray()
	var seen := {}
	for raw_id: String in ids:
		var pack_id := StringName(raw_id.strip_edges())
		if pack_id == &"core" or seen.has(pack_id):
			continue
		if not known.has(pack_id):
			return {"ok": false, "errors": PackedStringArray([
				"unknown content pack: %s" % pack_id
			])}
		seen[pack_id] = true
		normalized.append(pack_id)
	normalized.sort()
	_pending_pack_ids = normalized
	return {"ok": true, "errors": PackedStringArray(), "pending_pack_ids": normalized}


func apply_pending_at_main_menu(run_active: bool) -> Dictionary:
	if run_active:
		return _apply_failure("content pack changes can only be applied at the main menu")
	if _core_pack == null:
		return _apply_failure("core content pack is not available")
	var result: Dictionary = RegistryScript.new().build_candidate(
		_core_pack, _optional_packs, _pending_pack_ids, active_balance_pack
	)
	var errors: PackedStringArray = result.get("errors", PackedStringArray())
	if not errors.is_empty() or result.get("catalog") == null:
		last_errors = errors
		return result
	var save_error: Error = _state_store.save_enabled(_pending_pack_ids)
	if save_error != OK:
		return _apply_failure("could not save enabled packs: %s" % error_string(save_error))
	catalog = result.catalog as ContentCatalog
	_active_pack_ids = result.active_pack_ids
	_register_active_translations()
	catalog_changed.emit(catalog)
	result["ok"] = true
	return result


func content_pack_summaries() -> Array[Dictionary]:
	var installed_ids := {}
	for entry: Dictionary in _installer.installed_entries():
		installed_ids[StringName(entry.get("pack_id", ""))] = true
	var summaries: Array[Dictionary] = [{
		"pack_id": &"core",
		"display_name": "Core",
		"version": _core_pack.pack_version if _core_pack != null else "",
		"kind": ContentPackDef.PackKind.CORE,
		"enabled": true,
		"required": true,
	}]
	for pack: ContentPackDef in _optional_packs:
		summaries.append({
			"pack_id": pack.pack_id,
			"display_name": String(pack.display_name_key) if not pack.display_name_key.is_empty() else String(pack.pack_id),
			"version": pack.pack_version,
			"kind": pack.pack_kind,
			"enabled": String(pack.pack_id) in _pending_pack_ids,
			"required": false,
			"installed": installed_ids.has(pack.pack_id),
			"removable": installed_ids.has(pack.pack_id),
		})
	return summaries


func install_content_pack(pck_path: String) -> Dictionary:
	if not FileAccess.file_exists(pck_path):
		return _apply_failure("content PCK not found: %s" % pck_path)
	var descriptor_path := pck_path.get_basename() + ".contents.json"
	if not FileAccess.file_exists(descriptor_path):
		return _apply_failure("content descriptor not found: %s" % descriptor_path)
	var descriptor_data: Variant = JSON.parse_string(FileAccess.get_file_as_string(descriptor_path))
	if descriptor_data is Dictionary:
		var candidate_id := StringName(descriptor_data.get("pack_id", ""))
		if _builtin_pack_ids.has(candidate_id):
			return _apply_failure("built-in pack updates ship with a game update: %s" % candidate_id)
	var result: Dictionary = _installer.install(pck_path, descriptor_path)
	if not bool(result.get("ok", false)) or bool(result.get("restart_required", false)):
		return result
	var installed_pack_id := StringName(result.get("pack_id", ""))
	var installed_path := String(result.get("pck_path", ""))
	if not ProjectSettings.load_resource_pack(ProjectSettings.globalize_path(installed_path), false):
		var cleanup: Dictionary = _installer.remove(installed_pack_id)
		var message := "installed content pack could not be mounted"
		if not bool(cleanup.get("ok", false)):
			message += "; install rollback failed: %s" % "; ".join(cleanup.get("errors", PackedStringArray()))
		return _apply_failure(message)
	# Godot cannot unmount a resource pack. Mark it before reading the manifest so
	# any post-mount validation failure is staged for removal on the next restart.
	_installer.mark_mounted(installed_pack_id)
	var installed_entry: Dictionary
	for entry: Dictionary in _installer.installed_entries():
		if StringName(entry.get("pack_id", "")) == installed_pack_id:
			installed_entry = entry
			break
	var pack := _load_optional_manifest(String(installed_entry.get("manifest_virtual_path", "")))
	if pack == null or pack.pack_id != installed_pack_id:
		var cleanup: Dictionary = _installer.remove(installed_pack_id)
		var errors := PackedStringArray(["installed content manifest could not be loaded or its ID did not match"])
		if not bool(cleanup.get("ok", false)):
			errors.append_array(cleanup.get("errors", PackedStringArray()))
		last_errors = errors
		return {
			"ok": false,
			"catalog": null,
			"active_pack_ids": _active_pack_ids.duplicate(),
			"errors": errors,
			"restart_required": bool(cleanup.get("restart_required", true)),
		}
	_optional_packs.append(pack)
	return result


func remove_content_pack(pack_id: StringName) -> Dictionary:
	if _builtin_pack_ids.has(pack_id):
		return _apply_failure("built-in packs are replaced by a game update")
	var previous_ids := _pending_pack_ids.duplicate()
	var next_ids := _pending_pack_ids.duplicate()
	var pending_index := next_ids.find(String(pack_id))
	if pending_index >= 0:
		next_ids.remove_at(pending_index)
	var save_error: Error = _state_store.save_enabled(next_ids)
	if save_error != OK:
		return _apply_failure("could not save disabled pack state: %s" % error_string(save_error))
	var result: Dictionary = _installer.remove(pack_id)
	if not bool(result.get("ok", false)):
		var restore_error: Error = _state_store.save_enabled(previous_ids)
		if restore_error != OK:
			var errors: PackedStringArray = result.get("errors", PackedStringArray())
			errors.append("enabled pack state rollback failed: %s" % error_string(restore_error))
			result["errors"] = errors
		return result
	_pending_pack_ids = next_ids
	return result


func request_controlled_restart(run_active: bool) -> Dictionary:
	if run_active:
		return _apply_failure("restart is only allowed at the main menu")
	OS.set_restart_on_exit(true)
	get_tree().quit()
	return {"ok": true, "errors": PackedStringArray(), "restart_required": true}


func active_pack_ids() -> PackedStringArray:
	return _active_pack_ids.duplicate()


func pending_pack_ids() -> PackedStringArray:
	return _pending_pack_ids.duplicate()


func _initialize_optional_packs() -> void:
	_optional_packs.clear()
	_builtin_pack_ids.clear()
	var defaults := PackedStringArray()
	var pending_result: Dictionary = _installer.apply_pending_on_startup()
	if not bool(pending_result.get("ok", false)):
		last_errors.append_array(pending_result.get("errors", PackedStringArray()))
	if FileAccess.file_exists(BUILTIN_PACK_INDEX_PATH):
		var file := FileAccess.open(BUILTIN_PACK_INDEX_PATH, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
		if file != null:
			file.close()
		if parsed is Dictionary:
			for entry: Variant in parsed.get("packs", []):
				if not entry is Dictionary:
					continue
				var manifest_path := String(entry.get("manifest", ""))
				if not ResourceLoader.exists(manifest_path):
					var shipping_name := String(entry.get("shipping_pck", ""))
					var shipping_path := OS.get_executable_path().get_base_dir().path_join(
						"content_packs"
					).path_join(shipping_name)
					if not shipping_name.is_empty() and FileAccess.file_exists(shipping_path):
						ProjectSettings.load_resource_pack(shipping_path, false)
				var pack := _load_optional_manifest(manifest_path)
				if pack == null:
					continue
				_optional_packs.append(pack)
				_builtin_pack_ids[pack.pack_id] = true
				if bool(entry.get("default_enabled", false)):
					defaults.append(pack.pack_id)
	for entry: Dictionary in _installer.installed_entries():
		var pck_path := String(entry.get("pck_path", ""))
		var manifest_path := String(entry.get("manifest_virtual_path", ""))
		if pck_path.is_empty() or manifest_path.is_empty():
			continue
		if not ProjectSettings.load_resource_pack(ProjectSettings.globalize_path(pck_path), false):
			last_errors.append("installed content pack could not be mounted: %s" % pck_path)
			continue
		var pack := _load_optional_manifest(manifest_path)
		if pack == null:
			continue
		_optional_packs.append(pack)
		_installer.mark_mounted(pack.pack_id)
	var state: Dictionary = _state_store.load_state()
	var saved: PackedStringArray = state.get("enabled_pack_ids", PackedStringArray())
	_pending_pack_ids = saved if _state_store.last_error == OK and not saved.is_empty() else defaults
	var initial: Dictionary = RegistryScript.new().build_candidate(
		_core_pack, _optional_packs, _pending_pack_ids, active_balance_pack
	)
	if initial.get("catalog") != null and (initial.errors as PackedStringArray).is_empty():
		catalog = initial.catalog as ContentCatalog
		_active_pack_ids = initial.active_pack_ids
		_register_active_translations()
	else:
		last_errors.append_array(initial.get("errors", PackedStringArray()))


func _load_optional_manifest(path: String) -> ContentPackDef:
	if path.is_empty() or not ResourceLoader.exists(path):
		last_errors.append("optional content manifest not found: %s" % path)
		return null
	var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
	if not resource is ContentPackDef:
		last_errors.append("optional manifest is not a ContentPackDef: %s" % path)
		return null
	var pack := (resource as ContentPackDef).duplicate(true) as ContentPackDef
	var errors := ContentValidator.new().validate_pack(pack, path.get_base_dir())
	if not errors.is_empty():
		last_errors.append_array(errors)
		return null
	return pack


func _register_active_translations() -> void:
	var paths: Array[String] = []
	for path: String in _core_pack.translation_paths:
		paths.append(path)
	for pack: ContentPackDef in _optional_packs:
		if String(pack.pack_id) not in _active_pack_ids:
			continue
		for path: String in pack.translation_paths:
			if path not in paths:
				paths.append(path)
	_translation_paths = paths
	if is_inside_tree():
		_apply_registered_translations()


func _apply_failure(message: String) -> Dictionary:
	last_errors = PackedStringArray([message])
	return {
		"ok": false,
		"catalog": null,
		"active_pack_ids": _active_pack_ids.duplicate(),
		"errors": last_errors,
		"restart_required": false,
	}


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
