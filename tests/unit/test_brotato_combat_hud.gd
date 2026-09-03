extends GdUnitTestSuite


const SNAPSHOT_PATH := "res://game/ui/combat_hud_snapshot.gd"
const HUD_PATH := "res://game/ui/brotato_combat_hud.gd"


func test_typed_hud_runtime_scripts_exist() -> void:
	assert_bool(FileAccess.file_exists(SNAPSHOT_PATH)).is_true()
	assert_bool(FileAccess.file_exists(HUD_PATH)).is_true()


func test_snapshot_copies_all_canonical_player_values_and_inventory_arrays() -> void:
	if not FileAccess.file_exists(SNAPSHOT_PATH):
		return
	var snapshot_script := load(SNAPSHOT_PATH) as GDScript
	var player := SessionPlayerState.new()
	player.level = 3
	player.xp = 11
	player.xp_to_next_level = 42
	player.materials = 77
	player.current_health = 17.0
	player.max_health = 23.0
	var content := _content_fixture()
	var first_weapon := player.weapon_inventory.add_weapon(ValidationContentFactory.RANGED_ID, content, 1)
	var second_weapon := player.weapon_inventory.add_weapon(ValidationContentFactory.MELEE_ID, content, 1)
	assert_int(int(first_weapon.error)).is_equal(OK)
	assert_int(int(second_weapon.error)).is_equal(OK)
	player.item_ids.assign([&"i1"])
	var snapshot: Variant = snapshot_script.create(player, 9.25, 4, 2.5)
	assert_int(snapshot.level).is_equal(3)
	assert_int(snapshot.experience).is_equal(11)
	assert_int(snapshot.next_level_requirement).is_equal(42)
	assert_int(snapshot.materials).is_equal(77)
	assert_bool(_has_property(snapshot, &"wave_materials")).is_true()
	if not _has_property(snapshot, &"wave_materials"):
		return
	assert_int(snapshot.get(&"wave_materials")).is_zero()
	assert_float(snapshot.health).is_equal_approx(17.0, 0.0001)
	assert_float(snapshot.maximum_health).is_equal_approx(23.0, 0.0001)
	assert_float(snapshot.seconds).is_equal_approx(9.25, 0.0001)
	assert_float(snapshot.wave_elapsed).is_equal_approx(2.5, 0.0001)
	assert_int(snapshot.wave).is_equal(4)
	assert_array(snapshot.weapon_ids).is_equal([
		ValidationContentFactory.RANGED_ID,
		ValidationContentFactory.MELEE_ID,
	])
	assert_array(snapshot.item_ids).is_equal([&"i1"])
	assert_int(player.weapon_inventory.remove_weapon(int(first_weapon.instance_id))).is_equal(OK)
	player.item_ids.clear()
	assert_array(snapshot.weapon_ids).is_equal([
		ValidationContentFactory.RANGED_ID,
		ValidationContentFactory.MELEE_ID,
	])
	assert_array(snapshot.item_ids).is_equal([&"i1"])


func test_hud_uses_native_1280_layout_without_full_screen_or_inventory_frames() -> void:
	if not FileAccess.file_exists(SNAPSHOT_PATH) or not FileAccess.file_exists(HUD_PATH):
		return
	var snapshot_script := load(SNAPSHOT_PATH) as GDScript
	var hud_script := load(HUD_PATH) as GDScript
	var player := SessionPlayerState.new()
	player.current_health = 7.0
	player.max_health = 20.0
	player.level = 2
	player.xp = 8
	player.xp_to_next_level = 30
	player.materials = 91
	_add_fixture_weapons(player, _content_fixture(), 6)
	for index in 10:
		player.item_ids.append(StringName("gogobro.core:item/training_%d" % ((index % 6) + 1)))
	var snapshot: Variant = snapshot_script.create(player, 9.25, 1, 1.0)
	if _has_property(snapshot, &"wave_materials"):
		snapshot.set(&"wave_materials", 19)
	var hud := auto_free(hud_script.new()) as Control
	var static_snapshot := _static_ui_snapshot()
	hud.call("configure", snapshot, _content_fixture(), static_snapshot)
	add_child(hud)
	assert_vector(hud.custom_minimum_size).is_equal(Vector2(1280, 720))
	assert_vector(hud.size).is_equal(Vector2(1280, 720))
	assert_vector(hud.scale).is_equal(Vector2.ONE)
	assert_bool(hud.has_node("Backdrop")).is_false()
	assert_bool(hud.has_node("Shell")).is_true()
	var shell := hud.get_node("Shell") as TextureRect
	assert_object(shell.texture).is_null()
	assert_bool(shell.visible).is_false()
	assert_vector(shell.size).is_equal(Vector2(1280, 720))
	assert_int(shell.texture_filter).is_equal(CanvasItem.TEXTURE_FILTER_NEAREST)
	assert_bool(hud.has_node("FullScreenOrnamentalFrame")).is_false()
	assert_bool(hud.has_node("TopCenter/Timer")).is_true()
	assert_bool(hud.has_node("TopLeft/Health/HealthBar")).is_true()
	assert_bool(hud.has_node("TopLeft/Experience/ExperienceBar")).is_true()
	assert_bool(hud.has_node("TopLeft/Materials/Value")).is_true()
	assert_bool(hud.has_node("TopLeft/WaveMaterials/Value")).is_true()
	assert_bool(hud.has_node("TopLeft/Experience/ExperienceBar/Level")).is_true()
	assert_bool(hud.has_node("WeaponStrip")).is_false()
	assert_bool(hud.has_node("ItemStrip")).is_false()
	assert_float((hud.get_node("TopLeft/Health/HealthBar") as ProgressBar).value).is_equal(7.0)
	assert_str((hud.get_node("TopLeft/Materials/Value") as Label).text).is_equal("91")
	if hud.has_node("TopLeft/WaveMaterials/Value"):
		assert_str((hud.get_node("TopLeft/WaveMaterials/Value") as Label).text).is_equal("+19")
	assert_bool(hud.has_node("TopLeft/ShellAccent")).is_false()
	var backing_style := (hud.get_node("TopLeft/Backing") as Panel).get_theme_stylebox("panel") as StyleBoxFlat
	assert_bool(backing_style.bg_color.a > 0.0).is_true()


