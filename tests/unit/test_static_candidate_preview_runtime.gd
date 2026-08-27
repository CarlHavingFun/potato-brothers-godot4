extends GdUnitTestSuite


const PREVIEW_SERVICE_PATH := "res://game/content/assets/gogobro_static_candidate_preview_service.gd"
const SHIPPING_MANIFEST_PATH := "res://game/content/assets/gogobro_static_runtime_bindings_v1.json"
const REGISTRY_PATH := "res://game/content/assets/gogobro_static_assets_v1.json"
const SHIPPING_ROOT := "res://game/assets/gogobro_static/"


func test_development_overlay_adds_independent_butterfly_glock_and_ak_candidates() -> void:
	var service_script := load(PREVIEW_SERVICE_PATH) as Script
	assert_object(service_script).is_not_null()
	if service_script == null:
		return
	var shipping := GogoStaticAssetRuntimeService.new()
	var content := GogoContentRegistry.new().build_snapshot(ValidationContentFactory.create_packs())
	assert_int(shipping.stage(content)).is_equal(OK)
	assert_int(shipping.activate_staged(&"", null)).is_equal(OK)
	var approved_shiv_icon := shipping.active_snapshot().resolve_asset(&"warmup_shiv", &"icon")
	var approved_pistol_icon := shipping.active_snapshot().resolve_asset(&"service_pistol", &"icon")
	assert_object(approved_shiv_icon).is_not_null()
	assert_object(approved_pistol_icon).is_not_null()

	var preview_service: RefCounted = service_script.new()
	var preview: GogoStaticAssetSnapshot = preview_service.call(
		"build_overlay",
		shipping.active_snapshot(),
		content
	) as GogoStaticAssetSnapshot

	assert_object(preview).is_not_null()
	assert_bool(bool(preview.call("is_development_preview"))).is_true()
	assert_bool(bool(shipping.active_snapshot().call("is_development_preview"))).is_false()
	var ak := preview.resolve_asset(&"wood_stock_assault_rifle", &"world_sprite")
	var shiv := preview.resolve_asset(&"warmup_shiv", &"world_sprite")
	var shiv_icon := preview.resolve_asset(&"warmup_shiv", &"icon")
	var pistol := preview.resolve_asset(&"service_pistol", &"world_sprite")
	var pistol_icon := preview.resolve_asset(&"service_pistol", &"icon")
	assert_object(ak).is_not_null()
	assert_object(shiv).is_not_null()
	assert_object(shiv_icon).is_not_null()
	assert_object(pistol).is_not_null()
	assert_object(pistol_icon).is_not_null()
	if shiv == null or shiv_icon == null or pistol == null or pistol_icon == null:
		return
	assert_object(shiv.texture).is_same(shiv_icon.texture)
	assert_object(pistol.texture).is_same(pistol_icon.texture)
	assert_object(shiv.texture).is_not_same(approved_shiv_icon.texture)
	assert_object(pistol.texture).is_not_same(approved_pistol_icon.texture)
	assert_object(shiv.texture).is_not_same(pistol.texture)
	assert_object(shiv.texture).is_not_same(ak.texture)
	assert_object(pistol.texture).is_not_same(ak.texture)
	assert_int(ak.texture.get_width()).is_equal(96)
	assert_int(ak.texture.get_height()).is_equal(64)
	assert_bool(ak.pivot_px == Vector2i(37, 40)).is_true()
	assert_bool(ak.anchors_px.get("muzzle") == Vector2i(92, 25)).is_true()
	assert_bool(shiv.pivot_px == Vector2i(24, 39)).is_true()
	assert_bool(shiv.anchors_px.get("contact") == Vector2i(52, 25)).is_true()
	assert_bool(pistol.pivot_px == Vector2i(38, 40)).is_true()
	assert_bool(pistol.anchors_px.get("muzzle") == Vector2i(90, 27)).is_true()
	assert_str(String(preview.state_for_asset(&"wood_stock_assault_rifle"))).is_equal("preview_ready")
	assert_str(String(preview.state_for_asset(&"warmup_shiv"))).is_equal("preview_ready")
	assert_str(String(preview.state_for_asset(&"service_pistol"))).is_equal("preview_ready")
	assert_object(preview.resolve_asset(&"service_carbine", &"world_sprite")).is_null()


