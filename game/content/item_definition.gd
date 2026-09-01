class_name GogoItemDefinition
extends GogoContentDefinition

@export var tier: int = 1
@export var price: int = 12
@export var stat_modifiers: Dictionary = {}
@export var effect_ids: Array[StringName] = []
@export var max_count: int = 99
@export var owner_character_ids: Array[StringName] = []
@export var appearances: Array[GogoAppearanceDefinition] = []


func _init() -> void:
	kind = &"item"


func is_available_to(character_id: StringName) -> bool:
	return owner_character_ids.is_empty() or owner_character_ids.has(character_id)
