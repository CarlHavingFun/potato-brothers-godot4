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
	player.weapon_ids.assign([&"w1", &"w2"])
	player.item_ids.assign([&"i1"])
	var snapshot: Variant = snapshot_script.create(player, 9.25, 4, 2.5)
	assert_int(snapshot.level).is_equal(3)
	assert_int(snapshot.experience).is_equal(11)
	assert_int(snapshot.next_level_requirement).is_equal(42)
	assert_int(snapshot.materials).is_equal(77)
	assert_float(snapshot.health).is_equal_approx(17.0, 0.0001)
	assert_float(snapshot.maximum_health).is_equal_approx(23.0, 0.0001)
	assert_float(snapshot.seconds).is_equal_approx(9.25, 0.0001)
	assert_float(snapshot.wave_elapsed).is_equal_approx(2.5, 0.0001)
	assert_int(snapshot.wave).is_equal(4)
	assert_array(snapshot.weapon_ids).is_equal([&"w1", &"w2"])
	assert_array(snapshot.item_ids).is_equal([&"i1"])
	player.weapon_ids[0] = &"mutated"
	player.item_ids.clear()
	assert_array(snapshot.weapon_ids).is_equal([&"w1", &"w2"])
	assert_array(snapshot.item_ids).is_equal([&"i1"])


func test_hud_uses_fixed_320_by_180_brotato_hierarchy_and_inventory_caps() -> void:
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
	player.weapon_ids.assign([
		ValidationContentFactory.RANGED_ID,
		ValidationContentFactory.MELEE_ID,
		ValidationContentFactory.RANGED_ID,
		ValidationContentFactory.MELEE_ID,
		ValidationContentFactory.RANGED_ID,
		ValidationContentFactory.MELEE_ID,
	])
	for index in 10:
		player.item_ids.append(StringName("gogobro.core:item/training_%d" % ((index % 6) + 1)))
	var snapshot: Variant = snapshot_script.create(player, 9.25, 1, 1.0)
	var hud := auto_free(hud_script.new()) as Control
	hud.call("configure", snapshot, _content_fixture(), _static_ui_snapshot())
	add_child(hud)
	assert_vector(hud.custom_minimum_size).is_equal(Vector2(320, 180))
	assert_vector(hud.size).is_equal(Vector2(320, 180))
	assert_bool(hud.has_node("Shell")).is_true()
	assert_bool(hud.has_node("TopCenter/Timer")).is_true()
	assert_bool(hud.has_node("BottomLeft/HealthBar")).is_true()
	assert_bool(hud.has_node("BottomCenter/ExperienceBar")).is_true()
	assert_bool(hud.has_node("BottomRight/Materials")).is_true()
	assert_int(hud.get_node("WeaponStrip").get_child_count()).is_equal(6)
	assert_int(hud.get_node("ItemStrip").get_child_count()).is_equal(8)
	assert_object((hud.get_node("Shell") as TextureRect).texture).is_not_null()
	assert_bool((hud.get_node("Backdrop") as ColorRect).visible).is_false()
	assert_int((hud.get_node("Shell") as TextureRect).texture_filter).is_equal(
		CanvasItem.TEXTURE_FILTER_NEAREST
	)
	assert_float((hud.get_node("BottomLeft/HealthBar") as ProgressBar).value).is_equal(7.0)
	assert_str((hud.get_node("BottomRight/Materials") as Label).text).contains("91")


func test_control_hint_dismissal_is_permanent_after_move_or_four_elapsed_seconds() -> void:
	if not FileAccess.file_exists(SNAPSHOT_PATH) or not FileAccess.file_exists(HUD_PATH):
		return
	var snapshot_script := load(SNAPSHOT_PATH) as GDScript
	var hud_script := load(HUD_PATH) as GDScript
	var player := SessionPlayerState.new()
	var hud := auto_free(hud_script.new()) as Control
	hud.call("configure", snapshot_script.create(player, 12.0, 1, 0.0), _content_fixture())
	add_child(hud)
	assert_bool((hud.get_node("Backdrop") as ColorRect).visible).is_true()
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


func _content_fixture() -> ContentSnapshot:
	return GogoContentRegistry.new().build_snapshot(ValidationContentFactory.create_packs())


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
