extends GdUnitTestSuite


const REGISTRY_PATH := "res://game/content/assets/gogobro_static_assets_v1.json"
const CONSUMER_REGISTRY_PATH := "res://game/content/assets/gogobro_static_consumer_registry.gd"
const COVERAGE_AUDIT_PATH := "res://game/content/assets/gogobro_static_coverage_audit.gd"


func test_coverage_runtime_types_exist() -> void:
	assert_bool(FileAccess.file_exists(CONSUMER_REGISTRY_PATH)).is_true()
	assert_bool(FileAccess.file_exists(COVERAGE_AUDIT_PATH)).is_true()


func test_actual_consumers_cover_every_canonical_unit() -> void:
	if not FileAccess.file_exists(CONSUMER_REGISTRY_PATH):
		return
	GogoStaticConsumerRegistry.reset_current()
	var content := GogoContentRegistry.new().build_snapshot(ValidationContentFactory.create_packs())
	var snapshot := _debug_snapshot(content)
	assert_object(snapshot).is_not_null()
	_exercise_real_consumers(content, snapshot)

	var records := GogoStaticConsumerRegistry.current().records()
	var report := GogoStaticCoverageAudit.build(REGISTRY_PATH, snapshot, records)
	assert_int(report.expected_units).is_equal(70)
	assert_int(report.covered_units).is_equal(70)
	assert_array(report.unresolved_asset_ids).is_empty()
	assert_array(report.required_visual_failures).is_empty()
	assert_bool(report.complete).is_true()
	assert_int(report.source_unit_counts.approved_shipping).is_equal(5)
	assert_int(report.source_unit_counts.development_preview).is_equal(65)


func test_gallery_observation_cannot_satisfy_or_break_real_coverage() -> void:
	if not FileAccess.file_exists(CONSUMER_REGISTRY_PATH):
		return
	GogoStaticConsumerRegistry.reset_current()
	var content := GogoContentRegistry.new().build_snapshot(ValidationContentFactory.create_packs())
	var snapshot := _debug_snapshot(content)
	_exercise_real_consumers(content, snapshot)
	var records := GogoStaticConsumerRegistry.current().records()
	records.append({
		"asset_id": &"menu_background",
		"role": &"ui_texture",
		"selector": &"",
		"scene": "res://tools/gallery.gd",
		"node": "Gallery/Image",
		"texture_size": Vector2i(1920, 1080),
		"integer_display_scale": Vector2i.ONE,
		"source_kind": &"development_preview",
	})
	var report := GogoStaticCoverageAudit.build(REGISTRY_PATH, snapshot, records)
	assert_bool(report.complete).is_true()
	assert_bool(GogoStaticCoverageAudit.is_allowed_consumer_scene(
		"res://tools/gallery.gd"
	)).is_false()
	assert_int(report.rejected_observations.size()).is_equal(1)


func test_missing_required_floor_is_a_hard_failure_even_with_other_sixty_nine_units() -> void:
	if not FileAccess.file_exists(CONSUMER_REGISTRY_PATH):
		return
	GogoStaticConsumerRegistry.reset_current()
	var content := GogoContentRegistry.new().build_snapshot(ValidationContentFactory.create_packs())
	var snapshot := _debug_snapshot(content)
	_exercise_real_consumers(content, snapshot)
	var records: Array[Dictionary] = []
	for record: Dictionary in GogoStaticConsumerRegistry.current().records():
		if record.asset_id != &"community_server_floor":
			records.append(record)
	var report := GogoStaticCoverageAudit.build(REGISTRY_PATH, snapshot, records)
	assert_int(report.covered_units).is_equal(69)
	assert_array(report.unresolved_asset_ids).contains_exactly([&"community_server_floor"])
	assert_array(report.required_visual_failures).contains_exactly([&"community_server_floor"])
	assert_bool(report.complete).is_false()


