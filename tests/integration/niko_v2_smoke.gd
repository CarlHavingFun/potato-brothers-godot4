extends SceneTree

const NIKO_ID: StringName = &"character.niko:character/niko"


func _initialize() -> void:
	var registry := GogoContentRegistry.new()
	var snapshot := registry.build_snapshot(ValidationContentFactory.create_packs())
	if not _require(snapshot != null, "content snapshot"):
		return
	if not _require(snapshot.has_definition(NIKO_ID, &"character"), "Niko character pack registered"):
		return
	var definition := snapshot.definition(NIKO_ID, &"character") as CharacterDefinition
	var frames := definition.get("sprite_frames") as SpriteFrames
	if not _require(frames != null, "Niko SpriteFrames assigned"):
		return
	if not _require(frames.has_animation(&"walk_down"), "walk_down animation"):
		return
	if not _require(frames.get_frame_count(&"walk_down") == 8, "eight walk frames"):
		return
	if not _require(is_equal_approx(frames.get_animation_speed(&"walk_down"), 8.0), "eight FPS"):
		return

	var config := SessionConfig.new()
	config.seed = 9
	config.character_id = NIKO_ID
	config.starting_weapon_id = ValidationContentFactory.MELEE_ID
	config.difficulty_id = ValidationContentFactory.DIFFICULTY_ID
	config.zone_id = ValidationContentFactory.ZONE_ID
	var session := GameSession.new()
	if not _require(session.start(config, snapshot) == OK, "Niko session start"):
		return
	var root := Node2D.new()
	get_root().add_child(root)
	var world := CombatWorld.new()
	root.add_child(world)
	await process_frame
	var zone := snapshot.definition(ValidationContentFactory.ZONE_ID, &"zone") as GogoZoneDefinition
	var wave := snapshot.definition(zone.wave_ids[0], &"wave") as GogoWaveDefinition
	if not _require(world.start_wave(session, wave) == OK, "Niko combat world start"):
		return
	await process_frame
	if not _require(world.arena_rect.size == Vector2(2048.0, 1536.0), "Brotato-sized 32x24 tile arena"):
		return
	var camera := world.get_node_or_null("PlayerCamera") as Camera2D
	if not _require(camera != null and camera.enabled, "player-following combat camera"):
		return
	var actor := world.player_actor
	var visual := actor.get_node_or_null("CharacterVisual") as AnimatedSprite2D
	if not _require(visual != null, "runtime character visual"):
		return
	if not _require(visual.sprite_frames.get_frame_count(&"walk_down") == 8, "runtime uses Niko SpriteFrames"):
		return
	if not _require(visual.scale == Vector2.ONE, "runtime uses authored sprite size"):
		return
	var first_texture := visual.sprite_frames.get_frame_texture(&"walk_down", 0) as AtlasTexture
	if not _require(first_texture != null and first_texture.region.size == Vector2(128.0, 128.0), "runtime Niko cells are baked to 128px"):
		return
	print("NIKO_V2_SMOKE_OK frames=%d fps=%.1f" % [
		frames.get_frame_count(&"walk_down"),
		frames.get_animation_speed(&"walk_down"),
	])
	quit(0)


func _require(condition: bool, label: String) -> bool:
	if condition:
		return true
	push_error("NIKO_V2_SMOKE_FAILED: " + label)
	quit(1)
	return false
