extends SceneTree

const RIG_PATH := "res://game/content/packs/characters/niko/rig/niko_attachment_rig_v2.json"
const SOURCE_PROFILE_PATH := "res://tools/assets/rig_profiles/niko_walk_down_v1.json"
const EXPECTED_SOCKETS := [
	"back_center",
	"back_lower",
	"back_upper",
	"chest_center",
	"chest_left",
	"clothes_body",
	"face_mask",
	"feet_pair",
	"forearm_left",
	"forearm_right",
	"forehead",
	"hand_left",
	"hand_right",
	"head_shell",
	"hip_left",
	"hip_right",
	"shoulder_left",
	"shoulder_right",
	"trinket_left",
	"trinket_right",
	"upper_arm_left",
	"upper_arm_right",
	"wrist_left",
	"wrist_right",
]
const ARM_SOCKET_PAIRS := [
	[&"shoulder_left", &"shoulder_right"],
	[&"upper_arm_left", &"upper_arm_right"],
	[&"forearm_left", &"forearm_right"],
	[&"hand_left", &"hand_right"],
]
const EXPECTED_ANATOMY_POSITIONS := {
	&"clothes_body": [
		Vector2i(63, 103), Vector2i(64, 104), Vector2i(63, 104), Vector2i(63, 104),
		Vector2i(65, 103), Vector2i(65, 104), Vector2i(65, 104), Vector2i(63, 104),
	],
	&"shoulder_left": [
		Vector2i(48, 97), Vector2i(48, 98), Vector2i(50, 98), Vector2i(48, 98),
		Vector2i(50, 97), Vector2i(50, 98), Vector2i(50, 98), Vector2i(48, 98),
	],
	&"shoulder_right": [
		Vector2i(78, 97), Vector2i(79, 98), Vector2i(80, 96), Vector2i(79, 98),
		Vector2i(80, 97), Vector2i(79, 98), Vector2i(82, 96), Vector2i(79, 98),
	],
	&"upper_arm_left": [
		Vector2i(43, 99), Vector2i(43, 100), Vector2i(46, 100), Vector2i(43, 100),
		Vector2i(45, 99), Vector2i(45, 100), Vector2i(46, 100), Vector2i(43, 100),
	],
	&"upper_arm_right": [
		Vector2i(82, 99), Vector2i(84, 100), Vector2i(86, 98), Vector2i(84, 100),
		Vector2i(84, 99), Vector2i(84, 100), Vector2i(87, 98), Vector2i(84, 100),
	],
	&"forearm_left": [
		Vector2i(39, 101), Vector2i(39, 101), Vector2i(42, 101), Vector2i(39, 101),
		Vector2i(41, 101), Vector2i(41, 101), Vector2i(42, 101), Vector2i(39, 101),
	],
	&"forearm_right": [
		Vector2i(85, 101), Vector2i(87, 101), Vector2i(88, 100), Vector2i(87, 101),
		Vector2i(87, 101), Vector2i(86, 101), Vector2i(89, 100), Vector2i(86, 101),
	],
	&"hand_left": [
		Vector2i(37, 102), Vector2i(37, 102), Vector2i(41, 102), Vector2i(37, 102),
		Vector2i(39, 102), Vector2i(39, 102), Vector2i(41, 102), Vector2i(37, 102),
	],
	&"hand_right": [
		Vector2i(87, 102), Vector2i(89, 102), Vector2i(89, 102), Vector2i(89, 102),
		Vector2i(87, 102), Vector2i(87, 102), Vector2i(89, 102), Vector2i(87, 102),
	],
}


