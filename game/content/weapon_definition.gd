class_name GogoWeaponDefinition
extends GogoContentDefinition

enum Mode { MELEE, RANGED }

@export var mode: Mode = Mode.MELEE
@export_range(1, 4) var tier: int = 1
@export var damage: float = 5.0
@export var cooldown_seconds: float = 0.75
@export var attack_range: float = 120.0
@export var projectile_speed: float = 520.0
@export var projectile_count: int = 1
@export var spread_degrees: float = 0.0
@export var knockback: float = 30.0
@export var price: int = 15


func _init() -> void:
	kind = &"weapon"
