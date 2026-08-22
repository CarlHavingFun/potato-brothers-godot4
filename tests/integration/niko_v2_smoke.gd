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
	var actor := GogoPlayerActor.new()
	actor.configure(session, null)
	root.add_child(actor)
	await process_frame
	var visual := actor.get_node_or_null("CharacterVisual") as AnimatedSprite2D
	if not _require(visual != null, "runtime character visual"):
		return
	if not _require(visual.sprite_frames.get_frame_count(&"walk_down") == 8, "runtime uses Niko SpriteFrames"):
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