func _initialize() -> void:
	var character := NikoContentFactory.create_pack().definitions[0] as CharacterDefinition
	if not _require(character != null, "Niko character definition"):
		return
	var attachment_rig := character.attachment_rig
	if not _require(attachment_rig != null and attachment_rig.is_valid(), "valid attachment rig"):
		return
	if not _require(attachment_rig.character_id == character.content_id, "rig bound to Niko"):
		return
	if not _require(attachment_rig.frame_count(&"walk_down") == 8, "eight rig frames"):
		return
	if not _require(Array(attachment_rig.required_socket_ids()) == EXPECTED_SOCKETS, "socket catalog"):
		return
	if not _require(attachment_rig.animation_fps(&"walk_down") == 8.0, "rig declares eight FPS"):
		return
	if not _require(attachment_rig.validate_sprite_frames(character.sprite_frames).is_empty(), "runtime atlas binding"):
		return
	if not _require(_source_profile_matches_anatomy(), "source profile matches runtime anatomy"):
		return
	for frame_index in 8:
		for socket_id in EXPECTED_SOCKETS:
			if not _require(
				attachment_rig.has_socket(&"walk_down", frame_index, socket_id),
				"frame %d has %s" % [frame_index, socket_id]
			):
				return
		for socket_id in EXPECTED_ANATOMY_POSITIONS:
			if not _require(
				attachment_rig.socket_position_pixels(&"walk_down", frame_index, socket_id)
				== EXPECTED_ANATOMY_POSITIONS[socket_id][frame_index],
				"frame %d keeps authored %s coordinate" % [frame_index, socket_id]
			):
				return
		# left/right are authored screen-space labels for this facing-down atlas:
		# left always means the lower pixel x. Runtime never mirrors or swaps them.
		for pair in ARM_SOCKET_PAIRS:
			if not _require(
				attachment_rig.socket_position_pixels(&"walk_down", frame_index, pair[0]).x
				< attachment_rig.socket_position_pixels(&"walk_down", frame_index, pair[1]).x,
				"frame %d keeps screen-left before screen-right" % frame_index
			):
				return
	if not _require(
		attachment_rig.socket_slot(&"clothes_body") == &"clothes"
		and attachment_rig.socket_default_depth(&"clothes_body") == 20
		and attachment_rig.socket_allows_mode(&"clothes_body", "FRAME_OVERLAY")
		and not attachment_rig.socket_allows_mode(&"clothes_body", "RIGID"),
		"clothes uses a depth-20 synchronized overlay"
	):
		return
	for socket_id in [
		&"shoulder_left", &"shoulder_right", &"upper_arm_left", &"upper_arm_right",
		&"forearm_left", &"forearm_right", &"hand_left", &"hand_right",
	]:
		var expected_slot := &"arm_left" if String(socket_id).ends_with("_left") else &"arm_right"
		if not _require(
			attachment_rig.socket_slot(socket_id) == expected_slot
			and attachment_rig.socket_default_depth(socket_id) == 50
			and attachment_rig.socket_allows_mode(socket_id, "RIGID")
			and attachment_rig.socket_allows_mode(socket_id, "FRAME_OVERLAY"),
			"%s arm contract" % socket_id
		):
			return
	if not _require(_runtime_schema_rejects_malformed_rigs(), "runtime schema hard gates"):
		return
	if not _require(_sprite_frame_binding_gates(attachment_rig, character.sprite_frames), "sprite frame binding gates"):
		return
	if not _require(_invalid_rig_rejects_character_pack(character), "invalid rig rejects character pack"):
		return
	var character_with_death := character.duplicate(true) as CharacterDefinition
	character_with_death.sprite_frames = _sprite_frames_with_unbound_death(character.sprite_frames)
	if not _require(
		attachment_rig.validate_sprite_frames(character_with_death.sprite_frames).is_empty()
		and character_with_death.is_valid(),
		"unbound death animation is valid without death sockets"
	):
		return

	var helmet := GogoAppearanceDefinition.new()
	helmet.appearance_id = &"test/smoke_shell_helmet"
	helmet.target_character_id = NikoContentFactory.CHARACTER_ID
	helmet.texture = _texture(Color.ORANGE)
	helmet.slot = &"head"
	helmet.socket_id = &"head_shell"
	helmet.mode = GogoAppearanceDefinition.Mode.RIGID
	helmet.render_scale = Vector2(0.625, 0.625)
	helmet.rendered_pivot_px = Vector2i(36, 48)
	helmet.depth = 40

	var wrong_size_helmet := helmet.duplicate(true) as GogoAppearanceDefinition
	wrong_size_helmet.texture = _texture(Color.ORANGE, Vector2i(64, 64))
	if not _require(_configure_rejects(character, [wrong_size_helmet]), "runtime rejects wrong-size rigid appearance"):
		return

	var non_integral_helmet := helmet.duplicate(true) as GogoAppearanceDefinition
	non_integral_helmet.render_scale = Vector2(0.63, 0.63)
	if not _require(_configure_rejects(character, [non_integral_helmet]), "runtime rejects non-integral rigid render size"):
		return

	var out_of_bounds_pivot_helmet := helmet.duplicate(true) as GogoAppearanceDefinition
	out_of_bounds_pivot_helmet.rendered_pivot_px = Vector2i(80, 48)
	if not _require(_configure_rejects(character, [out_of_bounds_pivot_helmet]), "runtime rejects out-of-bounds rigid pivot"):
		return

	var overlay_frames := _overlay_frames()
	var liner := GogoAppearanceDefinition.new()
	liner.appearance_id = &"test/ballistic_liner"
	liner.target_character_id = NikoContentFactory.CHARACTER_ID
	liner.slot = &"torso"
	liner.socket_id = &"chest_center"
	liner.mode = GogoAppearanceDefinition.Mode.FRAME_OVERLAY
	liner.frame_overlay = overlay_frames
	liner.depth = 40

	var scaled_overlay := _liner_appearance(_overlay_frames(), 40)
	scaled_overlay.render_scale = Vector2(2.0, 2.0)
	if not _require(not scaled_overlay.is_valid(), "frame overlay scale must remain one"):
		return
	if not _require(_configure_rejects(character, [scaled_overlay]), "runtime rejects scaled frame overlay"):
		return

	var wrong_size_overlay := _liner_appearance(_overlay_frames(Vector2i(64, 64)), 40)
	if not _require(_configure_rejects(character, [wrong_size_overlay]), "runtime rejects wrong-size frame overlay"):
		return

	var wrong_depth_overlay := _liner_appearance(_overlay_frames(), 30)
	if not _require(_configure_rejects(character, [wrong_depth_overlay]), "runtime rejects socket depth mismatch"):
		return

	var clothes_frames := _overlay_frames()
	var clothes := GogoAppearanceDefinition.new()
	clothes.appearance_id = &"test/clothes_body"
	clothes.target_character_id = NikoContentFactory.CHARACTER_ID
	clothes.slot = &"clothes"
	clothes.socket_id = &"clothes_body"
	clothes.mode = GogoAppearanceDefinition.Mode.FRAME_OVERLAY
	clothes.frame_overlay = clothes_frames
	clothes.render_scale = Vector2.ONE
	clothes.depth = 20
	for frame_index in 8:
		if not _require(
			Vector2i(clothes_frames.get_frame_texture(&"walk_down", frame_index).get_size()) == Vector2i(128, 128),
			"clothes frame %d uses the full 128 canvas" % frame_index
		):
			return
	var rigid_clothes := _arm_appearance(&"test/invalid_rigid_clothes", &"clothes", &"clothes_body", 0)
	rigid_clothes.depth = 20
	if not _require(_configure_rejects(character, [rigid_clothes]), "clothes socket rejects rigid mode"):
		return

	var left_shoulder := _arm_appearance(&"test/left_shoulder_low", &"arm_left", &"shoulder_left", 1)
	var left_forearm := _arm_appearance(&"test/left_forearm_high", &"arm_left", &"forearm_left", 2)
	var right_hand := _arm_appearance(&"test/multi_character_arm", &"arm_right", &"hand_right", 1)
	var wrong_character_variant := GogoAppearanceDefinition.new()
	wrong_character_variant.appearance_id = right_hand.appearance_id
	wrong_character_variant.target_character_id = &"character.other:character/other"
	wrong_character_variant.mode = GogoAppearanceDefinition.Mode.RIGID
	wrong_character_variant.slot = &"not_a_niko_slot"
	wrong_character_variant.socket_id = &"not_a_niko_socket"
	wrong_character_variant.depth = 50
	var matching_invalid_variant := wrong_character_variant.duplicate(true) as GogoAppearanceDefinition
	matching_invalid_variant.target_character_id = NikoContentFactory.CHARACTER_ID
	if not _require(
		_configure_rejects(character, [matching_invalid_variant]),
		"matching-character formal variant fails closed"
	):
		return
	var missing_target_variant := right_hand.duplicate(true) as GogoAppearanceDefinition
	missing_target_variant.target_character_id = &""
	if not _require(
		_configure_rejects(character, [missing_target_variant]),
		"formal v2 variant requires target_character_id"
	):
		return

	var visual_rig := CharacterVisualRig.new()
	get_root().add_child(visual_rig)
	var configured_appearances: Array[GogoAppearanceDefinition] = [
		helmet,
		liner,
		clothes,
		left_shoulder,
		left_forearm,
		wrong_character_variant,
		right_hand,
	]
	if not _require(
		visual_rig.configure(character_with_death, configured_appearances) == OK,
		"configure visual rig with character-specific variants"
	):
		return
	var helmet_sprite := _appearance(visual_rig, helmet.appearance_id)
	var liner_sprite := _appearance(visual_rig, liner.appearance_id)
	var clothes_sprite := _appearance(visual_rig, clothes.appearance_id)
	var left_arm_sprite := _appearance(visual_rig, left_forearm.appearance_id)
	var right_arm_sprite := _appearance(visual_rig, right_hand.appearance_id)
	if not _require(
		helmet_sprite != null
		and liner_sprite != null
		and clothes_sprite != null
		and left_arm_sprite != null
		and right_arm_sprite != null,
		"appearance sprites"
	):
		return
	if not _require(_appearance(visual_rig, left_shoulder.appearance_id) == null, "arm-left conflict keeps higher priority"):
		return
	if not _require(_appearance_count(visual_rig, right_hand.appearance_id) == 1, "wrong-character variant is ignored"):
		return
	if not _require(not helmet_sprite.centered, "rigid sprite uses top-left pixel origin"):
		return
	if not _require(helmet_sprite.position == Vector2(-38.0, -41.0), "frame zero helmet origin"):
		return
	if not _require(liner_sprite.position == Vector2(-64.0, -64.0), "frame overlay canvas origin"):
		return
	if not _require(liner_sprite.texture == overlay_frames.get_frame_texture(&"walk_down", 0), "overlay frame zero"):
		return
	if not _require(
		clothes_sprite.position == Vector2(-64.0, -64.0)
		and clothes_sprite.texture == clothes_frames.get_frame_texture(&"walk_down", 0)
		and clothes_sprite.scale == Vector2.ONE
		and clothes_sprite.z_index == 20,
		"clothes overlay frame zero, scale and layering"
	):
		return
	if not _require(
		left_arm_sprite.position == Vector2(-33.0, 29.0)
		and right_arm_sprite.position == Vector2(15.0, 30.0)
		and left_arm_sprite.z_index == 50
		and right_arm_sprite.z_index == 50,
		"frame zero arm sockets and layering"
	):
		return

	visual_rig.base_sprite.frame = 2
	await process_frame
	if not _require(
		left_arm_sprite.position == Vector2(-30.0, 29.0)
		and right_arm_sprite.position == Vector2(17.0, 30.0),
		"asymmetric frame two arm sockets are authored independently"
	):
		return
	if not _require(
		clothes_sprite.texture == clothes_frames.get_frame_texture(&"walk_down", 2),
		"clothes overlay follows frame two"
	):
		return

	visual_rig.base_sprite.frame = 4
	await process_frame
	if not _require(helmet_sprite.position == Vector2(-36.0, -41.0), "frame four helmet follows socket"):
		return
	if not _require(liner_sprite.texture == overlay_frames.get_frame_texture(&"walk_down", 4), "overlay follows base frame"):
		return
	if not _require(
		clothes_sprite.texture == clothes_frames.get_frame_texture(&"walk_down", 4)
		and left_arm_sprite.position == Vector2(-31.0, 29.0)
		and right_arm_sprite.position == Vector2(15.0, 30.0),
		"frame four clothes and arm synchronization"
	):
		return

	visual_rig.base_sprite.frame = 7
	await process_frame
	if not _require(helmet_sprite.position == Vector2(-38.0, -41.0), "final frame returns to its own socket"):
		return
	if not _require(liner_sprite.texture == overlay_frames.get_frame_texture(&"walk_down", 7), "final overlay frame"):
		return
	if not _require(
		clothes_sprite.texture == clothes_frames.get_frame_texture(&"walk_down", 7)
		and left_arm_sprite.position == Vector2(-33.0, 29.0)
		and right_arm_sprite.position == Vector2(15.0, 30.0),
		"final clothes and arm frame"
	):
		return

	visual_rig.set_moving(false)
	if not _require(visual_rig.base_sprite.frame == 0, "stop resets base frame"):
		return
	if not _require(helmet_sprite.position == Vector2(-38.0, -41.0), "stop resynchronizes socket"):
		return
	if not _require(
		clothes_sprite.texture == clothes_frames.get_frame_texture(&"walk_down", 0)
		and left_arm_sprite.position == Vector2(-33.0, 29.0),
		"stop resynchronizes clothes and arm sockets"
	):
		return

	visual_rig.base_sprite.animation = &"death"
	visual_rig.base_sprite.frame = 2
	await process_frame
	if not _require(
		visual_rig.base_sprite.animation == &"death"
		and visual_rig.base_sprite.frame == 2
		and visual_rig.appearance_layer.visible,
		"unbound death animation remains the active unadorned base state"
	):
		return
	for sprite in visual_rig.appearance_sprites():
		if not _require(not sprite.visible, "unbound death animation hides every appearance without fallback"):
			return
	visual_rig.base_sprite.animation = &"walk_down"
	visual_rig.base_sprite.frame = 0
	await process_frame
	for sprite in visual_rig.appearance_sprites():
		if not _require(sprite.visible, "returning to bound walk restores each appearance"):
			return

	visual_rig.set_hit_flash(true)
	var flash_material := visual_rig.base_sprite.material as ShaderMaterial
	if not _require(
		visual_rig.is_hit_flash_active()
		and flash_material != null
		and flash_material.shader != null
		and flash_material.shader.code.contains(
			"COLOR = vec4(1.0, 1.0, 1.0, visible_alpha);"
		),
		"hit flash replaces opaque base pixels with pure white while preserving alpha"
	):
		return
	for sprite in visual_rig.appearance_sprites():
		if not _require(sprite.material == flash_material, "hit flash reaches every appearance layer"):
			return
	if not _require(
		visual_rig.rebuild_appearances(configured_appearances) == OK,
		"rebuild appearances while hit flash is active"
	):
		return
	for sprite in visual_rig.appearance_sprites():
		if not _require(sprite.material == flash_material, "rebuilt appearance inherits active hit flash"):
			return

	visual_rig.set_dead(true)
	if not _require(
		not visual_rig.is_hit_flash_active()
		and visual_rig.base_sprite.visible
		and visual_rig.base_sprite.material == null
		and not visual_rig.appearance_layer.visible,
		"death clears flash, keeps base, and hides the whole appearance layer"
	):
		return
	visual_rig.base_sprite.frame = 2
	await process_frame
	if not _require(not visual_rig.appearance_layer.visible, "frame sync cannot reveal death appearances"):
		return
	if not _require(
		visual_rig.rebuild_appearances(configured_appearances) == OK
		and not visual_rig.appearance_layer.visible,
		"appearance rebuild cannot reveal death appearances"
	):
		return
	print("ITEM_ATTACHMENT_SOCKET_V2_SMOKE_OK sockets=%d frames=%d" % [
		EXPECTED_SOCKETS.size(),
		attachment_rig.frame_count(&"walk_down"),
	])
	quit(0)


