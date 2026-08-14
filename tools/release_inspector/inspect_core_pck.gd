extends SceneTree


const FORBIDDEN_ROOTS := [
	"res://addons",
	"res://bin",
	"res://builds",
	"res://content_packs",
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
		push_error("Usage: inspect_core_pck.gd -- <core.pck>")
		quit(ERR_INVALID_PARAMETER)
		return
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
	if not ResourceLoader.exists("res://scenes/arena/arena.tscn"):
		push_error("Core PCK is missing the main arena scene")
		quit(ERR_FILE_NOT_FOUND)
		return
	print("CORE_PCK_INSPECTION passed: %s" % pack_path)
	quit(OK)
