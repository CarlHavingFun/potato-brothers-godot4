extends SceneTree

const OUTPUT_URI := "user://combat-feedback-visual-v1"
const CAPTURE_URI := OUTPUT_URI + "/capture-1280x720.png"
const CAPTURE_SIZE := Vector2i(1280, 720)


func _initialize() -> void:
	var output_path := ProjectSettings.globalize_path(OUTPUT_URI)
	if DirAccess.make_dir_recursive_absolute(output_path) != OK:
		_fail("could not create output directory")
		return

	var viewport := SubViewport.new()
	viewport.size = CAPTURE_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	get_root().add_child(viewport)

	var background := ColorRect.new()
	background.color = Color("171c25")
	background.size = Vector2(CAPTURE_SIZE)
	viewport.add_child(background)

	_add_title(viewport, "GOGOBRO · PIXEL COMBAT FEEDBACK", Vector2(40, 24), 28)
	_add_title(viewport, "MUZZLE · 8-DIRECTION INTEGER BLOCKS", Vector2(40, 82), 18)
	_add_title(viewport, "CONTACT · NORMAL / CRITICAL / PIERCE / EXPLOSION / MELEE", Vector2(40, 286), 18)
	_add_title(viewport, "DEATH BURST · FIXED POOL FALLBACK", Vector2(40, 494), 18)

	var presenter := GogoCombatFeedbackPresenter.new()
	presenter.set_physics_process(false)
	viewport.add_child(presenter)
	var profiles: Array[StringName] = [&"rapid", &"rifle", &"heavy", &"suppressed"]
	var directions := [Vector2.RIGHT, Vector2(1, 1), Vector2.UP, Vector2(-1, -1)]
	for index in profiles.size():
		var position := Vector2i(170 + index * 285, 190)
		presenter.present_weapon_fired(index + 1, profiles[index], position, directions[index], index + 1, 1)
		_add_caption(viewport, String(profiles[index]), Vector2(position.x - 54, position.y + 58))

	var impacts: Array[StringName] = [&"normal", &"critical", &"pierce_exit", &"explosion"]
	for index in impacts.size():
		var position := Vector2i(130 + index * 250, 395)
		presenter.present_projectile_contact(
			20 + index,
			40 + index,
			&"heavy" if impacts[index] == &"explosion" else &"rifle",
			position,
			Vector2.LEFT.rotated(float(index) * PI * 0.25),
			&"ballistic",
			impacts[index],
			1
		)
		_add_caption(viewport, String(impacts[index]), Vector2(position.x - 64, position.y + 58))
	var melee_position := Vector2i(1130, 395)
	presenter.present_melee_contact(99, 100, &"heavy", melee_position, Vector2.LEFT, &"melee", &"normal", 1)
	_add_caption(viewport, "melee", Vector2(melee_position.x - 64, melee_position.y + 58))

	for index in 4:
		var position := Vector2i(170 + index * 285, 602)
		presenter.present_enemy_defeated(80 + index, position, 2 + index * 3, 1 + index, 1)
		_add_caption(viewport, "reward %d" % (3 + index * 4), Vector2(position.x - 54, position.y + 58))

	await process_frame
	await RenderingServer.frame_post_draw
	await process_frame
	await RenderingServer.frame_post_draw
	var capture := viewport.get_texture().get_image()
	if capture == null or capture.get_size() != CAPTURE_SIZE:
		_fail("capture size mismatch")
		return
	var capture_path := ProjectSettings.globalize_path(CAPTURE_URI)
	if capture.save_png(capture_path) != OK:
		_fail("could not save capture")
		return
	var non_background := _count_non_background(capture, Color("171c25"))
	if non_background < 1000:
		_fail("capture contains too few visible feedback pixels")
		return
	print("COMBAT_FEEDBACK_VISUAL_V1_OK capture=%s visible_pixels=%d" % [capture_path, non_background])
	quit(0)


func _add_title(parent: Node, text: String, position: Vector2, font_size: int) -> void:
	var label := Label.new()
	label.text = text
	label.position = position
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", Color("e9dfbd"))
	parent.add_child(label)


func _add_caption(parent: Node, text: String, position: Vector2) -> void:
	var label := Label.new()
	label.text = text
	label.position = position
	label.custom_minimum_size = Vector2(128, 30)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override(&"font_size", 16)
	label.add_theme_color_override(&"font_color", Color("9eabc1"))
	parent.add_child(label)


func _count_non_background(image: Image, background: Color) -> int:
	var count := 0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y) != background:
				count += 1
	return count


func _fail(message: String) -> void:
	push_error("COMBAT_FEEDBACK_VISUAL_V1_FAILED: " + message)
	quit(1)
