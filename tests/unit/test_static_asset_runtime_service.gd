extends GdUnitTestSuite


const CANONICAL_REGISTRY_PATH := "res://game/content/assets/gogobro_static_assets_v1.json"
const FIXTURE_IMAGE_SIZE := Vector2i(64, 64)
const FIXTURE_ROOT_PREFIX := "user://static-asset-runtime-service-tests"

var _fixture_roots := PackedStringArray()
var _fixture_serial := 0


func after_test() -> void:
	for fixture_root: String in _fixture_roots:
		_remove_fixture_tree(fixture_root)
	_fixture_roots.clear()


func test_missing_shipping_manifest_activates_zero_ready_fallback_snapshot() -> void:
	var service := GogoStaticAssetRuntimeService.new("user://missing-static-runtime-bindings.json")
	var content := _validation_snapshot()

	assert_int(service.stage(content)).is_equal(OK)
	assert_int(service.activate_staged(&"", null)).is_equal(OK)
	var readiness := service.release_readiness()
	assert_int(int(readiness.get("expected_noncharacter_units", -1))).is_equal(70)
	assert_int(int(readiness.get("ready_units", -1))).is_equal(0)
	assert_int(int(readiness.get("fallback_units", -1))).is_equal(70)
	assert_bool(bool(readiness.get("release_ready", true))).is_false()
	assert_str(String((readiness.get("issues") as Array)[0].get("code", &""))).is_equal("shipping_manifest_missing")


func test_valid_inactive_manifest_projects_exactly_seventy_noncharacter_units() -> void:
	var manifest_path := _write_manifest_fixture(false)
	var service := GogoStaticAssetRuntimeService.new(manifest_path)

	assert_int(service.stage(_validation_snapshot())).is_equal(OK)
	assert_int(service.activate_staged(&"", null)).is_equal(OK)
	var snapshot := service.active_snapshot()
	assert_int(snapshot.ready_count()).is_equal(0)
	assert_int(snapshot.fallback_count()).is_equal(70)
	assert_str(String(snapshot.state_for_asset(&"service_pistol"))).is_equal("inactive")
	assert_int(snapshot.issues().size()).is_equal(0)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(manifest_path))


func test_canonical_shipping_manifest_activates_only_the_nine_approved_static_units() -> void:
	var service := GogoStaticAssetRuntimeService.new()
	assert_int(service.stage(_validation_snapshot())).is_equal(OK)
	assert_int(service.activate_staged(&"", null)).is_equal(OK)
	var snapshot := service.active_snapshot()

	assert_int(snapshot.ready_count()).is_equal(9)
	assert_int(snapshot.fallback_count()).is_equal(61)
	assert_int(snapshot.issues().size()).is_zero()
	for asset_id in [
		&"warmup_shiv",
		&"service_pistol",
		&"projectile_hit_kit",
		&"ballistic_liner",
		&"smoke_shell_helmet",
		&"one_more_round",
		&"hud_icon_kit",
		&"control_icon_kit",
		&"difficulty_badge_kit",
	]:
		assert_str(String(snapshot.state_for_asset(asset_id))).is_equal("ready")
	for excluded_asset_id in [
		&"community_tapper",
		&"supply_crate",
		&"four_state_button",
	]:
		assert_str(String(snapshot.state_for_asset(excluded_asset_id))).is_equal("inactive")

	assert_object(snapshot.resolve_content(
		&"weapon",
		&"weapon.training_blaster:weapon/training_blaster",
		&"icon"
	)).is_not_null()
	assert_object(snapshot.resolve_content(
		&"weapon",
		&"weapon.training_blade:weapon/training_blade",
		&"icon"
	)).is_not_null()
	assert_object(snapshot.resolve_asset(&"service_pistol", &"world_sprite")).is_null()
	assert_object(snapshot.resolve_asset(&"warmup_shiv", &"world_sprite")).is_null()
	assert_object(snapshot.resolve_asset(&"ballistic_liner", &"icon")).is_not_null()
	assert_object(snapshot.resolve_asset(&"ballistic_liner", &"appearance")).is_null()
	assert_object(snapshot.resolve_asset(&"smoke_shell_helmet", &"icon")).is_not_null()
	assert_object(snapshot.resolve_asset(&"smoke_shell_helmet", &"appearance")).is_null()
	assert_object(snapshot.resolve_global(&"hud_icon_kit", &"health")).is_not_null()
	assert_object(snapshot.resolve_global(&"control_icon_kit", &"move_keyboard_wasd")).is_not_null()
	assert_object(snapshot.resolve_global(&"difficulty_badge_kit", &"standard")).is_not_null()
	assert_object(snapshot.resolve_asset(&"projectile_hit_kit", &"projectile_sprite", &"rifle_round")).is_not_null()
	assert_object(snapshot.resolve_asset(&"projectile_hit_kit", &"impact_sprite", &"static_pierce_mark")).is_not_null()