func _appearance(rig: CharacterVisualRig, appearance_id: StringName) -> Sprite2D:
	for sprite in rig.appearance_sprites():
		if sprite.get_meta(&"appearance_id") == appearance_id:
			return sprite
	return null


func _appearance_count(rig: CharacterVisualRig, appearance_id: StringName) -> int:
	var count := 0
	for sprite in rig.appearance_sprites():
		if sprite.get_meta(&"appearance_id") == appearance_id:
			count += 1
	return count


func _runtime_schema_rejects_malformed_rigs() -> bool:
	var missing_fps := _rig_payload()
	_walk_down_state(missing_fps).erase("fps")
	if not _rig_rejects(missing_fps, "missing_fps"):
		return false

	var wrong_identity := _rig_payload()
	((_walk_down_state(wrong_identity)["frames"] as Array)[7] as Dictionary)["frame_name"] = "walk_down_wrong"
	if not _rig_rejects(wrong_identity, "wrong_identity"):
		return false

	var missing_protected := _rig_payload()
	((_walk_down_state(missing_protected)["frames"] as Array)[0] as Dictionary).erase("protected_regions")
	if not _rig_rejects(missing_protected, "missing_protected"):
		return false

	var wrong_geometry := _rig_payload()
	(wrong_geometry["atlas"] as Dictionary)["atlas_size"] = [512, 128]
	if not _rig_rejects(wrong_geometry, "wrong_geometry"):
		return false

	var wrong_hash := _rig_payload()
	(wrong_hash["atlas"] as Dictionary)["sha256"] = "0".repeat(64)
	if not _rig_rejects(wrong_hash, "wrong_hash"):
		return false

	var non_hex_hash := _rig_payload()
	(non_hex_hash["atlas"] as Dictionary)["sha256"] = "z".repeat(64)
	if not _rig_rejects(non_hex_hash, "non_hex_hash", "64 hexadecimal"):
		return false

	var missing_rgba8_hash := _rig_payload()
	(missing_rgba8_hash["atlas"] as Dictionary).erase("rgba8_sha256")
	if not _rig_rejects(missing_rgba8_hash, "missing_rgba8_hash", "atlas.rgba8_sha256"):
		return false

	var wrong_rgba8_hash := _rig_payload()
	(wrong_rgba8_hash["atlas"] as Dictionary)["rgba8_sha256"] = "0".repeat(64)
	if not _rig_rejects(wrong_rgba8_hash, "wrong_rgba8_hash", "decoded atlas.path pixels"):
		return false

	var fractional_socket := _rig_payload()
	var fractional_frame := ((_walk_down_state(fractional_socket)["frames"] as Array)[0] as Dictionary)
	(fractional_frame["sockets"] as Dictionary)["head_shell"] = [62.5, 71]
	if not _rig_rejects(fractional_socket, "fractional_socket"):
		return false

	var jittered_socket := _rig_payload()
	var jittered_frame := ((_walk_down_state(jittered_socket)["frames"] as Array)[7] as Dictionary)
	(jittered_frame["sockets"] as Dictionary)["head_shell"] = [63, 71]
	if not _rig_rejects(jittered_socket, "jittered_socket"):
		return false

	var wrong_back_depth := _rig_payload()
	((wrong_back_depth["socket_catalog"] as Dictionary)["back_center"] as Dictionary)["default_depth"] = 40
	if not _rig_rejects(wrong_back_depth, "wrong_back_depth"):
		return false

	var missing_column := _rig_payload()
	var missing_column_state := _walk_down_state(missing_column)
	missing_column_state["frame_count"] = 7
	(missing_column_state["frames"] as Array).resize(7)
	if not _rig_rejects(missing_column, "missing_column", "must cover every atlas column"):
		return false

	var duplicate_row := _rig_payload()
	var cloned_state := _walk_down_state(duplicate_row).duplicate(true) as Dictionary
	var cloned_frames := cloned_state["frames"] as Array
	for frame_index in cloned_frames.size():
		(cloned_frames[frame_index] as Dictionary)["frame_name"] = "walk_clone_%02d" % (frame_index + 1)
	(duplicate_row["animations"] as Dictionary)["walk_clone"] = cloned_state
	if not _rig_rejects(duplicate_row, "duplicate_row", "duplicates atlas row"):
		return false

	var missing_row := _rig_payload()
	_walk_down_state(missing_row)["row"] = 1
	return _rig_rejects(missing_row, "missing_row", "missing animation row 0")


