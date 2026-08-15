class_name GameplayEffectExecutor
extends RefCounted


const ENEMY_GROUP := &"effect_targets/enemies"
const ARENA_GROUP := &"effect_runtime/arena"


func apply_result(result: EffectResult, context: GameplayEventContext, tree: SceneTree) -> void:
	if result == null or context == null:
		return
	_apply_statuses(result.status_commands, context.target, context.source)
	if is_instance_valid(context.source):
		if context.source.has_method("apply_attack_effects"):
			context.source.call("apply_attack_effects", result)
		if not result.projectile_commands.is_empty() and context.source.has_method("spawn_effect_projectiles"):
			context.source.call("spawn_effect_projectiles", result.projectile_commands)
	_apply_area_commands(result.area_commands, context, tree)
	_spawn_entities(&"summon", result.summon_commands, context, tree)
	_spawn_entities(&"building", result.building_commands, context, tree)


func _apply_statuses(commands: Array[Dictionary], target: Object, source: Object) -> void:
	if not is_instance_valid(target) or not target.has_method("apply_effect_status"):
		return
	for command: Dictionary in commands:
		target.call("apply_effect_status", command, source)


func _apply_area_commands(
	commands: Array[Dictionary],
	context: GameplayEventContext,
	tree: SceneTree
) -> void:
	if tree == null or commands.is_empty():
		return
	var center_node := context.target as Node2D
	if center_node == null:
		center_node = context.source as Node2D
	if center_node == null:
		return
	var base_damage := float(context.values.get("damage", context.values.get("base_damage", 0.0)))
	if base_damage <= 0.0:
		return
	for command: Dictionary in commands:
		var radius := float(command.get("radius", 0.0))
		if radius <= 0.0:
			continue
		var candidates: Array[Node2D] = []
		for candidate: Node in tree.get_nodes_in_group(ENEMY_GROUP):
			if candidate is not Node2D or not candidate.has_method("apply_effect_damage"):
				continue
			var enemy := candidate as Node2D
			if center_node.global_position.distance_squared_to(enemy.global_position) <= radius * radius:
				candidates.append(enemy)
		candidates.sort_custom(func(first: Node2D, second: Node2D) -> bool:
			var first_distance := center_node.global_position.distance_squared_to(first.global_position)
			var second_distance := center_node.global_position.distance_squared_to(second.global_position)
			if not is_equal_approx(first_distance, second_distance):
				return first_distance < second_distance
			return first.get_instance_id() < second.get_instance_id()
		)
		var kind := int(command.get("kind", -1))
		var target_limit := int(command.get("targets", 0))
		var applied := 0
		for enemy: Node2D in candidates:
			if kind == EffectOperationDef.Kind.CHAIN and enemy == context.target:
				continue
			if target_limit > 0 and applied >= target_limit:
				break
			enemy.call("apply_effect_damage", base_damage * float(command.get("scale", 1.0)), context.source)
			applied += 1


func _spawn_entities(
	kind: StringName,
	commands: Array[Dictionary],
	context: GameplayEventContext,
	tree: SceneTree
) -> void:
	if tree == null or commands.is_empty():
		return
	var arenas := tree.get_nodes_in_group(ARENA_GROUP)
	if arenas.is_empty():
		return
	var arena := arenas[0] as Node
	if arena != null and arena.has_method("spawn_effect_entities"):
		arena.call("spawn_effect_entities", kind, commands, context)