func test_hud_information_rectangles_are_ordered_clear_and_outside_the_play_center() -> void:
	var snapshot_script := load(SNAPSHOT_PATH) as GDScript
	var hud_script := load(HUD_PATH) as GDScript
	var player := SessionPlayerState.new()
	player.current_health = 7.0
	player.max_health = 20.0
	player.level = 12
	player.xp = 8
	player.xp_to_next_level = 30
	player.materials = 91
	var hud := auto_free(hud_script.new()) as Control
	hud.call("configure", snapshot_script.create(player, 9.25, 3, 1.0), _content_fixture())
	add_child(hud)

	var timer := hud.get_node("TopCenter/Timer") as Label
	var wave := hud.get_node("TopCenter/Wave") as Label
	assert_bool(wave.position.y < timer.position.y).is_true()
	assert_bool(_local_rect(timer).intersects(_local_rect(wave))).is_false()
	assert_int(timer.get_theme_font_size("font_size")).is_equal(26)
	assert_vector(timer.scale).is_equal(Vector2.ONE)

	var health_icon := hud.get_node("TopLeft/Health/HealthIcon") as TextureRect
	var health_value := hud.get_node("TopLeft/Health/Value") as Label
	var health_bar := hud.get_node("TopLeft/Health/HealthBar") as ProgressBar
	assert_bool(_local_rect(health_icon).intersects(_local_rect(health_value))).is_false()
	assert_bool(_local_rect(health_icon).intersects(_local_rect(health_bar))).is_false()
	assert_bool(_local_rect(health_value).intersects(_local_rect(health_bar))).is_false()

	var health_metric := hud.get_node("TopLeft/Health") as Control
	var experience_metric := hud.get_node("TopLeft/Experience") as Control
	var material_metric := hud.get_node("TopLeft/Materials") as Control
	assert_bool(health_metric.position.y < experience_metric.position.y).is_true()
	assert_bool(experience_metric.position.y < material_metric.position.y).is_true()
	assert_bool(hud.has_node("TopLeft/Experience/ExperienceBar/Level")).is_true()
	if not hud.has_node("TopLeft/Experience/ExperienceBar/Level"):
		return
	var level := hud.get_node("TopLeft/Experience/ExperienceBar/Level") as Label
	assert_str(level.text).is_equal("LV.12")
	assert_int(level.get_theme_font_size("font_size")).is_equal(14)
	var experience_fill := (
		(hud.get_node("TopLeft/Experience/ExperienceBar") as ProgressBar)
		.get_theme_stylebox("fill") as StyleBoxFlat
	)
	assert_bool(experience_fill.bg_color.g > experience_fill.bg_color.r).is_true()
	assert_bool(experience_fill.bg_color.g > experience_fill.bg_color.b).is_true()
	var material_icon := hud.get_node_or_null("TopLeft/Materials/MaterialIcon") as TextureRect
	var material_value := hud.get_node("TopLeft/Materials/Value") as Label
	assert_object(material_icon).is_not_null()
	if material_icon == null:
		return
	assert_bool(_local_rect(material_icon).intersects(_local_rect(material_value))).is_false()

	var play_center := Rect2(440, 200, 400, 320)
	assert_bool(play_center.intersects(_local_rect(hud.get_node("ControlHint") as Control))).is_false()


