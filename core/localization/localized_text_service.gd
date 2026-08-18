class_name LocalizedTextService
extends RefCounted


const DEFAULT_ZH_MISSING_NAME := "未命名内容"
const DEFAULT_ZH_MISSING_DESCRIPTION := "暂无说明"
const DEFAULT_ZH_MISSING_TEXT := "暂无文本"

static var _core_catalogs: Dictionary = {}
static var _skin_catalogs: Dictionary = {}
static var _reported_missing: Dictionary = {}


static func configure_core_paths(paths: Array) -> void:
	_core_catalogs = _load_catalogs(paths)


static func configure_skin_paths(paths: Array) -> void:
	_skin_catalogs = _load_catalogs(paths)


static func clear_skin_paths() -> void:
	_skin_catalogs.clear()


static func resolve(
	text_id: StringName,
	args: Variant = [],
	english_fallback := "",
	locale_override := ""
) -> String:
	_ensure_runtime_catalogs()
	var locale := _normalized_locale(
		locale_override if not locale_override.is_empty() else TranslationServer.get_locale()
	)
	var message := _message_from(_skin_catalogs, locale, text_id)
	if message.is_empty():
		message = _message_from(_core_catalogs, locale, text_id)
	# TranslationServer may apply its configured fallback locale. Never query it
	# for Chinese: an English-only extension catalog must not leak visible copy.
	if message.is_empty() and not locale.begins_with("zh"):
		var registered: String = str(
			TranslationServer.translate(String(text_id))
			if locale_override.is_empty()
			else String(text_id)
		)
		if registered != String(text_id):
			message = registered
	if message.is_empty() and locale.begins_with("en"):
		message = english_fallback
	if message.is_empty():
		_report_missing_once(text_id, locale)
		message = _missing_placeholder(text_id, locale)
	return _format(message, args)


static func has_message(text_id: StringName, locale_override := "") -> bool:
	_ensure_runtime_catalogs()
	var locale := _normalized_locale(
		locale_override if not locale_override.is_empty() else TranslationServer.get_locale()
	)
	if not _message_from(_skin_catalogs, locale, text_id).is_empty():
		return true
	if not _message_from(_core_catalogs, locale, text_id).is_empty():
		return true
	if locale.begins_with("zh"):
		return false
	var registered: String = str(
		TranslationServer.translate(String(text_id))
		if locale_override.is_empty()
		else String(text_id)
	)
	return registered != String(text_id)


static func _ensure_runtime_catalogs() -> void:
	# Script-entry test runners can construct UI before autoload `_ready` callbacks
	# run. Recover the catalogs from the actual autoload nodes, never from detached
	# import/validation instances, so those instances cannot change visible copy.
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	if _core_catalogs.is_empty():
		var content := tree.root.get_node_or_null("Content")
		if content != null:
			var raw_core_paths: Variant = content.get("_translation_paths")
			if raw_core_paths is Array:
				configure_core_paths(raw_core_paths as Array)
	if _skin_catalogs.is_empty():
		var presentation := tree.root.get_node_or_null("Presentation")
		if presentation != null:
			var raw_skin: Variant = presentation.get("active_skin")
			if raw_skin is SkinPackDef:
				configure_skin_paths(Array((raw_skin as SkinPackDef).translation_paths))


static func _load_catalogs(paths: Array) -> Dictionary:
	var catalogs: Dictionary = {}
	for raw_path: Variant in paths:
		var path := str(raw_path)
		if path.is_empty() or not ResourceLoader.exists(path):
			continue
		var translation := ResourceLoader.load(
			path, "Translation", ResourceLoader.CACHE_MODE_REPLACE
		) as Translation
		if translation == null:
			continue
		catalogs[_normalized_locale(translation.locale)] = translation
	return catalogs


static func _message_from(catalogs: Dictionary, locale: String, text_id: StringName) -> String:
	var translation := _catalog_for_locale(catalogs, locale)
	if translation == null:
		return ""
	return str(translation.get_message(String(text_id)))


static func _catalog_for_locale(catalogs: Dictionary, locale: String) -> Translation:
	var exact := catalogs.get(locale) as Translation
	if exact != null:
		return exact
	var language := locale.get_slice("_", 0)
	var keys: Array[String] = []
	for raw_key: Variant in catalogs:
		keys.append(str(raw_key))
	keys.sort()
	for key: String in keys:
		if key == language or key.begins_with("%s_" % language):
			return catalogs[key] as Translation
	return null


static func _normalized_locale(locale: String) -> String:
	var normalized := locale.replace("-", "_")
	return normalized if not normalized.is_empty() else "zh_CN"


static func _missing_placeholder(text_id: StringName, locale: String) -> String:
	if locale.begins_with("zh"):
		var key := String(text_id)
		if key.ends_with(".name"):
			return DEFAULT_ZH_MISSING_NAME
		if key.ends_with(".description"):
			return DEFAULT_ZH_MISSING_DESCRIPTION
		return DEFAULT_ZH_MISSING_TEXT
	return english_fallback_placeholder(text_id)


static func english_fallback_placeholder(text_id: StringName) -> String:
	var key := String(text_id)
	if key.ends_with(".name"):
		return "Unnamed content"
	if key.ends_with(".description"):
		return "No description"
	return "Text unavailable"


static func _report_missing_once(text_id: StringName, locale: String) -> void:
	var report_key := "%s:%s" % [locale, text_id]
	if _reported_missing.has(report_key):
		return
	_reported_missing[report_key] = true
	push_warning("Missing localized text: %s (%s)" % [text_id, locale])


static func _format(message: String, args: Variant) -> String:
	if args == null:
		return message
	if args is Dictionary:
		return message.format(args)
	if args is Array and (args as Array).is_empty():
		return message
	if args is PackedStringArray and (args as PackedStringArray).is_empty():
		return message
	# A strict-language missing placeholder intentionally has no formatting
	# token. Returning it unchanged avoids turning a missing key into a runtime
	# formatting error merely because the caller supplied arguments.
	if not message.contains("%"):
		return message
	return message % args
