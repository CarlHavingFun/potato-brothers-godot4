class_name SessionPlayerState
extends Resource

const GogoWeaponInventory := preload("res://game/session/weapon_inventory.gd")
const INITIAL_MATERIALS := 20

@export var player_index: int = 0
@export var character_id: StringName = &""
@export var level: int = 1
@export var xp: int = 0
@export var xp_to_next_level: int = 20
@export var materials: int = INITIAL_MATERIALS
@export var economy_material_remainder: float = 0.0
@export var current_health: float = 10.0
@export var max_health: float = 10.0
@export var base_stats: Dictionary = {}
@export var final_stats: Dictionary = {}
@export_storage var weapon_inventory := GogoWeaponInventory.new()
var weapon_ids: Array[StringName]:
	get: return weapon_inventory.content_ids() if weapon_inventory != null else []
var next_weapon_instance_id: int:
	get: return weapon_inventory.next_id() if weapon_inventory != null else 0
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


func add_reward_materials(base_amount: int) -> int:
	var economy_percent := float(final_stats.get(&"economy", 0.0))
	var grant := GogoCombatStatRuntime.economy_reward_grant(
		base_amount,
		economy_percent,
		economy_material_remainder
	)
	var amount := int(grant.get(&"amount", 0))
	economy_material_remainder = float(grant.get(&"remainder", 0.0))
	add_materials(amount)
	return amount


func try_spend(amount: int) -> bool:
	if amount < 0 or materials < amount:
		return false
	materials -= amount
	return true


func duplicate_state() -> SessionPlayerState:
	return duplicate(true) as SessionPlayerState
