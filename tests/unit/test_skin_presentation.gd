extends GdUnitTestSuite


const DEV_SKIN := "res://content_packs/skins/dev_placeholder/skin.tres"
const ALT_SKIN := "res://content_packs/skins/test_alt/skin.tres"
const FORMAL_SKIN := "res://content_packs/skins/lets_gooooo/skin.tres"
const FORMAL_FONT_STACK := "res://assets/font/brotato_font_stack.tres"
const TEST_SKIN := "user://tests/skin_presentation/cache_isolation_skin.tres"


func test_skin_v2_exposes_required_qualified_asset_categories() -> void:
	assert_int(SkinPackDef.CURRENT_API_VERSION).is_equal(2)
	for skin_path: String in [DEV_SKIN, ALT_SKIN, FORMAL_SKIN]:
		var skin := load(skin_path) as SkinPackDef
		assert_int(skin.skin_api_version).is_equal(2)
		for category: StringName in SkinPackDef.ASSET_CATEGORIES:
			assert_bool(skin.fallback_asset_paths.has(category)).override_failure_message(
				"%s missing fallback %s" % [skin_path, category]
			).is_true()


func test_lets_gooooo_formal_skin_resolves_every_weapon_and_static_world_role() -> void:
	var resolver: SkinResolver = auto_free(SkinResolver.new())
	assert_int(resolver.load_manifest(FORMAL_SKIN)).is_equal(OK)
	assert_str(String(resolver.active_skin.skin_id)).is_equal("lets_gooooo")
	assert_str(resolver.active_skin.product_name).is_equal("Game Prototype")
	assert_bool(resolver.active_skin.show_product_branding).is_false()
	assert_array(resolver.active_skin.validate()).is_empty()
	for definition: WeaponDef in Content.catalog.get_weapons():
		var presentation_id := definition.get_presentation_id(Content.catalog.pack_id)
		for variant: StringName in [&"icon", &"world"]:
			var path := resolver.resolve_path(&"weapon", presentation_id, variant)
			assert_str(path).override_failure_message(
				"%s missing %s art" % [presentation_id, variant]
			).contains("/skins/lets_gooooo/assets/weapons/")
	for requirement: Array in [
		[&"pickup", &"pickup.material", &"world", "/assets/pickups/"],
		[&"pickup", &"pickup.heal", &"world", "/assets/pickups/"],
		[&"pickup", &"pickup.chest", &"world", "/assets/pickups/"],
		[&"prop", &"prop.supply_crate", &"world", "/assets/props/"],
		[&"prop", &"prop.weapon_rack", &"world", "/assets/props/"],
		[&"ally", &"ally.turret", &"world", "/assets/allies/"],
		[&"ally", &"ally.drone", &"world", "/assets/allies/"],
		[&"scene", &"scene.arena.floor", &"floor", "/assets/scenes/"],
		[&"ui", &"ui.logo", &"logo", "/assets/ui/"],
	]:
		assert_str(resolver.resolve_path(
			requirement[0], requirement[1], requirement[2]
		)).contains(requirement[3])
	for projectile_id: StringName in [
		&"projectile.enemy", &"weapon.pistol", &"weapon.revolver", &"weapon.smg",
		&"weapon.carbine", &"weapon.shotgun", &"weapon.laser", &"weapon.railbow",
	]:
		assert_str(resolver.resolve_path(
			&"projectile", projectile_id, &"world"
		)).contains("/skins/lets_gooooo/assets/projectiles/")
	assert_object(resolver.active_skin.theme).is_not_null()
	assert_str(resolver.resolve_path(
		&"scene", &"scene.arena.background", &"background"
	)).contains("/assets/scenes/arena_floor.png")
	assert_bool(resolver.resolve_path(
		&"scene", &"scene.arena.background", &"background"
	).contains("title_background")).is_false()


func test_formal_skin_theme_uses_anybody_medium_with_noto_sans_sc_fallback_at_runtime() -> void:
	var skin := load(FORMAL_SKIN) as SkinPackDef
	assert_object(skin).is_not_null()
	if skin == null:
		return
	assert_str(skin.font.resource_path).is_equal(FORMAL_FONT_STACK)
	assert_object(skin.theme).is_not_null()
	if skin.theme == null:
		return
	var theme_font := skin.theme.get_default_font()
	assert_object(theme_font).is_not_null()
	if theme_font == null:
		return
	assert_str(theme_font.resource_path).is_equal(FORMAL_FONT_STACK)
	var stack := load(FORMAL_FONT_STACK) as Font
	assert_object(stack).is_not_null()
	if stack == null:
		return
	assert_bool(stack.has_char("A".unicode_at(0))).is_true()
	assert_bool(stack.has_char("7".unicode_at(0))).is_true()
	assert_bool(stack.has_char("中".unicode_at(0))).is_true()
	var fallbacks := stack.get_fallbacks()
	assert_int(fallbacks.size()).is_equal(1)
	assert_str(fallbacks[0].resource_path).is_equal(
		"res://assets/font/NotoSansCJKsc-Medium.otf"
	)


