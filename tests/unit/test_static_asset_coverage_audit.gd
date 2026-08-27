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
	var expected_routes := {
		&"nine_slice_panel": ["res://game/ui/diagnostic_screen.gd", "Diagnostic/PrincipalSurface"],
		&"combat_hud_shell": ["res://game/ui/brotato_combat_hud.gd", "BrotatoHUD/Shell"],
		&"zone_thumbnail": [
			"res://game/ui/difficulty_select_screen.gd",
			"SelectedDifficultyDetail/ZoneThumbnail",
		],
	}
	for asset_id: StringName in expected_routes:
		var accepted := (report.accepted_observations as Array).filter(
			func(record: Dictionary) -> bool:
				return record.asset_id == asset_id and bool(record.visible_texture)
		)
		assert_int(accepted.size()).is_equal(1)
		if accepted.size() == 1:
			assert_str(String(accepted[0].scene)).is_equal(expected_routes[asset_id][0])
			assert_str(String(accepted[0].node)).is_equal(expected_routes[asset_id][1])


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


func test_required_ui_textures_reject_non_visible_observations() -> void:
	GogoStaticConsumerRegistry.reset_current()
	var content := GogoContentRegistry.new().build_snapshot(ValidationContentFactory.create_packs())
	var snapshot := _debug_snapshot(content)
	_exercise_real_consumers(content, snapshot)
	var route_nodes := {
		&"nine_slice_panel": "Diagnostic/PrincipalSurface",
		&"combat_hud_shell": "BrotatoHUD/Shell",
		&"zone_thumbnail": "SelectedDifficultyDetail/ZoneThumbnail",
	}
	for asset_id: StringName in route_nodes:
		var records: Array[Dictionary] = []
		for record: Dictionary in GogoStaticConsumerRegistry.current().records():
			if record.asset_id != asset_id:
				records.append(record)
		var handle := snapshot.resolve_global(asset_id)
		records.append({
			"asset_id": handle.asset_id,
			"role": handle.role,
			"selector": handle.selector,
			"scene": "res://game/ui/diagnostic_screen.gd",
			"node": route_nodes[asset_id],
			"texture_size": Vector2i(handle.texture.get_width(), handle.texture.get_height()),
			"integer_display_scale": Vector2i.ONE,
			"source_kind": handle.source_kind,
			"visible_texture": false,
		})
		var report := GogoStaticCoverageAudit.build(REGISTRY_PATH, snapshot, records)
		assert_array(report.unresolved_asset_ids).contains([asset_id])
		assert_bool(report.rejected_observations.any(func(rejection: Dictionary) -> bool:
			return (
				rejection.get("asset_id", &"") == asset_id
				and rejection.get("reason", &"") == &"texture_not_visibly_displayed"
			)
		)).is_true()


func test_visible_texture_observer_requires_exact_live_texture_and_provenance() -> void:
	var registry_script := load(CONSUMER_REGISTRY_PATH) as GDScript
	var method_exists := registry_script.get_script_method_list().any(
		func(method: Dictionary) -> bool:
			return method.get("name", "") == "observe_visible_texture"
	)
	assert_bool(method_exists).is_true()
	if not method_exists:
		return
	GogoStaticConsumerRegistry.reset_current()
	var content := GogoContentRegistry.new().build_snapshot(ValidationContentFactory.create_packs())
	var snapshot := _debug_snapshot(content)
	var handle := snapshot.resolve_global(&"zone_thumbnail")
	var app := auto_free(AppKernel.new()) as AppKernel
	app.add_to_group(&"gogobro_app")
	app.content_snapshot = content
	add_child(app)
	app.begin_selection()
	var screen := auto_free(load(
		"res://game/ui/difficulty_select_screen.gd"
	).new()) as GogoScreenBase
	screen.static_asset_snapshot_override = snapshot
	add_child(screen)
	var thumbnail := screen.get_node(
		"SelectedDifficultyDetail/ZoneThumbnail"
	) as TextureRect
	GogoStaticConsumerRegistry.reset_current()
	thumbnail.visible = false
	assert_bool(registry_script.call(
		"observe_visible_texture", handle, thumbnail,
		"res://game/ui/difficulty_select_screen.gd",
		"SelectedDifficultyDetail/ZoneThumbnail"
	)).is_false()
	thumbnail.visible = true
	thumbnail.texture = _texture(Vector2i(512, 288))
	assert_bool(registry_script.call(
		"observe_visible_texture", handle, thumbnail,
		"res://game/ui/difficulty_select_screen.gd",
		"SelectedDifficultyDetail/ZoneThumbnail"
	)).is_false()
	thumbnail.texture = handle.texture
	assert_bool(registry_script.call(
		"observe_visible_texture", handle, thumbnail,
		"res://tools/gallery.gd",
		"SelectedDifficultyDetail/ZoneThumbnail"
	)).is_false()
	assert_bool(registry_script.call(
		"observe_visible_texture", handle, thumbnail,
		"res://game/ui/diagnostic_screen.gd",
		"SelectedDifficultyDetail/ZoneThumbnail"
	)).is_false()
	assert_bool(registry_script.call(
		"observe_visible_texture", handle, thumbnail,
		"res://game/ui/difficulty_select_screen.gd",
		"SelectedDifficultyDetail/FakeThumbnail"
	)).is_false()
	assert_array(GogoStaticConsumerRegistry.current().records()).is_empty()
	assert_bool(registry_script.call(
		"observe_visible_texture", handle, thumbnail,
		"res://game/ui/difficulty_select_screen.gd",
		"SelectedDifficultyDetail/ZoneThumbnail"
	)).is_true()
	var record := GogoStaticConsumerRegistry.current().records()[0]
	assert_bool(record.get("visible_texture", false)).is_true()


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

	var app := auto_free(AppKernel.new()) as AppKernel
	app.add_to_group(&"gogobro_app")
	app.content_snapshot = content
	add_child(app)
	app.begin_selection()
	var main_menu := auto_free(load("res://game/ui/main_menu_screen.gd").new()) as GogoScreenBase
	main_menu.static_asset_snapshot_override = snapshot
	add_child(main_menu)
	var difficulty := auto_free(load(
		"res://game/ui/difficulty_select_screen.gd"
	).new()) as GogoScreenBase
	difficulty.static_asset_snapshot_override = snapshot
	add_child(difficulty)
	var diagnostic := auto_free(load("res://game/ui/diagnostic_screen.gd").new()) as GogoScreenBase
	diagnostic.static_asset_snapshot_override = snapshot
	diagnostic.call("receive_route_payload", {"message": "审计", "details": ["真实诊断路由"]})
	add_child(diagnostic)

	var hud := auto_free(GogoBrotatoCombatHud.new()) as GogoBrotatoCombatHud
	add_child(hud)
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


func _texture(size: Vector2i) -> ImageTexture:
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	return ImageTexture.create_from_image(image)


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
