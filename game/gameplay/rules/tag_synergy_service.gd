class_name TagSynergyService
extends RefCounted


func count_tags(snapshot: ContentSnapshot, player: SessionPlayerState) -> Dictionary:
	var counts: Dictionary = {}
	for content_id in player.weapon_ids + player.item_ids:
		var kind: StringName = &"weapon" if player.weapon_ids.has(content_id) else &"item"
		var definition := snapshot.definition(content_id, kind)
		if definition == null:
			continue
		for tag: StringName in definition.tags:
			counts[tag] = int(counts.get(tag, 0)) + 1
	return counts


func build_modifiers(tag_counts: Dictionary, thresholds: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for tag: StringName in thresholds:
		var tiers: Array = thresholds[tag]
		for tier: Dictionary in tiers:
			if int(tag_counts.get(tag, 0)) >= int(tier.get("count", 0)):
				for stat: StringName in Dictionary(tier.get("modifiers", {})):
					result[stat] = float(result.get(stat, 0.0)) + float(tier.modifiers[stat])
	return result
