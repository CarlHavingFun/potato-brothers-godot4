class_name PlayerBuildService
extends RefCounted

var pipeline := GogoStatPipeline.new()


func upgrade_reward_offers(session: GameSession, count: int = 4) -> Array[GogoUpgradeDefinition]:
	if session == null or session.run_state == null or session.content_snapshot == null:
		return []
	var pool: Array[GogoUpgradeDefinition] = []
	for definition in session.content_snapshot.all(&"upgrade"):
		pool.append(definition as GogoUpgradeDefinition)
	if pool.size() < count:
		return []
	var rng := RandomNumberGenerator.new()
	var state := session.run_state
	rng.seed = (
		state.run_seed
		+ state.current_wave * 1000003
		+ state.pending_upgrade_count * 9176
		+ state.upgrade_reroll_count * 31337
	)
	var result: Array[GogoUpgradeDefinition] = []
	while result.size() < count and not pool.is_empty():
		result.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
	return result


func upgrade_reroll_price(session: GameSession) -> int:
	return 1


func reroll_upgrade_rewards(session: GameSession) -> Error:
	if session == null or session.run_state == null:
		return ERR_INVALID_PARAMETER
	var player := session.run_state.player()
	if player == null or not player.try_spend(upgrade_reroll_price(session)):
		return ERR_UNAUTHORIZED
	session.run_state.upgrade_reroll_count += 1
	session.state_changed.emit()
	return OK


func rebuild(session: GameSession, player: SessionPlayerState) -> Error:
	if session == null or player == null:
		return ERR_INVALID_PARAMETER
	var character := session.content_snapshot.definition(player.character_id, &"character") as CharacterDefinition
	if character == null:
		return ERR_DOES_NOT_EXIST
	var equipment_modifiers: Array[Dictionary] = []
	for item_id in player.item_ids:
		var item := session.content_snapshot.definition(item_id, &"item") as GogoItemDefinition
		if item != null:
			equipment_modifiers.append(item.stat_modifiers)
	for upgrade_id in player.upgrade_ids:
		var upgrade := session.content_snapshot.definition(upgrade_id, &"upgrade") as GogoUpgradeDefinition
		if upgrade != null:
			equipment_modifiers.append(upgrade.stat_modifiers)
	var previous_max := player.max_health
	player.base_stats = character.base_stats.duplicate(true)
	player.final_stats = pipeline.rebuild(player.base_stats, {&"equipment": equipment_modifiers})
	player.max_health = float(player.final_stats.get(&"max_health", 1.0))
	player.current_health = clampf(player.current_health + maxf(player.max_health - previous_max, 0.0), 0.0, player.max_health)
	return OK


func apply_upgrade(session: GameSession, player: SessionPlayerState, upgrade_id: StringName) -> Error:
	if not session.content_snapshot.has_definition(upgrade_id, &"upgrade"):
		return ERR_DOES_NOT_EXIST
	player.upgrade_ids.append(upgrade_id)
	return rebuild(session, player)


func apply_item(session: GameSession, player: SessionPlayerState, item_id: StringName) -> Error:
	if not session.content_snapshot.has_definition(item_id, &"item"):
		return ERR_DOES_NOT_EXIST
	player.item_ids.append(item_id)
	return rebuild(session, player)