func test_development_overlay_replaces_liner_and_helmet_inventory_icons_without_shipping_mutation() -> void:
	var service_script := load(PREVIEW_SERVICE_PATH) as Script
	assert_object(service_script).is_not_null()
	if service_script == null:
		return
	var shipping := GogoStaticAssetRuntimeService.new()
	var content := GogoContentRegistry.new().build_snapshot(ValidationContentFactory.create_packs())
	assert_int(shipping.stage(content)).is_equal(OK)
	assert_int(shipping.activate_staged(&"", null)).is_equal(OK)
	var shipping_snapshot := shipping.active_snapshot()
	var shipping_liner := shipping_snapshot.resolve_asset(&"ballistic_liner", &"icon")
	var shipping_helmet := shipping_snapshot.resolve_asset(&"smoke_shell_helmet", &"icon")
	assert_object(shipping_liner).is_not_null()
	assert_object(shipping_helmet).is_not_null()

	var preview := service_script.new().call(
		"build_overlay", shipping_snapshot, content
	) as GogoStaticAssetSnapshot
	assert_object(preview).is_not_null()
	if preview == null or shipping_liner == null or shipping_helmet == null:
		return
	var preview_liner := preview.resolve_asset(&"ballistic_liner", &"icon")
	var preview_helmet := preview.resolve_asset(&"smoke_shell_helmet", &"icon")
	assert_object(preview_liner).is_not_null()
	assert_object(preview_helmet).is_not_null()
	if preview_liner == null or preview_helmet == null:
		return
	assert_object(preview_liner.texture).is_not_same(shipping_liner.texture)
	assert_object(preview_helmet.texture).is_not_same(shipping_helmet.texture)
	assert_str(
		FileAccess.get_sha256(
			"res://game/assets/gogobro_static/items/ballistic_liner.png"
		).to_upper()
	).is_equal("1F673E6190EB9627B58EAA287FD22DB0F113AE80A6C7529C63EC4FBCDF89BC9F")
	assert_str(
		FileAccess.get_sha256(
			"res://game/assets/gogobro_static/items/smoke_shell_helmet.png"
		).to_upper()
	).is_equal("9D5D9A14D005BE3B08C5CC90F2E11C74EF214BAC8C921452F34DC1DAEF509BEC")
	assert_str(
		FileAccess.get_sha256(
			"res://game/assets/gogobro_static/items/smoke_shell_helmet_appearance.png"
		).to_upper()
	).is_equal("B3932E02DAF39074CE048E45B6FAE7F221019D87AD7B3A4327FA40714F25874A")
	var preview_item := content.definition(
		&"gogobro.preview:item/smoke_shell_helmet", &"item"
	) as GogoItemDefinition
	assert_object(preview_item).is_not_null()
	if preview_item == null or preview_item.appearances.is_empty():
		return
	assert_str(String(preview_item.appearances[0].texture.resource_path)).is_equal(
		"res://game/assets/gogobro_static_preview/items/smoke_shell_helmet_appearance.png"
	)


