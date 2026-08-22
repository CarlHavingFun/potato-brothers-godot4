class_name NikoContentFactory
extends RefCounted

const CHARACTER_ID: StringName = &"character.niko:character/niko"
const NIKO_FRAMES := preload("res://game/content/packs/characters/niko/niko_animations.tres")


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
		&"movement_speed": 235.0,
		&"damage_multiplier": 1.0,
		&"attack_speed": 1.0,
		&"armor": 0.0,
		&"dodge": 0.0,
		&"pickup_range": 115.0,
		&"health_regen": 0.0,
	}
	character.sprite_frames = NIKO_FRAMES
	character.default_animation = &"walk_down"
	character.visual_scale = Vector2(0.1, 0.1)
	character.visual_offset = Vector2(0.0, -3.0)
	pack.definitions.append(character)
	return pack
