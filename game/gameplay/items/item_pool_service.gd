class_name ItemPoolService
extends RefCounted

const EARLY_WAVE_TIER_WEIGHTS := {
	1: {1: 100.0},
	2: {1: 80.0, 2: 20.0},
	3: {1: 65.0, 2: 30.0, 3: 5.0},
	4: {1: 55.0, 2: 32.0, 3: 13.0},
}
const MATURE_TIER_WEIGHTS := {1: 45.0, 2: 33.0, 3: 18.0, 4: 4.0}


func generate_shop_offers(
	snapshot: ContentSnapshot,
	player: SessionPlayerState,
	wave: int,
	count: int,
	rng: RandomNumberGenerator,
	excluded_ids: Array[StringName] = []
) -> Array[GogoContentDefinition]:
	var pool: Array[GogoContentDefinition] = []
	pool.append_array(snapshot.all(&"item"))
	pool.append_array(snapshot.all(&"weapon"))
	pool.sort_custom(func(a: GogoContentDefinition, b: GogoContentDefinition) -> bool:
		return String(a.content_id) < String(b.content_id)
	)
	if pool.is_empty() or count <= 0:
		return []
	var excluded_lookup: Dictionary = {}
	for content_id: StringName in excluded_ids:
		excluded_lookup[content_id] = true
	var tier_weights := rarity_weights_for_wave(wave)
	var character := snapshot.definition(
		player.character_id, &"character"
	) as CharacterDefinition
	var available_by_tier: Dictionary = {}
	for tier in range(1, 5):
		available_by_tier[tier] = []
	for candidate: GogoContentDefinition in pool:
		if excluded_lookup.has(candidate.content_id):
			continue
		if (
			candidate is GogoItemDefinition
			and player.item_ids.count(candidate.content_id) >= candidate.max_count
		):
			continue
		var tier := _tier_for(candidate)
		if float(tier_weights.get(tier, 0.0)) <= 0.0:
			continue
		if candidate is GogoItemDefinition:
			var item := candidate as GogoItemDefinition
			if not item.is_available_to(player.character_id):
				continue
		elif candidate is GogoWeaponDefinition:
			var weapon := candidate as GogoWeaponDefinition
			if character == null or not character.allows_weapon(weapon):
				continue
		(available_by_tier[tier] as Array).append(candidate)
	for tier in range(1, 5):
		(available_by_tier[tier] as Array).sort_custom(
			func(a: GogoContentDefinition, b: GogoContentDefinition) -> bool:
				return String(a.content_id) < String(b.content_id)
		)
	var result: Array[GogoContentDefinition] = []
	while result.size() < count:
		var tier := _weighted_available_tier(available_by_tier, tier_weights, rng)
		if tier <= 0:
			break
		var tier_pool := available_by_tier[tier] as Array
		var index := rng.randi_range(0, tier_pool.size() - 1)
		result.append(tier_pool.pop_at(index) as GogoContentDefinition)
	return result


func price_for(
	definition: GogoContentDefinition,
	wave: int,
	_reroll_count: int = 0
) -> int:
	var base := 10
	if definition is GogoItemDefinition:
		base = definition.price
	elif definition is GogoWeaponDefinition:
		base = definition.price
	return maxi(1, int(round(float(base) * (1.0 + 0.08 * maxf(wave - 1, 0)))))


func reroll_price(wave: int, reroll_count: int) -> int:
	return maxi(1, 1 + int(floor(float(wave) * 0.5)) + reroll_count)


static func rarity_weights_for_wave(wave: int) -> Dictionary:
	if wave >= 5:
		return MATURE_TIER_WEIGHTS.duplicate()
	return (EARLY_WAVE_TIER_WEIGHTS.get(maxi(wave, 1), {1: 100.0}) as Dictionary).duplicate()


static func maximum_tier_for_wave(wave: int) -> int:
	var result := 1
	var weights := rarity_weights_for_wave(wave)
	for tier: Variant in weights.keys():
		if float(weights.get(tier, 0.0)) > 0.0:
			result = maxi(result, int(tier))
	return result


static func _tier_for(definition: GogoContentDefinition) -> int:
	if definition is GogoItemDefinition:
		return clampi((definition as GogoItemDefinition).tier, 1, 4)
	if definition is GogoWeaponDefinition:
		return clampi((definition as GogoWeaponDefinition).tier, 1, 4)
	return 1


static func _weighted_available_tier(
	available_by_tier: Dictionary,
	tier_weights: Dictionary,
	rng: RandomNumberGenerator
) -> int:
	var total_weight := 0.0
	for tier in range(1, 5):
		if not (available_by_tier[tier] as Array).is_empty():
			total_weight += float(tier_weights.get(tier, 0.0))
	if total_weight <= 0.0:
		return 0
	var roll := rng.randf() * total_weight
	var last_available_tier := 0
	for tier in range(1, 5):
		if (available_by_tier[tier] as Array).is_empty():
			continue
		last_available_tier = tier
		roll -= float(tier_weights.get(tier, 0.0))
		if roll < 0.0:
			return tier
	return last_available_tier
