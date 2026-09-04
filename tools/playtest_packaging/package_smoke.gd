extends SceneTree

var failures: Array[String] = []
var app: Node
var shop: Control
var shop_service
var publication_counts := {"state": 0, "offers": 0}
const GLOCK_ID := &"weapon.training_blaster:weapon/training_blaster"
var viewport_directory := ""
var viewport_names: Array[String] = []
const VIEWPORT_NAMES := ["task-selector", "character-only", "weapon-choice", "difficulty-ready", "combat-after5s", "shop-after-merge"]

func _initialize() -> void:
	# No packaged script/manifest/profile read is allowed before actual OS paths agree.
	if not isolation_guard():
		finish()
		return
	if not prepare_viewports():
		finish()
		return
	call_deferred("_run")

func _run() -> void:
	# Official 4.7.1 export templates disable --script. The configured full engine
	# loads this external fixture with --main-pack, testing only packaged resources.
	var package_dir := OS.get_cmdline_user_args()[0].replace("\\", "/")
	var resource_root := ProjectSettings.globalize_path("res://")
	check(not DirAccess.dir_exists_absolute(resource_root.path_join("game")), "no loose game source fallback")
	print("PACKAGE_RESOURCE_ROOT %s loose_game=false" % resource_root)
	check(OS.is_debug_build(), "debug development-preview build")
	check(String(ProjectSettings.get_setting("application/run/main_scene")) == "res://game/app/app_root.tscn", "current application entrypoint")
	if not failures.is_empty():
		finish()
		return
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(package_dir.path_join("SNAPSHOT.json")))
	var checked_files := 0
	for record: Dictionary in manifest.source_files:
		var path := "res://" + String(record.path)
		if path.ends_with(".json") or path.ends_with(".png"):
			check(FileAccess.file_exists(path), "raw resource present: " + path)
			check(FileAccess.get_sha256(path).to_upper() == record.sha256, "raw resource hash: " + path)
			if path.ends_with(".json"):
				check(JSON.parse_string(FileAccess.get_file_as_string(path)) != null, "JSON parse: " + path)
			checked_files += 1
	check(not DirAccess.dir_exists_absolute("res://game/assets/top20"), "Top20 art absent")
	check(not DirAccess.dir_exists_absolute("res://game/content/packs/items/top20"), "Top20 pack absent")
	for excluded in ["reports", "tests", "tools", ".superpowers", "addons"]:
		check(not DirAccess.dir_exists_absolute("res://" + excluded), "excluded root: " + excluded)
	if not failures.is_empty():
		finish()
		return
	print("PACKAGE_RESOURCES_OK raw_png_json=%d user_dir=%s" % [checked_files, OS.get_user_data_dir()])
	app = load("res://game/app/app_root.tscn").instantiate()
	root.add_child(app)
	await settle()
	check(app.boot_result != null and app.boot_result.is_ok(), "actual application boot")
	var content = app.content_snapshot
	check(content.all(&"character").size() == 1, "one NiKo character")
	check(content.all(&"weapon").size() == 12, "twelve live weapons")
	check(content.all(&"wave").size() == 20, "twenty live waves")
	check(load("res://game/gameplay/world/floor_readability.gdshader") is Shader, "floor shader from PCK")
	check(not content.pack_ids.has(&"gogobro.top20.items"), "Top20 pack inactive")
	var assets = app.static_asset_service.active_snapshot()
	check(assets != null and assets.is_development_preview(), "development overlay active")
	check(app.static_candidate_preview_service.last_errors.is_empty(), "preview resource validation")
	for weapon in content.all(&"weapon"):
		var handle = assets.resolve_content(&"weapon", weapon.content_id, &"icon")
		check(handle != null and handle.texture != null, "weapon icon " + String(weapon.content_id))
	if not failures.is_empty():
		finish()
		return
	var host: Node = app.get_node_or_null("SceneHost")
	check(host != null and host.get_child_count() == 1, "one actual SceneHost screen")
	check(app.scene_flow.current_route() == &"main_menu", "ordinary menu route")
	if not failures.is_empty():
		finish()
		return
	var menu_background := host.get_child(0).get_node_or_null("StaticMenuBackground") as TextureRect
	var start_button := host.get_child(0).get_node_or_null("ContentRoot/Body/MenuActions/StartButton") as Button
	check(menu_background != null and menu_background.texture != null, "menu texture loaded")
	check(start_button != null and start_button.is_visible_in_tree() and not start_button.disabled, "actual menu start button")
	if not failures.is_empty():
		finish()
		return
	start_button.pressed.emit()
	await settle()
	check(app.scene_flow.current_route() == &"character_select", "menu to character")
	if not failures.is_empty():
		finish()
		return
	var selection_host := host.get_child(0)
	var task_option := selection_host.get_node_or_null("TaskOptionButton") as OptionButton
	var task_summary := selection_host.get_node_or_null("TaskCurrentSummary") as Panel
	var task_summary_label := (
		task_summary.get_node_or_null("Label") as Label if task_summary != null else null
	)
	var task_summary_icon := (
		task_summary.get_node_or_null("Icon") as TextureRect if task_summary != null else null
	)
	var zone_stage := selection_host.get_node_or_null("ZoneStage")
	var roster := selection_host.get_node_or_null("RosterStrip") as GridContainer
	var weapon_stage := selection_host.get_node_or_null("WeaponStage") as Control
	var difficulty_stage := selection_host.get_node_or_null("DifficultyStage") as Control
	var niko_preview := selection_host.get_node_or_null("NikoDetail/Preview") as TextureRect
	var niko_cell := selection_host.get_node_or_null("RosterStrip/NikoCell") as Button
	check(task_option != null and task_summary != null and zone_stage == null
		and weapon_stage != null and difficulty_stage != null,
		"single-task summary and same-host later stages exist")
	check(niko_preview != null and niko_preview.texture != null, "NiKo preview loaded")
	check(niko_cell != null and niko_cell.is_visible_in_tree() and not niko_cell.disabled, "actual NiKo choice")
	check(roster != null and roster.columns == 8 and roster.get_child_count() == 32, "exact 8x4 character roster")
	if roster != null and roster.get_child_count() == 32:
		check(roster.get_child(0) == niko_cell and niko_cell.focus_mode != Control.FOCUS_NONE
			and niko_cell.has_meta(&"content_id"), "NiKo is the only live first roster cell")
		for index in range(1, 32):
			var placeholder := roster.get_child(index) as Button
			var slot_index := placeholder.get_node_or_null("SlotIndex") as Label if placeholder != null else null
			var glyph := placeholder.get_node_or_null("Glyph") as Label if placeholder != null else null
			var status := placeholder.get_node_or_null("Status") as Label if placeholder != null else null
			check(placeholder != null and placeholder.disabled and placeholder.focus_mode == Control.FOCUS_NONE
				and not placeholder.has_meta(&"content_id") and placeholder.text.is_empty()
				and placeholder.get_signal_connection_list(&"pressed").is_empty()
				and slot_index != null and slot_index.text == "%02d" % (index + 1)
				and glyph != null and glyph.text == "空位" and status != null and status.text == "待开放",
				"neutral unavailable character placeholder %d" % index)
	if (
		task_option == null
		or task_summary == null
		or roster == null
		or weapon_stage == null
		or difficulty_stage == null
		or niko_cell == null
	):
		finish()
		return
	var zone := content.definition(
		&"gogobro.core:zone/training_ground", &"zone"
	) as GogoZoneDefinition
	var task_item_ready := task_option != null and task_option.item_count == 1
	var task_item_id: StringName = (
		StringName(task_option.get_item_metadata(0)) if task_item_ready else &""
	)
	var task_item_icon: Texture2D = task_option.get_item_icon(0) if task_item_ready else null
	check(app.current_session == null, "no inventory/session before character choice")
	check(task_item_ready and not task_option.is_visible_in_tree() and task_option.disabled
		and task_option.focus_mode == Control.FOCUS_NONE
		and task_option.get_signal_connection_list(&"item_selected").is_empty()
		and task_option.selected == 0 and task_option.text == "任务 · 训练场"
		and task_option.tooltip_text == "训练场 · 20 波 · 从第 1 波开始",
		"single-task option stays hidden and noninteractive")
	check(task_summary.is_visible_in_tree() and task_summary.focus_mode == Control.FOCUS_NONE
		and task_summary.mouse_filter == Control.MOUSE_FILTER_IGNORE
		and task_summary_label != null and task_summary_label.text == "当前任务 · 训练场"
		and task_summary_icon != null and task_summary_icon.texture != null,
		"current-task summary visibly presents the selected training ground")
	check(task_item_id == &"gogobro.core:zone/training_ground"
		and task_option.get_item_text(0) == "任务 · 训练场"
		and task_option.get_item_tooltip(0) == "训练场 · 20 波 · 从第 1 波开始",
		"task option metadata is the actual sequential zone contract")
	check(zone != null and zone.icon_asset_id == &"zone_thumbnail" and task_item_icon != null,
		"training-ground task option resolves its declared real icon")
	check(content.all(&"zone").size() == task_option.item_count,
		"task option contains every real zone and no synthetic entries")
	check(selection_host.find_children("UnavailableZoneSlot*", "Button", true, false).is_empty(),
		"task option has no unavailable task placeholders")
	check(roster.visible and not weapon_stage.visible and not difficulty_stage.visible,
		"current-task summary keeps the character page visible")
	check(not task_option.has_focus(), "hidden single-task option never owns focus")
	check(app.current_session == null, "task summary creates no session")
	if not failures.is_empty():
		finish()
		return
	print("PACKAGE_TASK_ZONE_OK zone=training_ground waves=20 start=1 items=1 placeholders=0 summary=true interactive=false")
	if not await save_viewport("task-selector"):
		finish()
		return
	niko_cell.grab_focus()
	await settle()
	check(niko_cell.has_focus() and not niko_cell.disabled, "character roster remains actionable after task choice")
	print("PACKAGE_CHARACTER_GRID_OK columns=8 rows=4 live=1 placeholders=31")
	check(not weapon_stage.visible and not difficulty_stage.visible, "character-only hides later stages")
	if not failures.is_empty() or not await save_viewport("character-only"):
		finish()
		return
	niko_cell.pressed.emit()
	await settle()
	check(bool(niko_cell.get_meta(&"selected", false)), "NiKo choice updates shared setup")
	check(host.get_child(0) == selection_host and app.scene_flow.current_route() == &"character_select", "NiKo retains identical setup host")
	check(weapon_stage.visible and not difficulty_stage.visible, "NiKo reveals weapons only")
	check(app.current_session == null, "no inventory/session before difficulty")
	if not failures.is_empty():
		finish()
		return
	var weapon_columns := selection_host.get_node_or_null("WeaponStage/WeaponColumns")
	check(weapon_columns != null, "nested weapon columns exist")
	if not failures.is_empty():
		finish()
		return
	var weapons := weapon_columns.find_children("WeaponOption*", "Button", true, false)
	check(weapons.size() == 12, "twelve actual weapon buttons")
	var ak_button: Button
	var glock_button: Button
	var niko = content.definition(&"character.niko:character/niko", &"character")
	for button: Button in weapons:
		var definition = content.definition(button.get_meta(&"content_id", &""), &"weapon")
		check(button.is_visible_in_tree() and not button.disabled and definition != null
			and niko != null and niko.allows_weapon(definition), "visible enabled eligible weapon " + button.name)
		if button.get_meta(&"content_id", &"") == &"gogobro.preview:weapon/wood_stock_assault_rifle":
			ak_button = button
		if button.get_meta(&"content_id", &"") == GLOCK_ID:
			glock_button = button
	check(ak_button != null and glock_button != null, "actual AK and Glock content IDs found")
	if not failures.is_empty():
		finish()
		return
	var quality_badge := ak_button.get_node_or_null("QualityBadge") as Label
	var quality_rules = load("res://game/gameplay/weapons/weapon_quality_rules.gd")
	check(quality_badge != null and quality_rules != null, "AK badge and packaged quality rules exist")
	if not failures.is_empty():
		finish()
		return
	check(quality_badge.text == "I" and quality_badge.text == quality_rules.label(1)
		and quality_badge.get_theme_color(&"font_color") == quality_rules.color(1), "AK begins at packaged white quality I")
	check(app.current_session == null and app.selection_draft.get("weapon_id", &"") == &"", "AK display creates no inventory/session")
	if not failures.is_empty() or not await save_viewport("weapon-choice"):
		finish()
		return
	glock_button.pressed.emit()
	await settle()
	check(host.get_child(0) == selection_host and app.scene_flow.current_route() == &"character_select", "weapon choice stays on identical shared setup host")
	check(app.selection_draft.get("weapon_id", &"") == GLOCK_ID, "Glock remains actual starting selection")
	check(weapon_stage.visible and difficulty_stage.visible, "weapon choice reveals same-host difficulty")
	check(app.current_session == null, "session waits for difficulty choice; no inventory yet")
	var difficulty_button := selection_host.get_node_or_null("DifficultyStage/DifficultyStrip/DifficultyOption0") as Button
	check(difficulty_button != null, "same-host difficulty control exists")
	if not failures.is_empty():
		finish()
		return
	check(difficulty_button.is_visible_in_tree() and not difficulty_button.disabled, "same-host difficulty control actionable")
	if not failures.is_empty() or not await save_viewport("difficulty-ready"):
		finish()
		return
	difficulty_button.pressed.emit()
	await settle()
	check(app.current_session != null, "difficulty creates real session")
	check(app.scene_flow.current_route() == &"combat", "difficulty to real combat")
	if not failures.is_empty():
		finish()
		return
	var combat = host.get_child(0)
	var world = combat.world
	check(world != null and world.player_actor != null, "combat player created")
	if not failures.is_empty():
		finish()
		return
	var origin: Vector2 = world.player_actor.position
	Input.action_press("move_right")
	for frame in 30:
		await physics_frame
	Input.action_release("move_right")
	check(world.player_actor.position.x > origin.x + 80, "real movement input")
	for frame in 300:
		await physics_frame
	check(world.wave_runtime.elapsed > 5.0, "short real combat advanced")
	check(app.current_session.run_state.current_wave == 1, "short runtime stays in first wave")
	if not failures.is_empty():
		finish()
		return
	if not await save_viewport("combat-after5s"):
		finish()
		return
	# Measure the exported PCK's real player actor, not only the source-level rule.
	# The player is paused only after the combat viewport was captured. Temporarily
	# detach only this actor from world hitstop/clamping and collision so a hitstop
	# latched on the final rendered frame cannot randomize the synchronous timing.
	var real_player := world.player_actor as GogoPlayerActor
	var original_combat_world := real_player.combat_world
	var original_collision_mask := real_player.collision_mask
	var original_position := real_player.global_position
	var original_physics_processing := real_player.is_physics_processing()
	real_player.set_physics_process(false)
	real_player.combat_world = null
	real_player.collision_mask = 0
	for action in [&"move_left", &"move_right", &"move_up", &"move_down"]:
		Input.action_release(action)
	var movement_speed := float(real_player.player_state.final_stats.get(&"movement_speed", 0.0))
	var counter_strafe_brake := float(real_player.player_state.final_stats.get(&"counter_strafe_brake", 0.0))
	check(is_equal_approx(movement_speed, 300.0) and is_zero_approx(counter_strafe_brake),
		"actual NiKo baseline counter-strafe fixture")
	if not failures.is_empty():
		finish()
		return
	real_player.global_position = world.arena_rect.get_center()
	real_player.velocity = Vector2(movement_speed, 0.0)
	var release_frames := -1
	var release_first_velocity := -1.0
	for frame in 60:
		real_player._physics_process(1.0 / 60.0)
		if frame == 0:
			release_first_velocity = real_player.velocity.x
		if real_player.velocity.is_zero_approx():
			release_frames = frame + 1
			break
	check(release_first_velocity > 0.0 and release_first_velocity < movement_speed,
		"release braking is neither absent nor an instant stop")
	check(release_frames == 8, "300-speed release braking stops in exactly 8 frames")
	real_player.global_position = world.arena_rect.get_center()
	real_player.velocity = Vector2(movement_speed, 0.0)
	Input.action_press(&"move_left")
	var reverse_frames := -1
	var reverse_first_velocity := -1.0
	var reverse_crossed_zero := false
	for frame in 60:
		real_player._physics_process(1.0 / 60.0)
		if frame == 0:
			reverse_first_velocity = real_player.velocity.x
		if real_player.velocity.x < 0.0:
			reverse_crossed_zero = true
			break
		if real_player.velocity.is_zero_approx():
			reverse_frames = frame + 1
			break
	Input.action_release(&"move_left")
	real_player.velocity = Vector2.ZERO
	real_player.global_position = original_position
	real_player.collision_mask = original_collision_mask
	real_player.combat_world = original_combat_world
	real_player.set_physics_process(original_physics_processing)
	check(reverse_first_velocity > 0.0 and reverse_first_velocity < movement_speed,
		"reverse braking is neither absent nor an instant direction flip")
	check(not reverse_crossed_zero and reverse_frames == 5,
		"300-speed reverse braking reaches zero in exactly 5 frames without crossing")
	if not failures.is_empty():
		finish()
		return
	print("PACKAGE_COUNTER_STRAFE_OK speed=300 release_frames=8 release_ms=133.33 reverse_frames=5 reverse_ms=83.33")
	print("PACKAGE_ROUTE_OK menu>character_select[task>character>weapon>difficulty;same-host]>combat elapsed=%.2f input=.pressed.emit/action_input os_input=false" % world.wave_runtime.elapsed)
	# Deliberately forced shop transition is a route/resource check, not wave-clear evidence.
	check(app.current_session.transition(&"shop") == OK, "fixture shop transition")
	check(app.route(&"shop") == OK, "actual shop route")
	await settle()
	shop = host.get_child(0) as Control
	check(shop.has_node("OfferRow") and shop.has_node("ContinueButton"), "shop controls loaded")
	check(shop.get_node("OfferRow").get_child_count() == 4, "four actual shop offers")
	shop_service = shop.get("_shop")
	if not failures.is_empty() or not await purchase_first_weapon():
		finish()
		return
	shop.get_node("ContinueButton").pressed.emit()
	await settle()
	check(app.scene_flow.current_route() == &"combat" and app.current_session.run_state.current_wave == 2, "shop continue returns to combat")
	if not failures.is_empty():
		finish()
		return
	print("PACKAGE_SHOP_OK forced-route-only wave=2 input=.pressed.emit os_input=false")
	# Remove W2's real combat scene before replacing its session; no further combat ticks.
	check(app.route(&"main_menu") == OK, "close W2 route before controlled session")
	await settle()
	app.close_session(false)
	if not failures.is_empty() or not await controlled_quality_shop(host) or not await controlled_progression_chain(host) or not profile_wire():
		finish()
		return
	# Test-owned teardown: stop asynchronous audio voices before disposing the app.
	for voice: AudioStreamPlayer in app.audio_service.sfx_players:
		voice.stop()
		voice.stream = null
	app.audio_service.music_player.stop()
	app.close_session(false)
	app.queue_free()
	for frame in 8:
		await process_frame
	finish()

