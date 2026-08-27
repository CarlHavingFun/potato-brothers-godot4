extends GdUnitTestSuite


const OUTPUT_URI := "user://full-static-assets-menu-v1/menu-1280x720.png"
const CAPTURE_SIZE := Vector2i(1280, 720)
const APP_SCENE := preload("res://game/app/app_root.tscn")


func test_capture_actual_menu_at_1280() -> void:
	GogoStaticConsumerRegistry.reset_current()
	var root_window := auto_free(SubViewport.new()) as SubViewport
	root_window.size = CAPTURE_SIZE
	root_window.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_tree().root.add_child(root_window)
	var app := APP_SCENE.instantiate() as AppKernel
	root_window.add_child(app)
	await get_tree().process_frame
	await get_tree().process_frame
	if not _require(app.boot_result != null and app.boot_result.is_ok(), "application boot"):
		return
	var snapshot := app.static_asset_service.active_snapshot()
	if not _require(snapshot != null and snapshot.is_development_preview(), "development preview assets"):
		return
	if not _require(app.content_snapshot.all(&"character").size() == 1, "Niko-only character scope"):
		return

	var host := app.get_node("SceneHost") as Node
	var main_menu := _current_screen(host)
	if not _require(main_menu != null, "main menu route"):
		return
	if not _require(_texture_visible(main_menu, "Center/StaticNineSlicePanel/Body/Wordmark"), "wordmark consumer"):
		return
	if not _require(_texture_visible(main_menu, "StaticMenuBackground"), "menu background consumer"):
		return
	if not _require(main_menu.get_node_or_null("Center/StaticNineSlicePanel") != null, "nine-slice panel consumer"):
		return
	if not _require(main_menu.get_node_or_null("Center/StaticNineSlicePanel/Body/StartButton") is Button, "four-state button consumer"):
		return

	app.begin_selection()
	app.selection_draft["character_id"] = ValidationContentFactory.CHARACTER_ID
	if not _require(app.route(FlowRoute.WEAPON_SELECT) == OK, "weapon selection route"):
		return
	await get_tree().process_frame
	var weapon_screen := _current_screen(host)
	var grid := weapon_screen.get_node_or_null("Center/StaticNineSlicePanel/Body/WeaponCardGrid") as GridContainer
	if not _require(grid != null and grid.get_child_count() >= 12, "weapon card grid"):
		return
	var first_card := grid.get_child(0) as Control
	if not _require(_texture_visible(first_card, "Frame") and _texture_visible(first_card, "Icon"), "card frame and icon consumers"):
		return

	app.selection_draft["weapon_id"] = ValidationContentFactory.RANGED_ID
	if not _require(app.route(FlowRoute.DIFFICULTY_SELECT) == OK, "difficulty selection route"):
		return
	await get_tree().process_frame
	var difficulty_screen := _current_screen(host)
	if not _require(_texture_visible(difficulty_screen, "Center/StaticNineSlicePanel/Body/ZoneThumbnail"), "zone thumbnail consumer"):
		return
	var difficulty_button := _first_button(difficulty_screen)
	if not _require(difficulty_button != null and difficulty_button.icon != null, "difficulty badge consumer"):
		return

	if not _require(app.route(FlowRoute.MAIN_MENU) == OK, "return to main menu"):
		return
	await get_tree().process_frame
	main_menu = _current_screen(host)
	_add_selection_evidence(main_menu, app.content_snapshot, snapshot)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var output_path := ProjectSettings.globalize_path(OUTPUT_URI)
	if DirAccess.make_dir_recursive_absolute(output_path.get_base_dir()) != OK:
		_fail("could not create menu capture directory")
		return
	var image := root_window.get_texture().get_image()
	if not _require(image != null and image.get_size() == CAPTURE_SIZE, "1280x720 menu capture"):
		return
	if image.save_png(output_path) != OK:
		_fail("could not save menu capture")
		return
	print("FULL_STATIC_ASSETS_MENU_V1_OK capture=%s" % output_path)


func _add_selection_evidence(
	menu: Control,
	content: ContentSnapshot,
	snapshot: GogoStaticAssetSnapshot
) -> void:
	var panel := PanelContainer.new()
	panel.name = "SelectionEvidence"
	panel.position = Vector2(964, 104)
	panel.size = Vector2(300, 500)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("111722e8")
	style.border_color = Color("d39b43")
	style.set_border_width_all(3)
	style.set_corner_radius_all(6)
	panel.add_theme_stylebox_override(&"panel", style)
	menu.add_child(panel)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override(&"separation", 10)
	panel.add_child(stack)
	var title := Label.new()
	title.text = "同风格 · 选择界面预览"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override(&"font_size", 20)
	title.add_theme_color_override(&"font_color", Color("f0c76b"))
	stack.add_child(title)

	var zone := TextureRect.new()
	zone.custom_minimum_size = Vector2(280, 158)
	zone.texture = snapshot.resolve_global(&"zone_thumbnail").texture
	zone.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	zone.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	zone.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	stack.add_child(zone)

	var weapon := content.all(&"weapon")[2] as GogoWeaponDefinition
	var card := GogoStaticCardPresenter.build_card(weapon, "远程 · 自动开火", snapshot)
	card.custom_minimum_size = Vector2(286, 76)
	stack.add_child(card)

	var difficulty_row := HBoxContainer.new()
	difficulty_row.alignment = BoxContainer.ALIGNMENT_CENTER
	difficulty_row.add_theme_constant_override(&"separation", 10)
	stack.add_child(difficulty_row)
	var badge := TextureRect.new()
	badge.custom_minimum_size = Vector2(64, 64)
	badge.texture = snapshot.resolve_global(&"difficulty_badge_kit", &"standard").texture
	badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	badge.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	difficulty_row.add_child(badge)
	var label := Label.new()
	label.text = "标准难度\n社区服训练场"
	label.add_theme_font_size_override(&"font_size", 16)
	label.add_theme_color_override(&"font_color", Color("f3edd7"))
	difficulty_row.add_child(label)


func _current_screen(host: Node) -> Control:
	if host == null or host.get_child_count() != 1:
		return null
	return host.get_child(0) as Control


func _texture_visible(parent: Node, path: String) -> bool:
	if parent == null:
		return false
	var texture_rect := parent.get_node_or_null(path) as TextureRect
	return texture_rect != null and texture_rect.texture != null and texture_rect.is_visible_in_tree()


func _first_button(parent: Node) -> Button:
	if parent == null:
		return null
	for node in parent.find_children("*", "Button", true, false):
		return node as Button
	return null


func _require(condition: bool, label: String) -> bool:
	if condition:
		return true
	_fail(label)
	return false


func _fail(message: String) -> void:
	fail("FULL_STATIC_ASSETS_MENU_V1_FAILED: " + message)
