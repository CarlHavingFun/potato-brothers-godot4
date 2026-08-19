extends Area2D
class_name EcologyPickup

var pickup_kind := 0
var amount := 8.0
var _skin_visual: Sprite2D


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
	_apply_skin_visual(body)


func _apply_skin_visual(fallback_body: Polygon2D) -> void:
	if Presentation.active_skin == null:
		return
	var presentation_id := &"pickup.heal"
	if pickup_kind == ArenaEcology.PickupKind.MATERIAL:
		presentation_id = &"pickup.material"
	elif pickup_kind in [
		ArenaEcology.PickupKind.CHEST,
		ArenaEcology.PickupKind.LEGENDARY_CHEST,
	]:
		presentation_id = &"pickup.chest"
	var table: Variant = Presentation.active_skin.asset_tables.get(&"pickup/world", {})
	if table is not Dictionary or not (table as Dictionary).has(presentation_id):
		fallback_body.visible = true
		return
	var texture := Presentation.resolve_texture(&"pickup", presentation_id, null, &"world")
	if texture == null:
		fallback_body.visible = true
		return
	if not is_instance_valid(_skin_visual):
		_skin_visual = Sprite2D.new()
		_skin_visual.name = "SkinVisual"
		_skin_visual.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_skin_visual.scale = Vector2.ONE * 0.28
		_skin_visual.z_index = 1
		add_child(_skin_visual)
	_skin_visual.texture = texture
	_skin_visual.modulate = (
		Color(1.15, 1.0, 0.52, 1.0)
		if pickup_kind == ArenaEcology.PickupKind.LEGENDARY_CHEST
		else Color.WHITE
	)
	_skin_visual.visible = true
	fallback_body.visible = false


static func healing_amount_for_run(base_amount: float, run_state: RunState) -> float:
	if run_state == null:
		return maxf(0.0, base_amount)
	return maxf(
		0.0,
		base_amount * run_state.pickup_healing_multiplier
		+ run_state.consumable_healing_bonus
	)


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
		var healing := healing_amount_for_run(amount, Global.current_run)
		player.health_component.heal(healing)
		Global.on_create_heal_text.emit(player, healing)
		Global.dispatch_gameplay_event(
			GameplayEvent.Type.PICKED_UP, {"amount": healing}, [&"pickup/heal"] as Array[StringName]
		)
	queue_free()