func _source_profile_matches_anatomy() -> bool:
	var rig_payload: Variant = JSON.parse_string(FileAccess.get_file_as_string(RIG_PATH))
	var profile_payload: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE_PROFILE_PATH))
	if not rig_payload is Dictionary or not profile_payload is Dictionary:
		return false
	var rig_frames: Array = ((rig_payload as Dictionary)["animations"] as Dictionary)["walk_down"]["frames"]
	var profile_frames: Array = (profile_payload as Dictionary)["frames"]
	if rig_frames.size() != 8 or profile_frames.size() != 8:
		return false
	for frame_index in 8:
		var rig_regions := (rig_frames[frame_index] as Dictionary)["regions"] as Dictionary
		var profile_regions := (profile_frames[frame_index] as Dictionary)["attachment_regions"] as Dictionary
		for socket_id in EXPECTED_ANATOMY_POSITIONS:
			if rig_regions.get(String(socket_id)) != profile_regions.get(String(socket_id)):
				return false
	var slots := (profile_payload as Dictionary)["slot_profiles"] as Dictionary
	return (
		int((slots["clothes"] as Dictionary)["expected_depth"]) == 20
		and int((slots["arm_left"] as Dictionary)["expected_depth"]) == 50
		and int((slots["arm_right"] as Dictionary)["expected_depth"]) == 50
		and (slots["arm_left"] as Dictionary)["flip_behavior"] == "none"
		and (slots["arm_right"] as Dictionary)["flip_behavior"] == "none"
	)


