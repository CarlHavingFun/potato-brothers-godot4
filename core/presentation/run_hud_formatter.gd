class_name RunHudFormatter
extends RefCounted


static func encounter_key(wave: WaveDef) -> StringName:
	if wave == null:
		return &"ui.hud.encounter.unknown"
	for spawn: WaveSpawnDef in wave.spawns:
		if spawn != null and spawn.is_boss:
			return &"ui.hud.encounter.boss"
	for spawn: WaveSpawnDef in wave.spawns:
		if spawn != null and spawn.is_elite:
			return &"ui.hud.encounter.elite"
	if &"horde_wave" in wave.tags or &"swarm_wave" in wave.tags:
		return &"ui.hud.encounter.horde"
	return &"ui.hud.encounter.standard"


static func status_entries(statuses: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var keys: Array[String] = []
	for raw_key: Variant in statuses:
		keys.append(str(raw_key))
	keys.sort()
	for key: String in keys:
		var state: Variant = statuses.get(StringName(key), statuses.get(key, {}))
		if state is not Dictionary:
			continue
		var values := state as Dictionary
		result.append({
			"status_id": key,
			"stacks": maxi(1, int(values.get("stacks", 1))),
			"remaining": maxf(0.0, float(values.get("remaining", 0.0))),
		})
	return result


static func boss_snapshot(enemies: Array) -> Dictionary:
	var count := 0
	var health := 0.0
	var maximum := 0.0
	var phase := &"base"
	for candidate: Variant in enemies:
		# `is Enemy` itself raises when its left operand is a freed Object. Always
		# validate the generic Variant before performing a type check or property read.
		if typeof(candidate) != TYPE_OBJECT or not is_instance_valid(candidate):
			continue
		if candidate is not Enemy:
			continue
		var enemy := candidate as Enemy
		if enemy.definition == null or &"boss" not in enemy.definition.tags:
			continue
		var health_component := enemy.health_component
		if not is_instance_valid(health_component):
			continue
		count += 1
		health += maxf(0.0, health_component.current_health)
		maximum += maxf(0.0, health_component.max_health)
		if enemy is MouseDogBoss and (enemy as MouseDogBoss).enraged:
			phase = &"enraged"
		elif enemy is ScrapTitanBoss and (enemy as ScrapTitanBoss).overdrive:
			phase = &"overdrive"
	if count == 0:
		return {}
	return {
		"count": count,
		"health": health,
		"maximum_health": maximum,
		"health_ratio": health / maximum if maximum > 0.0 else 0.0,
		"phase": phase,
	}
