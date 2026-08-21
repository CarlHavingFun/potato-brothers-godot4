extends SceneTree


const FORBIDDEN_ROOTS := [
	"res://addons",
	"res://bin",
	"res://builds",
	"res://content_packs/default",
	"res://dist",
	"res://docs",
	"res://reports",
	"res://reference",
	"res://references",
	"res://screenshots",
	"res://test_reports",
	"res://tests",
	"res://tools",
	"res://vscode",
	"res://.github",
]
const FORBIDDEN_SKIN_ARTIFACTS := [
	"/identity/",
	"/review/",
	"/source/",
	"/candidate/",
	"/candidates/",
	"/prompt/",
	"/prompts/",
	"/raw/",
	"/frames/",
	"/qa/",
	"/exports/",
	"/curated/",
	".prompt.",
	".qa.",
	"contact-sheet",
	".ds_store",
]
const FORBIDDEN_SKIN_EXTENSIONS := [
	".jpg",
	".jpeg",
	".psd",
	".psb",
	".ase",
	".aseprite",
	".kra",
	".xcf",
	".blend",
	".zip",
	".7z",
	".rar",
	".tar",
	".gz",
	".mp4",
	".webm",
	".mov",
	".avi",
	".mkv",
	".gif",
]
const APPROVED_SKIN_ART_EXTENSIONS := ["png", "svg"]
const STATIC_ART_EXTENSIONS := [
	"png", "svg", "jpg", "jpeg", "webp", "bmp", "tga", "gif",
	"psd", "psb", "ase", "aseprite", "kra", "xcf",
]

# Character and enemy sprites are deliberately retained by the mechanics layer
# until their animated presentation scenes move into a future skin pack.
const ALLOWED_DYNAMIC_ART_ROOTS := [
	"res://assets/sprites/Players/",
	"res://assets/sprites/Enemies/",
]
const ALLOWED_CORE_ART_FILES := [
	"res://assets/sprites/shadow.png",
]
const EXPORTED_PROJECT_BINARY := "res://project.binary"
const FORMAL_GLOBAL_FONT_PATH := "res://assets/font/brotato_font_stack.tres"
const FORMAL_PRIMARY_FONT_PATH := "res://assets/font/Anybody-Medium.ttf"
const FORMAL_FALLBACK_FONT_PATH := "res://assets/font/NotoSansCJKsc-Medium.otf"
const FORMAL_SKIN_THEME_PATH := "res://content_packs/skins/lets_gooooo/assets/ui/lets_gooooo_theme.tres"
const GLOBAL_FONT_SETTING := "gui/theme/custom_font"


func _init() -> void:
	# A mounted export includes project.binary. Keep the inspector's own minimal
	# theme active so the mounted game's font is never initialized here.
	ProjectSettings.set_setting("gui/theme/custom_font", "")
	var arguments := OS.get_cmdline_user_args()
	if arguments.is_empty():
		_fail(
			"Usage: inspect_core_pck.gd -- <core.pck> --skin-manifest "
			+ "<res://.../skin.tres> --asset-manifest <asset_manifest.json>",
			ERR_INVALID_PARAMETER
		)
		return
	var skin_manifest := _argument(arguments, "--skin-manifest")
	var asset_manifest := _argument(arguments, "--asset-manifest")
	if skin_manifest.is_empty() or asset_manifest.is_empty():
		_fail("Both --skin-manifest and --asset-manifest are required.", ERR_INVALID_PARAMETER)
		return

	var pack_path := ProjectSettings.globalize_path(arguments[0])
	if not FileAccess.file_exists(pack_path):
		_fail("Core PCK not found: %s" % pack_path, ERR_FILE_NOT_FOUND)
		return
	if not ProjectSettings.load_resource_pack(pack_path, false):
		_fail("Core PCK could not be mounted: %s" % pack_path, ERR_CANT_OPEN)
		return
	ProjectSettings.set_setting("gui/theme/custom_font", "")
	for forbidden_path: String in FORBIDDEN_ROOTS:
		if DirAccess.dir_exists_absolute(forbidden_path) or FileAccess.file_exists(forbidden_path):
			_fail("Forbidden release path found in core PCK: %s" % forbidden_path, ERR_INVALID_DATA)
			return
	if not ResourceLoader.exists(skin_manifest):
		_fail("Selected skin is missing from core PCK: %s" % skin_manifest, ERR_FILE_NOT_FOUND)
		return
	var manifest_result := _load_approved_skin_assets(asset_manifest, skin_manifest)
	if not String(manifest_result.error).is_empty():
		_fail(String(manifest_result.error), ERR_INVALID_DATA)
		return
	var approved_skin_assets: Dictionary = manifest_result.approved
	var global_font_error := _validate_exported_global_font()
	if not global_font_error.is_empty():
		_fail(global_font_error, ERR_INVALID_DATA)
		return

	var skin_manifests := PackedStringArray()
	_collect_skin_manifests("res://content_packs/skins", skin_manifests)
	if skin_manifests.size() != 1 or skin_manifests[0] != skin_manifest:
		_fail("Core PCK must contain only the selected skin: %s" % skin_manifests, ERR_INVALID_DATA)
		return
	var closure_error := _validate_skin_asset_closure(skin_manifest, approved_skin_assets)
	if not closure_error.is_empty():
		_fail(closure_error, ERR_INVALID_DATA)
		return
	var core_art_error := _validate_core_static_art()
	if not core_art_error.is_empty():
		_fail(core_art_error, ERR_INVALID_DATA)
		return
	if not ResourceLoader.exists("res://scenes/arena/arena.tscn"):
		_fail("Core PCK is missing the main arena scene", ERR_FILE_NOT_FOUND)
		return
	print(
		"CORE_PCK_INSPECTION passed: %s (%d approved skin assets)"
		% [pack_path, approved_skin_assets.size()]
	)
	quit(OK)