func test_manifest_count_rejects_near_integer_json_number() -> void:
	var manifest_path := _write_manifest_fixture(false, 70.000001)
	var service := GogoStaticAssetRuntimeService.new(manifest_path)

	assert_int(service.stage(_validation_snapshot())).is_equal(OK)
	assert_int(service.activate_staged(&"", null)).is_equal(OK)
	var codes := PackedStringArray()
	for issue: Dictionary in service.active_snapshot().issues():
		codes.append(String(issue.get("code", &"")))
	assert_array(codes).contains(["shipping_manifest_count_mismatch"])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(manifest_path))


func test_requested_active_without_shipping_contract_is_quarantined() -> void:
	var manifest_path := _write_manifest_fixture(true)
	var service := GogoStaticAssetRuntimeService.new(manifest_path)

	assert_int(service.stage(_validation_snapshot())).is_equal(OK)
	assert_int(service.activate_staged(&"", null)).is_equal(OK)
	var snapshot := service.active_snapshot()
	assert_int(snapshot.ready_count()).is_equal(0)
	assert_str(String(snapshot.state_for_asset(&"service_pistol"))).is_equal("quarantined")
	assert_object(snapshot.resolve_asset(&"service_pistol", &"icon", &"")).is_null()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(manifest_path))


func test_requested_active_installs_approved_hash_bound_texture_and_integer_metadata() -> void:
	var fixture := _write_installable_fixture()
	var snapshot := _activate_fixture(fixture)

	assert_int(snapshot.ready_count()).is_equal(1)
	assert_int(snapshot.fallback_count()).is_equal(69)
	assert_str(String(snapshot.state_for_asset(&"service_pistol"))).is_equal("ready")
	assert_int(snapshot.issues().size()).is_zero()
	var handle := snapshot.resolve_asset(&"service_pistol", &"icon", &"")
	assert_object(handle).is_not_null()
	assert_str(String(handle.binding_key)).is_equal("service_pistol|icon|")
	assert_str(String(handle.asset_id)).is_equal("service_pistol")
	assert_str(String(handle.role)).is_equal("icon")
	assert_str(String(handle.selector)).is_empty()
	assert_object(handle.texture).is_not_null()
	assert_int(handle.texture.get_width()).is_equal(FIXTURE_IMAGE_SIZE.x)
	assert_int(handle.texture.get_height()).is_equal(FIXTURE_IMAGE_SIZE.y)
	assert_bool(handle.texture.get_image().has_mipmaps()).is_false()
	assert_int(typeof(handle.display_size_px)).is_equal(TYPE_VECTOR2I)
	assert_bool(handle.display_size_px == FIXTURE_IMAGE_SIZE).is_true()
	assert_bool(handle.display_scale == Vector2.ONE).is_true()
	assert_int(typeof(handle.pivot_px)).is_equal(TYPE_VECTOR2I)
	assert_bool(handle.pivot_px == Vector2i(32, 32)).is_true()
	assert_int(typeof(handle.atlas_rect_px)).is_equal(TYPE_RECT2I)
	assert_bool(handle.atlas_rect_px == Rect2i(0, 0, 64, 64)).is_true()
	var muzzle_anchor: Variant = handle.anchors_px.get("muzzle")
	assert_int(typeof(muzzle_anchor)).is_equal(TYPE_VECTOR2I)
	assert_bool(muzzle_anchor == Vector2i(56, 32)).is_true()
	assert_object(snapshot.resolve_asset(&"service_pistol", &"icon", &"unknown")).is_null()
	_assert_other_noncharacter_units_inactive(snapshot)


