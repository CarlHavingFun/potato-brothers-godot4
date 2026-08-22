class_name CharacterDefinition
extends GogoContentDefinition

@export var base_stats: Dictionary = {}
@export var starting_item_ids: Array[StringName] = []
@export var allowed_weapon_tags: Array[StringName] = []
@export var sprite_frames: SpriteFrames
@export var default_animation: StringName = &""
@export var visual_scale := Vector2.ONE
@export var visual_offset := Vector2.ZERO


func _init() -> void:
	kind = &"character"