func test_formal_theme_centralizes_brotato_text_outline_tokens() -> void:
	var skin := load(FORMAL_SKIN) as SkinPackDef
	assert_object(skin).is_not_null()
	if skin == null or skin.theme == null:
		return
	var theme := skin.theme
	assert_int(theme.get_constant(&"outline_size", &"Label")).is_equal(2)
	assert_int(theme.get_constant(&"outline_size", &"Button")).is_equal(2)
	assert_int(theme.get_constant(&"outline_size", &"BrotatoTitle")).is_equal(4)
	assert_int(theme.get_constant(&"outline_size", &"BrotatoCombatNumber")).is_equal(6)
	for type_name: StringName in [&"Label", &"Button", &"BrotatoTitle", &"BrotatoCombatNumber"]:
		assert_bool(theme.get_color(&"font_outline_color", type_name).is_equal_approx(
			Color(0.01, 0.01, 0.01, 1.0)
		)).is_true()


func test_frontend_applies_skin_theme_and_restores_scene_fallback_for_theme_less_skin() -> void:
	var original_skin: SkinPackDef = Presentation.active_skin
	var frontend: FrontendShell = auto_free(load(
		"res://scenes/ui/frontend/frontend_shell.tscn"
	).instantiate() as FrontendShell)
	add_child(frontend)
	var formal_theme: Theme = (load(FORMAL_SKIN) as SkinPackDef).theme
	assert_object(formal_theme).is_not_null()
	assert_bool(frontend.theme.get_color(
		&"font_hover_color", &"Button"
	).is_equal_approx(formal_theme.get_color(
		&"font_hover_color", &"Button"
	))).is_true()

	var fallback_theme: Theme = frontend._fallback_theme
	var theme_less_skin := (load(DEV_SKIN) as SkinPackDef).duplicate(true) as SkinPackDef
	theme_less_skin.theme = null
	Presentation.active_skin = theme_less_skin
	frontend._apply_skin_branding()
	assert_bool(frontend.theme.get_color(
		&"font_hover_color", &"Button"
	).is_equal_approx(fallback_theme.get_color(
		&"font_hover_color", &"Button"
	))).is_true()
	Presentation.active_skin = original_skin
	frontend._apply_skin_branding()


func test_lets_gooooo_formal_skin_has_exact_passive_and_upgrade_icons() -> void:
	var skin := load(FORMAL_SKIN) as SkinPackDef
	assert_object(skin).is_not_null()
	if skin == null:
		return
	var passive_table: Dictionary = skin.asset_tables.get(&"passive/icon", {})
	var upgrade_table: Dictionary = skin.asset_tables.get(&"upgrade/icon", {})
	assert_int(passive_table.size()).is_equal(60)
	assert_int(upgrade_table.size()).is_equal(64)
	for definition: PassiveItemDef in Content.catalog.get_passives():
		var presentation_id := definition.get_presentation_id(Content.catalog.pack_id)
		assert_bool(passive_table.has(presentation_id)).override_failure_message(
			"Missing exact passive icon: %s" % presentation_id
		).is_true()
		var path := str(passive_table.get(presentation_id, ""))
		assert_bool(ResourceLoader.exists(path)).override_failure_message(path).is_true()
	for definition: UpgradeDef in Content.catalog.get_upgrades():
		var presentation_id := definition.get_presentation_id(Content.catalog.pack_id)
		assert_bool(upgrade_table.has(presentation_id)).override_failure_message(
			"Missing exact upgrade icon: %s" % presentation_id
		).is_true()
		assert_bool(ResourceLoader.exists(str(upgrade_table.get(presentation_id, "")))).is_true()


