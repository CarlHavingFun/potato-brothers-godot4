class_name DropTableDef
extends Resource


enum DropKind {
	NONE,
	MATERIAL,
	HEAL,
	CHEST,
	LEGENDARY_CHEST,
}

@export_range(0.0, 1.0, 0.001) var normal_heal_chance := 0.035
@export_range(0.0, 0.01, 0.0001) var normal_heal_luck_scale := 0.0002
@export_range(0.0, 0.01, 0.0001) var normal_chest_luck_scale := 0.00045
@export_range(0.0, 1.0, 0.01) var maximum_normal_chest_chance := 0.18
@export_range(0.0, 1.0, 0.01) var tree_material_chance := 0.22
@export_range(0.0, 1.0, 0.01) var tree_chest_chance := 0.08
@export_range(0.0, 0.01, 0.0001) var tree_chest_luck_scale := 0.001


func weights_for(source_tags: Array[StringName], luck: float, current_wave: int) -> Dictionary:
	if &"boss" in source_tags:
		return {DropKind.LEGENDARY_CHEST: 1.0}
	if &"elite" in source_tags:
		return {DropKind.CHEST: 1.0}
	if &"source/tree" in source_tags:
		return _tree_weights(luck, current_wave)
	if &"normal" in source_tags:
		return _normal_enemy_weights(luck)
	return {DropKind.NONE: 1.0}


func roll(weights: Dictionary, unit_roll: float) -> int:
	var roll_value := clampf(unit_roll, 0.0, 0.999999)
	var total_weight := 0.0
	for kind in DropKind.values():
		total_weight += maxf(0.0, float(weights.get(kind, 0.0)))
	if total_weight <= 0.0:
		return DropKind.NONE
	var cursor := roll_value * total_weight
	for kind in DropKind.values():
		var weight := maxf(0.0, float(weights.get(kind, 0.0)))
		if weight <= 0.0:
			continue
		cursor -= weight
		if cursor <= 0.0:
			return int(kind)
	return DropKind.NONE


func _normal_enemy_weights(luck: float) -> Dictionary:
	var effective_luck := clampf(luck, 0.0, 500.0)
	var heal_chance := clampf(
		normal_heal_chance + effective_luck * normal_heal_luck_scale, 0.0, 0.16
	)
	var chest_chance := minf(
		maximum_normal_chest_chance, effective_luck * normal_chest_luck_scale
	)
	return {
		DropKind.NONE: maxf(0.0, 1.0 - heal_chance - chest_chance),
		DropKind.HEAL: heal_chance,
		DropKind.CHEST: chest_chance,
	}


func _tree_weights(luck: float, current_wave: int) -> Dictionary:
	var effective_luck := clampf(luck, 0.0, 300.0)
	var chest_chance := clampf(
		tree_chest_chance
		+ effective_luck * tree_chest_luck_scale
		+ minf(0.05, maxi(0, current_wave - 1) * 0.002),
		0.0,
		0.42
	)
	var material_chance := maxf(0.12, tree_material_chance - effective_luck * 0.0002)
	return {
		DropKind.MATERIAL: material_chance,
		DropKind.HEAL: maxf(0.0, 1.0 - material_chance - chest_chance),
		DropKind.CHEST: chest_chance,
	}
