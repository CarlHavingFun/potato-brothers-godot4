class_name CharacterVisualRig
extends Node2D

var base_sprite: AnimatedSprite2D
var appearance_layer: Node2D


func configure(character: CharacterDefinition, appearances: Array[GogoAppearanceDefinition]) -> Error:
	if character == null or character.sprite_frames == null or character.default_animation.is_empty():
		return ERR_INVALID_PARAMETER
	if not character.sprite_frames.has_animation(character.default_animation):
		return ERR_DOES_NOT_EXIST
	position = character.visual_offset
	scale = character.visual_scale
	_build_nodes()
	base_sprite.sprite_frames = character.sprite_frames
	base_sprite.animation = character.default_animation
	base_sprite.frame = 0
	rebuild_appearances(appearances)
	return OK


func rebuild_appearances(appearances: Array[GogoAppearanceDefinition]) -> void:
	_build_nodes()
	for child in appearance_layer.get_children():
		appearance_layer.remove_child(child)
		child.free()
	var accepted := _resolve_appearances(appearances)
	for index in accepted.size():
		var definition := accepted[index]
		var sprite := Sprite2D.new()
		sprite.name = "Appearance%02d" % index
		sprite.texture = definition.texture
		sprite.position = definition.offset
		sprite.modulate = definition.modulate
		sprite.z_index = clampi(definition.depth, RenderingServer.CANVAS_ITEM_Z_MIN, RenderingServer.CANVAS_ITEM_Z_MAX)
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.set_meta(&"appearance_id", definition.appearance_id)
		sprite.set_meta(&"slot", definition.slot)
		appearance_layer.add_child(sprite)


func set_moving(moving: bool) -> void:
	if base_sprite == null:
		return
	if moving:
		if not base_sprite.is_playing():
			base_sprite.play()
	else:
		base_sprite.pause()
		base_sprite.frame = 0


func appearance_sprites() -> Array[Sprite2D]:
	var result: Array[Sprite2D] = []
	if appearance_layer == null:
		return result
	for child in appearance_layer.get_children():
		if child is Sprite2D:
			result.append(child as Sprite2D)
	return result


func _build_nodes() -> void:
	if base_sprite == null:
		base_sprite = AnimatedSprite2D.new()
		base_sprite.name = "CharacterVisual"
		base_sprite.centered = true
		base_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(base_sprite)
	if appearance_layer == null:
		appearance_layer = Node2D.new()
		appearance_layer.name = "Appearances"
		add_child(appearance_layer)


func _resolve_appearances(appearances: Array[GogoAppearanceDefinition]) -> Array[GogoAppearanceDefinition]:
	var free_slot: Array[GogoAppearanceDefinition] = []
	var slotted: Dictionary = {}
	for definition in appearances:
		if definition == null or not definition.is_valid():
			continue
		if definition.slot.is_empty():
			free_slot.append(definition)
			continue
		var previous := slotted.get(definition.slot) as GogoAppearanceDefinition
		if previous == null or definition.display_priority >= previous.display_priority:
			slotted[definition.slot] = definition
	var accepted: Array[GogoAppearanceDefinition] = free_slot
	for definition in slotted.values():
		accepted.append(definition as GogoAppearanceDefinition)
	accepted.sort_custom(_appearance_before)
	return accepted


func _appearance_before(left: GogoAppearanceDefinition, right: GogoAppearanceDefinition) -> bool:
	if left.depth != right.depth:
		return left.depth < right.depth
	return String(left.appearance_id) < String(right.appearance_id)
