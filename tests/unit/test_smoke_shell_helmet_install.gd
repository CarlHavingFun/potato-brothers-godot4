extends GdUnitTestSuite


const ICON_PATH := "res://game/assets/gogobro_static/items/smoke_shell_helmet.png"
const APPEARANCE_PATH := "res://game/assets/gogobro_static/items/smoke_shell_helmet_appearance.png"
const PREVIEW_APPEARANCE_PATH := (
	"res://game/assets/gogobro_static_preview/items/smoke_shell_helmet_appearance.png"
)
const ANCHORS_PATH := (
	"res://game/content/packs/items/smoke_shell_helmet/anchors_walk_down.json"
)
const EXPECTED_ICON_SHA256 := "AC3ACB1118DEFA21907EE7323BC4D07B8DEE53FCCCABDD94CD26DA73686680DE"
const EXPECTED_APPEARANCE_SHA256 := "B3932E02DAF39074CE048E45B6FAE7F221019D87AD7B3A4327FA40714F25874A"
const EXPECTED_ANCHORS_SHA256 := "7055D9A6A12B35C06BA3744A78F8CA7CC4B5C9E7E48CF0BA94BA383898C0978E"


func test_installed_files_match_the_approved_shipping_icon_and_appearance_artifacts() -> void:
	assert_bool(FileAccess.file_exists(ICON_PATH)).is_true()
	assert_bool(FileAccess.file_exists(APPEARANCE_PATH)).is_true()
	assert_bool(FileAccess.file_exists(ANCHORS_PATH)).is_true()
	if not (
		FileAccess.file_exists(ICON_PATH)
		and FileAccess.file_exists(APPEARANCE_PATH)
		and FileAccess.file_exists(ANCHORS_PATH)
	):
		return
	assert_str(FileAccess.get_sha256(ICON_PATH).to_upper()).is_equal(EXPECTED_ICON_SHA256)
	assert_str(FileAccess.get_sha256(APPEARANCE_PATH).to_upper()).is_equal(
		EXPECTED_APPEARANCE_SHA256
	)
	assert_str(FileAccess.get_sha256(ANCHORS_PATH).to_upper()).is_equal(EXPECTED_ANCHORS_SHA256)
	assert_vector(Vector2(load(ICON_PATH).get_size())).is_equal(Vector2(64, 64))
	assert_vector(Vector2(load(APPEARANCE_PATH).get_size())).is_equal(Vector2(128, 128))


func test_debug_item_definition_installs_the_approved_niko_head_shell_appearance() -> void:
	var content := GogoContentRegistry.new().build_snapshot(ValidationContentFactory.create_packs())
	assert_object(content).is_not_null()
	if content == null:
		return
	var item := content.definition(
		&"gogobro.preview:item/smoke_shell_helmet",
		&"item"
	) as GogoItemDefinition
	assert_object(item).is_not_null()
	if item == null:
		return
	assert_str(String(item.icon_asset_id)).is_equal("smoke_shell_helmet")
	assert_int(item.appearances.size()).is_equal(1)
	if item.appearances.is_empty():
		return
	var appearance := item.appearances[0]
	assert_str(String(appearance.appearance_id)).is_equal(
		"gogobro.preview:appearance/smoke_shell_helmet"
	)
	assert_str(String(appearance.target_character_id)).is_equal(String(NikoContentFactory.CHARACTER_ID))
	assert_str(String(appearance.slot)).is_equal("head")
	assert_str(String(appearance.socket_id)).is_equal("head_shell")
	assert_int(appearance.mode).is_equal(GogoAppearanceDefinition.Mode.RIGID)
	assert_int(appearance.depth).is_equal(40)
	assert_vector(appearance.render_scale).is_equal(Vector2(0.625, 0.625))
	assert_vector(Vector2(appearance.rendered_pivot_px)).is_equal(Vector2(36, 48))
	assert_vector(Vector2(appearance.local_offset_px)).is_equal(Vector2.ZERO)
	assert_object(appearance.texture).is_not_null()
	assert_str(String(appearance.texture.resource_path)).is_equal(PREVIEW_APPEARANCE_PATH)
	assert_bool(appearance.is_valid()).is_true()


func test_shipping_snapshot_resolves_the_approved_inventory_icon() -> void:
	var content := GogoContentRegistry.new().build_snapshot(
		ValidationContentFactory.create_packs(false)
	)
	assert_object(content).is_not_null()
	if content == null:
		return
	var service := GogoStaticAssetRuntimeService.new()
	assert_int(service.stage(content)).is_equal(OK)
	assert_int(service.activate_staged(&"", null)).is_equal(OK)
	var snapshot := service.active_snapshot()
	assert_str(String(snapshot.state_for_asset(&"smoke_shell_helmet"))).is_equal("ready")
	assert_object(snapshot.resolve_asset(&"smoke_shell_helmet", &"icon")).is_not_null()
	assert_object(snapshot.resolve_asset(&"smoke_shell_helmet", &"appearance")).is_null()


func test_approved_anchor_contract_stays_aligned_across_all_eight_niko_walk_frames() -> void:
	var content := GogoContentRegistry.new().build_snapshot(ValidationContentFactory.create_packs())
	assert_object(content).is_not_null()
	if content == null:
		return
	var item := content.definition(
		&"gogobro.preview:item/smoke_shell_helmet",
		&"item"
	) as GogoItemDefinition
	var character := content.definition(
		NikoContentFactory.CHARACTER_ID,
		&"character"
	) as CharacterDefinition
	assert_object(item).is_not_null()
	assert_object(character).is_not_null()
	if item == null or character == null or item.appearances.is_empty():
		return
	var rig := auto_free(CharacterVisualRig.new()) as CharacterVisualRig
	assert_int(rig.configure(character, item.appearances)).is_equal(OK)
	if rig.appearance_sprites().is_empty():
		return
	var sprite := rig.appearance_sprites()[0]
	var anchors := JSON.parse_string(FileAccess.get_file_as_string(ANCHORS_PATH)) as Dictionary
	var frames := anchors.get("frames", []) as Array
	assert_int(frames.size()).is_equal(8)
	for frame_index in frames.size():
		rig.base_sprite.frame = frame_index
		var expected_top_left_values := (frames[frame_index] as Dictionary).get("offset", []) as Array
		var expected_top_left := Vector2(
			float(expected_top_left_values[0]),
			float(expected_top_left_values[1])
		)
		var actual_top_left := sprite.position + Vector2(64, 64)
		assert_vector(actual_top_left).is_equal(expected_top_left)
		assert_bool(sprite.visible).is_true()
