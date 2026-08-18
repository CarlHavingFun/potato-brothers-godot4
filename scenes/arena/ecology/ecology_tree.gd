extends StaticBody2D
class_name EcologyTree

signal harvested(world_position: Vector2, pickup_kind: int)

@export var max_health := 3.0
var current_health := 3.0
var pickup_kind := 0
var _harvested := false


func _ready() -> void:
	current_health = max_health


func _on_hurtbox_damaged(hitbox: HitboxComponent) -> void:
	if hitbox == null or current_health <= 0.0 or _harvested:
		return
	var request := HitRequest.from_hitbox(hitbox, self)
	request.raw_damage = maxf(1.0, request.raw_damage)
	var result := HitResolver.new(Global.combat_resolver).resolve(request)
	if not result.landed:
		return
	var health_before := current_health
	current_health = maxf(0.0, current_health - result.damage)
	result.record_health_change(health_before, current_health)
	var trunk := $Trunk as Polygon2D
	trunk.modulate = Color(1.35, 1.35, 1.35, 1.0)
	var tween := create_tween()
	tween.tween_property(trunk, "modulate", Color.WHITE, 0.1)
	if current_health <= 0.0:
		_harvested = true
		harvested.emit(global_position, pickup_kind)
		call_deferred("queue_free")
	hitbox.confirm_hit(result)
