extends StaticBody2D
class_name EcologyTree

signal harvested(world_position: Vector2, pickup_kind: int)

@export var max_health := 3.0
var current_health := 3.0
var pickup_kind := 0
var presentation_id: StringName = &"prop.supply_crate"
var _harvested := false
var _skin_visual: Sprite2D


func _ready() -> void:
	current_health = max_health
	_apply_skin_visual()


func configure_presentation(value: StringName) -> void:
	presentation_id = value if not value.is_empty() else &"prop.supply_crate"
	if is_node_ready():
		_apply_skin_visual()


func _apply_skin_visual() -> void:
	if Presentation.active_skin == null:
		return
	var table: Variant = Presentation.active_skin.asset_tables.get(&"prop/world", {})
	if table is not Dictionary or not (table as Dictionary).has(presentation_id):
		return
	var texture := Presentation.resolve_texture(
		&"prop", presentation_id, null, &"world"
	)
	if texture == null:
		return
	if is_instance_valid(_skin_visual):
		_skin_visual.texture = texture
		return
	_skin_visual = Sprite2D.new()
	_skin_visual.name = "SkinVisual"
	_skin_visual.texture = texture
	_skin_visual.position = Vector2(0.0, -24.0)
	_skin_visual.scale = Vector2.ONE * 0.34
	_skin_visual.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_skin_visual.z_index = 1
	add_child(_skin_visual)
	($Trunk as Polygon2D).visible = false
	($Crown as Polygon2D).visible = false


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
	var damage_visual: CanvasItem = _skin_visual if is_instance_valid(_skin_visual) else $Trunk
	damage_visual.modulate = Color(1.35, 1.35, 1.35, 1.0)
	var tween := create_tween()
	tween.tween_property(damage_visual, "modulate", Color.WHITE, 0.1)
	if current_health <= 0.0:
		_harvested = true
		harvested.emit(global_position, pickup_kind)
		call_deferred("queue_free")
	hitbox.confirm_hit(result)