func test_atlas_bindings_resolve_exact_selector_slices_at_declared_display_size() -> void:
	var fixture := _write_installable_fixture({"two_selector_atlas": true})
	var snapshot := _activate_fixture(fixture)

	assert_int(snapshot.ready_count()).is_equal(1)
	var left := snapshot.resolve_asset(&"service_pistol", &"icon", &"left")
	var right := snapshot.resolve_asset(&"service_pistol", &"icon", &"right")
	assert_object(left).is_not_null()
	assert_object(right).is_not_null()
	assert_bool(left.atlas_rect_px == Rect2i(0, 0, 32, 32)).is_true()
	assert_bool(right.atlas_rect_px == Rect2i(32, 0, 32, 32)).is_true()
	for handle: GogoStaticAssetHandle in [left, right]:
		assert_int(handle.texture.get_width()).is_equal(64)
		assert_int(handle.texture.get_height()).is_equal(64)
		assert_bool(handle.display_scale == Vector2(2.0, 2.0)).is_true()
	var left_image := left.texture.get_image()
	var right_image := right.texture.get_image()
	assert_bool(left_image.get_pixel(0, 0).is_equal_approx(Color8(204, 62, 74, 255))).is_true()
	assert_bool(left_image.get_pixel(63, 63).is_equal_approx(Color8(204, 62, 74, 255))).is_true()
	assert_bool(right_image.get_pixel(0, 0).is_equal_approx(Color8(65, 176, 118, 255))).is_true()
	assert_bool(right_image.get_pixel(63, 63).is_equal_approx(Color8(65, 176, 118, 255))).is_true()
	assert_object(snapshot.resolve_asset(&"service_pistol", &"icon", &"")).is_null()


func test_requested_active_hash_mismatch_is_quarantined_without_loading_texture() -> void:
	var fixture := _write_installable_fixture({"declared_sha256": "0".repeat(64)})
	_assert_fixture_quarantined(fixture, "shipping_binding_hash_mismatch")


func test_requested_active_rgba8_pixel_hash_mismatch_is_quarantined() -> void:
	var fixture := _write_installable_fixture({"declared_rgba8_sha256": "0".repeat(64)})
	_assert_fixture_quarantined(fixture, "shipping_binding_pixel_hash_mismatch")


func test_requested_active_pixel_size_mismatch_is_quarantined_without_loading_texture() -> void:
	var fixture := _write_installable_fixture({"declared_pixel_size": Vector2i(63, 64)})
	_assert_fixture_quarantined(fixture, "shipping_binding_size_mismatch")


func test_requested_active_path_outside_allowed_root_is_quarantined_without_loading_texture() -> void:
	var fixture := _write_installable_fixture({"path_outside_allowed_root": true})
	_assert_fixture_quarantined(fixture, "shipping_binding_path_outside_allowed_root")


func test_requested_active_registry_unit_must_be_approved() -> void:
	var fixture := _write_installable_fixture({"registry_approval_status": "planned"})
	_assert_fixture_quarantined(fixture, "shipping_binding_registry_not_approved")


func test_duplicate_binding_key_quarantines_the_whole_requested_active_unit() -> void:
	var fixture := _write_installable_fixture({"duplicate_binding": true})
	_assert_fixture_quarantined(fixture, "shipping_binding_key_duplicate")


func test_out_of_bounds_atlas_rect_quarantines_the_whole_requested_active_unit() -> void:
	var fixture := _write_installable_fixture({"atlas_rect_px": [0, 0, 65, 64]})
	_assert_fixture_quarantined(fixture, "shipping_binding_atlas_rect_invalid")


func test_near_integer_atlas_component_is_rejected_without_truncation() -> void:
	var fixture := _write_installable_fixture({"atlas_rect_px": [0.000001, 0, 64, 64]})
	_assert_fixture_quarantined(fixture, "shipping_binding_atlas_rect_invalid")


func test_wrapping_atlas_rect_integer_quarantines_the_whole_requested_active_unit() -> void:
	var fixture := _write_installable_fixture({"atlas_rect_px": [2147483640, 0, 64, 64]})
	_assert_fixture_quarantined(fixture, "shipping_binding_atlas_rect_invalid")


func test_pivot_on_display_size_boundary_is_outside_and_quarantined() -> void:
	var fixture := _write_installable_fixture({"pivot_px": [64, 32]})
	_assert_fixture_quarantined(fixture, "shipping_binding_pivot_invalid")


