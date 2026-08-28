extends SceneTree


const ATLAS := "res://game/content/packs/characters/niko/animations/walk_down/sprite-sheet-alpha.png"
const ATLAS_RGBA8_SHA256 := "5e859f78f2bd302c3b2735985f0d2e8efd58c3f57a7e75b8c16473909bad75e7"
const RIG := "res://game/content/packs/characters/niko/rig/niko_attachment_rig_v2.json"
const RIG_SCRIPT := "res://game/content/character_attachment_rig.gd"
const NIKO_FACTORY := "res://game/content/packs/characters/niko/niko_content_factory.gd"
const STATIC_SERVICE_SCRIPT := "res://game/content/assets/gogobro_static_asset_runtime_service.gd"
const APP_SCENE := "res://game/app/app_root.tscn"
const MAIN_MENU_ROUTE: StringName = &"main_menu"
const WEAPON_SELECT_ROUTE: StringName = &"weapon_select"
const NIKO_ID: StringName = &"character.niko:character/niko"

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
		if rig != null:
			var decoded_hash: Variant = rig.get("character_atlas_rgba8_sha256")
			_expect(decoded_hash is String, "Niko attachment rig declares a decoded RGBA8 atlas identity")
			if decoded_hash is String:
				_expect(
					decoded_hash == ATLAS_RGBA8_SHA256,
					"Niko attachment rig pins the decoded RGBA8 atlas identity"
				)
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

		var static_service_script := ResourceLoader.load(STATIC_SERVICE_SCRIPT) as GDScript
		_expect(static_service_script != null, "shipping static asset service script loads")
		if static_service_script != null:
			var shipping_service: Variant = static_service_script.new()
			var content: Variant = app.get("content_snapshot")
			_expect(content != null, "exported app exposes its release content snapshot")
			if content != null:
				_expect(shipping_service.call("stage", content) == OK, "shipping static snapshot stages")
				_expect(
					shipping_service.call("activate_staged", &"", null) == OK,
					"shipping static snapshot activates"
				)
				var shipping_snapshot: Variant = shipping_service.call("active_snapshot")
				var readiness := shipping_snapshot.call("release_readiness") as Dictionary
				_expect(
					int(readiness.get("ready_units", -1)) == 70,
					"shipping snapshot has 70 ready units (actual %s)" % readiness.get("ready_units", -1)
				)
				_expect(
					int(readiness.get("fallback_units", -1)) == 0,
					"shipping snapshot has 0 fallback units (actual %s)" % readiness.get("fallback_units", -1)
				)
				_expect(bool(readiness.get("release_ready", false)), "shipping snapshot is release ready")
				_expect(
					(shipping_snapshot.call("issues") as Array).is_empty(),
					"shipping snapshot has no quarantined static assets"
				)
				_expect(
					_handle_has_texture(shipping_snapshot.call("resolve_global", &"gogobro_wordmark")),
					"shipping wordmark handle has a texture"
				)
				for state: StringName in [&"normal", &"hover", &"pressed", &"disabled"]:
					_expect(
						_handle_has_texture(shipping_snapshot.call("resolve_global", &"four_state_button", state)),
						"shipping four-state button handle '%s' has a texture" % state
					)

				# Re-route with the shipping-only snapshot. The inspector itself runs under
				# a debug Godot binary, so the app's initial route may otherwise use the
				# candidate-preview overlay and conceal release-only quarantine failures.
				app.set("static_asset_service", shipping_service)
				app.call("route", MAIN_MENU_ROUTE)
				await process_frame
				if host != null and host.get_child_count() == 1:
					var main_menu := host.get_child(0)
					var wordmark := main_menu.get_node_or_null("ContentRoot/Body/Wordmark") as TextureRect
					_expect(wordmark != null and wordmark.texture != null, "shipping MainMenuScreen renders its wordmark")
					var start_button := main_menu.get_node_or_null("ContentRoot/Body/MenuActions/StartButton") as Button
					_expect(_button_uses_texture_style(start_button), "shipping MainMenuScreen uses authored button states")

				app.call("begin_selection")
				var draft := app.get("selection_draft") as Dictionary
				draft["character_id"] = NIKO_ID
				app.call("route", WEAPON_SELECT_ROUTE)
				await process_frame
				if host != null and host.get_child_count() == 1:
					var weapon_screen := host.get_child(0)
					var strip := weapon_screen.get_node_or_null("WeaponStrip") as HBoxContainer
					_expect(strip != null and strip.get_child_count() == 12, "shipping weapon select shows exactly 12 choices")
					if strip != null:
						for choice: Node in strip.get_children():
							var icon := choice.get_node_or_null("Icon") as TextureRect
							_expect(
								icon != null and icon.texture != null,
								"shipping weapon choice '%s' renders its icon" % choice.name
							)
					var detail_icon := weapon_screen.get_node_or_null("SelectedWeaponDetail/Icon") as TextureRect
					_expect(
						detail_icon != null and detail_icon.texture != null,
						"shipping weapon detail renders its selected icon"
					)
		app.queue_free()
		await process_frame

	_finish()


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_fail(description)


func _fail(message: String) -> void:
	_failures.append(message)


func _handle_has_texture(handle: Variant) -> bool:
	return handle != null and handle.get("texture") != null


func _button_uses_texture_style(button: Button) -> bool:
	if button == null:
		return false
	var style := button.get_theme_stylebox(&"normal")
	return style is StyleBoxTexture and (style as StyleBoxTexture).texture != null


func _finish() -> void:
	if not _failures.is_empty():
		for failure in _failures:
			print("GOGOBRO_RELEASE_DIAGNOSTIC: %s" % failure)
		quit(1)
		return
	print("GOGOBRO_RELEASE_PCK_SMOKE_OK route=main_menu atlas=decoded_rgba8_verified niko_pack=valid")
	quit(0)