func test_development_overlay_resolves_complete_ui_and_decor_variant_sets() -> void:
	var preview := _development_preview()
	assert_object(preview).is_not_null()
	if preview == null:
		return
	for selector in [&"normal", &"hover", &"pressed", &"disabled"]:
		var button := preview.resolve_global(&"four_state_button", selector)
		assert_object(button).is_not_null()
		assert_str(String(button.selector)).is_equal(String(selector))
	for selector in [&"common", &"uncommon", &"rare", &"legendary"]:
		var frame := preview.resolve_global(&"card_and_rarity_frame_kit", selector)
		assert_object(frame).is_not_null()
		assert_str(String(frame.selector)).is_equal(String(selector))
	for index in range(1, 7):
		var selector := StringName("decor_variant_%02d" % index)
		var decor := preview.resolve_asset(&"community_server_decor_pack", &"world_sprite", selector)
		assert_object(decor).is_not_null()
		assert_str(String(decor.selector)).is_equal(String(selector))


func test_development_weapon_candidates_do_not_alias_each_other() -> void:
	var preview := _development_preview()
	assert_object(preview).is_not_null()
	if preview == null:
		return
	var shiv := preview.resolve_asset(&"warmup_shiv", &"world_sprite")
	var pistol := preview.resolve_asset(&"service_pistol", &"world_sprite")
	var ak := preview.resolve_asset(&"wood_stock_assault_rifle", &"world_sprite")
	assert_object(shiv).is_not_null()
	assert_object(pistol).is_not_null()
	assert_object(ak).is_not_null()
	if shiv == null or pistol == null or ak == null:
		return
	assert_object(shiv.texture).is_not_same(pistol.texture)
	assert_object(shiv.texture).is_not_same(ak.texture)
	assert_object(pistol.texture).is_not_same(ak.texture)
	assert_object(pistol.texture).is_same(preview.resolve_asset(&"service_pistol", &"icon").texture)


func test_shipping_service_requires_explicit_development_authorization_before_preview_activation() -> void:
	var service_script := load(PREVIEW_SERVICE_PATH) as Script
	assert_object(service_script).is_not_null()
	if service_script == null:
		return
	var content := GogoContentRegistry.new().build_snapshot(ValidationContentFactory.create_packs())
	var locked := GogoStaticAssetRuntimeService.new()
	assert_int(locked.stage(content)).is_equal(OK)
	assert_int(locked.activate_staged(&"", null)).is_equal(OK)
	var preview_service: RefCounted = service_script.new()
	var preview := preview_service.call("build_overlay", locked.active_snapshot(), content) as GogoStaticAssetSnapshot
	assert_object(preview).is_not_null()
	assert_int(int(locked.call("activate_development_preview", preview, &"", null))).is_equal(ERR_UNAUTHORIZED)
	assert_bool(bool(locked.active_snapshot().call("is_development_preview"))).is_false()

	var runtime_script := load("res://game/content/assets/gogobro_static_asset_runtime_service.gd") as Script
	var allowed := runtime_script.new(
		SHIPPING_MANIFEST_PATH,
		REGISTRY_PATH,
		SHIPPING_ROOT,
		true
	) as GogoStaticAssetRuntimeService
	assert_int(allowed.stage(content)).is_equal(OK)
	assert_int(allowed.activate_staged(&"", null)).is_equal(OK)
	assert_int(int(allowed.call("activate_development_preview", preview, &"", null))).is_equal(OK)
	assert_bool(bool(allowed.active_snapshot().call("is_development_preview"))).is_true()


func test_brotato_weapon_layout_keeps_one_and_six_weapons_close_and_evenly_spaced() -> void:
	var actor := auto_free(GogoPlayerActor.new()) as GogoPlayerActor
	var single := actor.call("weapon_orbit_offset", 0, 1) as Vector2
	assert_float(single.length()).is_between(28.0, 32.0)
	var offsets: Array[Vector2] = []
	for index in 6:
		offsets.append(actor.call("weapon_orbit_offset", index, 6) as Vector2)
	var expected := [
		Vector2(56.0, 0.0),
		Vector2(28.0, 48.497423),
		Vector2(-28.0, 48.497423),
		Vector2(-56.0, 0.0),
		Vector2(-28.0, -48.497423),
		Vector2(28.0, -48.497423),
	]
	for index in 6:
		assert_vector(offsets[index]).is_equal_approx(expected[index], Vector2(0.001, 0.001))
		assert_float(offsets[index].length()).is_between(54.0, 60.0)


