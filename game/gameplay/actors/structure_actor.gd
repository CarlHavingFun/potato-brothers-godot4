class_name GogoStructureActor
extends StaticBody2D

var maximum_health := 20.0
var current_health := 20.0
var owner_player_index := 0
var static_visual: Sprite2D


func configure(health: float, player_index: int) -> void:
	maximum_health = maxf(health, 1.0)
	current_health = maximum_health
	owner_player_index = player_index
	queue_redraw()


func configure_visual(handle: GogoStaticAssetHandle) -> bool:
	if handle == null or handle.texture == null:
		return false
	if static_visual == null:
		static_visual = Sprite2D.new()
		static_visual.name = "StaticVisual"
		static_visual.centered = false
		static_visual.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(static_visual)
	static_visual.texture = handle.texture
	static_visual.position = -Vector2(handle.pivot_px)
	queue_redraw()
	return true


func take_damage(amount: float) -> void:
	current_health = maxf(current_health - maxf(amount, 0.0), 0.0)
	if current_health <= 0.0:
		queue_free()


func _draw() -> void:
	if static_visual == null or static_visual.texture == null:
		draw_rect(Rect2(-14.0, -14.0, 28.0, 28.0), Color("77a7c8"))