func test_variant_resolution_distinguishes_weapon_icon_and_world_assets() -> void:
	var skin := SkinPackDef.new()
	skin.asset_tables = {
		&"weapon/icon": {&"weapon.demo": "res://icon.svg"},
		&"weapon/world": {
			&"weapon.demo": "res://assets/sprites/Weapons/Range/WeaponPistol.png",
		},
	}
	skin.fallback_asset_paths = {
		&"weapon/icon": "res://icon.svg",
		&"weapon/world": "res://assets/sprites/Weapons/Range/WeaponPistol.png",
	}

	assert_str(skin.asset_path(&"weapon", &"weapon.demo", &"icon")).is_equal(
		"res://icon.svg"
	)
	assert_str(skin.asset_path(&"weapon", &"weapon.demo", &"world")).is_equal(
		"res://assets/sprites/Weapons/Range/WeaponPistol.png"
	)
	# The legacy three-argument resolver defaults gameplay weapons to world art.
	assert_str(skin.asset_path(&"weapon", &"weapon.demo")).is_equal(
		"res://assets/sprites/Weapons/Range/WeaponPistol.png"
	)


func test_v1_tables_remain_readable_but_fail_formal_validation() -> void:
	var legacy := SkinPackDef.new()
	legacy.skin_id = &"legacy"
	legacy.skin_api_version = SkinPackDef.LEGACY_API_VERSION
	legacy.asset_tables = {
		&"weapon": {&"weapon.demo": "res://icon.svg"},
	}
	legacy.fallback_asset_paths = {
		&"weapon": "res://icon.svg",
	}

	assert_str(legacy.asset_path(&"weapon", &"weapon.demo", &"icon")).is_equal(
		"res://icon.svg"
	)
	assert_array(legacy.validate()).contains(["unsupported skin_api_version: 1"])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_SKIN.get_base_dir()))
	assert_int(ResourceSaver.save(legacy, TEST_SKIN)).is_equal(OK)
	var resolver: SkinResolver = auto_free(SkinResolver.new())
	assert_int(resolver.load_manifest(TEST_SKIN)).is_equal(ERR_INVALID_DATA)
	assert_object(resolver.active_skin).is_null()
	assert_array(resolver.notices).contains(["unsupported skin_api_version: 1"])


func test_content_texture_resolution_uses_presentation_id_not_stable_id() -> void:
	var skin := SkinPackDef.new()
	skin.asset_tables = {
		&"passive/icon": {&"passive.demo": "res://icon.svg"},
	}
	skin.fallback_asset_paths = {
		&"passive/icon": "res://assets/sprites/Gold/gold_1.png",
	}
	var resolver: SkinResolver = auto_free(SkinResolver.new())
	resolver.active_skin = skin
	var definition := PassiveItemDef.new()
	definition.content_id = &"passive/demo"
	definition.presentation_id = &"passive.demo"

	var resolved := resolver.resolve_content_texture(
		definition,
		null,
		&"icon",
		&"core"
	)
	assert_object(resolved).is_not_null()
	assert_str(resolved.resource_path).is_equal("res://icon.svg")


func test_item_ui_surfaces_resolve_icons_from_content_definitions() -> void:
	for path: String in [
		"res://scenes/ui/item_card/item_card.gd",
		"res://scenes/ui/shop_card/shop_card.gd",
		"res://scenes/ui/reward_panel/reward_panel.gd",
		"res://scenes/ui/upgrade_card/upgrade_card.gd",
		"res://scenes/ui/codex/codex_panel.gd",
	]:
		assert_str(FileAccess.get_file_as_string(path)).override_failure_message(path).contains(
			"resolve_content_texture"
		)
	var shop_source := FileAccess.get_file_as_string(
		"res://scenes/ui/shop_card/shop_card.gd"
	)
	assert_str(shop_source).contains("Content.catalog.get_item_definition(value)")


func after_test() -> void:
	if FileAccess.file_exists(TEST_SKIN):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SKIN))


