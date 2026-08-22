class_name ItemPoolService
extends RefCounted


func generate_shop_offers(snapshot: ContentSnapshot, player: SessionPlayerState, wave: int, count: int, rng: RandomNumberGenerator) -> Array[GogoContentDefinition]:
	var pool: Array[GogoContentDefinition] = []
	pool.append_array(snapshot.all(&"item"))
	pool.append_array(snapshot.all(&"weapon"))
	if pool.is_empty():
		return []
	var result: Array[GogoContentDefinition] = []
	var available := pool.duplicate()
	while result.size() < count and not available.is_empty():
		var index := rng.randi_range(0, available.size() - 1)
		var candidate: GogoContentDefinition = available.pop_at(index)
		if candidate is GogoItemDefinition and player.item_ids.count(candidate.content_id) >= candidate.max_count:
			continue
		result.append(candidate)
	return result


func price_for(definition: GogoContentDefinition, wave: int, reroll_count: int = 0) -> int:
	var base := 10
	if definition is GogoItemDefinition:
		base = definition.price
	elif definition is GogoWeaponDefinition:
		base = definition.price
	return maxi(1, int(round(float(base) * (1.0 + 0.08 * maxf(wave - 1, 0)) + reroll_count)))


func reroll_price(wave: int, reroll_count: int) -> int:
	return maxi(1, 1 + int(floor(float(wave) * 0.5)) + reroll_count)