func _sprite_frame_binding_gates(rig: GogoCharacterAttachmentRig, source: SpriteFrames) -> bool:
	var with_unbound_death := _sprite_frames_with_unbound_death(source)
	if not rig.validate_sprite_frames(with_unbound_death).is_empty():
		return false
	var missing_walk := with_unbound_death.duplicate(true) as SpriteFrames
	missing_walk.remove_animation(&"walk_down")
	if not "\n".join(rig.validate_sprite_frames(missing_walk)).contains("missing animation: walk_down"):
		return false
	var wrong_fps := _copy_sprite_frames(source, 0, 7.0)
	if not "\n".join(rig.validate_sprite_frames(wrong_fps)).contains("fps mismatch"):
		return false
	var reordered := _copy_sprite_frames(source, 1, 8.0)
	if not "\n".join(rig.validate_sprite_frames(reordered)).contains("atlas region mismatch"):
		return false
	var unbound := _unbound_atlas_frames()
	return "\n".join(rig.validate_sprite_frames(unbound)).contains("atlas path mismatch")


func _sprite_frames_with_unbound_death(source: SpriteFrames) -> SpriteFrames:
	var frames := source.duplicate(true) as SpriteFrames
	frames.add_animation(&"death")
	frames.set_animation_loop(&"death", false)
	frames.set_animation_speed(&"death", 6.0)
	for frame_index in 3:
		frames.add_frame(&"death", _texture(Color(0.3 + frame_index * 0.2, 0.1, 0.1, 1.0)))
	return frames