func test_two_skin_manifests_resolve_content_and_missing_assets_with_fallbacks() -> void:
	var dev: SkinResolver = auto_free(SkinResolver.new())
	var alt: SkinResolver = auto_free(SkinResolver.new())
	assert_int(dev.load_manifest(DEV_SKIN)).is_equal(OK)
	assert_int(alt.load_manifest(ALT_SKIN)).is_equal(OK)
	assert_str(String(dev.active_skin.skin_id)).is_equal("dev_placeholder")
	assert_str(String(alt.active_skin.skin_id)).is_equal("test_alt")
	assert_str(dev.active_skin.product_name).is_not_equal(alt.active_skin.product_name)

	for definition: ContentDef in _all_content_definitions():
		var presentation_id := definition.get_presentation_id(Content.catalog.pack_id)
		assert_bool(presentation_id.is_empty()).is_false()
		assert_str(dev.resolve_path(_category_for(definition), presentation_id)).is_not_empty()
		assert_str(alt.resolve_path(_category_for(definition), presentation_id)).is_not_empty()
	assert_str(dev.resolve_path(&"weapon", &"missing.weapon")).is_not_empty()
	assert_str(alt.resolve_path(&"enemy", &"missing.enemy")).is_not_empty()
	for definitions: Array in [
		Content.catalog.get_characters(),
		Content.catalog.get_weapons(),
		Content.catalog.get_enemies(),
	]:
		for definition: ContentDef in definitions:
			var category := _category_for(definition)
			var table_category := SkinPackDef.qualified_category(
				category, &"icon" if definition is WeaponDef else &""
			)
			var table: Dictionary = dev.active_skin.asset_tables.get(table_category, {})
			assert_bool(table.has(definition.presentation_id)).is_true()


func test_active_skin_isolated_from_same_path_cache_replacement() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_SKIN.get_base_dir()))
	var first := (load(DEV_SKIN) as SkinPackDef).duplicate(true) as SkinPackDef
	first.skin_id = &"cache_isolation"
	first.product_name = "Runtime Original"
	first.accent_color = Color(0.1, 0.2, 0.3, 1.0)
	assert_int(ResourceSaver.save(first, TEST_SKIN)).is_equal(OK)

	var resolver: SkinResolver = auto_free(SkinResolver.new())
	assert_int(resolver.load_manifest(TEST_SKIN)).is_equal(OK)
	assert_str(resolver.active_skin.product_name).is_equal("Runtime Original")
	assert_int(resolver.active_skin.get_instance_id()).is_not_equal(first.get_instance_id())

	var replacement := first.duplicate(true) as SkinPackDef
	replacement.product_name = "Replacement"
	replacement.accent_color = Color(0.9, 0.8, 0.7, 1.0)
	assert_int(ResourceSaver.save(replacement, TEST_SKIN)).is_equal(OK)
	var reloaded := ResourceLoader.load(
		TEST_SKIN,
		"SkinPackDef",
		ResourceLoader.CACHE_MODE_REPLACE
	) as SkinPackDef

	assert_str(reloaded.product_name).is_equal("Replacement")
	assert_bool(reloaded.accent_color.is_equal_approx(Color(0.9, 0.8, 0.7, 1.0))).is_true()
	assert_str(resolver.active_skin.product_name).is_equal("Runtime Original")
	assert_bool(
		resolver.active_skin.accent_color.is_equal_approx(Color(0.1, 0.2, 0.3, 1.0))
	).is_true()


func test_gameplay_cue_bus_only_emits_semantic_cues() -> void:
	var bus: GameplayCueBus = auto_free(GameplayCueBus.new())
	var received: Array[Dictionary] = []
	bus.cue_emitted.connect(func(cue_id: StringName, context: Dictionary) -> void:
		received.append({"cue_id": cue_id, "context": context.duplicate(true)})
	)
	var original := {"damage": 12.0, "critical": true}

	assert_bool(bus.emit_cue(&"hit.critical", original)).is_true()
	assert_bool(bus.emit_cue(&"not a semantic cue", {})).is_false()

	assert_int(received.size()).is_equal(1)
	assert_str(String(received[0].cue_id)).is_equal("hit.critical")
	assert_dict(original).is_equal({"damage": 12.0, "critical": true})


func test_presentation_controller_exposes_all_required_semantic_states() -> void:
	var controller: PresentationController = auto_free(PresentationController.new())
	for state: StringName in [
		&"idle", &"move", &"attack", &"hit", &"death", &"dash", &"spawn", &"telegraph",
	]:
		assert_bool(controller.set_semantic_state(state)).is_true()
		assert_str(String(controller.semantic_state)).is_equal(String(state))
	assert_bool(controller.set_semantic_state(&"gameplay.damage.plus_ten")).is_false()


func test_each_skin_controls_semantic_animation_mapping() -> void:
	var dev: SkinResolver = auto_free(SkinResolver.new())
	var alt: SkinResolver = auto_free(SkinResolver.new())
	assert_int(dev.load_manifest(DEV_SKIN)).is_equal(OK)
	assert_int(alt.load_manifest(ALT_SKIN)).is_equal(OK)
	var dev_map: Dictionary = dev.resolve_animation_map(&"character", &"character.well_rounded")
	var alt_map: Dictionary = alt.resolve_animation_map(&"character", &"character.well_rounded")
	assert_str(str(dev_map.get(&"move", ""))).is_equal("move")
	assert_str(str(alt_map.get(&"move", ""))).is_equal("idle")


