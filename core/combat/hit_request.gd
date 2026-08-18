class_name HitRequest
extends RefCounted


var raw_damage := 0.0
var damage_multiplier := 1.0
var armor := 0.0
var dodge_chance := 0.0
var critical := false
var knockback := 0.0
var source: Object
var gameplay_source: Object
var target: Object
var tags: Array[StringName] = []


static func from_hitbox(hitbox: HitboxComponent, hit_target: Object) -> HitRequest:
	var request := HitRequest.new()
	if hitbox == null:
		return request
	request.raw_damage = hitbox.damage
	request.critical = hitbox.critical
	request.knockback = hitbox.knockback_power
	request.source = hitbox.source
	request.gameplay_source = (
		hitbox.gameplay_source
		if is_instance_valid(hitbox.gameplay_source)
		else hitbox.source
	)
	request.target = hit_target
	request.tags = hitbox.gameplay_tags.duplicate()
	return request
