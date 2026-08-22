class_name CharacterDefinition
extends GogoContentDefinition

@export var base_stats: Dictionary = {}
@export var starting_item_ids: Array[StringName] = []
@export var allowed_weapon_tags: Array[StringName] = []


func _init() -> void:
	kind = &"character"
