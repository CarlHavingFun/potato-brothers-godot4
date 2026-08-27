extends GdUnitTestSuite


const PREVIEW_SERVICE_PATH := "res://game/content/assets/gogobro_static_candidate_preview_service.gd"
const SHIPPING_MANIFEST_PATH := "res://game/content/assets/gogobro_static_runtime_bindings_v1.json"
const REGISTRY_PATH := "res://game/content/assets/gogobro_static_assets_v1.json"
const SHIPPING_ROOT := "res://game/assets/gogobro_static/"


func test_development_overlay_preserves_shipping_handles_and_adds_ak_world_sprite() -> void:
	var service_script := load(PREVIEW_SERVICE_PATH) as Script
	assert_object(service_script).is_not_null()
	if service_script == null:
		return
	var shipping := GogoStaticAssetRuntimeService.new()
	var content := GogoContentRegistry.new().build_snapshot(ValidationContentFactory.create_packs())
	assert_int(shipping.stage(content)).is_equal(OK)
	assert_int(shipping.activate_staged(&"", null)).is_equal(OK)
	var approved_icon := shipping.active_snapshot().resolve_asset(&"service_pistol", &"icon")
	assert_object(approved_icon).is_not_null()

	var preview_service: RefCounted = service_script.new()
	var preview: GogoStaticAssetSnapshot = preview_service.call(
		"build_overlay",
		shipping.active_snapshot(),
		content
	) as GogoStaticAssetSnapshot

	assert_object(preview).is_not_null()
	assert_bool(bool(preview.call("is_development_preview"))).is_true()
	assert_object(preview.resolve_asset(&"service_pistol", &"icon")).is_same(approved_icon)
	var ak := preview.resolve_asset(&"wood_stock_assault_rifle", &"world_sprite")
	assert_object(ak).is_not_null()
	assert_int(ak.texture.get_width()).is_equal(96)
	assert_int(ak.texture.get_height()).is_equal(64)
	assert_bool(ak.pivot_px == Vector2i(33, 34)).is_true()
	assert_bool(ak.anchors_px.get("muzzle") == Vector2i(91, 22)).is_true()
	assert_str(String(preview.state_for_asset(&"wood_stock_assault_rifle"))).is_equal("preview_ready")
	assert_object(preview.resolve_asset(&"service_carbine", &"world_sprite")).is_null()


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


func test_brotato_weapon_layout_keeps_six_weapons_evenly_orbiting_niko() -> void:
	var actor := auto_free(GogoPlayerActor.new()) as GogoPlayerActor
	var offsets: Array[Vector2] = []
	for index in 6:
		offsets.append(actor.call("weapon_orbit_offset", index, 6) as Vector2)
	var expected := [
		Vector2(72.0, 0.0),
		Vector2(36.0, 62.353828),
		Vector2(-36.0, 62.353828),
		Vector2(-72.0, 0.0),
		Vector2(-36.0, -62.353828),
		Vector2(36.0, -62.353828),
	]
	for index in 6:
		assert_vector(offsets[index]).is_equal_approx(expected[index], Vector2(0.001, 0.001))
		assert_float(offsets[index].length()).is_equal_approx(72.0, 0.001)


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
	assert_object(training_weapon.texture).is_same(ak.texture)
	assert_bool(training_weapon.pivot_px == ak.pivot_px).is_true()
	assert_bool(training_weapon.anchors_px.get("muzzle") == ak.anchors_px.get("muzzle")).is_true()
	assert_bool(kernel.static_asset_service.release_readiness().get("release_ready", true) == false).is_true()


func test_validation_content_keeps_niko_as_the_only_character_placeholder() -> void:
	var content := GogoContentRegistry.new().build_snapshot(ValidationContentFactory.create_packs())
	var characters := content.all(&"character")
	assert_int(characters.size()).is_equal(1)
	assert_str(String(characters[0].content_id)).is_equal("character.niko:character/niko")
	var niko := characters[0] as CharacterDefinition
	assert_object(niko.sprite_frames).is_not_null()
	assert_str(String(ValidationContentFactory.CHARACTER_ID)).is_equal("character.niko:character/niko")