func test_skin_choice_cannot_change_deterministic_gameplay_hash() -> void:
	var expected := _gameplay_hash_for_skin(DEV_SKIN)
	assert_str(expected).is_equal(_gameplay_hash_for_skin(ALT_SKIN))
	assert_str(expected).is_equal(_gameplay_hash_for_skin(FORMAL_SKIN))


func test_cue_presenter_resolves_audio_shake_and_rumble_without_touching_gameplay() -> void:
	var presenter: GameplayCuePresenter = auto_free(GameplayCuePresenter.new())
	var presented: Array[Dictionary] = []
	presenter.cue_presented.connect(func(_cue_id: StringName, resolved: Dictionary) -> void:
		presented.append(resolved)
	)
	var run := RunState.new(42)
	var before := run.to_dict()

	presenter.handle_cue(&"hit.critical", {"run_state": run})

	assert_int(presented.size()).is_equal(1)
	assert_str(str(presented[0].audio)).is_not_empty()
	assert_bool((presented[0].screen_shake as Dictionary).has("strength")).is_true()
	assert_bool((presented[0].rumble as Dictionary).has("strong")).is_true()
	assert_dict(run.to_dict()).is_equal(before)


func test_boss_mechanics_do_not_reference_default_pack_presentation_assets() -> void:
	var scene_source := FileAccess.get_file_as_string(
		"res://scenes/unit/enemy/boss/mouse_dog.tscn"
	)
	var script_source := FileAccess.get_file_as_string(
		"res://scenes/unit/enemy/boss/mouse_dog.gd"
	)
	assert_bool(scene_source.contains("content_packs/default/assets")).is_false()
	assert_bool(script_source.contains("AttackAudio")).is_false()


func test_runtime_uses_presentation_controller_and_semantic_audio_only() -> void:
	var unit_source := FileAccess.get_file_as_string("res://scenes/unit/unit.gd")
	var player_source := FileAccess.get_file_as_string("res://scenes/unit/players/player.gd")
	var enemy_source := FileAccess.get_file_as_string("res://scenes/unit/enemy/enemy.gd")
	var weapon_source := FileAccess.get_file_as_string("res://scenes/weapons/weapon.gd")
	for source: String in [unit_source, player_source, enemy_source, weapon_source]:
		assert_str(source).contains("presentation_controller")
	assert_str(unit_source).contains("PresentationController.new")
	assert_str(player_source).contains("set_semantic_state")
	assert_str(enemy_source).contains("set_semantic_state")
	assert_str(weapon_source).contains("set_semantic_state")

	var semantic_audio_paths := [
		"res://scenes/components/hitbox_component.gd",
		"res://scenes/weapons/range/range_behavior.gd",
		"res://scenes/ui/item_card/item_card.gd",
		"res://scenes/ui/selection_panel/selection_card.gd",
		"res://scenes/ui/selection_panel/selection_panel.gd",
		"res://scenes/ui/shop_card/shop_card.gd",
		"res://scenes/ui/shop_panel/shop_panel.gd",
		"res://scenes/ui/upgrade_card/upgrade_card.gd",
	]
	for path: String in semantic_audio_paths:
		assert_bool(
			FileAccess.get_file_as_string(path).contains("SoundManager.play_sound")
		).override_failure_message(path).is_false()
	assert_bool(
		FileAccess.get_file_as_string("res://project.godot").contains("SoundManager=\"")
	).is_false()

	for skin_path: String in [DEV_SKIN, ALT_SKIN]:
		var skin := load(skin_path) as SkinPackDef
		assert_str(str(skin.music_tracks.get(&"combat", ""))).is_not_empty()
		for cue_id: StringName in [&"hit.normal", &"ui.confirm", &"ui.hover"]:
			assert_str(str(skin.audio_cues.get(cue_id, ""))).is_not_empty()
		assert_str(str(skin.particle_cues.get(&"hit.critical", ""))).is_not_empty()


