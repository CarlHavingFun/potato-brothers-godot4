class_name NikoContentFactory
extends RefCounted

const CHARACTER_ID: StringName = &"character.niko:character/niko"
const NIKO_FRAMES := preload("res://game/content/packs/characters/niko/niko_animations.tres")
const NIKO_ATTACHMENT_RIG_PATH := "res://game/content/packs/characters/niko/rig/niko_attachment_rig_v2.json"


static func create_pack() -> GogoContentPackDefinition:
	var pack := GogoContentPackDefinition.new()
	pack.pack_id = &"character.niko"
	pack.pack_kind = &"character"
	var character := CharacterDefinition.new()
	character.content_id = CHARACTER_ID
	character.display_name = "Niko"
	character.tags = [&"niko", &"balanced"]
	character.base_stats = {
		&"max_health": 20.0,
		&"movement_speed": 300.0,
		&"damage_multiplier": 1.0,
		&"attack_speed": 1.0,
		&"armor": 0.0,
		&"dodge": 0.0,
		&"pickup_range": 115.0,
		&"health_regen": 0.0,
	}
	character.sprite_frames = NIKO_FRAMES
	character.default_animation = &"walk_down"
	character.visual_scale = Vector2.ONE
	character.visual_offset = Vector2(0.0, -25.0)
	var attachment_rig := GogoCharacterAttachmentRig.load_from_path(NIKO_ATTACHMENT_RIG_PATH)
	character.attachment_rig = attachment_rig
	if not attachment_rig.is_valid():
		push_error("Niko attachment rig is invalid: %s" % "; ".join(attachment_rig.validation_errors()))
	pack.definitions.append(character)
	return pack