func prepare_viewports() -> bool:
	if DisplayServer.get_name() == "headless":
		return true
	# This runs only after the actual-user guard. Images never enter package/profile.
	viewport_directory = OS.get_environment("TEMP").path_join("package-viewports")
	check(not DirAccess.dir_exists_absolute(viewport_directory) and not FileAccess.file_exists(viewport_directory), "fresh viewport directory")
	if not failures.is_empty(): return false
	check(DirAccess.make_dir_absolute(viewport_directory) == OK, "create fresh TEMP viewport directory")
	return failures.is_empty()

func save_viewport(stage_name: String) -> bool:
	if DisplayServer.get_name() == "headless":
		return true
	check(not viewport_directory.is_empty() and viewport_names.size() < VIEWPORT_NAMES.size()
		and stage_name == VIEWPORT_NAMES[viewport_names.size()], "exact ordered viewport stage " + stage_name)
	if not failures.is_empty(): return false
	var path := viewport_directory.path_join(stage_name + ".png")
	check(not FileAccess.file_exists(path) and not DirAccess.dir_exists_absolute(path), "no viewport overwrite " + stage_name)
	if not failures.is_empty(): return false
	await RenderingServer.frame_post_draw
	var texture := root.get_texture()
	check(texture != null, "actual viewport texture " + stage_name)
	if not failures.is_empty(): return false
	var image := texture.get_image()
	check(image != null, "actual viewport image " + stage_name)
	if not failures.is_empty(): return false
	check(image.get_width() == 1280 and image.get_height() == 720, "native unmodified 1280x720 viewport " + stage_name)
	if not failures.is_empty(): return false
	check(image.save_png(path) == OK, "save actual viewport " + stage_name)
	if not failures.is_empty(): return false
	viewport_names.append(stage_name)
	print("PACKAGE_VIEWPORT " + JSON.stringify({"name": stage_name, "path": path,
		"sha256": FileAccess.get_sha256(path).to_upper(), "bytes": FileAccess.get_file_as_bytes(path).size(),
		"width": image.get_width(), "height": image.get_height()}))
	return failures.is_empty()

