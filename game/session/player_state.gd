class_name SessionPlayerState
extends Resource

@export var player_index: int = 0
@export var character_id: StringName = &""
@export var level: int = 1
@export var xp: int = 0
@export var xp_to_next_level: int = 20
@export var materials: int = 35
@export var current_health: float = 10.0
@export var max_health: float = 10.0
@export var base_stats: Dictionary = {}
@export var final_stats: Dictionary = {}
@export var weapon_ids: Array[StringName] = []
@export var weapon_levels: Dictionary = {}
@export var item_ids: Array[StringName] = []
@export var upgrade_ids: Array[StringName] = []


func add_xp(amount: int) -> int:
	xp += maxi(amount, 0)
	var gained := 0
	while xp >= xp_to_next_level:
		xp -= xp_to_next_level
		level += 1
		gained += 1
		xp_to_next_level = int(round(20.0 + 8.0 * pow(float(level - 1), 1.35)))
	return gained


func add_materials(amount: int) -> void:
	materials = maxi(materials + amount, 0)


func try_spend(amount: int) -> bool:
	if amount < 0 or materials < amount:
		return false
	materials -= amount
	return true


func duplicate_state() -> SessionPlayerState:
	return duplicate(true) as SessionPlayerState
