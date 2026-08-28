extends SceneTree


const ATLAS := "res://game/content/packs/characters/niko/animations/walk_down/sprite-sheet-alpha.png"
const RIG := "res://game/content/packs/characters/niko/rig/niko_attachment_rig_v2.json"
const RIG_SCRIPT := "res://game/content/character_attachment_rig.gd"
const NIKO_FACTORY := "res://game/content/packs/characters/niko/niko_content_factory.gd"
const APP_SCENE := "res://game/app/app_root.tscn"
const MAIN_MENU_ROUTE: StringName = &"main_menu"

var _failures := PackedStringArray()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.is_empty():
		_fail("Expected an exported PCK path.")
		_finish()
		return
	var pck_path := arguments[0]
	_expect(ProjectSettings.load_resource_pack(pck_path, false), "exported PCK mounts")
	_expect(not FileAccess.file_exists(ATLAS), "export keeps the atlas as an imported resource")
	_expect(ResourceLoader.exists(ATLAS, "Texture2D"), "logical atlas resource exists")
	var texture := ResourceLoader.load(ATLAS, "Texture2D", ResourceLoader.CACHE_MODE_IGNORE) as Texture2D
	_expect(texture != null, "logical atlas loads as Texture2D")
	if texture != null:
		_expect(Vector2i(texture.get_size()) == Vector2i(1024, 128), "logical atlas keeps 1024x128 geometry")

	var rig_script := ResourceLoader.load(RIG_SCRIPT) as GDScript
	_expect(rig_script != null, "attachment rig script loads")
	if rig_script != null:
		var rig: Variant = rig_script.call("load_from_path", RIG)
		_expect(rig != null and bool(rig.call("is_valid")), "Niko attachment rig is valid in the exported PCK")
		if rig != null and not bool(rig.call("is_valid")):
			_fail("Niko attachment rig errors: %s" % [rig.call("validation_errors")])

	var factory_script := ResourceLoader.load(NIKO_FACTORY) as GDScript
	_expect(factory_script != null, "Niko content factory loads")
	if factory_script != null:
		var pack: Variant = factory_script.call("create_pack")
		_expect(pack != null and bool(pack.call("is_valid")), "Niko content pack is valid in the exported PCK")

	var packed_app := ResourceLoader.load(APP_SCENE) as PackedScene
	_expect(packed_app != null, "exported main scene loads")
	if packed_app != null:
		var app := packed_app.instantiate()
		root.add_child(app)
		await process_frame
		var flow := app.get_node_or_null("SceneFlow")
		var host := app.get_node_or_null("SceneHost") as Node
		var route := StringName()
		if flow != null:
			route = flow.call("current_route") as StringName
		_expect(route == MAIN_MENU_ROUTE, "exported app boots to main_menu, not diagnostic")
		_expect(host != null and host.get_child_count() == 1, "exported app has one routed screen")
		if host != null and host.get_child_count() == 1:
			_expect(host.get_child(0).name == &"MainMenuScreen", "exported app displays MainMenuScreen")
		app.queue_free()
		await process_frame

	_finish()


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_fail(description)


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if not _failures.is_empty():
		for failure in _failures:
			print("GOGOBRO_RELEASE_DIAGNOSTIC: %s" % failure)
		quit(1)
		return
	print("GOGOBRO_RELEASE_PCK_SMOKE_OK route=main_menu atlas=imported_resource niko_pack=valid")
	quit(0)