func isolation_guard() -> bool:
	var expected_app := OS.get_environment("GOGOBRO_TEST_EXPECTED_APPDATA").replace("\\", "/")
	var expected_local := OS.get_environment("GOGOBRO_TEST_EXPECTED_LOCALAPPDATA").replace("\\", "/")
	var expected_user := OS.get_environment("GOGOBRO_TEST_EXPECTED_USER_DATA_DIR").replace("\\", "/")
	var temp := OS.get_environment("TEMP").replace("\\", "/")
	var tmp := OS.get_environment("TMP").replace("\\", "/")
	var receipt := {"schema_version": 1, "phase": "before-manifest-app-profile", "pid": OS.get_process_id(),
		"temp": temp, "tmp": tmp, "appdata": OS.get_environment("APPDATA"),
		"localappdata": OS.get_environment("LOCALAPPDATA"), "user_data": OS.get_user_data_dir(),
		"expected_appdata": expected_app, "expected_localappdata": expected_local, "expected_user_data": expected_user}
	check(OS.get_cmdline_user_args().size() == 1, "one external package argument")
	for path in [expected_app, expected_local, expected_user, temp, tmp]:
		check(not path.is_empty() and path.is_absolute_path(), "nonempty absolute isolation path")
	check(same_path(receipt.appdata, expected_app) and same_path(receipt.localappdata, expected_local)
		and same_path(receipt.user_data, expected_user), "actual OS user and child environment match")
	check(same_path(temp, tmp) and same_path(expected_user, expected_app.path_join("GOGOBRO"))
		and same_path(expected_local.get_base_dir(), expected_app.get_base_dir())
		and same_path(temp.get_base_dir(), expected_app.get_base_dir()), "one fresh external seven-variable root")
	if not failures.is_empty():
		print("PACKAGE_ISOLATION_FAIL " + JSON.stringify(receipt))
		return false
	var package_dir := OS.get_cmdline_user_args()[0].replace("\\", "/").simplify_path().to_lower()
	check(not expected_app.replace("\\", "/").simplify_path().to_lower().begins_with(package_dir + "/"), "synthetic user is outside package")
	if not failures.is_empty():
		print("PACKAGE_ISOLATION_FAIL " + JSON.stringify(receipt))
		return false
	# Only now is user:// safe to inspect; no ProfileService preload is needed.
	receipt["profile_before"] = profile_presence()
	check(receipt.profile_before == {"profile": false, "temporary": false, "backup": false}, "three profile files absent before App boot")
	print(("PACKAGE_ISOLATION_OK " if failures.is_empty() else "PACKAGE_ISOLATION_FAIL ") + JSON.stringify(receipt))
	return failures.is_empty()