func _load_approved_skin_assets(asset_manifest: String, skin_manifest: String) -> Dictionary:
	var expected_manifest := skin_manifest.get_base_dir().path_join("asset_manifest.json")
	if asset_manifest != expected_manifest:
		return {
			"error": "Asset manifest must be packaged beside the selected skin manifest: %s" % expected_manifest,
			"approved": {},
		}
	# This lookup deliberately happens only after the exported PCK is mounted.
	# An external build-machine manifest must never satisfy the release closure.
	if not FileAccess.file_exists(asset_manifest):
		return {"error": "Formal skin asset manifest is missing from core PCK: %s" % asset_manifest, "approved": {}}
	var file := FileAccess.open(asset_manifest, FileAccess.READ)
	if file == null:
		return {"error": "Formal skin asset manifest could not be opened from core PCK: %s" % asset_manifest, "approved": {}}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return {"error": "Formal skin asset manifest is not valid JSON: %s" % asset_manifest, "approved": {}}
	var payload: Dictionary = parsed
	if String(payload.get("skin_id", "")) != skin_manifest.get_base_dir().get_file():
		return {"error": "Formal skin asset manifest identity does not match selected skin.", "approved": {}}
	var assets: Variant = payload.get("assets", null)
	if not assets is Array or assets.is_empty():
		return {"error": "Formal skin asset manifest has no assets list.", "approved": {}}
	var expected_root := skin_manifest.get_base_dir().path_join("assets") + "/"
	var approved := {}
	for asset_value: Variant in assets:
		if not asset_value is Dictionary:
			return {"error": "Formal skin asset manifest contains a non-object entry.", "approved": {}}
		var asset: Dictionary = asset_value
		var path := String(asset.get("path", "")).replace("\\", "/")
		if not path.begins_with(expected_root):
			return {"error": "Approved skin asset is outside %s: %s" % [expected_root, path], "approved": {}}
		if approved.has(path):
			return {"error": "Formal skin asset manifest contains a duplicate path: %s" % path, "approved": {}}
		if not APPROVED_SKIN_ART_EXTENSIONS.has(path.get_extension().to_lower()):
			return {"error": "Approved skin asset uses a non-shipping extension: %s" % path, "approved": {}}
		var approval: Dictionary = asset.get("approval", {})
		var rights: Dictionary = asset.get("rights", {})
		if not bool(asset.get("shipping_allowed", false)) \
				or String(approval.get("status", "")) != "approved" \
				or String(rights.get("status", "")) != "cleared":
			return {
				"error": "Skin asset is not approved, rights-cleared, and shipping_allowed=true: %s" % path,
				"approved": {},
			}
		approved[path] = true
	return {"error": "", "approved": approved}


func _validate_skin_asset_closure(skin_manifest: String, approved_assets: Dictionary) -> String:
	var skin_files := PackedStringArray()
	_collect_files(skin_manifest.get_base_dir(), skin_files)
	for skin_file: String in skin_files:
		var normalized := skin_file.replace("\\", "/")
		var lowered := normalized.to_lower()
		for forbidden_artifact: String in FORBIDDEN_SKIN_ARTIFACTS:
			if lowered.contains(forbidden_artifact):
				return "Forbidden source/review artifact found in selected skin: %s" % skin_file
		var logical_path := _logical_source_path(normalized)
		var extension := "." + logical_path.get_extension().to_lower()
		if FORBIDDEN_SKIN_EXTENSIONS.has(extension):
			return "Forbidden source/review extension found in selected skin: %s" % skin_file
		if logical_path.begins_with(skin_manifest.get_base_dir().path_join("assets") + "/") \
				and STATIC_ART_EXTENSIONS.has(logical_path.get_extension().to_lower()):
			if not APPROVED_SKIN_ART_EXTENSIONS.has(logical_path.get_extension().to_lower()):
				return "Selected skin contains unsupported shipping art: %s" % logical_path
			if not approved_assets.has(logical_path):
				return "Selected skin art is absent from asset_manifest.json: %s" % logical_path
	for approved_path: String in approved_assets:
		if not ResourceLoader.exists(approved_path):
			return "Approved skin asset is missing from core PCK: %s" % approved_path
	return ""


