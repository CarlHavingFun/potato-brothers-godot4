class_name GogoUpgradeDefinition
extends GogoContentDefinition

@export var tier: int = 1
@export var stat_modifiers: Dictionary = {}


func _init() -> void:
	kind = &"upgrade"