func same_path(left: String, right: String) -> bool:
	return left.replace("\\", "/").simplify_path().nocasecmp_to(right.replace("\\", "/").simplify_path()) == 0

func profile_presence() -> Dictionary:
	return {"profile": FileAccess.file_exists("user://profile.json"),
		"temporary": FileAccess.file_exists("user://profile.tmp"), "backup": FileAccess.file_exists("user://profile.backup")}

func purchase_first_weapon() -> bool:
	var player = app.current_session.run_state.player()
	var starting: Array = player.weapon_inventory.records()
	check(starting == records([[1, 1]]) and player.next_weapon_instance_id == 2, "actual starting Glock #1/I next2")
	var original_materials: int = player.materials
	player.materials = 500 # Explicit controlled affordability fixture, not earned economy.
	print("PACKAGE_B_FIXTURE " + JSON.stringify({"phase": "purchase", "starting_inventory": starting,
		"materials_before": original_materials, "materials_after": 500, "controlled": true}))
	var index := -1
	for slot in shop_service.offers.size():
		if shop_service.offers[slot] != null and shop_service.offers[slot].kind == &"weapon":
			index = slot
			break
	check(index >= 0, "first W1 real weapon quote exists without seed search")
	if not failures.is_empty(): return false
	var definition = shop_service.offers[index]
	var price: int = shop_service.item_pool.price_for(definition, app.current_session.run_state.current_wave, app.current_session.run_state.reroll_count)
	check(price >= 0 and price <= 500, "real weapon quote is affordable")
	# Lock the quote through its actual UI so purchase must really remove that lock.
	if not failures.is_empty() or not await click(shop.get_node_or_null("OfferRow/OfferSlot%d/Lock" % index) as Button, "lock_purchase_quote"): return false
	check(app.current_session.run_state.locked_shop_offer_ids.has(definition.content_id), "purchase quote actually locked")
	var before := model_snapshot()
	var quote_before := quote_snapshot()
	check((shop.get_node("OfferRow/OfferSlot%d/Card/PriceOrState" % index) as Label).text == "%d 金币" % price, "visible actual purchase price")
	if not failures.is_empty() or not await click(shop.get_node_or_null("OfferRow/OfferSlot%d/Card" % index) as Button, "buy_first_weapon_quote"): return false
	var expected := before.duplicate(true)
	expected.state.players[0].weapons.append({"instance_id": 2, "content_id": String(definition.content_id), "quality": 1})
	expected.state.players[0].next_weapon_instance_id = 3
	expected.state.players[0].materials = 500 - price
	expected.state.shop_offer_ids[index] = ""
	expected.state.locked_shop_offer_ids.erase(String(definition.content_id))
	var after := model_snapshot()
	check(after == expected, "purchase #2/I next3 actual debit; only quote/cache/lock change, RNG stable")
	var quote_after := quote_snapshot()
	for slot in 4:
		if slot == index:
			check(shop_service.offers[slot] == null and shop.get_node("OfferRow/OfferSlot%d" % slot).get_child_count() == 0, "purchased slot is truly childless")
		else:
			check(quote_after[slot] == quote_before[slot], "unpurchased quote slot stable %d" % slot)
	print("PACKAGE_B_PURCHASE_STATE " + JSON.stringify({"before": before, "after": after, "quotes_before": quote_before, "quotes_after": quote_after}))
	if failures.is_empty():
		print("PACKAGE_B_PURCHASE_OK " + JSON.stringify({"content_id": String(definition.content_id), "price": price, "slot": index, "input": "Viewport.push_input", "os_input": false}))
	return failures.is_empty()

