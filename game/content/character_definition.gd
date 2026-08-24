class_name CharacterDefinition
extends GogoContentDefinition

@export var base_stats: Dictionary = {}
@export var starting_item_ids: Array[StringName] = []
@export var allowed_weapon_tags: Array[StringName] = []
@export var sprite_frames: SpriteFrames
@export var default_animation: StringName = &""
@export var visual_scale := Vector2.ONE
@export var visual_offset := Vector2.ZERO
@export var attachment_rig: GogoCharacterAttachmentRig
@export var appearances: Array[GogoAppearanceDefinition] = []


func _init() -> void:
	kind = &"character"


func is_valid() -> bool:
	if not super.is_valid():
		return false
	if attachment_rig == null:
		return true
	if not attachment_rig.is_valid() or attachment_rig.character_id != content_id:
		return false
	return attachment_rig.validate_sprite_frames(sprite_frames).is_empty()
