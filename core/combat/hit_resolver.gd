class_name HitResolver
extends RefCounted


const ARMOR_HALF_DAMAGE_POINT := 15.0

var combat_resolver: CombatResolver
var _fallback_rng := RandomNumberGenerator.new()


func _init(resolver: CombatResolver = null) -> void:
	combat_resolver = resolver
	_fallback_rng.seed = 0x48495452


func resolve(request: HitRequest) -> HitResult:
	var result := HitResult.new()
	if request == null:
		return result
	result.raw_damage = maxf(0.0, request.raw_damage)
	result.critical = request.critical
	result.knockback = request.knockback
	result.source = request.source
	result.gameplay_source = request.gameplay_source
	result.target = request.target
	result.tags = request.tags.duplicate()
	result.attempted = result.raw_damage > 0.0
	if not result.attempted:
		return result

	var dodge_chance := clampf(request.dodge_chance, 0.0, 1.0)
	if dodge_chance > 0.0 and _roll_chance(dodge_chance):
		result.dodged = true
		return result

	var scaled_damage := result.raw_damage * maxf(0.0, request.damage_multiplier)
	result.damage = _damage_after_armor(scaled_damage, request.armor)
	result.landed = result.damage > 0.0
	return result


func _damage_after_armor(raw_damage: float, armor: float) -> float:
	if combat_resolver != null:
		return combat_resolver.damage_after_armor(raw_damage, armor)
	if armor >= 0.0:
		return raw_damage * ARMOR_HALF_DAMAGE_POINT / (ARMOR_HALF_DAMAGE_POINT + armor)
	return raw_damage * (1.0 + absf(armor) / ARMOR_HALF_DAMAGE_POINT)


func _roll_chance(chance: float) -> bool:
	if combat_resolver != null:
		return combat_resolver.roll_chance(chance)
	return _fallback_rng.randf() < chance