func controlled_quality_shop(host: Node) -> bool:
	app.selection_draft = {"seed": 83411, "character_id": &"character.niko:character/niko", "weapon_id": GLOCK_ID,
		"difficulty_id": &"gogobro.core:difficulty/standard", "zone_id": &"gogobro.core:zone/training_ground"}
	check(app.create_session_from_draft() == OK, "independent real AppKernel seed83411 session")
	if not failures.is_empty(): return false
	var session = app.current_session
	var player = session.run_state.player()
	var inventory_type = load("res://game/session/weapon_inventory.gd")
	var parsed: Dictionary = inventory_type.parse_records(records([[11, 1], [22, 2], [33, 3], [44, 4], [55, 1], [66, 4]]), 70, app.content_snapshot)
	check(parsed.error == OK, "strict six-copy controlled inventory parse")
	if not failures.is_empty(): return false
	player.weapon_inventory = parsed.inventory
	player.materials = 500
	var definition = app.content_snapshot.definition(GLOCK_ID, &"weapon")
	check(definition != null, "registered real Glock definition")
	if not failures.is_empty(): return false
	check(definition.damage == 4.0 and definition.price == 15 and player.item_ids.is_empty() and player.upgrade_ids.is_empty()
		and float(player.final_stats.get(&"damage_multiplier", 1.0)) == 1.0
		and float(player.final_stats.get(&"ranged_damage", 0.0)) == 0.0, "approved unmodified NiKo/Glock baseline")
	var runtime_service = load("res://game/gameplay/weapons/weapon_runtime_service.gd").new()
	var damages: Array = []
	for quality in range(1, 5):
		var runtime = runtime_service.build_instance(definition, player, quality)
		check(runtime != null, "actual weapon runtime quality %d" % quality)
		if not failures.is_empty(): return false
		damages.append(runtime.damage)
	check(damages == [4.0, 6.0, 8.0, 10.0], "independent literal I/II/III/IV damage oracle")
	check(session.transition(&"shop") == OK and app.route(&"shop") == OK, "controlled shop phase and actual route")
	await settle()
	if not failures.is_empty(): return false
	shop = host.get_child(0) as Control
	shop_service = shop.get("_shop")
	check(shop.get_script().resource_path == "res://game/ui/shop_screen.gd" and shop_service.offers.size() == 4, "actual ShopScreen and four new original quotes")
	for quote in shop_service.offers:
		check(quote != null, "controlled quote baseline has no purchased holes")
	if not failures.is_empty(): return false
	var original_quotes := quote_snapshot()
	var before_lock := model_snapshot()
	if not await click(shop.get_node_or_null("OfferRow/OfferSlot0/Lock") as Button, "lock_controlled_first_quote"): return false
	var expected_lock := before_lock.duplicate(true)
	expected_lock.state.locked_shop_offer_ids = [String(shop_service.offers[0].content_id)]
	check(model_snapshot() == expected_lock, "controlled lock changes only first content-ID lock")
	var quote_baseline := quote_snapshot()
	print("PACKAGE_B_QUALITY_FIXTURE " + JSON.stringify({"controlled": true, "seed": 83411, "original_quotes": original_quotes, "locked_quotes": quote_baseline, "state": model_snapshot(), "damage": damages}))
	# Publications are measured only after the real initial lock has completed.
	session.state_changed.connect(func() -> void: publication_counts.state += 1)
	shop_service.offers_changed.connect(func(_offers) -> void: publication_counts.offers += 1)
	if not failures.is_empty() or not await select_weapon(55): return false
	check(player.weapon_inventory.combination_partner(55) == 11, "#55 selects first partner #11")
	var before_combine := model_snapshot()
	if not failures.is_empty() or not await click(weapon_action_button("CombineButton") as Button, "combine_55"): return false
	var combined := before_combine.duplicate(true)
	combined.state.players[0].weapons = records([[22, 2], [33, 3], [44, 4], [55, 2], [66, 4]], true)
	combined.signals.state = 1
	check(model_snapshot() == combined and quote_snapshot() == quote_baseline, "consume only #11 preserve #55/II order next70 materials500 four quotes locks RNG; state1 offers0")
	check_weapon_focus(55)
	print("PACKAGE_B_COMBINE_STATE " + JSON.stringify({"before": before_combine, "after": model_snapshot()}))
	if not await save_viewport("shop-after-merge"): return false
	if not failures.is_empty() or not await refused_combine(33, "出售 11 金币 · 无同品质合成伙伴") or not await refused_combine(44, "出售 13 金币 · 已达最高品质，无法合成"): return false
	if not await select_weapon(55): return false
	check((weapon_action_label("SaleValue") as Label).text == "出售可得 8 金币" and (weapon_action_label("CombineDetail") as Label).text == "合成伙伴 #22 · 下一品质 III", "visible actual II sale credit8 and same-quality partner")
	var before_sale := model_snapshot()
	if not failures.is_empty() or not await click(weapon_action_button("SellButton") as Button, "sell_55_II"): return false
	var sold := before_sale.duplicate(true)
	sold.state.players[0].weapons = records([[22, 2], [33, 3], [44, 4], [66, 4]], true)
	sold.state.players[0].materials = 508
	sold.signals.state = 2
	check(model_snapshot() == sold and quote_snapshot() == quote_baseline, "sale removes only55 credits8 to508 preserves next70 quotes locks RNG; state2 offers0")
	check_weapon_focus(66)
	check(publication_counts == {"state": 2, "offers": 0}, "exact two state and zero quote publications after lock")
	print("PACKAGE_B_SALE_STATE " + JSON.stringify({"before": before_sale, "after": model_snapshot(), "focus": focus_snapshot()}))
	if failures.is_empty():
		print("PACKAGE_B_QUALITY_OK " + JSON.stringify({"damage": damages, "signals": publication_counts, "focus_id": 66, "focus_role": "weapon", "input": "Viewport.push_input", "refusals": "service_probe_not_user_click", "os_input": false}))
	return failures.is_empty()