func test_approximately_equal_display_scale_is_not_an_exact_mapping() -> void:
	var fixture := _write_installable_fixture({"display_scale": [1.000001, 1.0]})
	_assert_fixture_quarantined(fixture, "shipping_binding_display_mapping_invalid")


func test_content_consumer_with_missing_definition_is_quarantined() -> void:
	var fixture := _write_installable_fixture({
		"consumers": [{
			"kind": "content",
			"content_kind": "weapon",
			"content_id": "missing.pack:weapon/not_present",
			"role": "icon",
		}],
	})
	_assert_fixture_quarantined(fixture, "shipping_binding_consumer_unresolved")


func test_content_consumer_icon_asset_must_match_bound_asset() -> void:
	var content_id := &"test.static-runtime:weapon/consumer"
	var fixture := _write_installable_fixture({
		"consumers": [{
			"kind": "content",
			"content_kind": "weapon",
			"content_id": String(content_id),
			"role": "icon",
		}],
	})
	var content := _content_snapshot_with_icon(content_id, &"weapon", &"different_static_asset")
	_assert_fixture_quarantined(fixture, "shipping_binding_consumer_asset_mismatch", content)


func test_zone_consumer_with_missing_zone_is_quarantined() -> void:
	var fixture := _write_installable_fixture({
		"consumers": [{
			"kind": "zone",
			"zone_id": "missing.pack:zone/not_present",
			"role": "service_pistol",
			"selector": "",
		}],
	})
	_assert_fixture_quarantined(fixture, "shipping_binding_consumer_unresolved")


func test_global_consumer_role_must_name_the_bound_asset() -> void:
	var fixture := _write_installable_fixture({
		"consumers": [{
			"kind": "global",
			"role": "icon",
			"selector": "",
		}],
	})
	_assert_fixture_quarantined(fixture, "shipping_binding_consumer_asset_mismatch")


func test_registry_approved_status_without_candidate_and_approval_evidence_is_quarantined() -> void:
	var fixture := _write_installable_fixture({"omit_approval_evidence": true})
	_assert_fixture_quarantined(fixture, "shipping_binding_approval_evidence_invalid")


func test_approval_evidence_must_bind_exact_rgba8_pixels() -> void:
	var fixture := _write_installable_fixture({"approval_rgba8_mismatch": true})
	_assert_fixture_quarantined(fixture, "shipping_binding_approval_evidence_invalid")


func test_approval_evidence_must_bind_exact_runtime_bindings() -> void:
	var fixture := _write_installable_fixture({"approval_runtime_bindings_hash_mismatch": true})
	_assert_fixture_quarantined(fixture, "shipping_binding_approval_evidence_invalid")


func test_registry_output_dimensions_require_exact_integers() -> void:
	var fixture := _write_installable_fixture({"registry_output_width": 64.000001})
	_assert_fixture_quarantined(fixture, "shipping_binding_size_mismatch")


func test_approval_output_dimensions_require_exact_integers() -> void:
	var fixture := _write_installable_fixture({"approval_output_width": 64.000001})
	_assert_fixture_quarantined(fixture, "shipping_binding_approval_evidence_invalid")


func test_manifest_bindings_must_exactly_match_registry_runtime_bindings() -> void:
	var fixture := _write_installable_fixture({"registry_runtime_bindings_mismatch": true})
	_assert_fixture_quarantined(fixture, "shipping_binding_registry_metadata_mismatch")


func test_activation_is_refused_during_a_session() -> void:
	var service := GogoStaticAssetRuntimeService.new("user://missing-static-runtime-bindings.json")
	assert_int(service.stage(_validation_snapshot())).is_equal(OK)
	assert_int(service.activate_staged(FlowRoute.COMBAT, GameSession.new())).is_equal(ERR_BUSY)
	service.discard_staged()


func _validation_snapshot() -> ContentSnapshot:
	return GogoContentRegistry.new().build_snapshot(ValidationContentFactory.create_packs())


func _content_snapshot_with_icon(
	content_id: StringName,
	kind: StringName,
	icon_asset_id: StringName
) -> ContentSnapshot:
	var definition := GogoContentDefinition.new()
	definition.content_id = content_id
	definition.display_name = "Static runtime consumer fixture"
	definition.kind = kind
	definition.icon_asset_id = icon_asset_id
	var pack := GogoContentPackDefinition.new()
	pack.pack_id = &"test.static-runtime"
	pack.pack_kind = &"core"
	pack.definitions.append(definition)
	return GogoContentRegistry.new().build_snapshot([pack])