func test_mechanical_scenes_do_not_embed_skin_asset_files() -> void:
	var mechanical_roots := [
		"res://scenes/unit",
		"res://scenes/weapons",
		"res://scenes/projectiles",
		"res://scenes/coins",
		"res://scenes/effects",
	]
	var forbidden_extensions := [".png\"", ".jpg\"", ".jpeg\"", ".webp\"", ".svg\"", ".mp3\"", ".wav\"", ".ogg\""]
	for root: String in mechanical_roots:
		for path: String in _scene_files_below(root):
			var source := FileAccess.get_file_as_string(path).to_lower()
			for extension: String in forbidden_extensions:
				assert_bool(source.contains(extension)).override_failure_message(path).is_false()
	assert_bool(
		FileAccess.get_file_as_string("res://content_packs/default/pack.tres").contains(
			"res://assets/"
		)
	).override_failure_message("gameplay content pack embeds presentation assets").is_false()


func _gameplay_hash_for_skin(skin_path: String) -> String:
	var resolver: SkinResolver = auto_free(SkinResolver.new())
	assert_int(resolver.load_manifest(skin_path)).is_equal(OK)
	var run := RunState.new()
	run.random_seed = 8675309
	run.run_mode = RunMode.ENDLESS
	run.wave = 50
	run.difficulty = 4
	var generator := EndlessWaveGenerator.new(
		Content.catalog,
		run.random_seed,
		EndlessScalingDef.new()
	)
	var wave := generator.generate(run.wave, run.difficulty)
	var shop := ShopService.new(run.random_seed)
	var offers: Array[String] = []
	var tier_config := {
		"rare": {"base": 0.2, "per_wave": 0.01},
		"epic": {"base": 0.05, "per_wave": 0.005},
		"legendary": {"base": 0.01, "per_wave": 0.002},
	}
	for item: ItemBase in shop.select_offers(
		Content.catalog.get_shop_items(), run.wave, 0.0, tier_config, 4, Content.catalog
	):
		offers.append(String(Content.catalog.get_item_stable_id(item)))
	var reward_service := RewardService.new(run.random_seed)
	var reward_item := reward_service.select_reward(Content.catalog.get_shop_items(), run.wave)
	var spawn_snapshot: Array[Dictionary] = []
	var drop_snapshot: Array[Dictionary] = []
	var combat_events: Array[Dictionary] = []
	for spawn: WaveSpawnDef in wave.spawns:
		spawn_snapshot.append({"id": String(spawn.enemy_id), "weight": spawn.weight})
		var enemy := Content.catalog.get_enemy(spawn.enemy_id)
		if enemy != null:
			drop_snapshot.append({
				"id": String(spawn.enemy_id),
				"materials": floori(
					enemy.stats.gold_drop
					* EndlessScalingDef.new().material_drop_multiplier(run.wave)
				),
			})
			combat_events.append({
				"event": "spawn",
				"enemy_id": String(spawn.enemy_id),
				"priority": spawn.is_priority_spawn(),
			})
	var snapshot := {
		"run": run.to_dict(),
		"wave_tags": wave.tags.map(func(tag: StringName) -> String: return String(tag)),
		"priority_count": wave.priority_spawn_count,
		"density": wave.spawn_density_multiplier,
		"spawns": spawn_snapshot,
		"drops": drop_snapshot,
		"offers": offers,
		"reward": String(Content.catalog.get_item_stable_id(reward_item)),
		"combat_events": combat_events,
	}
	return JSON.stringify(snapshot).sha256_text()


func _all_content_definitions() -> Array[ContentDef]:
	var result: Array[ContentDef] = []
	result.append_array(Content.catalog.get_characters())
	result.append_array(Content.catalog.get_weapons())
	result.append_array(Content.catalog.get_passives())
	result.append_array(Content.catalog.get_upgrades())
	result.append_array(Content.catalog.get_enemies())
	result.append_array(Content.catalog.get_waves())
	return result


func _category_for(definition: ContentDef) -> StringName:
	if definition is CharacterDef:
		return &"character"
	if definition is WeaponDef:
		return &"weapon"
	if definition is EnemyDef:
		return &"enemy"
	if definition is PassiveItemDef:
		return &"passive"
	if definition is UpgradeDef:
		return &"upgrade"
	return &"scene"


func _scene_files_below(root: String) -> PackedStringArray:
	var result := PackedStringArray()
	var directory := DirAccess.open(root)
	if directory == null:
		return result
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		var path := root.path_join(entry)
		if directory.current_is_dir():
			result.append_array(_scene_files_below(path))
		elif entry.ends_with(".tscn"):
			result.append(path)
		entry = directory.get_next()
	directory.list_dir_end()
	return result
