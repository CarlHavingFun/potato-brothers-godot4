class_name HitResult
extends RefCounted


var attempted := false
var landed := false
var dodged := false
var critical := false
var raw_damage := 0.0
var damage := 0.0
var knockback := 0.0
var source: Object
var gameplay_source: Object
var target: Object
var tags: Array[StringName] = []
var health_before := 0.0
var health_after := 0.0
var killed := false


func apply_extra_damage(amount: float) -> void:
	damage = maxf(0.0, damage + amount)


func record_health_change(before: float, after: float) -> void:
	health_before = before
	health_after = after
	killed = before > 0.0 and after <= 0.0
