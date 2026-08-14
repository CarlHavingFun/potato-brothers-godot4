class_name CombatResolver
extends RefCounted


const ARMOR_HALF_DAMAGE_POINT := 15.0


func damage_after_armor(raw_damage: float, armor: float) -> float:
	var damage := maxf(0.0, raw_damage)
	if armor >= 0.0:
		return damage * ARMOR_HALF_DAMAGE_POINT / (ARMOR_HALF_DAMAGE_POINT + armor)
	return damage * (1.0 + absf(armor) / ARMOR_HALF_DAMAGE_POINT)