func controlled_progression_chain(host: Node) -> bool:
	# This is a deterministic route/state contract. It deliberately completes each
	# live CombatWorld through its owned completion hook; it is not a survival,
	# movement, long-session balance, or restart/resume claim.
	check(app.route(&"main_menu") == OK, "leave controlled quality shop before progression fixture")
	await settle()
	app.close_session(false)
	app.selection_draft = {"seed": 6202122, "character_id": &"character.niko:character/niko", "weapon_id": GLOCK_ID,
		"difficulty_id": &"gogobro.core:difficulty/standard", "zone_id": &"gogobro.core:zone/training_ground"}
	check(app.create_session_from_draft() == OK and app.route(&"combat") == OK, "fresh real twenty-wave session")
	await settle()
	if not failures.is_empty(): return false
	var session = app.current_session
	var traversed: Array[int] = []
	for expected_wave in range(1, 21):
		check(app.scene_flow.current_route() == &"combat" and session.run_state.current_wave == expected_wave,
			"real combat route wave %d" % expected_wave)
		var combat = host.get_child(0)
		var world = combat.get("world")
		check(world != null and world.running and world.wave_runtime.wave.wave_number == expected_wave,
			"live authored world wave %d" % expected_wave)
		if not failures.is_empty(): return false
		traversed.append(expected_wave)
		world.call("_finish_wave")
		await settle()
		while session.run_state.pending_upgrade_count > 0:
			check(app.scene_flow.current_route() == &"upgrade", "upgrade route wave %d" % expected_wave)
			var choice := host.get_child(0).get_node_or_null("UpgradeChoiceRow/UpgradeChoice0") as Button
			check(choice != null and choice.is_visible_in_tree() and not choice.disabled,
				"actual upgrade choice wave %d" % expected_wave)
			if not failures.is_empty(): return false
			choice.pressed.emit()
			await settle()
		check(app.scene_flow.current_route() == &"shop" and session.run_state.current_wave == expected_wave
			and not session.run_state.ended and not session.run_state.won,
			"shop reached without early victory wave %d" % expected_wave)
		if not failures.is_empty(): return false
		shop = host.get_child(0) as Control
		if expected_wave < 20:
			var continue_button := shop.get_node_or_null("ContinueButton") as Button
			check(continue_button != null and not continue_button.disabled, "continue control wave %d" % expected_wave)
			if not failures.is_empty(): return false
			continue_button.pressed.emit()
			await settle()
	check(traversed.size() == 20 and traversed[0] == 1 and traversed[-1] == 20
		and session.is_final_shop(), "continuous authored W1-W20 final shop")
	if failures.is_empty():
		print("PACKAGE_PROGRESS_20_OK " + JSON.stringify({"controlled": true, "full_survival_pilot": false,
			"first": traversed[0], "last": traversed[-1], "count": traversed.size(), "final_shop": true}))
	if not failures.is_empty(): return false
	shop = host.get_child(0) as Control
	var endless_button := shop.get_node_or_null("EndlessButton") as Button
	check(endless_button != null and endless_button.is_visible_in_tree() and not endless_button.disabled,
		"actual final-shop EndlessButton")
	if not failures.is_empty(): return false
	endless_button.pressed.emit()
	check(app.scene_flow.current_route() == &"combat" and session.run_state.current_wave == 21
		and session.run_state.endless and not session.run_state.ended,
		"actual EndlessButton enters wave 21")
	var checkpoint_21 = fresh_checkpoint_state()
	check(checkpoint_21 != null and checkpoint_21.to_dictionary() == session.run_state.to_dictionary(),
		"fresh strict checkpoint readback wave 21")
	if not failures.is_empty(): return false
	await settle()
	var world_21 = host.get_child(0).get("world")
	check(world_21 != null and world_21.running and world_21.wave_runtime.wave.wave_number == 21,
		"live endless world 21")
	if not failures.is_empty(): return false
	world_21.call("_finish_wave")
	await settle()
	while session.run_state.pending_upgrade_count > 0:
		check(app.scene_flow.current_route() == &"upgrade", "endless 21 upgrade route")
		var choice_21 := host.get_child(0).get_node_or_null("UpgradeChoiceRow/UpgradeChoice0") as Button
		check(choice_21 != null and not choice_21.disabled, "actual endless 21 upgrade choice")
		if not failures.is_empty(): return false
		choice_21.pressed.emit()
		await settle()
	check(app.scene_flow.current_route() == &"shop", "endless 21 shop route")
	if not failures.is_empty(): return false
	shop = host.get_child(0) as Control
	check(shop.get_node_or_null("EndlessButton") == null and shop.get_node_or_null("FinishRunButton") == null,
		"endless shop has no terminal fork")
	var continue_21 := shop.get_node_or_null("ContinueButton") as Button
	check(continue_21 != null and not continue_21.disabled, "actual endless continue control")
	if not failures.is_empty(): return false
	continue_21.pressed.emit()
	var checkpoint_22 = fresh_checkpoint_state()
	check(checkpoint_22 != null and checkpoint_22.to_dictionary() == session.run_state.to_dictionary(),
		"fresh strict checkpoint readback wave 22")
	if not failures.is_empty(): return false
	await settle()
	var world_22 = host.get_child(0).get("world")
	check(app.scene_flow.current_route() == &"combat" and session.run_state.current_wave == 22
		and session.run_state.endless and world_22 != null and world_22.running
		and world_22.wave_runtime.wave.wave_number == 22, "actual endless wave 22 world")
	if failures.is_empty():
		print("PACKAGE_ENDLESS_21_22_OK " + JSON.stringify({"controlled": true, "full_survival_pilot": false,
			"endless_button": 21, "continue_button": 22, "live_world": 22}))
		print("PACKAGE_PROFILE_READBACK_OK " + JSON.stringify({"resume_claim": false, "waves": [21, 22],
			"profile_sha256": FileAccess.get_sha256("user://profile.json").to_upper()}))
	return failures.is_empty()

