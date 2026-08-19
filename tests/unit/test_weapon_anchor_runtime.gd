extends GdUnitTestSuite


const DEV_SKIN := "res://content_packs/skins/dev_placeholder/skin.tres"
const FORMAL_SKIN := "res://content_packs/skins/lets_gooooo/skin.tres"

var _restore_manifest_path := ""


func after_test() -> void:
	if not _restore_manifest_path.is_empty():
		Presentation.load_manifest(_restore_manifest_path)
		_restore_manifest_path = ""


func test_formal_ak_and_c4_logical_anchors_are_consumed_by_weapon_runtime() -> void:
	var resolver: SkinResolver = auto_free(SkinResolver.new())
	assert_int(resolver.load_manifest(FORMAL_SKIN)).is_equal(OK)
	assert_object(resolver.resolve_logical_anchor(
		&"weapon", &"weapon.carbine", &"pivot", &"world"
	)).is_equal(Vector2(27.0, 35.0))
	assert_object(resolver.resolve_logical_anchor(
		&"weapon", &"weapon.carbine", &"muzzle_logical", &"world"
	)).is_equal(Vector2(60.0, 30.0))
	assert_object(resolver.resolve_logical_anchor(
		&"weapon", &"weapon.turret_kit", &"placement_origin", &"world"
	)).is_equal(Vector2(32.0, 43.0))

	var holder := auto_free(Node2D.new()) as Node2D
	add_child(holder)
	var ak_definition: WeaponDef = Content.catalog.get_weapon(&"weapon/carbine")
	var ak := auto_free(ak_definition.tiers[0].scene.instantiate() as Weapon) as Weapon
	holder.add_child(ak)
	ak.setup_weapon(ak_definition.tiers[0])
	ak.sprite.texture = resolver.resolve_texture(
		&"weapon", &"weapon.carbine", ak.sprite.texture, &"world"
	)
	assert_bool(ak.apply_presentation_anchors(&"weapon.carbine", resolver)).is_true()
	assert_int(ak.sprite.texture_filter).is_equal(CanvasItem.TEXTURE_FILTER_NEAREST)
	assert_object(ak.sprite.offset).is_equal(Vector2(20.0, -12.0))
	assert_object((ak.get_node("%Muzzle") as Marker2D).position).is_equal(
		Vector2(132.0, -20.0)
	)

	var c4_definition: WeaponDef = Content.catalog.get_weapon(&"weapon/turret_kit")
	var c4 := auto_free(c4_definition.tiers[0].scene.instantiate() as Weapon) as Weapon
	holder.add_child(c4)
	c4.setup_weapon(c4_definition.tiers[0])
	c4.sprite.texture = resolver.resolve_texture(
		&"weapon", &"weapon.turret_kit", c4.sprite.texture, &"world"
	)
	assert_bool(c4.apply_presentation_anchors(&"weapon.turret_kit", resolver)).is_true()
	assert_object(c4.sprite.offset).is_equal(Vector2(12.0, -36.0))
	assert_object((c4.get_node("%Muzzle") as Marker2D).position).is_equal(
		Vector2(12.0, 8.0)
	)


func test_live_skin_switch_restores_scene_fallback_without_changing_combat_state() -> void:
	var fallback: SkinResolver = auto_free(SkinResolver.new())
	assert_int(fallback.load_manifest(DEV_SKIN)).is_equal(OK)
	assert_dict(fallback.resolve_logical_anchors(
		&"weapon", &"weapon.carbine", &"world"
	)).is_empty()
	_restore_manifest_path = Presentation.manifest_path
	assert_int(Presentation.load_manifest(FORMAL_SKIN)).is_equal(OK)

	var holder := auto_free(Node2D.new()) as Node2D
	add_child(holder)
	var definition: WeaponDef = Content.catalog.get_weapon(&"weapon/carbine")
	var weapon := auto_free(definition.tiers[0].scene.instantiate() as Weapon) as Weapon
	holder.add_child(weapon)
	var scene_offset := weapon.sprite.offset
	var scene_muzzle := (weapon.get_node("%Muzzle") as Marker2D).position
	weapon.setup_weapon(definition.tiers[0])
	assert_object(weapon.sprite.offset).is_equal(Vector2(20.0, -12.0))
	weapon.is_attacking = true
	weapon.weapon_spread = 0.125
	weapon.pending_pierce = 2
	weapon.pending_bounce = 1
	var combat_snapshot := {
		"data": weapon.data,
		"is_attacking": weapon.is_attacking,
		"weapon_spread": weapon.weapon_spread,
		"pending_pierce": weapon.pending_pierce,
		"pending_bounce": weapon.pending_bounce,
	}

	assert_int(Presentation.load_manifest(DEV_SKIN)).is_equal(OK)
	assert_object(weapon.sprite.offset).is_equal(scene_offset)
	assert_object((weapon.get_node("%Muzzle") as Marker2D).position).is_equal(scene_muzzle)
	assert_object(weapon.data).is_same(combat_snapshot.data)
	assert_bool(weapon.is_attacking).is_equal(combat_snapshot.is_attacking)
	assert_float(weapon.weapon_spread).is_equal(combat_snapshot.weapon_spread)
	assert_int(weapon.pending_pierce).is_equal(combat_snapshot.pending_pierce)
	assert_int(weapon.pending_bounce).is_equal(combat_snapshot.pending_bounce)


func test_formal_shadow_daggers_keep_base_visual_scale_separate_from_hitbox_scale() -> void:
	var resolver := auto_free(SkinResolver.new()) as SkinResolver
	assert_int(resolver.load_manifest(FORMAL_SKIN)).is_equal(OK)
	var holder := auto_free(Node2D.new()) as Node2D
	add_child(holder)
	var definition: WeaponDef = Content.catalog.get_weapon(&"weapon/punch")
	var weapon := auto_free(definition.tiers[0].scene.instantiate() as Weapon) as Weapon
	holder.add_child(weapon)
	weapon.setup_weapon(definition.tiers[0])
	weapon.sprite.texture = resolver.resolve_texture(
		&"weapon", &"weapon.punch", weapon.sprite.texture, &"world"
	)
	assert_bool(weapon.apply_presentation_anchors(&"weapon.punch", resolver)).is_true()

	assert_object(weapon.sprite.scale).is_equal(Vector2(0.5, 0.5))
	assert_object((weapon.get_node("Sprite2D/HitboxComponent") as Area2D).scale).is_equal(
		Vector2(2.0, 2.0)
	)
	assert_float(weapon.sprite.texture.get_width() * weapon.sprite.scale.x).is_equal(128.0)