func _invalid_rig_rejects_character_pack(character: CharacterDefinition) -> bool:
	var invalid_character := character.duplicate(true) as CharacterDefinition
	invalid_character.attachment_rig = GogoCharacterAttachmentRig.new()
	if invalid_character.is_valid():
		return false
	var invalid_pack := GogoContentPackDefinition.new()
	invalid_pack.pack_id = &"character.invalid_rig_test"
	invalid_pack.pack_kind = &"character"
	invalid_pack.definitions.append(invalid_character)
	if invalid_pack.is_valid():
		return false
	var packs: Array[GogoContentPackDefinition] = [invalid_pack]
	return GogoContentRegistry.new().build_snapshot(packs) == null


func _configure_rejects(character: CharacterDefinition, appearances: Array[GogoAppearanceDefinition]) -> bool:
	var visual_rig := CharacterVisualRig.new()
	get_root().add_child(visual_rig)
	var error := visual_rig.configure(character, appearances)
	visual_rig.free()
	return error == ERR_INVALID_DATA


func _liner_appearance(frames: SpriteFrames, depth: int) -> GogoAppearanceDefinition:
	var liner := GogoAppearanceDefinition.new()
	liner.appearance_id = &"test/liner_validation"
	liner.target_character_id = NikoContentFactory.CHARACTER_ID
	liner.slot = &"torso"
	liner.socket_id = &"chest_center"
	liner.mode = GogoAppearanceDefinition.Mode.FRAME_OVERLAY
	liner.frame_overlay = frames
	liner.depth = depth
	return liner


