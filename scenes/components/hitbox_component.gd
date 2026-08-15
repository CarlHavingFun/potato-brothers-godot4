extends Area2D
class_name HitboxComponent

signal on_hit_hurtbox(hurtbox: HurtboxComponent)

@export_range(0.0, 10.0, 0.05, "or_greater") var repeat_interval := 0.0

var damage := 1.0
var display_damage := 1.0
var critical := false
var knockback_power := 0.0
var source: Node2D
var gameplay_source: Object
var gameplay_tags: Array[StringName] = []

func enable() -> void:
	set_deferred("monitoring", true)
	set_deferred("monitorable", true)

func disable() -> void:
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)

func setup(
	damage: float,
	critical: bool,
	knockback: float,
	source: Node2D,
	effect_source: Object = null,
	effect_tags: Array[StringName] = []
) -> void:
	self.damage = damage
	display_damage = damage
	self.critical = critical
	knockback_power = knockback
	self.source = source
	gameplay_source = effect_source if effect_source != null else source
	gameplay_tags = effect_tags.duplicate()


func _on_area_entered(area: Area2D) -> void:
	if area is HurtboxComponent:
		on_hit_hurtbox.emit(area)
