class_name PlayerBuildService
extends RefCounted

var pipeline := GogoStatPipeline.new()


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
