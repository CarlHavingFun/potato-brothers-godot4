extends Resource
class_name UnitStats

enum UnitType {
	PLAYER,
	ENEMY
}

@export var name: String
@export var content_id: StringName
@export var type: UnitType
@export var icon: Texture2D
@export var health := 1
@export var health_increase_per_wave := 1.0
@export var damage := 1.0
@export var damage_increase_per_wave := 1.0
@export var speed := 300
@export var luck := 1.0
@export var block_chance := 0.0
@export var gold_drop := 1
@export var hp_regen := 0.0
@export var life_steal := 0.0
@export var harvesting := 0.0


func get_stable_id() -> StringName:
	if not content_id.is_empty():
		return content_id
	if not resource_path.is_empty():
		return StringName(resource_path)
	return StringName(name.to_snake_case())