func _write_manifest_fixture(
	request_first_active: bool,
	expected_noncharacter_units: Variant = 70
) -> String:
	var canonical: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(CANONICAL_REGISTRY_PATH)
	)
	var units: Array = []
	for unit_variant: Variant in canonical.get("units", []) as Array:
		var unit := unit_variant as Dictionary
		if String(unit.get("category", "")) == "character_creature":
			continue
		units.append({
			"asset_id": unit.get("asset_id", ""),
			"static_content_id": unit.get("content_id", ""),
			"category": unit.get("category", ""),
			"declared_runtime_state": (
				"requested_active"
				if request_first_active and String(unit.get("asset_id", "")) == "service_pistol"
				else "inactive"
			),
		})
	var fixture := {
		"schema_version": GogoStaticAssetRuntimeService.SCHEMA_VERSION,
		"kind": GogoStaticAssetRuntimeService.MANIFEST_KIND,
		"canonical_registry_sha256": FileAccess.get_sha256(CANONICAL_REGISTRY_PATH).to_lower(),
		"expected_noncharacter_units": expected_noncharacter_units,
		"units": units,
	}
	var path := "user://static-runtime-bindings-%s.json" % Time.get_ticks_usec()
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(fixture))
	file.close()
	return path


func _write_installable_fixture(options: Dictionary = {}) -> Dictionary:
	_fixture_serial += 1
	var fixture_root := "%s/fixture-%s-%s" % [FIXTURE_ROOT_PREFIX, Time.get_ticks_usec(), _fixture_serial]
	var allowed_asset_root := fixture_root.path_join("allowed-assets")
	var resource_path := allowed_asset_root.path_join("service_pistol.png")
	if bool(options.get("path_outside_allowed_root", false)):
		resource_path = fixture_root.path_join("outside-assets/service_pistol.png")
	_fixture_roots.append(fixture_root)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(resource_path.get_base_dir()))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(allowed_asset_root))

	var image := Image.create(FIXTURE_IMAGE_SIZE.x, FIXTURE_IMAGE_SIZE.y, false, Image.FORMAT_RGBA8)
	if bool(options.get("two_selector_atlas", false)):
		image.fill(Color(0.0, 0.0, 0.0, 0.0))
		image.fill_rect(Rect2i(0, 0, 32, 32), Color8(204, 62, 74, 255))
		image.fill_rect(Rect2i(32, 0, 32, 32), Color8(65, 176, 118, 255))
	else:
		image.fill(Color8(234, 151, 39, 255))
		image.fill_rect(Rect2i(4, 28, 56, 8), Color8(44, 51, 57, 255))
	assert_int(image.save_png(ProjectSettings.globalize_path(resource_path))).is_equal(OK)
	var actual_sha256 := FileAccess.get_sha256(resource_path).to_lower()
	var rgba8_sha256 := _rgba8_sha256(image)
	var declared_sha256 := String(options.get("declared_sha256", actual_sha256)).to_lower()
	var declared_rgba8_sha256 := String(options.get("declared_rgba8_sha256", rgba8_sha256)).to_lower()
	var registry_approval_status := String(options.get("registry_approval_status", "approved"))
	var declared_pixel_size: Vector2i = options.get("declared_pixel_size", FIXTURE_IMAGE_SIZE)
	var atlas_rect_px: Array = options.get(
		"atlas_rect_px",
		[0, 0, FIXTURE_IMAGE_SIZE.x, FIXTURE_IMAGE_SIZE.y]
	)
	var display_scale: Array = options.get("display_scale", [1, 1])
	var pivot_px: Array = options.get("pivot_px", [32, 32])
	var consumers: Array = options.get("consumers", [])
	var binding := {
		"binding_key": "service_pistol|icon|",
		"role": "icon",
		"selector": "",
		"display_size_px": [64, 64],
		"display_scale": display_scale,
		"pivot_px": pivot_px,
		"atlas_rect_px": atlas_rect_px,
		"anchors_px": {"muzzle": [56, 32]},
		"consumers": consumers,
	}
	var bindings: Array = [binding]
	if bool(options.get("two_selector_atlas", false)):
		bindings = []
		for selector: String in ["left", "right"]:
			var index := bindings.size()
			bindings.append({
				"binding_key": "service_pistol|icon|%s" % selector,
				"role": "icon",
				"selector": selector,
				"display_size_px": [64, 64],
				"display_scale": [2, 2],
				"pivot_px": [32, 32],
				"atlas_rect_px": [index * 32, 0, 32, 32],
				"anchors_px": {},
				"consumers": [],
			})
	if bool(options.get("duplicate_binding", false)):
		bindings.append(binding.duplicate(true))

	var registry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CANONICAL_REGISTRY_PATH))
	for unit_variant: Variant in registry.get("units", []) as Array:
		var unit := unit_variant as Dictionary
		if String(unit.get("asset_id", "")) != "service_pistol":
			continue
		unit["approval_status"] = registry_approval_status
		unit["hashes"] = {
			"sha256": declared_sha256,
			"rgba8_sha256": declared_rgba8_sha256,
		}
		unit["intended_file_paths"] = [resource_path]
		unit["output_spec"] = {
			"type": "png",
			"width": options.get("registry_output_width", FIXTURE_IMAGE_SIZE.x),
			"height": FIXTURE_IMAGE_SIZE.y,
			"alpha": true,
		}
		var registry_runtime_bindings := bindings.duplicate(true)
		if bool(options.get("registry_runtime_bindings_mismatch", false)):
			((registry_runtime_bindings[0] as Dictionary))["pivot_px"] = [31, 32]
		unit["runtime_bindings"] = registry_runtime_bindings
		if not bool(options.get("omit_approval_evidence", false)):
			var candidate_id := "candidate-runtime-fixture"
			var approval_rgba8_sha256 := declared_rgba8_sha256
			if bool(options.get("approval_rgba8_mismatch", false)):
				approval_rgba8_sha256 = "0".repeat(64)
			var approval_runtime_bindings_sha256 := _canonical_variant_sha256(bindings)
			if bool(options.get("approval_runtime_bindings_hash_mismatch", false)):
				approval_runtime_bindings_sha256 = "0".repeat(64)
			unit["active_candidate_id"] = candidate_id
			unit["candidate_history"] = [{
				"candidate_id": candidate_id,
				"decision": "review",
				"harmony_verdict": "harmony_pass",
				"runtime_bindings_sha256": approval_runtime_bindings_sha256,
				"artifacts": [{
					"role": "shipping_texture",
					"path": resource_path,
					"sha256": declared_sha256,
					"rgba8_sha256": approval_rgba8_sha256,
					"pixel_size": [FIXTURE_IMAGE_SIZE.x, FIXTURE_IMAGE_SIZE.y],
					"output_spec": {
						"format": "PNG",
						"width": options.get("approval_output_width", FIXTURE_IMAGE_SIZE.x),
						"height": FIXTURE_IMAGE_SIZE.y,
						"alpha": true,
					},
				}],
			}]
			unit["approval_history"] = [{
				"candidate_id": candidate_id,
				"decision": "approved",
				"authority": "explicit_user_approval_in_current_task",
				"approved_at_utc": "2026-08-26T00:00:00Z",
			}]

	var registry_path := fixture_root.path_join("registry.json")
	_write_json(registry_path, registry)
	var registry_sha256 := FileAccess.get_sha256(registry_path).to_lower()

	var manifest_units: Array = []
	for unit_variant: Variant in registry.get("units", []) as Array:
		var unit := unit_variant as Dictionary
		if String(unit.get("category", "")) == "character_creature":
			continue
		var asset_id := String(unit.get("asset_id", ""))
		var manifest_unit := {
			"asset_id": asset_id,
			"static_content_id": unit.get("content_id", ""),
			"category": unit.get("category", ""),
			"declared_runtime_state": "requested_active" if asset_id == "service_pistol" else "inactive",
			"approval_status": "approved" if asset_id == "service_pistol" else unit.get("approval_status", "planned"),
		}
		if asset_id == "service_pistol":
			manifest_unit["shipping"] = {
				"resource_path": resource_path,
				"sha256": declared_sha256,
				"rgba8_sha256": declared_rgba8_sha256,
				"pixel_size": [declared_pixel_size.x, declared_pixel_size.y],
				"texture_filter": "nearest",
				"mipmaps": false,
			}
			manifest_unit["bindings"] = bindings
		manifest_units.append(manifest_unit)

	var manifest := {
		"schema_version": GogoStaticAssetRuntimeService.SCHEMA_VERSION,
		"kind": GogoStaticAssetRuntimeService.MANIFEST_KIND,
		"canonical_registry_sha256": registry_sha256,
		"expected_noncharacter_units": 70,
		"units": manifest_units,
	}
	var manifest_path := fixture_root.path_join("manifest.json")
	_write_json(manifest_path, manifest)
	return {
		"manifest_path": manifest_path,
		"registry_path": registry_path,
		"allowed_asset_root": allowed_asset_root,
		"resource_path": resource_path,
	}


