extends Area2D
class_name EcologyPickup

var pickup_kind := 0
var amount := 8.0


func configure(kind: int, value: float = 8.0) -> void:
	pickup_kind = kind
	amount = value
	if is_node_ready():
		_update_visual()


func _ready() -> void:
	_update_visual()


func _update_visual() -> void:
	var body := $Body as Polygon2D
	match pickup_kind:
		ArenaEcology.PickupKind.MATERIAL:
			body.color = Color(0.36, 0.78, 0.91, 1.0)
			body.polygon = PackedVector2Array([
				Vector2(0, -24), Vector2(22, 0), Vector2(0, 24), Vector2(-22, 0),
			])
		ArenaEcology.PickupKind.CHEST, ArenaEcology.PickupKind.LEGENDARY_CHEST:
			body.color = (
				Color(0.96, 0.82, 0.22, 1.0)
				if pickup_kind == ArenaEcology.PickupKind.LEGENDARY_CHEST
				else Color(0.91, 0.58, 0.16, 1.0)
			)
			body.polygon = PackedVector2Array([
				Vector2(-24, -18), Vector2(24, -18), Vector2(28, 18), Vector2(-28, 18),
			])
		_:
			body.color = Color(0.43, 0.85, 0.45, 1.0)
			body.polygon = PackedVector2Array([
				Vector2(0, -24), Vector2(21, -4), Vector2(13, 23),
				Vector2(-13, 23), Vector2(-21, -4),
			])


func _on_body_entered(body: Node2D) -> void:
	if not body is Player:
		return
	if pickup_kind in [
		ArenaEcology.PickupKind.CHEST,
		ArenaEcology.PickupKind.LEGENDARY_CHEST,
	]:
		Global.reward_service.collect_world_drop(Global.current_run, pickup_kind, 1)
		Global.dispatch_gameplay_event(
			GameplayEvent.Type.PICKED_UP,
			{"amount": 1, "drop_kind": pickup_kind},
			[&"pickup/chest"] as Array[StringName]
		)
	elif pickup_kind == ArenaEcology.PickupKind.MATERIAL:
		var collected: int = Global.reward_service.collect_world_drop(
			Global.current_run, pickup_kind, maxi(1, roundi(amount))
		)
		Global.materials_changed.emit(Global.current_run.materials)
		Global.dispatch_gameplay_event(
			GameplayEvent.Type.PICKED_UP,
			{"amount": collected, "drop_kind": pickup_kind},
			[&"pickup/material"] as Array[StringName]
		)
	else:
		var player := body as Player
		var healing := amount * (
			Global.current_run.pickup_healing_multiplier if Global.current_run != null else 1.0
		)
		player.health_component.heal(healing)
		Global.on_create_heal_text.emit(player, healing)
		Global.dispatch_gameplay_event(
			GameplayEvent.Type.PICKED_UP, {"amount": healing}, [&"pickup/heal"] as Array[StringName]
		)
	queue_free()
