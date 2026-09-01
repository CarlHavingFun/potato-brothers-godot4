class_name GogoWaveResolver
extends RefCounted

# Validation bounds also protect WaveRuntime from untrusted content allocations.
const MAX_GROUPS := 64
const MAX_SCHEDULED_ENEMIES := 4096
const MAX_DURATION := 3600.0


static func validate_wave(wave: GogoWaveDefinition, snapshot: ContentSnapshot, number: int, spawn_multiplier: float = 1.0) -> Error:
	if wave == null or snapshot == null or number < 1 or wave.wave_number != number:
		return ERR_INVALID_DATA
	if not is_finite(wave.duration_seconds) or wave.duration_seconds <= 0.0 or wave.duration_seconds > MAX_DURATION:
		return ERR_INVALID_DATA
	if not is_finite(spawn_multiplier) or spawn_multiplier < 0.0 or spawn_multiplier > 16.0:
		return ERR_INVALID_DATA
	for multiplier in [wave.enemy_health_multiplier, wave.enemy_damage_multiplier, wave.enemy_speed_multiplier]:
		if not is_finite(multiplier) or multiplier <= 0.0 or multiplier > 100.0:
			return ERR_INVALID_DATA
	if wave.spawn_groups.is_empty() or wave.spawn_groups.size() > MAX_GROUPS:
		return ERR_INVALID_DATA
	var total := 0
	for group in wave.spawn_groups:
		var enemy_id := StringName(group.get("enemy_id", ""))
		if enemy_id.is_empty() or not snapshot.has_definition(enemy_id, &"enemy"):
			return ERR_INVALID_DATA
		var count := int(group.get("count", 0))
		var start := float(group.get("start", 0.0))
		var end := float(group.get("end", wave.duration_seconds))
		if count <= 0 or count > MAX_SCHEDULED_ENEMIES or not is_finite(start) or not is_finite(end):
			return ERR_INVALID_DATA
		if start < 0.0 or end <= start or end > wave.duration_seconds:
			return ERR_INVALID_DATA
		var batch := int(group.get("batch_size", 1))
		if batch <= 0 or batch > count:
			return ERR_INVALID_DATA
		var interval := float(group.get("interval_seconds", (end - start) / float(count)))
		if not is_finite(interval) or interval <= 0.0:
			return ERR_INVALID_DATA
		total += count
		if total > MAX_SCHEDULED_ENEMIES:
			return ERR_INVALID_DATA
	# Only compile after bounding every raw group. Check actual nonempty slots
	# against the authored end (which is already <= the wave deadline), using
	# the same incremental additions as tick(), not a raw last-time estimate.
	var effective_total := 0
	for group in wave.spawn_groups:
		var end := float(group.get("end", wave.duration_seconds))
		for schedule in WaveRuntime.build_group_schedules(group, wave.duration_seconds, spawn_multiplier):
			var remaining := int(schedule["remaining"])
			effective_total += remaining
			if effective_total > MAX_SCHEDULED_ENEMIES:
				return ERR_INVALID_DATA
			var next_spawn := float(schedule["next_spawn"])
			while remaining > 0:
				if not is_finite(next_spawn) or next_spawn > end:
					return ERR_INVALID_DATA
				remaining -= mini(int(schedule["batch_size"]), remaining)
				next_spawn += float(schedule["interval"])
	return OK


static func validate_zone(snapshot: ContentSnapshot, zone: GogoZoneDefinition, spawn_multiplier: float = 1.0) -> Error:
	if snapshot == null or zone == null or zone.wave_ids.is_empty():
		return ERR_INVALID_DATA
	if not zone.arena_size.is_finite() or zone.arena_size.x <= 0.0 or zone.arena_size.y <= 0.0:
		return ERR_INVALID_DATA
	for index in zone.wave_ids.size():
		var wave := snapshot.definition(zone.wave_ids[index], &"wave") as GogoWaveDefinition
		if validate_wave(wave, snapshot, index + 1, spawn_multiplier) != OK:
			return ERR_INVALID_DATA
	return OK


static func resolve(session: GameSession) -> GogoWaveDefinition:
	if session == null or session.run_state == null or session.content_snapshot == null:
		return null
	var state := session.run_state
	if state.ended or state.phase != &"combat" or state.current_wave < 1:
		return null
	var snapshot := session.content_snapshot
	var difficulty := snapshot.definition(state.difficulty_id, &"difficulty") as GogoDifficultyDefinition
	if difficulty == null:
		return null
	var zone := snapshot.definition(state.zone_id, &"zone") as GogoZoneDefinition
	if zone == null or zone.wave_ids.is_empty() or state.total_waves != zone.wave_ids.size():
		return null
	var wave: GogoWaveDefinition
	if state.current_wave <= state.total_waves:
		if state.endless:
			return null
		wave = snapshot.definition(zone.wave_ids[state.current_wave - 1], &"wave") as GogoWaveDefinition
	else:
		if not state.endless:
			return null
		var enemy_ids: Array[StringName] = [
			&"gogobro.core:enemy/drifter", &"gogobro.core:enemy/spark",
			&"gogobro.core:enemy/rammer", ValidationContentFactory.ELITE_RAMMER_ID,
		]
		wave = EndlessWaveFactory.new().build(state.current_wave, enemy_ids, state.total_waves)
	return wave if validate_wave(wave, snapshot, state.current_wave, difficulty.spawn_multiplier) == OK else null