func fresh_checkpoint_state():
	var profile_type = load("res://game/platform/profile_service.gd")
	var reader = profile_type.new()
	check(reader.load_profile(app.content_snapshot) == OK, "fresh profile reader")
	check(reader.profile_data.has("run_checkpoint"), "fresh reader checkpoint present")
	if not failures.is_empty(): return null
	var run_codec = load("res://game/session/run_state_codec.gd")
	var parsed: Dictionary = run_codec.parse(reader.profile_data.run_checkpoint, app.content_snapshot)
	check(parsed.error == OK, "fresh reader strict checkpoint parse")
	return parsed.state if failures.is_empty() else null

func refused_combine(instance_id: int, flavor: String) -> bool:
	if not await select_weapon(instance_id): return false
	var combine := weapon_action_button("CombineButton") as Button
	check(combine != null and combine.disabled, "visible disabled CombineButton #%d" % instance_id)
	check((weapon_action_label("CombineDetail") as Label).text == ("已达最高品质 IV，无法合成" if instance_id == 44 else "无同品质合成伙伴"), "actual refusal reason #%d" % instance_id)
	var before := {"model": model_snapshot(), "quotes": quote_snapshot(), "focus": focus_snapshot()}
	# Explicit service probe: impossible UI actions are not claimed as user clicks.
	var error: int = shop_service.combine_weapon(app.current_session, instance_id)
	await settle()
	var after := {"model": model_snapshot(), "quotes": quote_snapshot(), "focus": focus_snapshot()}
	check(error == ERR_UNAVAILABLE and shop_service.last_failure_reason == "no_matching_weapon" and before == after, "refused service probe preserves canonical state next money quotes locks RNG focus #%d" % instance_id)
	print("PACKAGE_B_REFUSAL " + JSON.stringify({"input": "service_probe_not_user_click", "id": instance_id, "error": error, "before": before, "after": after, "flavor": flavor}))
	(weapon_action_button("CancelButton") as Button).pressed.emit()
	await settle()
	return failures.is_empty()

func records(rows: Array, serialized: bool = false) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for row in rows:
		result.append({"instance_id": row[0], "content_id": String(GLOCK_ID) if serialized else GLOCK_ID, "quality": row[1]})
	return result

func model_snapshot() -> Dictionary:
	return {"state": app.current_session.run_state.to_dictionary().duplicate(true),
		"rng_state_exact": str(app.current_session.rng.state), "signals": publication_counts.duplicate(true)}

