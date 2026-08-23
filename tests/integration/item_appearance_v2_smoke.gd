extends SceneTree

const APPEARANCE_SCRIPT := preload("res://game/content/appearance_definition.gd")


func _initialize() -> void:
	var low := APPEARANCE_SCRIPT.new()
	low.appearance_id = &"test/hat_low"
	low.texture = _texture(Color.RED)
	low.slot = &"hat"
	low.display_priority = 1
	low.depth = 20
	var high := APPEARANCE_SCRIPT.new()
	high.appearance_id = &"test/hat_high"
	high.texture = _texture(Color.GREEN)
	high.slot = &"hat"
	high.display_priority = 2
	high.depth = 30
	var back := APPEARANCE_SCRIPT.new()
	back.appearance_id = &"test/back"
	back.texture = _texture(Color.BLUE)
	back.slot = &""
	back.depth = -10

	var first_item_id := &"gogobro.core:item/training_1"
	var second_item_id := &"gogobro.core:item/training_2"
	var packs := ValidationContentFactory.create_packs()
	for pack in packs:
		for definition in pack.definitions:
			if definition.content_id == first_item_id:
				(definition as GogoItemDefinition).appearances = [low, back]
			elif definition.content_id == second_item_id:
				(definition as GogoItemDefinition).appearances = [high]
	var registry := GogoContentRegistry.new()
	var snapshot := registry.build_snapshot(packs)
	if not _require(snapshot != null, "content snapshot"):
		return

	var config := SessionConfig.new()
	config.seed = 19
	config.character_id = NikoContentFactory.CHARACTER_ID
	config.starting_weapon_id = ValidationContentFactory.MELEE_ID
	config.difficulty_id = ValidationContentFactory.DIFFICULTY_ID
	config.zone_id = ValidationContentFactory.ZONE_ID
	var session := GameSession.new()
	if not _require(session.start(config, snapshot) == OK, "session start"):
		return
	session.run_state.player().item_ids.assign([first_item_id, first_item_id, second_item_id])

	var root := Node2D.new()
	get_root().add_child(root)
	var world := CombatWorld.new()
	root.add_child(world)
	await process_frame
	var zone := snapshot.definition(config.zone_id, &"zone") as GogoZoneDefinition
	var wave := snapshot.definition(zone.wave_ids[0], &"wave") as GogoWaveDefinition
	if not _require(world.start_wave(session, wave) == OK, "world start"):
		return
	await process_frame

	var rig := world.player_actor.get_node_or_null("VisualRig") as CharacterVisualRig
	if not _require(rig != null, "visual rig"):
		return
	if not _require(rig.base_sprite != null and rig.base_sprite.sprite_frames.get_frame_count(&"walk_down") == 8, "base animation preserved"):
		return
	var sprites := rig.appearance_sprites()
	if not _require(sprites.size() == 2, "duplicate item collapsed and slot conflict resolved"):
		return
	if not _require(sprites[0].get_meta(&"appearance_id") == &"test/back" and sprites[0].z_index == -10, "back appearance depth"):
		return
	if not _require(sprites[1].get_meta(&"appearance_id") == &"test/hat_high" and sprites[1].z_index == 30, "higher priority hat wins"):
		return

	session.run_state.player().item_ids.erase(second_item_id)
	world.player_actor.rebuild_appearances()
	sprites = rig.appearance_sprites()
	if not _require(sprites.size() == 2, "rebuild keeps one duplicate appearance"):
		return
	if not _require(sprites[1].get_meta(&"appearance_id") == &"test/hat_low", "lower priority hat restored after removal"):
		return
	print("ITEM_APPEARANCE_V2_SMOKE_OK overlays=%d" % sprites.size())
	quit(0)


func _texture(color: Color) -> ImageTexture:
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)


func _require(condition: bool, label: String) -> bool:
	if condition:
		return true
	push_error("ITEM_APPEARANCE_V2_SMOKE_FAILED: " + label)
	quit(1)
	return false
