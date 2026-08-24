class_name CharacterVisualRig
extends Node2D

const HIT_FLASH_SHADER_CODE := """
shader_type canvas_item;

void fragment() {
	float visible_alpha = COLOR.a;
	COLOR = vec4(1.0, 1.0, 1.0, visible_alpha);
}
"""

var base_sprite: AnimatedSprite2D
var appearance_layer: Node2D
var attachment_rig: GogoCharacterAttachmentRig
var target_character_id: StringName = &""
var _hit_flash_active := false
var _dead := false
var _hit_flash_material: ShaderMaterial


func configure(character: CharacterDefinition, appearances: Array[GogoAppearanceDefinition]) -> Error:
	if character == null or character.sprite_frames == null or character.default_animation.is_empty():
		return ERR_INVALID_PARAMETER
	if not character.sprite_frames.has_animation(character.default_animation):
		return ERR_DOES_NOT_EXIST
	target_character_id = character.content_id
	attachment_rig = character.attachment_rig
	if attachment_rig != null:
		if not attachment_rig.is_valid() or attachment_rig.character_id != character.content_id:
			return ERR_INVALID_DATA
		if not attachment_rig.validate_sprite_frames(character.sprite_frames).is_empty():
			return ERR_INVALID_DATA
	_hit_flash_active = false
	_dead = false
	position = character.visual_offset
	scale = character.visual_scale
	_build_nodes()
	base_sprite.sprite_frames = character.sprite_frames
	base_sprite.animation = character.default_animation
	base_sprite.frame = 0
	var appearance_error := rebuild_appearances(appearances)
	if appearance_error != OK:
		return appearance_error
	return OK


func rebuild_appearances(appearances: Array[GogoAppearanceDefinition]) -> Error:
	_build_nodes()
	var selected: Array[GogoAppearanceDefinition] = []
	for definition in appearances:
		if definition == null:
			continue
		if definition.mode != GogoAppearanceDefinition.Mode.LEGACY_STATIC:
			if definition.target_character_id.is_empty():
				return ERR_INVALID_DATA
			if definition.target_character_id != target_character_id:
				continue
		selected.append(definition)
	var validation_error := _validate_formal_appearances(selected)
	if validation_error != OK:
		return validation_error
	for child in appearance_layer.get_children():
		appearance_layer.remove_child(child)
		child.free()
	var accepted := _resolve_appearances(selected)
	for index in accepted.size():
		var definition := accepted[index]
		var sprite := Sprite2D.new()
		sprite.name = "Appearance%02d" % index
		sprite.texture = definition.texture
		sprite.modulate = definition.modulate
		sprite.z_index = clampi(definition.depth, RenderingServer.CANVAS_ITEM_Z_MIN, RenderingServer.CANVAS_ITEM_Z_MAX)
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.set_meta(&"appearance_id", definition.appearance_id)
		sprite.set_meta(&"slot", definition.slot)
		sprite.set_meta(&"socket_id", definition.socket_id)
		sprite.set_meta(&"appearance_definition", definition)
		appearance_layer.add_child(sprite)
	_sync_appearances()
	return OK


func set_moving(moving: bool) -> void:
	if base_sprite == null:
		return
	if moving:
		if not base_sprite.is_playing():
			base_sprite.play()
	else:
		base_sprite.pause()
		base_sprite.frame = 0
		_sync_appearances()


func set_hit_flash(active: bool) -> void:
	_hit_flash_active = active and not _dead
	_apply_visual_state()


func is_hit_flash_active() -> bool:
	return _hit_flash_active


func set_dead(dead: bool) -> void:
	_dead = dead
	if _dead:
		_hit_flash_active = false
	_apply_visual_state()


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
		base_sprite.frame_changed.connect(_on_base_frame_changed)
		base_sprite.animation_changed.connect(_on_base_animation_changed)
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


func _sync_appearances() -> void:
	if base_sprite == null or appearance_layer == null:
		return
	for child in appearance_layer.get_children():
		if not child is Sprite2D:
			continue
		var sprite := child as Sprite2D
		var definition := sprite.get_meta(&"appearance_definition") as GogoAppearanceDefinition
		if definition == null:
			sprite.visible = false
			continue
		_sync_appearance(sprite, definition)
	_apply_visual_state()


func _apply_visual_state() -> void:
	if appearance_layer != null:
		appearance_layer.visible = not _dead
	var material: Material = null
	if _hit_flash_active:
		material = _get_hit_flash_material()
	if base_sprite != null:
		base_sprite.material = material
	for sprite in appearance_sprites():
		sprite.material = material


func _get_hit_flash_material() -> ShaderMaterial:
	if _hit_flash_material == null:
		var shader := Shader.new()
		shader.code = HIT_FLASH_SHADER_CODE
		_hit_flash_material = ShaderMaterial.new()
		_hit_flash_material.shader = shader
	return _hit_flash_material


