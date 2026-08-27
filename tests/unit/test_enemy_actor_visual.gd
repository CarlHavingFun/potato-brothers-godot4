extends GdUnitTestSuite


func test_authored_texture_creates_centered_nearest_sprite_without_fallback() -> void:
	var definition := GogoEnemyDefinition.new()
	assert_bool(_has_property(definition, &"visual_texture")).is_true()
	if not _has_property(definition, &"visual_texture"):
		return
	var authored_texture := _authored_texture()
	definition.set(&"visual_texture", authored_texture)
	var actor := _configured_actor(definition)
	var sprite := actor.get_node_or_null("VisualSprite") as Sprite2D

	assert_object(sprite).is_not_null()
	if sprite == null:
		return
	assert_object(sprite.texture).is_same(authored_texture)
	assert_int(sprite.texture_filter).is_equal(CanvasItem.TEXTURE_FILTER_NEAREST)
	assert_bool(sprite.centered).is_true()
	assert_vector(sprite.position).is_equal(Vector2.ZERO)
	assert_vector(sprite.offset).is_equal(Vector2.ZERO)
	assert_vector(sprite.scale).is_equal(Vector2.ONE)
	assert_bool(actor.get(&"fallback_visual_active") == true).is_false()
	_assert_collision_radius(actor)


func test_missing_texture_keeps_circle_fallback_and_collision_radius() -> void:
	var definition := GogoEnemyDefinition.new()
	var actor := _configured_actor(definition)

	assert_object(actor.get_node_or_null("VisualSprite")).is_null()
	assert_bool(actor.get(&"fallback_visual_active") == true).is_true()
	_assert_collision_radius(actor)


func _configured_actor(definition: GogoEnemyDefinition) -> GogoEnemyActor:
	var difficulty := GogoDifficultyDefinition.new()
	var actor := auto_free(GogoEnemyActor.new()) as GogoEnemyActor
	actor.configure(definition, null, difficulty)
	add_child(actor)
	return actor


func _authored_texture() -> ImageTexture:
	var image := Image.create_empty(64, 64, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	image.set_pixel(32, 32, Color.WHITE)
	return ImageTexture.create_from_image(image)


func _assert_collision_radius(actor: GogoEnemyActor) -> void:
	var collisions := actor.find_children("*", "CollisionShape2D", true, false)
	var collision := collisions.front() as CollisionShape2D if not collisions.is_empty() else null
	assert_object(collision).is_not_null()
	if collision == null:
		return
	var circle := collision.shape as CircleShape2D
	assert_object(circle).is_not_null()
	if circle != null:
		assert_float(circle.radius).is_equal(14.0)


func _has_property(target: Object, property_name: StringName) -> bool:
	for property: Dictionary in target.get_property_list():
		if StringName(property.get("name", "")) == property_name:
			return true
	return false