func test_weapon_orbit_radius_derives_from_body_bounds_and_rejects_invalid_slots() -> void:
	var actor := auto_free(GogoPlayerActor.new()) as GogoPlayerActor
	assert_bool(actor.has_method("weapon_orbit_radius")).is_true()
	if not actor.has_method("weapon_orbit_radius"):
		return
	var standard_bounds: Array[Vector2i] = [Vector2i(96, 64)]
	var taller_bounds: Array[Vector2i] = [Vector2i(96, 80)]
	assert_float(float(actor.call("weapon_orbit_radius", 1, standard_bounds))).is_equal_approx(30.0, 0.001)
	assert_float(float(actor.call("weapon_orbit_radius", 6, standard_bounds))).is_equal_approx(56.0, 0.001)
	assert_float(float(actor.call("weapon_orbit_radius", 6, taller_bounds))).is_equal_approx(70.0, 0.001)
	assert_vector(actor.call("weapon_orbit_offset", -1, 6)).is_equal(Vector2.ZERO)
	assert_vector(actor.call("weapon_orbit_offset", 6, 6)).is_equal(Vector2.ZERO)
	assert_vector(actor.call("weapon_orbit_offset", 0, 0)).is_equal(Vector2.ZERO)


func test_app_kernel_debug_boot_activates_candidate_overlay_without_shipping_approval() -> void:
	var kernel := auto_free(AppKernel.new()) as AppKernel
	kernel.configure(null, null)
	var result := kernel.boot()
	assert_int(result.status).is_equal(BootResult.Status.OK)
	var snapshot := kernel.static_asset_service.active_snapshot()
	assert_bool(bool(snapshot.call("is_development_preview"))).is_true()
	var ak := snapshot.resolve_asset(&"wood_stock_assault_rifle", &"world_sprite")
	assert_object(ak).is_not_null()
	var training_weapon := snapshot.resolve_asset(&"service_pistol", &"world_sprite")
	assert_object(training_weapon).is_not_null()
	assert_object(training_weapon.texture).is_not_same(ak.texture)
	assert_object(training_weapon.texture).is_same(snapshot.resolve_asset(&"service_pistol", &"icon").texture)
	assert_bool(training_weapon.pivot_px == Vector2i(38, 40)).is_true()
	assert_bool(training_weapon.anchors_px.get("muzzle") == Vector2i(90, 27)).is_true()
	assert_bool(training_weapon.display_scale == Vector2.ONE).is_true()
	assert_bool(kernel.static_asset_service.release_readiness().get("release_ready", true) == false).is_true()


func test_validation_content_keeps_niko_as_the_only_character_placeholder() -> void:
	var content := GogoContentRegistry.new().build_snapshot(ValidationContentFactory.create_packs())
	var characters := content.all(&"character")
	assert_int(characters.size()).is_equal(1)
	assert_str(String(characters[0].content_id)).is_equal("character.niko:character/niko")
	var niko := characters[0] as CharacterDefinition
	assert_object(niko.sprite_frames).is_not_null()
	assert_str(String(ValidationContentFactory.CHARACTER_ID)).is_equal("character.niko:character/niko")


func _development_preview() -> GogoStaticAssetSnapshot:
	var service_script := load(PREVIEW_SERVICE_PATH) as Script
	var shipping := GogoStaticAssetRuntimeService.new()
	var content := GogoContentRegistry.new().build_snapshot(ValidationContentFactory.create_packs())
	assert_int(shipping.stage(content)).is_equal(OK)
	assert_int(shipping.activate_staged(&"", null)).is_equal(OK)
	return service_script.new().call(
		"build_overlay",
		shipping.active_snapshot(),
		content
	) as GogoStaticAssetSnapshot
