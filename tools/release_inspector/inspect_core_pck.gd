extends SceneTree


const FORBIDDEN_ROOTS := [
	"res://addons",
	"res://bin",
	"res://builds",
	"res://content_packs/default",
	"res://dist",
	"res://docs",
	"res://reports",
	"res://test_reports",
	"res://tests",
	"res://tools",
	"res://vscode",
	"res://.github",
]


func _init() -> void:
	# A mounted export includes project.binary. Keep the inspector's own minimal
	# theme active so the mounted game's font is never initialized here.
	ProjectSettings.set_setting("gui/theme/custom_font", "")
	var arguments := OS.get_cmdline_user_args()
	if arguments.is_empty():
		push_error("Usage: inspect_core_pck.gd -- <core.pck> --skin-manifest <res://.../skin.tres>")
		quit(ERR_INVALID_PARAMETER)
		return
	var skin_manifest := _argument(
		arguments, "--skin-manifest", "res://content_packs/skins/dev_placeholder/skin.tres"
	)
	var pack_path := ProjectSettings.globalize_path(arguments[0])
	if not FileAccess.file_exists(pack_path):
		push_error("Core PCK not found: %s" % pack_path)
		quit(ERR_FILE_NOT_FOUND)
		return
	if not ProjectSettings.load_resource_pack(pack_path, false):
		push_error("Core PCK could not be mounted: %s" % pack_path)
		quit(ERR_CANT_OPEN)
		return
	ProjectSettings.set_setting("gui/theme/custom_font", "")
	for forbidden_path: String in FORBIDDEN_ROOTS:
		if DirAccess.dir_exists_absolute(forbidden_path) or FileAccess.file_exists(forbidden_path):
			push_error("Forbidden release path found in core PCK: %s" % forbidden_path)
			quit(ERR_INVALID_DATA)
			return
	if not ResourceLoader.exists(skin_manifest):
		push_error("Selected skin is missing from core PCK: %s" % skin_manifest)
		quit(ERR_FILE_NOT_FOUND)
		return
	var skin_manifests := PackedStringArray()
	_collect_skin_manifests("res://content_packs/skins", skin_manifests)
	if skin_manifests.size() != 1 or skin_manifests[0] != skin_manifest:
		push_error("Core PCK must contain only the selected skin: %s" % skin_manifests)
		quit(ERR_INVALID_DATA)
		return
	if not ResourceLoader.exists("res://scenes/arena/arena.tscn"):
		push_error("Core PCK is missing the main arena scene")
		quit(ERR_FILE_NOT_FOUND)
		return
	print("CORE_PCK_INSPECTION passed: %s" % pack_path)
	quit(OK)


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


func _argument(arguments: PackedStringArray, name: String, fallback: String) -> String:
	var index := arguments.find(name)
	if index >= 0 and index + 1 < arguments.size():
		return arguments[index + 1]
	return fallback
