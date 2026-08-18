class_name StatRebuildService
extends RefCounted


## Rebuilds versioned primary stats without touching wave, economy, inventory, or
## random streams. Legacy v3 checkpoints have no complete upgrade ledger, so
## their stored stat snapshot is preserved rather than guessing and losing a
## player's build. Checkpoints produced after v4 can be deterministically
## rebuilt from character, passive, and upgrade records.
func rebuild_if_required(
	run_state: RunState,
	catalog: ContentCatalog,
	balance_pack: BalancePackDef
) -> bool:
	if run_state == null:
		return false
	var target_stat_rules_version := _target_stat_rules_version(balance_pack)
	var target_balance_pack_version := _target_balance_pack_version(balance_pack)
	if not run_state.requires_stat_rebuild(
		target_stat_rules_version,
		target_balance_pack_version
	):
		return true

	var rebuilt_stats := _legacy_snapshot(run_state)
	if rebuilt_stats == null:
		rebuilt_stats = _rebuild_from_ledger(run_state, catalog)
	if rebuilt_stats == null:
		# A removed content definition must not erase or block a resumable build.
		rebuilt_stats = run_state.player_stats.copy()
	return run_state.mark_stats_rebuilt(
		rebuilt_stats,
		target_stat_rules_version,
		target_balance_pack_version
	)


func stamp_current_versions(run_state: RunState, balance_pack: BalancePackDef) -> bool:
	if run_state == null or run_state.player_stats == null:
		return false
	return run_state.mark_stats_rebuilt(
		run_state.player_stats,
		_target_stat_rules_version(balance_pack),
		_target_balance_pack_version(balance_pack)
	)


func _legacy_snapshot(run_state: RunState) -> PlayerStats:
	if (
		run_state.stat_rules_version != RunState.LEGACY_STAT_RULES_VERSION
		and run_state.balance_pack_version != RunState.LEGACY_BALANCE_PACK_VERSION
	):
		return null
	var raw_stats: Variant = run_state.stat_rebuild_source.get("legacy_player_stats", {})
	if raw_stats is Dictionary and not raw_stats.is_empty():
		return PlayerStats.from_dict(raw_stats)
	return run_state.player_stats.copy() if run_state.player_stats != null else null


func _rebuild_from_ledger(
	run_state: RunState,
	catalog: ContentCatalog
) -> PlayerStats:
	if catalog == null:
		return null
	var character := catalog.get_character(run_state.character_id)
	if character == null or character.stats == null:
		return null
	var result := TutorialStatsAdapter.to_player_stats(character.stats)
	var gain_multipliers := {}
	if character.rules != null:
		_apply_modifiers(result, character.rules.starting_stat_modifiers, 1)
		gain_multipliers = character.rules.stat_modification_multipliers

	var inventory_data := run_state.inventory.to_dict() if run_state.inventory != null else {}
	var passive_counts: Variant = inventory_data.get("passives", {})
	if passive_counts is Dictionary:
		for raw_passive_id: Variant in passive_counts:
			var passive := catalog.get_passive(StringName(str(raw_passive_id)))
			if passive != null:
				_apply_modifiers(
					result,
					passive.stat_modifiers,
					maxi(0, int(passive_counts[raw_passive_id])),
					gain_multipliers
				)

	for upgrade: Dictionary in run_state.applied_upgrades:
		var stat_id := int(upgrade.get("stat_id", -1))
		if StatId.is_valid(stat_id):
			result.add_stat(stat_id, float(upgrade.get("value", 0.0)))
	return result


func _apply_modifiers(
	stats: PlayerStats,
	modifiers: Dictionary,
	count: int,
	gain_multipliers: Dictionary = {}
) -> void:
	if stats == null or count <= 0:
		return
	for raw_stat_key: Variant in modifiers:
		var stat_id := StatId.from_key(str(raw_stat_key))
		if StatId.is_valid(stat_id):
			stats.add_stat(
				stat_id,
				float(modifiers[raw_stat_key])
				* count
				* float(gain_multipliers.get(StatId.key(stat_id), 1.0))
			)


func _target_stat_rules_version(balance_pack: BalancePackDef) -> String:
	if balance_pack != null and balance_pack.stat_rules != null:
		return balance_pack.stat_rules.rules_version
	return RunState.CURRENT_STAT_RULES_VERSION


func _target_balance_pack_version(balance_pack: BalancePackDef) -> String:
	if balance_pack != null and not balance_pack.balance_pack_version.is_empty():
		return balance_pack.balance_pack_version
	return RunState.CURRENT_BALANCE_PACK_VERSION