func test_timer_switches_to_danger_color_only_in_the_final_ten_seconds() -> void:
	var snapshot_script := load(SNAPSHOT_PATH) as GDScript
	var hud_script := load(HUD_PATH) as GDScript
	var player := SessionPlayerState.new()
	var hud := auto_free(hud_script.new()) as Control
	hud.call(
		"configure",
		snapshot_script.create(player, 12.0, 1, 1.0),
		_content_fixture()
	)
	add_child(hud)
	var timer := hud.get_node("TopCenter/Timer") as Label
	var calm_color := timer.get_theme_color("font_color")
	hud.call("apply_snapshot", snapshot_script.create(player, 10.0, 1, 3.0))
	var danger_color := timer.get_theme_color("font_color")
	assert_bool(danger_color.is_equal_approx(calm_color)).is_false()
	hud.call("apply_snapshot", snapshot_script.create(player, 11.0, 1, 4.0))
	assert_bool(timer.get_theme_color("font_color").is_equal_approx(calm_color)).is_true()


func test_control_hint_dismissal_is_permanent_after_move_or_four_elapsed_seconds() -> void:
	if not FileAccess.file_exists(SNAPSHOT_PATH) or not FileAccess.file_exists(HUD_PATH):
		return
	var snapshot_script := load(SNAPSHOT_PATH) as GDScript
	var hud_script := load(HUD_PATH) as GDScript
	var player := SessionPlayerState.new()
	var hud := auto_free(hud_script.new()) as Control
	hud.call("configure", snapshot_script.create(player, 12.0, 1, 0.0), _content_fixture())
	add_child(hud)
	assert_bool(hud.has_node("Backdrop")).is_false()
	var hint := hud.get_node("ControlHint") as Control
	assert_bool(hint.visible).is_true()
	hud.call("note_movement", Vector2.RIGHT)
	assert_bool(hint.visible).is_false()
	hud.call("apply_snapshot", snapshot_script.create(player, 11.0, 1, 0.0))
	assert_bool(hint.visible).is_false()

	var timed_hud := auto_free(hud_script.new()) as Control
	timed_hud.call("configure", snapshot_script.create(player, 8.0, 1, 4.0), _content_fixture())
	add_child(timed_hud)
	assert_bool((timed_hud.get_node("ControlHint") as Control).visible).is_false()

	var later_wave_hud := auto_free(hud_script.new()) as Control
	later_wave_hud.call("configure", snapshot_script.create(player, 8.0, 2, 0.0), _content_fixture())
	add_child(later_wave_hud)
	assert_bool((later_wave_hud.get_node("ControlHint") as Control).visible).is_false()


func _content_fixture() -> ContentSnapshot:
	return GogoContentRegistry.new().build_snapshot(ValidationContentFactory.create_packs())


func _add_fixture_weapons(player: SessionPlayerState, content: ContentSnapshot, count: int) -> void:
	for index in count:
		var content_id := (
			ValidationContentFactory.RANGED_ID
			if index % 2 == 0
			else ValidationContentFactory.MELEE_ID
		)
		var result := player.weapon_inventory.add_weapon(content_id, content, 1)
		assert_int(int(result.error)).is_equal(OK)


func _local_rect(control: Control) -> Rect2:
	return Rect2(control.position, control.size)


func _has_property(object: Object, property_name: StringName) -> bool:
	for property: Dictionary in object.get_property_list():
		if StringName(property.get("name", "")) == property_name:
			return true
	return false


func _static_ui_snapshot() -> GogoStaticAssetSnapshot:
	var texture := _test_texture()
	var handle := GogoStaticAssetHandle.new()
	handle._configure({
		"binding_key": &"combat_hud_shell|ui_texture|",
		"asset_id": &"combat_hud_shell",
		"role": &"ui_texture",
		"selector": &"",
		"display_size_px": Vector2i(320, 180),
		"display_scale": Vector2.ONE,
		"pivot_px": Vector2i(160, 90),
		"anchors_px": {},
		"atlas_rect_px": Rect2i(0, 0, 320, 180),
	}, texture)
	var snapshot := GogoStaticAssetSnapshot.new()
	snapshot._configure(
		1,
		"fixture",
		70,
		{&"combat_hud_shell": &"preview_ready"},
		{"combat_hud_shell|ui_texture|": handle},
		{},
		{},
		{"global||combat_hud_shell|": "combat_hud_shell|ui_texture|"},
		[]
	)
	return snapshot


func _test_texture() -> ImageTexture:
	var image := Image.create(320, 180, false, Image.FORMAT_RGBA8)
	image.fill(Color8(18, 23, 25, 255))
	return ImageTexture.create_from_image(image)