func _activate_fixture(
	fixture: Dictionary,
	content: ContentSnapshot = null
) -> GogoStaticAssetSnapshot:
	var service := GogoStaticAssetRuntimeService.new(
		String(fixture["manifest_path"]),
		String(fixture["registry_path"]),
		String(fixture["allowed_asset_root"])
	)
	var staged_content := content if content != null else _validation_snapshot()
	assert_int(service.stage(staged_content)).is_equal(OK)
	assert_int(service.activate_staged(&"", null)).is_equal(OK)
	return service.active_snapshot()


func _assert_fixture_quarantined(
	fixture: Dictionary,
	expected_issue_code: String,
	content: ContentSnapshot = null
) -> void:
	var snapshot := _activate_fixture(fixture, content)
	assert_int(snapshot.ready_count()).is_zero()
	assert_int(snapshot.fallback_count()).is_equal(70)
	assert_str(String(snapshot.state_for_asset(&"service_pistol"))).is_equal("quarantined")
	assert_object(snapshot.resolve_asset(&"service_pistol", &"icon", &"")).is_null()
	assert_str(_issue_codes(snapshot)).contains(expected_issue_code)


func _assert_other_noncharacter_units_inactive(snapshot: GogoStaticAssetSnapshot) -> void:
	var registry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CANONICAL_REGISTRY_PATH))
	var inactive_count := 0
	for unit_variant: Variant in registry.get("units", []) as Array:
		var unit := unit_variant as Dictionary
		if String(unit.get("category", "")) == "character_creature":
			continue
		var asset_id := StringName(String(unit.get("asset_id", "")))
		if asset_id == &"service_pistol":
			continue
		assert_str(String(snapshot.state_for_asset(asset_id))).is_equal("inactive")
		inactive_count += 1
	assert_int(inactive_count).is_equal(69)


