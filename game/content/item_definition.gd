class_name GogoItemDefinition
extends GogoContentDefinition

@export var tier: int = 1
@export var price: int = 12
@export var stat_modifiers: Dictionary = {}
@export var effect_ids: Array[StringName] = []
@export var max_count: int = 99


func _init() -> void:
	kind = &"item"