func _validate_exported_global_font() -> String:
	if not FileAccess.file_exists(EXPORTED_PROJECT_BINARY):
		return "Core PCK is missing project.binary."
	if not ResourceLoader.exists(FORMAL_GLOBAL_FONT_PATH):
		return "Core PCK is missing the formal global font: %s" % FORMAL_GLOBAL_FONT_PATH
	var font_resource: Resource = ResourceLoader.load(FORMAL_GLOBAL_FONT_PATH)
	if not font_resource is FontVariation:
		return "Formal global font resource is not a FontVariation: %s" % FORMAL_GLOBAL_FONT_PATH
	var stack := font_resource as FontVariation
	if stack.base_font == null or stack.base_font.resource_path != FORMAL_PRIMARY_FONT_PATH:
		return "Formal font stack primary is not Anybody Medium: %s" % FORMAL_PRIMARY_FONT_PATH
	var fallbacks := stack.get_fallbacks()
	if fallbacks.size() != 1 or fallbacks[0].resource_path != FORMAL_FALLBACK_FONT_PATH:
		return "Formal font stack fallback is not Noto Sans SC Medium: %s" % FORMAL_FALLBACK_FONT_PATH
	for glyph: String in ["A", "7", "中"]:
		if not stack.has_char(glyph.unicode_at(0)):
			return "Formal font stack cannot resolve glyph: %s" % glyph
	var formal_theme := ResourceLoader.load(FORMAL_SKIN_THEME_PATH) as Theme
	if formal_theme == null or formal_theme.get_default_font().resource_path != FORMAL_GLOBAL_FONT_PATH:
		return "Formal skin theme does not use the composite font stack."
	var font_uid := ResourceLoader.get_resource_uid(FORMAL_GLOBAL_FONT_PATH)
	if font_uid == ResourceUID.INVALID_ID:
		return "Formal global font has no exported resource UID: %s" % FORMAL_GLOBAL_FONT_PATH
	var project_binary := FileAccess.get_file_as_bytes(EXPORTED_PROJECT_BINARY)
	if project_binary.is_empty():
		return "Exported project.binary is empty or unreadable."
	if not _bytes_contain_utf8(project_binary, GLOBAL_FONT_SETTING):
		return "Exported project.binary has no gui/theme/custom_font setting."
	var font_uid_text := ResourceUID.id_to_text(font_uid)
	if not _bytes_contain_utf8(project_binary, font_uid_text):
		return (
			"Exported gui/theme/custom_font does not reference the formal font UID: %s"
			% font_uid_text
		)
	return ""


func _validate_core_static_art() -> String:
	var core_files := PackedStringArray()
	_collect_files("res://assets", core_files)
	for core_file: String in core_files:
		var logical_path := _logical_source_path(core_file.replace("\\", "/"))
		if not STATIC_ART_EXTENSIONS.has(logical_path.get_extension().to_lower()):
			continue
		if ALLOWED_CORE_ART_FILES.has(logical_path):
			continue
		var allowed := false
		for root: String in ALLOWED_DYNAMIC_ART_ROOTS:
			if logical_path.begins_with(root):
				allowed = true
				break
		if not allowed:
			return "Core PCK contains non-manifest static art outside the dynamic compatibility boundary: %s" % logical_path
	return ""


func _bytes_contain_utf8(haystack: PackedByteArray, needle: String) -> bool:
	var needle_bytes := needle.to_utf8_buffer()
	if needle_bytes.is_empty() or needle_bytes.size() > haystack.size():
		return false
	for start: int in range(haystack.size() - needle_bytes.size() + 1):
		var matches := true
		for offset: int in range(needle_bytes.size()):
			if haystack[start + offset] != needle_bytes[offset]:
				matches = false
				break
		if matches:
			return true
	return false


func _logical_source_path(path: String) -> String:
	if path.ends_with(".remap"):
		return path.trim_suffix(".remap")
	if path.ends_with(".import"):
		return path.trim_suffix(".import")
	return path


func _collect_skin_manifests(path: String, manifests: PackedStringArray) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var entry_path := path.path_join(entry)
			if directory.current_is_dir():
				_collect_skin_manifests(entry_path, manifests)
			elif entry == "skin.tres" or entry == "skin.tres.remap":
				manifests.append(entry_path.trim_suffix(".remap"))
		entry = directory.get_next()
	directory.list_dir_end()
	manifests.sort()


func _collect_files(path: String, files: PackedStringArray) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var entry_path := path.path_join(entry)
			if directory.current_is_dir():
				_collect_files(entry_path, files)
			else:
				files.append(entry_path)
		entry = directory.get_next()
	directory.list_dir_end()
	files.sort()


func _argument(arguments: PackedStringArray, name: String) -> String:
	var index := arguments.find(name)
	if index >= 0 and index + 1 < arguments.size():
		return arguments[index + 1]
	return ""


func _fail(message: String, code: int) -> void:
	push_error(message)
	quit(code)
