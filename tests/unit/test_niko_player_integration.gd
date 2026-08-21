extends GdUnitTestSuite


const NIKO_SCENE_PATH := "res://scenes/unit/players/player_niko.tscn"
const NIKO_RUNTIME_PATH := (
	"res://tools/sprites/niko_character_library/runtime/niko_runtime_frames.tres"
)
const NIKO_AUTHORING_PATH := (
	"res://tools/sprites/niko_character_library/authoring/niko_all_actions.tres"
)
const DEFAULT_PACK_PATH := "res://content_packs/default/pack.tres"
const EXPECTED_ACTIONS: Array[StringName] = [
	&"spawn_down",
	&"idle_down",
	&"walk_down",
	&"hit_down",
	&"death_down",
	&"victory_down",
]
const EXPECTED_SOURCE_TRACKS: Array[StringName] = [
	&"source__spawn_down__born",
	&"source__idle_down__calm",
	&"source__walk_down__happy",
	&"source__walk_down__power",
	&"source__walk_down__strong",
	&"source__hit_down__hit",
	&"source__death_down__die",
	&"source__death_down__niko_die",
	&"source__victory_down__happy_jump",
]


func test_authoring_resource_exposes_every_full_video_take_and_frame_018() -> void:
	var authoring := ResourceLoader.load(
		NIKO_AUTHORING_PATH, "SpriteFrames", ResourceLoader.CACHE_MODE_REPLACE
	) as SpriteFrames
	assert_object(authoring).is_not_null()
	if authoring == null:
		return
	var expected_names: Array[StringName] = []
	expected_names.append_array(EXPECTED_ACTIONS)
	expected_names.append_array(EXPECTED_SOURCE_TRACKS)
	assert_array(authoring.get_animation_names()).contains_exactly_in_any_order(expected_names)
	for animation_name: StringName in expected_names:
		assert_int(authoring.get_frame_count(animation_name)).override_failure_message(
			String(animation_name)
		).is_equal(124)
		assert_float(authoring.get_animation_speed(animation_name)).override_failure_message(
			String(animation_name)
		).is_equal_approx(24.0, 0.001)
		assert_object(authoring.get_frame_texture(animation_name, 17)).override_failure_message(
			"frame 018 missing from %s" % animation_name
		).is_not_null()


func test_niko_player_scene_uses_compact_runtime_and_preserves_the_root_anchor() -> void:
	assert_bool(ResourceLoader.exists(NIKO_SCENE_PATH)).is_true()
	if not ResourceLoader.exists(NIKO_SCENE_PATH):
		return
	var packed := ResourceLoader.load(NIKO_SCENE_PATH, "PackedScene") as PackedScene
	var player := auto_free(packed.instantiate()) as Player
	var visual := player.get_node_or_null("Visuals/DirectionalSpriteVisual") as DirectionalSpriteVisual
	assert_object(visual).is_not_null()
	if visual == null:
		return
	assert_vector(visual.position).is_equal(Vector2(-128, -232))
	assert_bool(visual.centered).is_false()
	assert_int(visual.texture_filter).is_equal(CanvasItem.TEXTURE_FILTER_NEAREST)
	assert_object(visual.sprite_frames).is_not_null()
	assert_str(visual.sprite_frames.resource_path).is_equal(NIKO_RUNTIME_PATH)
	assert_array(visual.sprite_frames.get_animation_names()).contains_exactly_in_any_order(
		EXPECTED_ACTIONS
	)
	for action: StringName in EXPECTED_ACTIONS:
		assert_int(visual.sprite_frames.get_frame_count(action)).override_failure_message(
			String(action)
		).is_equal(124)
	assert_bool(visual.sprite_frames.has_animation(&"dash_down")).is_false()
	for direction: StringName in DirectionalSpriteVisual.DIRECTIONS:
		assert_str(visual.animation_name_for(&"walk", direction)).override_failure_message(
			String(direction)
		).is_equal("walk_down")


func test_only_well_rounded_uses_the_niko_player_scene_in_the_default_pack() -> void:
	var pack := ResourceLoader.load(DEFAULT_PACK_PATH, "ContentPackDef") as ContentPackDef
	assert_object(pack).is_not_null()
	if pack == null:
		return
	var found_well_rounded := false
	for character: CharacterDef in pack.characters:
		if character.content_id == &"character/well_rounded":
			found_well_rounded = true
			assert_str(character.scene.resource_path).is_equal(NIKO_SCENE_PATH)
		elif character.content_id == &"character/almighty":
			assert_str(character.scene.resource_path).is_equal(
				"res://scenes/unit/players/player_well_rounded.tscn"
			)
	assert_bool(found_well_rounded).is_true()