func _arm_appearance(
	appearance_id: StringName,
	slot: StringName,
	socket_id: StringName,
	priority: int
) -> GogoAppearanceDefinition:
	var definition := GogoAppearanceDefinition.new()
	definition.appearance_id = appearance_id
	definition.target_character_id = NikoContentFactory.CHARACTER_ID
	definition.texture = _texture(Color.CYAN)
	definition.slot = slot
	definition.socket_id = socket_id
	definition.mode = GogoAppearanceDefinition.Mode.RIGID
	definition.display_priority = priority
	definition.depth = 50
	definition.render_scale = Vector2.ONE
	definition.rendered_pivot_px = Vector2i(8, 8)
	return definition


func _copy_sprite_frames(source: SpriteFrames, frame_shift: int, fps: float) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	frames.add_animation(&"walk_down")
	frames.set_animation_loop(&"walk_down", true)
	frames.set_animation_speed(&"walk_down", fps)
	for index in 8:
		frames.add_frame(&"walk_down", source.get_frame_texture(&"walk_down", (index + frame_shift) % 8))
	return frames


func _unbound_atlas_frames() -> SpriteFrames:
	var atlas_image := Image.create(1024, 128, false, Image.FORMAT_RGBA8)
	atlas_image.fill(Color.ORANGE)
	var atlas := ImageTexture.create_from_image(atlas_image)
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	frames.add_animation(&"walk_down")
	frames.set_animation_loop(&"walk_down", true)
	frames.set_animation_speed(&"walk_down", 8.0)
	for index in 8:
		var frame := AtlasTexture.new()
		frame.atlas = atlas
		frame.region = Rect2(index * 128, 0, 128, 128)
		frames.add_frame(&"walk_down", frame)
	return frames


