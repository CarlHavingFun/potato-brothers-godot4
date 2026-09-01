class_name GogoEnemyDefinition
extends GogoContentDefinition

enum Role { CHASER, SHOOTER, CHARGER }

@export var role: Role = Role.CHASER
@export var visual_texture: Texture2D
@export var max_health: float = 8.0
@export var movement_speed: float = 90.0
@export var touch_damage: float = 2.0
@export var xp_value: int = 4
@export var material_value: int = 2
@export var is_boss: bool = false


func _init() -> void:
	kind = &"enemy"
