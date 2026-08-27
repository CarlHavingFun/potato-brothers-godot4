extends SceneTree

const OUTPUT_URI := "user://static-shipping-runtime-visual-v1/capture-1280x720.png"
const CAPTURE_SIZE := Vector2i(1280, 720)
const BACKGROUND := Color("111722")


func _initialize() -> void:
	var content := GogoContentRegistry.new().build_snapshot(ValidationContentFactory.create_packs())
	if content == null:
		_fail("validation content snapshot could not be built")
		return
	var service := GogoStaticAssetRuntimeService.new()
	if service.stage(content) != OK or service.activate_staged(&"", null) != OK:
		_fail("canonical static shipping snapshot could not be activated")
		return
	var snapshot := service.active_snapshot()
	if snapshot == null or snapshot.ready_count() != 9 or snapshot.expected_count() != 70:
		_fail("canonical static shipping readiness mismatch")
		return
	if not snapshot.issues().is_empty():
		_fail("canonical static shipping snapshot contains issues")
		return

	var root_window := get_root()
	root_window.size = CAPTURE_SIZE
	var canvas := Control.new()
	canvas.name = "StaticShippingRuntimeVisualProof"
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_window.add_child(canvas)
	var background := ColorRect.new()
	background.color = BACKGROUND
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(background)
	_add_label(canvas, "GOGOBRO · CANONICAL STATIC SHIPPING · RUNTIME PROOF", Vector2(520, 18), 26, Color("f2e8c9"))
	_add_label(canvas, "9 READY / 61 FALLBACK · SCOPE 70 · NIKO-ONLY CHARACTER", Vector2(522, 54), 15, Color("8fe0b0"))

	var hud_player := SessionPlayerState.new()
	hud_player.current_health = 20.0
	hud_player.max_health = 20.0
	var hud := GogoBrotatoCombatHud.new()
	hud.name = "CanonicalShippingHUD"
	hud.scale = Vector2(4.0, 4.0)
	hud.configure(
		GogoCombatHudSnapshot.create(hud_player, 11.4, 1, 0.6),
		content,
		snapshot
	)
	canvas.add_child(hud)

	_add_panel(canvas, Rect2(28, 190, 580, 500), "CONTENT + PROJECTILES · EXACT CANONICAL HANDLES")
	var content_entries := [
		[&"service_pistol", &"icon", &"", "PISTOL ICON"],
		[&"warmup_shiv", &"icon", &"", "SHIV ICON"],
		[&"ballistic_liner", &"icon", &"", "SHOP · 防弹内衬"],
		[&"one_more_round", &"icon", &"", "UPGRADE · 多活一回合"],
	]
	for index in content_entries.size():
		var entry: Array = content_entries[index]
		var handle := snapshot.resolve_asset(entry[0], entry[1], entry[2])
		if handle == null:
			_fail("missing content handle %s" % entry[0])
			return
		_add_handle(canvas, handle, Vector2(56 + (index % 2) * 270, 242 + (index / 2) * 120), String(entry[3]))

	var projectile_selectors := [&"pistol_smg_round", &"rifle_round", &"sniper_round", &"hostile_pulse"]
	for index in projectile_selectors.size():
		var selector: StringName = projectile_selectors[index]
		var handle := snapshot.resolve_asset(&"projectile_hit_kit", &"projectile_sprite", selector)
		if handle == null:
			_fail("missing projectile selector %s" % selector)
			return
		_add_projectile_handle(canvas, handle, Vector2(56 + index * 132, 494), String(selector))

	_add_panel(canvas, Rect2(632, 190, 620, 500), "ACTUAL COMBAT FEEDBACK CONSUMER · STATIC IMPACTS")
	var presenter := GogoCombatFeedbackPresenter.new()
	presenter.name = "CanonicalImpactPresenter"
	presenter.z_index = 20
	presenter.configure(null, snapshot)
	canvas.add_child(presenter)
	presenter.process_mode = Node.PROCESS_MODE_DISABLED
	var impacts := [&"normal", &"critical", &"pierce_exit", &"explosion"]
	for index in impacts.size():
		var position := Vector2i(716 + (index % 2) * 270, 300 + (index / 2) * 190)
		if not presenter.present_projectile_contact(
			index + 1,
			index + 101,
			&"rifle",
			position,
			Vector2.LEFT,
			&"ballistic",
			impacts[index],
			1
		):
			_fail("impact presentation rejected %s" % impacts[index])
			return
		_add_label(canvas, String(impacts[index]), Vector2(position.x - 52, position.y + 52), 15, Color("f0c76b"))
	for effect: Dictionary in presenter.debug_effects():
		if String(effect.get("visual_source", "")) != "static_asset":
			_fail("impact fell back to procedural rendering")
			return
	if not presenter.debug_block_primitives().is_empty():
		_fail("static impact proof unexpectedly retained procedural blocks")
		return

	var output_path := ProjectSettings.globalize_path(OUTPUT_URI)
	if DirAccess.make_dir_recursive_absolute(output_path.get_base_dir()) != OK:
		_fail("could not create output directory")
		return
	await process_frame
	await RenderingServer.frame_post_draw
	await process_frame
	await RenderingServer.frame_post_draw
	if presenter.debug_effects().size() != 4:
		_fail("static impact proof effects expired before capture")
		return
	var image := root_window.get_texture().get_image()
	if image == null or image.get_size() != CAPTURE_SIZE:
		_fail("capture size mismatch")
		return
	if image.save_png(output_path) != OK:
		_fail("could not save runtime visual proof")
		return
	print("STATIC_SHIPPING_RUNTIME_VISUAL_V1_OK capture=%s" % output_path)
	quit(0)


func _add_panel(parent: Control, rect: Rect2, title: String) -> void:
	var panel := ColorRect.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.color = Color("192333")
	parent.add_child(panel)
	_add_label(parent, title, rect.position + Vector2(18, 14), 17, Color("f0c76b"))


func _add_handle(parent: Control, handle: GogoStaticAssetHandle, position: Vector2, caption: String) -> void:
	var icon := TextureRect.new()
	icon.position = position
	icon.size = Vector2(handle.display_size_px)
	icon.texture = handle.texture
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	parent.add_child(icon)
	_add_label(parent, caption, position + Vector2(72, 18), 13, Color("d8deea"))


func _add_projectile_handle(parent: Control, handle: GogoStaticAssetHandle, position: Vector2, caption: String) -> void:
	var icon := TextureRect.new()
	icon.position = position
	icon.size = Vector2(handle.display_size_px)
	icon.texture = handle.texture
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	parent.add_child(icon)
	_add_label(parent, caption, position + Vector2(0, 72), 11, Color("d8deea"))


func _add_label(parent: Control, text: String, position: Vector2, font_size: int, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.position = position
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", color)
	parent.add_child(label)


func _fail(message: String) -> void:
	push_error("STATIC_SHIPPING_RUNTIME_VISUAL_V1_FAILED: " + message)
	quit(1)