func test_real_rarity_selectors_produce_opaque_readable_accent_colors() -> void:
	var content := GogoContentRegistry.new().build_snapshot(ValidationContentFactory.create_packs())
	var snapshot := _debug_snapshot(content)
	assert_object(snapshot).is_not_null()
	var card_background := Color("171b1e")
	for tier in range(1, 5):
		var definition := GogoItemDefinition.new()
		definition.content_id = StringName("fixture:item/contrast_tier_%d" % tier)
		definition.display_name = "稀有度 %d" % tier
		definition.tier = tier
		var card := auto_free(GogoStaticCardPresenter.build_card(
			definition,
			"已接入",
			snapshot
		)) as Control
		var accent := card.get_node("RarityAccent") as ColorRect
		assert_float(accent.color.a).is_equal_approx(1.0, 0.0001)
		assert_float(_contrast_ratio(accent.color, card_background)).is_greater_equal(3.0)


func _exercise_real_consumers(
	content: ContentSnapshot,
	snapshot: GogoStaticAssetSnapshot
) -> void:
	for kind in [&"weapon", &"item", &"upgrade"]:
		for definition: GogoContentDefinition in content.all(kind):
			var card := auto_free(GogoStaticCardPresenter.build_card(
				definition, "已接入", snapshot
			)) as Control

	var player := SessionPlayerState.new()
	for raw in content.all(&"weapon"):
		var weapon := auto_free(GogoWeaponInstance.new()) as GogoWeaponInstance
		weapon.static_asset_snapshot_override = snapshot
		add_child(weapon)
		weapon.configure(
			WeaponRuntimeService.new().build_instance(raw as GogoWeaponDefinition, player),
			null
		)

	var world := auto_free(GogoStaticWorldPresenter.new()) as GogoStaticWorldPresenter
	add_child(world)
	world.configure(snapshot, Rect2(Vector2.ZERO, Vector2(2048, 1536)), 9137, true)
	var marker := auto_free(GogoStaticSpawnMarker.new()) as GogoStaticSpawnMarker
	add_child(marker)
	marker.configure_visual(snapshot.resolve_asset(&"spawn_marker", &"world_sprite"))

	var screen := auto_free(GogoScreenBase.new()) as GogoScreenBase
	screen.static_asset_snapshot_override = snapshot
	screen.build_screen("审计")
	screen.add_principal_surface(Rect2(192, 144, 640, 360))
	screen.add_static_texture(&"gogobro_wordmark", "Wordmark", Vector2(460, 115))
	screen.add_static_texture(&"zone_thumbnail", "ZoneThumbnail", Vector2(320, 180))
	screen.resolve_global_icon(&"difficulty_badge_kit", &"standard")
	screen.add_action("审计按钮", func() -> void: pass)

	var hud := auto_free(GogoBrotatoCombatHud.new()) as GogoBrotatoCombatHud
	hud.configure(null, content, snapshot)
	var projectile := auto_free(GogoProjectile.new()) as GogoProjectile
	projectile.static_asset_snapshot_override = snapshot
	projectile.activate(null, 1, 1, 1, 1, &"rifle", &"ballistic", &"normal")


func _debug_snapshot(content: ContentSnapshot) -> GogoStaticAssetSnapshot:
	var shipping := GogoStaticAssetRuntimeService.new()
	assert_int(shipping.stage(content)).is_equal(OK)
	assert_int(shipping.activate_staged(&"", null)).is_equal(OK)
	return GogoStaticAssetCandidatePreviewService.new().build_overlay(
		shipping.active_snapshot(),
		content
	)


func _contrast_ratio(first: Color, second: Color) -> float:
	var first_luminance := _relative_luminance(first)
	var second_luminance := _relative_luminance(second)
	return (
		(maxf(first_luminance, second_luminance) + 0.05)
		/ (minf(first_luminance, second_luminance) + 0.05)
	)


func _relative_luminance(color: Color) -> float:
	return (
		0.2126 * _linear_channel(color.r)
		+ 0.7152 * _linear_channel(color.g)
		+ 0.0722 * _linear_channel(color.b)
	)


func _linear_channel(channel: float) -> float:
	if channel <= 0.04045:
		return channel / 12.92
	return pow((channel + 0.055) / 1.055, 2.4)