func _rig_payload() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(RIG_PATH))
	return (parsed as Dictionary).duplicate(true) if parsed is Dictionary else {}


func _walk_down_state(payload: Dictionary) -> Dictionary:
	return (payload["animations"] as Dictionary)["walk_down"] as Dictionary


func _rig_rejects(payload: Dictionary, suffix: String, expected_error := "") -> bool:
	var path := "user://attachment_rig_%s_%d.json" % [suffix, Time.get_ticks_usec()]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(payload))
	file.close()
	var rig := GogoCharacterAttachmentRig.load_from_path(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if rig.is_valid():
		return false
	return expected_error.is_empty() or "\n".join(rig.validation_errors()).contains(expected_error)


func _overlay_frames(size := Vector2i(128, 128)) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	frames.add_animation(&"walk_down")
	frames.set_animation_loop(&"walk_down", true)
	frames.set_animation_speed(&"walk_down", 8.0)
	for index in 8:
		frames.add_frame(&"walk_down", _texture(Color(float(index + 1) / 8.0, 0.2, 0.4, 1.0), size))
	return frames


func _texture(color: Color, size := Vector2i(128, 128)) -> ImageTexture:
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)


func _require(condition: bool, label: String) -> bool:
	if condition:
		return true
	push_error("ITEM_ATTACHMENT_SOCKET_V2_SMOKE_FAILED: " + label)
	quit(1)
	return false
