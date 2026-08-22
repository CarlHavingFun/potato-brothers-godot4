class_name GogoEffectDefinition
extends GogoContentDefinition

enum Stage { CHARACTER, EQUIPMENT, TEMPORARY, DIFFICULTY, FINAL_CLAMP }

@export var event_id: StringName = &""
@export var stage: Stage = Stage.EQUIPMENT
@export var operations: Array[Dictionary] = []


func _init() -> void:
	kind = &"effect"