func quote_snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index in shop_service.offers.size():
		var definition = shop_service.offers[index]
		var slot := shop.get_node("OfferRow/OfferSlot%d" % index) as Control
		var rect := slot.get_global_rect()
		var value := {"index": index, "content_id": String(definition.content_id) if definition != null else "",
			"children": slot.get_child_count(), "rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y]}
		if definition != null:
			value["price"] = (slot.get_node("Card/PriceOrState") as Label).text
			value["lock"] = (slot.get_node("Lock") as Button).text
			value["quality"] = slot.get_node("Card").get_meta(&"quality", 0)
		result.append(value)
	return result

func weapon_button(instance_id: int) -> Button:
	for child in shop.get_node("LoadoutBar/Weapons").get_children():
		if child is Button and child.get_meta(&"inventory_instance_id", 0) == instance_id:
			return child as Button
	return null

func weapon_action_button(node_name: String) -> Button:
	return shop.get_node_or_null("WeaponActionMenu/Panel/%s" % node_name) as Button

func weapon_action_label(node_name: String) -> Label:
	return shop.get_node_or_null("WeaponActionMenu/Panel/%s" % node_name) as Label

func select_weapon(instance_id: int) -> bool:
	var before := model_snapshot()
	if not await click(weapon_button(instance_id), "select_%d" % instance_id): return false
	check(model_snapshot() == before, "selection does not mutate state RNG publications")
	check(weapon_action_button("CancelButton") != null and weapon_action_label("InstanceId") != null and (weapon_action_label("InstanceId") as Label).text == "实例 ID #%d" % instance_id, "selection opens exact local weapon action menu #%d" % instance_id)
	return failures.is_empty()

func check_weapon_focus(instance_id: int) -> void:
	var focused := root.gui_get_focus_owner()
	check(focused != null and focused == weapon_button(instance_id)
		and typeof(focused.get_meta(&"focus_role", &"")) == TYPE_STRING_NAME
		and focused.get_meta(&"focus_role", &"") == &"weapon"
		and shop.get("_selected_weapon_instance_id") == instance_id, "exact selected weapon focus #%d role StringName weapon" % instance_id)

func focus_snapshot() -> Dictionary:
	var focused := root.gui_get_focus_owner()
	return {} if focused == null else {"object_id": str(focused.get_instance_id()),
		"role": String(focused.get_meta(&"focus_role", &"")), "role_type": typeof(focused.get_meta(&"focus_role", &"")), "inventory_id": focused.get_meta(&"inventory_instance_id", 0),
		"selected": shop.get("_selected_weapon_instance_id")}

func click(button: Button, action: String) -> bool:
	check(button != null and button.is_visible_in_tree() and not button.disabled, "actionable real control " + action)
	if not failures.is_empty(): return false
	var point := button.get_global_rect().get_center()
	check(root.get_visible_rect().has_point(point), "control is inside actual Viewport " + action)
	if not failures.is_empty(): return false
	var observation := {"action": action, "input": "Viewport.push_input", "os_input": false,
		"target": String(shop.get_path_to(button)), "position": [point.x, point.y], "events": [], "pressed_signals": 0}
	button.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			observation.events.append({"pressed": event.pressed, "button_index": event.button_index}))
	button.pressed.connect(func() -> void: observation.pressed_signals += 1)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	motion.relative = Vector2(1, 0)
	root.push_input(motion, true)
	await process_frame
	var hovered := root.gui_get_hovered_control()
	observation["hovered"] = String(shop.get_path_to(hovered)) if hovered != null and shop.is_ancestor_of(hovered) else ""
	var press := InputEventMouseButton.new()
	press.position = point
	press.global_position = point
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	root.push_input(press, true)
	await process_frame
	var release := press.duplicate() as InputEventMouseButton
	release.pressed = false
	root.push_input(release, true)
	await settle()
	check(observation.events == [{"pressed": true, "button_index": MOUSE_BUTTON_LEFT}, {"pressed": false, "button_index": MOUSE_BUTTON_LEFT}]
		and observation.pressed_signals == 1, "actual press/release and one pressed signal " + action)
	print("PACKAGE_B_INPUT " + JSON.stringify(observation))
	return failures.is_empty()

func profile_wire() -> bool:
	# Continue already saved a normal synthetic W2 checkpoint. Preserve it, do not
	# claim the files are still absent or delete it before the real wire operation.
	var pre_presence := profile_presence()
	var pre_sha := FileAccess.get_sha256("user://profile.json").to_upper() if pre_presence.profile else ""
	print("PACKAGE_PROFILE_PRE_WIRE " + JSON.stringify({"sha256": pre_sha, "presence": pre_presence,
		"text": FileAccess.get_file_as_string("user://profile.json") if pre_presence.profile else ""}))
	var run_codec = load("res://game/session/run_state_codec.gd")
	var profile_type = load("res://game/platform/profile_service.gd")
	var candidate: Dictionary = run_codec.parse(app.current_session.run_state.to_dictionary(), app.content_snapshot)
	check(candidate.error == OK, "detached checkpoint")
	if not failures.is_empty(): return false
	var live_before := model_snapshot()
	candidate.state.run_seed = 9007199254740993
	var writer = profile_type.new()
	var write_load_error: int = writer.load_profile(app.content_snapshot)
	check(write_load_error == OK, "guarded synthetic profile load")
	if not failures.is_empty(): return false
	var save_error: int = writer.save_checkpoint(candidate.state)
	check(save_error == OK, "real wire save")
	if not failures.is_empty(): return false
	var reader = profile_type.new()
	var read_error: int = reader.load_profile(app.content_snapshot)
	check(read_error == OK, "real wire read")
	if not failures.is_empty(): return false
	check(reader.profile_data.has("run_checkpoint"), "checkpoint present")
	if not failures.is_empty(): return false
	var raw: Dictionary = reader.profile_data.run_checkpoint
	check(reader.profile_data.schema_version == 1 and raw.schema_version == 3, "two schema layers")
	check(typeof(raw.run_seed) == TYPE_INT and raw.run_seed == 9007199254740993, "exact int64 wire")
	check(typeof(raw.rng_state) == TYPE_INT and raw.rng_state == candidate.state.rng_state,
		"exact schema3 RNG wire")
	var decoded: Dictionary = run_codec.parse(raw, app.content_snapshot)
	check(decoded.error == OK, "readback strict parse")
	if not failures.is_empty(): return false
	check(decoded.state.to_dictionary() == candidate.state.to_dictionary(), "exact checkpoint roundtrip")
	check(model_snapshot() == live_before, "detached wire save does not mutate live shop")
	if failures.is_empty():
		print("PACKAGE_PROFILE_WIRE_OK " + JSON.stringify({"pre_wire_sha256": pre_sha,
			"profile_sha256": FileAccess.get_sha256("user://profile.json").to_upper(), "profile_presence": profile_presence(),
			"run_seed_exact": str(raw.run_seed), "rng_state_exact": str(raw.rng_state),
			"profile_schema": reader.profile_data.schema_version, "checkpoint_schema": raw.schema_version,
			"text": FileAccess.get_file_as_string("user://profile.json")}))
	return failures.is_empty()

func check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
		push_error("PACKAGE_SMOKE_FAILED " + label)

func settle() -> void:
	await process_frame
	await process_frame

func finish() -> void:
	if failures.is_empty() and DisplayServer.get_name() != "headless":
		check(viewport_names.size() == VIEWPORT_NAMES.size(), "all native viewport images saved")
	print("PACKAGE_SMOKE_RESULT failures=%d" % failures.size())
	quit(0 if failures.is_empty() else 1)
