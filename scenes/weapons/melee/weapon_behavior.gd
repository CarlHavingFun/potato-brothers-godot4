extends Node2D
class_name WeaponBehavior

@export var weapon: Weapon

var critical := false

func execute_attack() -> void:
	pass


func on_hit_confirmed(result: HitResult) -> void:
	if result == null or not result.landed or result.damage <= 0.0:
		return
	apply_life_steal()

func get_damage() -> float:
	critical = false
	var scaling_stat_id := get_scaling_stat_id()
	var configured_coefficients: Dictionary = weapon.data.stats.scaling_coefficients
	var damage := Global.combat_resolver.weapon_damage_with_coefficients(
		weapon.data.stats.damage,
		Global.current_run.player_stats,
		configured_coefficients if not configured_coefficients.is_empty() else {
			scaling_stat_id: 1.0,
		},
		weapon.data.stats.is_engineering_structure
	)
	var crit_chance := Global.combat_resolver.critical_chance(
		weapon.data.stats.crit_chance, Global.current_run.player_stats
	)
	if Global.get_chance_sucess(crit_chance):
		critical = true
		damage = ceil(damage * weapon.data.stats.crit_damage)
	return damage


func apply_life_steal() -> void:
	var can_steal := Global.combat_resolver != null and Global.combat_resolver.try_life_steal(
		weapon.data.stats.life_steal, Global.current_run.player_stats
	)
	if can_steal and is_instance_valid(Global.player):
		var heal_amount := Global.combat_resolver.stat_rules.life_steal_heal_amount
		Global.player.health_component.heal(heal_amount)
		Global.on_create_heal_text.emit(Global.player, heal_amount)


func get_scaling_stat_id() -> int:
	var stable_id := String(weapon.data.get_stable_id())
	if stable_id.contains("wand"):
		return StatId.ELEMENTAL_DAMAGE
	if weapon.data.type == ItemWeapon.WeaponType.RANGE:
		return StatId.RANGED_DAMAGE
	return StatId.MELEE_DAMAGE