func _write_json(path: String, payload: Dictionary) -> void:
	var absolute_path := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	var file := FileAccess.open(absolute_path, FileAccess.WRITE)
	assert_object(file).is_not_null()
	file.store_string(JSON.stringify(payload))
	file.close()


func _rgba8_sha256(source: Image) -> String:
	var rgba8 := source.duplicate()
	rgba8.convert(Image.FORMAT_RGBA8)
	var hashing := HashingContext.new()
	assert_int(hashing.start(HashingContext.HASH_SHA256)).is_equal(OK)
	assert_int(hashing.update(rgba8.get_data())).is_equal(OK)
	return hashing.finish().hex_encode()


func _canonical_variant_sha256(value: Variant) -> String:
	# Match the runtime boundary: manifests and registries are hashed after JSON parsing,
	# where numeric values have been normalized to JSON number variants.
	var normalized: Variant = JSON.parse_string(JSON.stringify(value))
	return JSON.stringify(normalized, "", true).sha256_text()


func _remove_fixture_tree(path: String) -> void:
	var absolute_path := ProjectSettings.globalize_path(path)
	if not absolute_path.contains("static-asset-runtime-service-tests"):
		fail("Refusing unsafe static runtime fixture cleanup: %s" % absolute_path)
		return
	_remove_absolute_tree(absolute_path)


func _remove_absolute_tree(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		var child := path.path_join(entry)
		if directory.current_is_dir():
			_remove_absolute_tree(child)
		else:
			DirAccess.remove_absolute(child)
		entry = directory.get_next()
	directory.list_dir_end()
	DirAccess.remove_absolute(path)


func _issue_codes(snapshot: GogoStaticAssetSnapshot) -> String:
	var codes := PackedStringArray()
	for issue: Dictionary in snapshot.issues():
		codes.append(String(issue.get("code", &"")))
	return ",".join(codes)