func _sync_appearance(sprite: Sprite2D, definition: GogoAppearanceDefinition) -> void:
	if definition.mode == GogoAppearanceDefinition.Mode.LEGACY_STATIC:
		sprite.visible = definition.texture != null
		sprite.texture = definition.texture
		sprite.centered = true
		sprite.position = definition.offset
		sprite.scale = definition.render_scale
		sprite.flip_h = false
		return
	if definition.target_character_id != target_character_id:
		sprite.visible = false
		return
	if attachment_rig == null:
		sprite.visible = false
		return
	if attachment_rig.socket_slot(definition.socket_id) != definition.slot:
		sprite.visible = false
		return
	if not attachment_rig.socket_allows_mode(definition.socket_id, definition.mode_name()):
		sprite.visible = false
		return
	if attachment_rig.socket_default_depth(definition.socket_id) != definition.depth:
		sprite.visible = false
		return
	var animation := base_sprite.animation
	var frame_index := base_sprite.frame
	if not attachment_rig.has_socket(animation, frame_index, definition.socket_id):
		sprite.visible = false
		return
	sprite.centered = false
	sprite.rotation = 0.0
	sprite.scale = definition.render_scale
	sprite.flip_h = attachment_rig.socket_flip_h(animation, frame_index, definition.socket_id)
	if definition.mode == GogoAppearanceDefinition.Mode.FRAME_OVERLAY:
		if (
			definition.frame_overlay == null
			or not definition.frame_overlay.has_animation(animation)
			or definition.frame_overlay.get_frame_count(animation) != attachment_rig.frame_count(animation)
		):
			sprite.visible = false
			return
		sprite.texture = definition.frame_overlay.get_frame_texture(animation, frame_index)
		if sprite.texture == null or Vector2i(sprite.texture.get_size()) != attachment_rig.frame_size:
			sprite.visible = false
			return
		sprite.position = -Vector2(attachment_rig.frame_size) * 0.5 + Vector2(definition.local_offset_px)
		sprite.visible = true
		return
	sprite.texture = definition.texture
	var socket_position := attachment_rig.socket_position_pixels(animation, frame_index, definition.socket_id)
	var top_left := socket_position - definition.rendered_pivot_px + definition.local_offset_px
	sprite.position = Vector2(top_left) - Vector2(attachment_rig.frame_size) * 0.5
	sprite.visible = sprite.texture != null


func _validate_formal_appearances(appearances: Array[GogoAppearanceDefinition]) -> Error:
	for definition in appearances:
		if definition == null or definition.mode == GogoAppearanceDefinition.Mode.LEGACY_STATIC:
			continue
		if (
			not definition.is_valid()
			or definition.target_character_id != target_character_id
			or attachment_rig == null
		):
			return ERR_INVALID_DATA
		if attachment_rig.socket_slot(definition.socket_id) != definition.slot:
			return ERR_INVALID_DATA
		if not attachment_rig.socket_allows_mode(definition.socket_id, definition.mode_name()):
			return ERR_INVALID_DATA
		if attachment_rig.socket_default_depth(definition.socket_id) != definition.depth:
			return ERR_INVALID_DATA
		if definition.mode == GogoAppearanceDefinition.Mode.RIGID:
			if Vector2i(definition.texture.get_size()) != attachment_rig.frame_size:
				return ERR_INVALID_DATA
			var rendered_size_float := Vector2(definition.texture.get_size()) * definition.render_scale
			var rendered_size := Vector2i(roundi(rendered_size_float.x), roundi(rendered_size_float.y))
			if (
				not is_equal_approx(rendered_size_float.x, float(rendered_size.x))
				or not is_equal_approx(rendered_size_float.y, float(rendered_size.y))
				or definition.rendered_pivot_px.x < 0
				or definition.rendered_pivot_px.y < 0
				or definition.rendered_pivot_px.x >= rendered_size.x
				or definition.rendered_pivot_px.y >= rendered_size.y
			):
				return ERR_INVALID_DATA
			continue
		if definition.render_scale != Vector2.ONE:
			return ERR_INVALID_DATA
		for animation_id in attachment_rig.animation_ids():
			var animation := StringName(animation_id)
			if not definition.frame_overlay.has_animation(animation):
				return ERR_INVALID_DATA
			if definition.frame_overlay.get_frame_count(animation) != attachment_rig.frame_count(animation):
				return ERR_INVALID_DATA
			for frame_index in attachment_rig.frame_count(animation):
				var texture := definition.frame_overlay.get_frame_texture(animation, frame_index)
				if texture == null or Vector2i(texture.get_size()) != attachment_rig.frame_size:
					return ERR_INVALID_DATA
	return OK


func _on_base_frame_changed() -> void:
	_sync_appearances()


func _on_base_animation_changed() -> void:
	_sync_appearances()
