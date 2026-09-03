extends GdUnitTestSuite

const RANGED := ValidationContentFactory.RANGED_ID
const MELEE := ValidationContentFactory.MELEE_ID
const SHOP_SCREEN := preload("res://game/ui/shop_screen.gd")
const INVENTORY := preload("res://game/session/weapon_inventory.gd")
const QUALITY_RULES := preload("res://game/gameplay/weapons/weapon_quality_rules.gd")
var _publication_counts := {"state": 0, "offers": 0}


# Catches aggregate-only ownership: even the real start must persist copy identity.
func test_actual_start_serializes_first_copy_at_quality_one() -> void:
	var session := _session(4)
	var serialized: Dictionary = session.run_state.to_dictionary().players[0]
	assert_array(serialized.get("weapons", [])).is_equal([
		{"instance_id": 1, "content_id": String(RANGED), "quality": 1},
	])
	assert_int(int(serialized.get("next_weapon_instance_id", 0))).is_equal(2)


# Catches spending/clearing/publication on an illegal phase without API setup.
func test_buy_outside_shop_is_transactionally_rejected() -> void:
	var session := _session()
	var shop := _quoted_shop(session)
	session.run_state.phase = &"combat"
	_observe(session, shop)
	var before := canonical_snapshot(session, shop)
	assert_int(shop.buy(session, 0)).is_not_equal(OK)
	assert_dict(canonical_snapshot(session, shop)).is_equal(before)


func test_purchase_allocates_next_quality_one_and_clears_only_its_quote() -> void:
	var session := _session(4)
	var player := session.run_state.player()
	_set_inventory(session, [RANGED], [3], [9], 20)
	var shop := _quoted_shop(session)
	_observe(session, shop)
	var before := canonical_snapshot(session, shop)
	assert_int(shop.buy(session, 0)).is_equal(OK)
	assert_array(player.weapon_inventory.records()).is_equal([
		{"instance_id": 9, "content_id": RANGED, "quality": 3},
		{"instance_id": 20, "content_id": RANGED, "quality": 1}])
	assert_int(player.next_weapon_instance_id).is_equal(21)
	assert_int(player.materials).is_equal(985)
	assert_array(session.run_state.shop_offer_ids).is_equal([&"", &"", MELEE, &""])
	assert_array(shop.offers.map(func(value): return value.content_id if value != null else &"")).is_equal([&"", &"", MELEE, &""])
	assert_int(session.run_state.shop_offer_initialization_id).is_equal(7)
	assert_int(session.rng.state).is_equal(before.rng)
	assert_dict(_publication_counts).is_equal({"state": 1, "offers": 1})
	assert_int((session.content_snapshot.definition(RANGED, &"weapon") as GogoWeaponDefinition).tier).is_equal(4)


func test_combine_preserves_selected_copy_first_partner_and_order_for_three_four_interleaved() -> void:
	for layout in [[RANGED, RANGED, RANGED], [RANGED, RANGED, RANGED, RANGED], [RANGED, MELEE, RANGED, MELEE, RANGED]]:
		var session := _session()
		var qualities := []
		var ids := []
		for index in layout.size():
			qualities.append(1)
			ids.append(index + 11)
		_set_inventory(session, layout, qualities, ids, 30)
		var player := session.run_state.player()
		var shop := _quoted_shop(session)
		_observe(session, shop)
		var selected: int = ids.back()
		var expected := player.weapon_inventory.records()
		expected[expected.size() - 1].quality = 2
		expected.remove_at(0)
		var before := canonical_snapshot(session, shop)
		assert_int(shop.combine_weapon(session, selected)).is_equal(OK)
		assert_array(player.weapon_inventory.records()).is_equal(expected)
		assert_dict(player.weapon_inventory.record(11)).is_empty()
		assert_int(player.next_weapon_instance_id).is_equal(30)
		assert_int(player.materials).is_equal(1000)
		assert_int(session.rng.state).is_equal(before.rng)
		assert_array(canonical_snapshot(session, shop).offers).is_equal(before.offers)
		assert_array(session.run_state.locked_shop_offer_ids).is_equal([RANGED])
		assert_dict(_publication_counts).is_equal({"state": 1, "offers": 0})


func test_sale_uses_quality_price_and_identity_not_layout_index() -> void:
	var session := _session()
	_set_inventory(session, [RANGED, MELEE, RANGED], [1, 1, 2], [11, 22, 33], 50)
	var shop := _quoted_shop(session)
	_observe(session, shop)
	assert_int(shop.sell_weapon(session, 33)).is_equal(OK)
	assert_int(session.run_state.player().materials).is_equal(1008)
	assert_array(session.run_state.player().weapon_inventory.records()).is_equal([
		{"instance_id": 11, "content_id": RANGED, "quality": 1}, {"instance_id": 22, "content_id": MELEE, "quality": 1}])
	assert_int(session.run_state.player().next_weapon_instance_id).is_equal(50)
	assert_dict(_publication_counts).is_equal({"state": 1, "offers": 0})


# Catches removal/credit overflow at admitted int64 balances; price is hand-checked 5.
func test_sale_credit_capacity_rejects_overflow_and_accepts_exact_int64_limit() -> void:
	for balance in [9223372036854775803, 9223372036854775807]:
		var session := _session()
		_set_inventory(session, [RANGED, MELEE], [1, 1], [11, 22], 50)
		session.run_state.player().materials = balance
		var shop := _quoted_shop(session)
		_observe(session, shop)
		var before := canonical_snapshot(session, shop)
		assert_int(shop.sell_weapon(session, 11)).is_not_equal(OK)
		var after := canonical_snapshot(session, shop)
		if after != before:
			print("SALE_OVERFLOW_BEFORE=", var_to_str(before))
			print("SALE_OVERFLOW_AFTER=", var_to_str(after))
		assert_dict(after).is_equal(before)
	var session := _session()
	_set_inventory(session, [RANGED, MELEE], [1, 1], [11, 22], 50)
	session.run_state.player().materials = 9223372036854775802
	var shop := _quoted_shop(session)
	_observe(session, shop)
	var expected := canonical_snapshot(session, shop)
	expected.state.players[0].materials = 9223372036854775807
	expected.state.players[0].weapons.remove_at(0)
	expected.publications.state = 1
	assert_int(shop.sell_weapon(session, 11)).is_equal(OK)
	assert_dict(canonical_snapshot(session, shop)).is_equal(expected)


# Catches a quality-priced sale refusal replacing or losing its local action menu.
func test_ui_sale_credit_overflow_keeps_existing_controls_focus_and_canonical_state() -> void:
	var session := _session()
	_set_inventory(session, [RANGED, MELEE], [1, 1], [11, 22], 50)
	session.run_state.player().materials = 9223372036854775807
	var app := auto_free(AppKernel.new()) as AppKernel
	app.add_to_group(&"gogobro_app")
	app.content_snapshot = session.content_snapshot
	app.current_session = session
	add_child(app)
	var screen := auto_free(SHOP_SCREEN.new()) as GogoScreenBase
	add_child(screen)
	await get_tree().process_frame
	(screen.get_node("LoadoutBar/Weapons/WeaponSlot0") as Button).pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	var menu := screen.get_node_or_null("WeaponActionMenu") as Control
	assert_object(menu).is_not_null()
	if menu == null:
		return
	var sell := menu.get_node_or_null("Panel/SellButton") as Button
	assert_object(sell).is_not_null()
	if sell == null:
		return
	sell.grab_focus()
	var controls := screen.find_children("*", "Control", true, false).map(func(value): return value.get_instance_id())
	var selected_id: int = screen.get("_selected_weapon_instance_id")
	var shop := screen.get("_shop") as ShopRuntimeService
	_observe(session, shop)
	var before := canonical_snapshot(session, shop)
	assert_str((screen.get_node("OfferFlavor") as Label).text).contains("5 金币")
	sell.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	var after := canonical_snapshot(session, shop)
	if after != before:
		print("UI_SALE_OVERFLOW_BEFORE=", var_to_str(before))
		print("UI_SALE_OVERFLOW_AFTER=", var_to_str(after))
	assert_dict(after).is_equal(before)
	assert_array(screen.find_children("*", "Control", true, false).map(func(value): return value.get_instance_id())).is_equal(controls)
	assert_object(get_viewport().gui_get_focus_owner()).is_same(sell)
	assert_int(int(screen.get("_selected_weapon_instance_id"))).is_equal(selected_id)
	assert_str((screen.get_node("Status") as Label).text).is_equal("金币已达上限，无法出售")


func test_failure_matrix_preserves_complete_canonical_state_and_observers() -> void:
	for defect in ["null_session", "null_state", "no_player", "null_player", "no_content", "unknown_content", "combat", "ended", "zero", "negative", "stale", "mixed", "four"]:
		var session := _session()
		_set_inventory(session, [RANGED, RANGED], [1, 1], [11, 22], 30)
		var shop := _quoted_shop(session)
		var id := 22
		match defect:
			"null_state": session.run_state = null
			"no_player": session.run_state.players.clear()
			"null_player": session.run_state.players[0] = null
			"no_content": session.content_snapshot = null
			"unknown_content": session.content_snapshot = ContentSnapshot.new()
			"combat": session.run_state.phase = &"combat"
			"ended": session.run_state.ended = true
			"zero": id = 0
			"negative": id = -1
			"stale": id = 999
			"mixed": _set_inventory(session, [RANGED, RANGED], [1, 2], [11, 22], 30)
			"four": _set_inventory(session, [RANGED, RANGED], [4, 4], [11, 22], 30)
		_observe(session, shop)
		var before := canonical_snapshot(session, shop)
		var target := null if defect == "null_session" else session
		assert_int(shop.combine_weapon(target, id)).is_not_equal(OK)
		assert_dict(canonical_snapshot(session, shop)).is_equal(before)
		if defect not in ["mixed", "four"]:
			assert_int(shop.sell_weapon(target, id)).is_not_equal(OK)
			assert_dict(canonical_snapshot(session, shop)).is_equal(before)
		if defect not in ["zero", "negative", "stale", "mixed", "four"]:
			assert_int(shop.buy(target, 0)).is_not_equal(OK)
			assert_int(shop.reroll(target)).is_not_equal(OK)
			assert_dict(canonical_snapshot(session, shop)).is_equal(before)


func test_full_exhausted_and_unaffordable_purchase_fail_before_spend_or_normalization() -> void:
	for defect in ["full", "exhausted", "unaffordable"]:
		var session := _session()
		if defect == "full": _set_inventory(session, [RANGED, RANGED, RANGED, RANGED, RANGED, RANGED], [1, 1, 1, 1, 1, 1], [1, 2, 3, 4, 5, 6], 7)
		if defect == "exhausted": _set_inventory(session, [RANGED], [1], [11], 9007199254740991)
		if defect == "unaffordable": session.run_state.player().materials = 0
		var shop := _quoted_shop(session)
		session.run_state.shop_offer_initialized = false
		_observe(session, shop)
		var before := canonical_snapshot(session, shop)
		assert_int(shop.buy(session, 0)).is_not_equal(OK)
		assert_dict(canonical_snapshot(session, shop)).is_equal(before)


func test_final_wave_combine_then_real_endless_transition_keeps_inventory_and_next() -> void:
	var session := _session()
	session.run_state.current_wave = 20
	_set_inventory(session, [RANGED, RANGED], [2, 2], [11, 22], 30)
	var shop := _quoted_shop(session)
	assert_int(shop.combine_weapon(session, 22)).is_equal(OK)
	var expected := session.run_state.player().weapon_inventory.records()
	assert_int(expected[0].quality).is_equal(3)
	assert_bool(session.continue_endless()).is_true()
	assert_int(session.run_state.current_wave).is_equal(21)
	assert_bool(session.run_state.endless).is_true()
	assert_array(session.run_state.player().weapon_inventory.records()).is_equal(expected)
	assert_int(session.run_state.player().next_weapon_instance_id).is_equal(30)


func test_duplicate_player_and_derived_ids_do_not_alias_authoritative_inventory() -> void:
	var session := _session()
	_set_inventory(session, [RANGED, RANGED], [1, 1], [11, 22], 30)
	var player := session.run_state.player()
	var copy := player.duplicate_state()
	var ids := player.weapon_ids
	ids.clear()
	assert_int(player.weapon_inventory.size()).is_equal(2)
	assert_int(copy.weapon_inventory.combine_weapon(22)).is_equal(OK)
	assert_int(copy.weapon_inventory.add_weapon(MELEE, session.content_snapshot).instance_id).is_equal(30)
	assert_int(player.weapon_inventory.size()).is_equal(2)
	assert_int(player.weapon_inventory.record(22).quality).is_equal(1)
	assert_int(player.next_weapon_instance_id).is_equal(30)
	assert_int(copy.next_weapon_instance_id).is_equal(31)


func test_owned_quality_reaches_actual_projectile_and_melee_health_with_independent_runtime_ids() -> void:
	for mode in [GogoWeaponDefinition.Mode.RANGED, GogoWeaponDefinition.Mode.MELEE]:
		var session := _session()
		var content_id := RANGED if mode == GogoWeaponDefinition.Mode.RANGED else MELEE
		_set_inventory(session, [content_id, content_id], [1, 2], [11, 27], 40)
		var player := session.run_state.player()
		player.final_stats = {&"damage_multiplier": 1.2, &"ranged_damage": 3.0, &"melee_damage": 3.0}
		var world := auto_free(CombatWorld.new()) as CombatWorld
		add_child(world)
		world.session = session
		var enemy := _enemy(world)
		assert_int(enemy.runtime_instance_id).is_equal(1)
		var owner := GogoPlayerActor.new()
		owner.configure(session, world)
		world.add_child(owner)
		var weapons := owner.weapon_orbit.get_children()
		assert_int(weapons.size()).is_equal(2)
		for index in 2:
			var weapon := weapons[index] as GogoWeaponInstance
			weapon.global_position = Vector2.ZERO
			assert_int(weapon.runtime_instance_id).is_equal(index + 2)
			var inventory_id: Variant = weapon.get("inventory_instance_id")
			assert_int(inventory_id if inventory_id is int else 0).is_equal([11, 27][index])
			if mode == GogoWeaponDefinition.Mode.RANGED:
				assert_int(weapon._fire_projectiles(Vector2.RIGHT)).is_equal(1)
				var projectile := world.projectile_layer.get_child(index) as GogoProjectile
				assert_int(projectile.runtime_instance_id).is_equal(index + 4)
				projectile._physics_process(0.2)
			else:
				assert_bool(weapon._commit_melee_contact(enemy, Vector2.RIGHT)).is_true()
			assert_float(enemy.current_health).is_equal_approx([85.0, 64.0][index], 0.0001)


func test_owned_quality_negative_damage_clamp_is_consumed_as_zero_health_loss() -> void:
	for mode in [GogoWeaponDefinition.Mode.RANGED, GogoWeaponDefinition.Mode.MELEE]:
		var session := _session()
		_set_inventory(session, [RANGED if mode == GogoWeaponDefinition.Mode.RANGED else MELEE], [2], [11], 40)
		session.run_state.player().final_stats = {&"damage_multiplier": -1.2, &"ranged_damage": 3.0, &"melee_damage": 3.0}
		var world := auto_free(CombatWorld.new()) as CombatWorld
		add_child(world)
		world.session = session
		var enemy := _enemy(world)
		var owner := GogoPlayerActor.new()
		owner.configure(session, world)
		world.add_child(owner)
		var weapon := owner.weapon_orbit.get_child(0) as GogoWeaponInstance
		weapon.global_position = Vector2.ZERO
		if mode == GogoWeaponDefinition.Mode.RANGED:
			weapon._fire_projectiles(Vector2.RIGHT)
			(world.projectile_layer.get_child(0) as GogoProjectile)._physics_process(0.2)
		else:
			weapon._commit_melee_contact(enemy, Vector2.RIGHT)
		assert_float(enemy.current_health).is_equal(100.0)


func test_owned_ui_selection_uses_inventory_id_and_failure_preserves_controls_and_focus() -> void:
	var session := _session()
	_set_inventory(session, [RANGED, RANGED, RANGED], [1, 1, 2], [11, 22, 33], 40)
	session.run_state.player().final_stats = {&"damage_multiplier": 1.2, &"ranged_damage": 3.0}
	var app := auto_free(AppKernel.new()) as AppKernel
	app.add_to_group(&"gogobro_app")
	app.content_snapshot = session.content_snapshot
	app.current_session = session
	add_child(app)
	var screen := auto_free(SHOP_SCREEN.new()) as GogoScreenBase
	add_child(screen)
	await get_tree().process_frame
	(screen.get_node("LoadoutBar/Weapons/WeaponSlot1") as Button).pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	var selected := screen.get_node("LoadoutBar/Weapons/WeaponSlot1") as Button
	assert_int(int(selected.get_meta(&"inventory_instance_id", 0))).is_equal(22)
	assert_int(int(selected.get_meta(&"quality", 0))).is_equal(1)
	assert_str((screen.get_node("OfferDescription") as Label).text).contains("15 → 21")
	assert_str((screen.get_node("OfferFlavor") as Label).text).contains("#11")
	assert_str((screen.get_node("OfferFlavor") as Label).text).contains("5 金币")
	var menu := screen.get_node_or_null("WeaponActionMenu") as Control
	assert_object(menu).is_not_null()
	if menu == null:
		return
	var combine := menu.get_node_or_null("Panel/CombineButton") as Button
	assert_object(combine).is_not_null()
	if combine == null:
		return
	combine.grab_focus()
	session.run_state.player().weapon_inventory.remove_weapon(11)
	var shop := screen.get("_shop") as ShopRuntimeService
	_observe(session, shop)
	var before := canonical_snapshot(session, shop)
	var status_node := screen.get_node("Status")
	combine.pressed.emit()
	await get_tree().process_frame
	assert_dict(canonical_snapshot(session, shop)).is_equal(before)
	assert_object(screen.get_node("LoadoutBar/Weapons/WeaponSlot1")).is_same(selected)
	assert_object(screen.get_node("Status")).is_same(status_node)
	assert_object(get_viewport().gui_get_focus_owner()).is_same(menu.get_node("Panel/CancelButton"))
	session.run_state.player().materials = 0
	before = canonical_snapshot(session, shop)
	screen.call("_buy", 0)
	screen.call("_reroll")
	screen.call("_sell_weapon", 999)
	await get_tree().process_frame
	assert_dict(canonical_snapshot(session, shop)).is_equal(before)
	assert_object(screen.get_node("Status")).is_same(status_node)
	assert_object(get_viewport().gui_get_focus_owner()).is_same(menu.get_node("Panel/CancelButton"))


func test_weapon_cards_use_quality_one_for_quotes_without_changing_item_rarity() -> void:
	var session := _session(4)
	var definition := session.content_snapshot.definition(RANGED, &"weapon")
	var card := auto_free(GogoStaticCardPresenter.build_card(definition, "15 金币", null)) as Control
	assert_str((card.get_node("RarityLabel") as Label).text).is_equal("I")
	assert_str((card.get_node("Name") as Label).text).contains(" I")
	assert_bool((card.get_node("RarityAccent") as ColorRect).color.is_equal_approx(Color("e8e6dc"))).is_true()
	var item := session.content_snapshot.all(&"item")[0] as GogoItemDefinition
	item.tier = 4
	var item_card := auto_free(GogoStaticCardPresenter.build_card(item, "10 金币", null)) as Control
	assert_str((item_card.get_node("RarityLabel") as Label).text).is_equal("传说")
	var owned := auto_free(GogoStaticCardPresenter.build_card(definition, "13 金币", null, &"compact", Color.WHITE, 4)) as Control
	assert_str((owned.get_node("RarityLabel") as Label).text).is_equal("IV")
	assert_bool((owned.get_node("RarityAccent") as ColorRect).color.is_equal_approx(Color("ef6a67"))).is_true()
	assert_str(owned.tooltip_text).contains(" IV")


func test_ui_success_retains_selected_id_after_partner_before_it_and_sale_focuses_nearest() -> void:
	var session := _session()
	_set_inventory(session, [RANGED, MELEE, RANGED, RANGED], [1, 1, 1, 2], [11, 15, 22, 33], 40)
	var app := auto_free(AppKernel.new()) as AppKernel
	app.add_to_group(&"gogobro_app")
	app.content_snapshot = session.content_snapshot
	app.current_session = session
	add_child(app)
	var screen := auto_free(SHOP_SCREEN.new()) as GogoScreenBase
	add_child(screen)
	await get_tree().process_frame
	(screen.get_node("LoadoutBar/Weapons/WeaponSlot2") as Button).pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	var menu := screen.get_node_or_null("WeaponActionMenu") as Control
	assert_object(menu).is_not_null()
	if menu == null:
		return
	(menu.get_node_or_null("Panel/CombineButton") as Button).pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	var focus := get_viewport().gui_get_focus_owner()
	assert_int(int(focus.get_meta(&"inventory_instance_id", 0))).is_equal(22)
	assert_int(int(focus.get_meta(&"slot_index", -1))).is_equal(1)
	assert_str((screen.get_node("LoadoutBar/Weapons/WeaponSlot1/QualityBadge") as Label).text).is_equal("II")
	assert_str((screen.get_node("LoadoutBar/Weapons/WeaponSlot2/QualityBadge") as Label).text).is_equal("II")
	assert_str((screen.get_node("OfferFlavor") as Label).text).contains("#33")
	(screen.get_node("LoadoutBar/Weapons/WeaponSlot1") as Button).pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	menu = screen.get_node_or_null("WeaponActionMenu") as Control
	assert_object(menu).is_not_null()
	if menu == null:
		return
	(menu.get_node_or_null("Panel/SellButton") as Button).pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	focus = get_viewport().gui_get_focus_owner()
	assert_int(int(focus.get_meta(&"inventory_instance_id", 0))).is_equal(33)
	assert_int(int(focus.get_meta(&"slot_index", -1))).is_equal(1)
	assert_bool(screen.has_node("LoadoutBar/Weapons/WeaponSlot1/Actions")).is_false()
	assert_int(session.run_state.player().next_weapon_instance_id).is_equal(40)


func test_repeated_failure_feedback_restores_balance_color_without_rebuilding() -> void:
	var session := _session()
	var app := auto_free(AppKernel.new()) as AppKernel
	app.add_to_group(&"gogobro_app")
	app.content_snapshot = session.content_snapshot
	app.current_session = session
	add_child(app)
	var screen := auto_free(SHOP_SCREEN.new()) as GogoScreenBase
	add_child(screen)
	await get_tree().process_frame
	var materials := screen.get_node("TopBand/Materials") as Label
	var original_color := materials.get_theme_color(&"font_color")
	session.run_state.player().materials = 0
	screen.call("_buy", 0)
	screen.call("_reroll")
	await get_tree().create_timer(0.3).timeout
	assert_object(screen.get_node("TopBand/Materials")).is_same(materials)
	assert_bool(materials.get_theme_color(&"font_color").is_equal_approx(original_color)).is_true()
	var status := screen.get_node("Status") as Label
	screen.call("_buy", 999)
	assert_str(status.text).is_equal("报价已失效")
	session.run_state = null
	screen.call("_sell_weapon", 1)
	assert_str(status.text).is_equal("当前无法操作武器")


func test_quality_changes_only_base_damage_before_flat_not_other_combat_parameters() -> void:
	var player := SessionPlayerState.new()
	player.final_stats = {&"damage_multiplier": 1.2, &"ranged_damage": 3.0, &"attack_speed": 2.0,
		&"attack_range_bonus": 10.0, &"critical_chance": 0.25, &"explosion_damage_multiplier": 0.5}
	var definition := GogoWeaponDefinition.new()
	definition.mode = GogoWeaponDefinition.Mode.RANGED
	definition.damage = 10.0
	definition.cooldown_seconds = 0.8
	definition.attack_range = 90.0
	definition.projectile_speed = 200.0
	definition.projectile_count = 2
	definition.spread_degrees = 3.0
	definition.knockback = 4.0
	var service := WeaponRuntimeService.new()
	assert_object(service.build_instance(definition, player, 0)).is_null()
	assert_object(service.build_instance(definition, player, 5)).is_null()
	assert_float(service.build_instance(definition, player).damage).is_equal_approx(15.0, 0.0001)
	for quality in [1, 2, 3, 4]:
		var stats := service.build_instance(definition, player, quality)
		assert_float(stats.damage).is_equal_approx([15.0, 21.0, 27.0, 33.0][quality - 1], 0.0001)
		assert_int(stats.weapon_quality).is_equal(quality)
		assert_float(stats.cooldown_seconds).is_equal_approx(0.4, 0.0001)
		assert_float(stats.attack_range).is_equal(100.0)
		assert_float(stats.projectile_speed).is_equal(200.0)
		assert_int(stats.projectile_count).is_equal(2)
		assert_float(stats.spread_degrees).is_equal(3.0)
		assert_float(stats.knockback).is_equal(4.0)
		assert_float(stats.critical_chance).is_equal(0.25)
		assert_float(stats.explosion_damage_multiplier).is_equal(1.5)


# Fresh fixtures only: these are rendered coverage added after the implementation.
func test_rendered_menu_outside_press_closes_without_background_activation() -> void:
	var fixture := await _rendered_menu_fixture([RANGED, RANGED], [1, 1], [11, 22], 1000)
	var screen := fixture.screen as GogoScreenBase
	var session := fixture.session as GameSession
	var slot := _weapon_button_for_id(screen, 22)
	var slot_observation := {"events": [], "activations": 0}
	slot.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton: slot_observation.events.append({"pressed": event.pressed, "button": event.button_index}))
	slot.pressed.connect(func() -> void: slot_observation.activations += 1)
	var menu := await _open_rendered_weapon_menu(screen, 22)
	if menu == null: return
	assert_array(slot_observation.events).is_equal([{"pressed": true, "button": MOUSE_BUTTON_LEFT}, {"pressed": false, "button": MOUSE_BUTTON_LEFT}])
	assert_int(slot_observation.activations).is_equal(1)
	var buy := screen.get_node("OfferRow/OfferSlot0/Card") as Button
	var buy_observation := {"activations": 0}
	buy.pressed.connect(func() -> void: buy_observation.activations += 1)
	var focus_trace: Array = []
	var menu_instance_id := menu.get_instance_id()
	buy.mouse_entered.connect(func() -> void: _append_focus_trace(focus_trace, "offer_mouse_entered", screen, menu_instance_id))
	buy.focus_entered.connect(func() -> void: _append_focus_trace(focus_trace, "offer_focus_entered", screen, menu_instance_id))
	var before := canonical_snapshot(session, screen.get("_shop") as ShopRuntimeService)
	await _viewport_click_traced(buy.get_global_rect().get_center(), focus_trace, screen, menu_instance_id)
	assert_bool(not screen.has_node("WeaponActionMenu")).is_true()
	assert_int(buy_observation.activations).is_zero()
	assert_dict(canonical_snapshot(session, screen.get("_shop") as ShopRuntimeService)).is_equal(before)
	# Closing defers ShopScreen's identity-based focus restoration by one frame.
	await get_tree().process_frame
	_append_focus_trace(focus_trace, "end", screen, menu_instance_id)
	print("OUTSIDE_FOCUS_TRACE %s" % JSON.stringify(focus_trace))
	var restored := _weapon_button_for_id(screen, 22)
	assert_object(get_viewport().gui_get_focus_owner()).is_same(restored)
	await _viewport_mouse_motion(Vector2(1200, 40))
	await _viewport_mouse_motion(buy.get_global_rect().get_center())
	assert_object(get_viewport().gui_get_focus_owner()).is_same(buy)


func test_rendered_menu_keyboard_cycles_exact_actions_and_escape_restores_origin() -> void:
	var fixture := await _rendered_menu_fixture([RANGED, RANGED], [1, 1], [11, 22], 1000)
	var screen := fixture.screen as GogoScreenBase
	var session := fixture.session as GameSession
	var menu := await _open_rendered_weapon_menu(screen, 22)
	if menu == null: return
	var cancel := menu.get_node("Panel/CancelButton") as Button
	var sell := menu.get_node("Panel/SellButton") as Button
	var combine := menu.get_node("Panel/CombineButton") as Button
	for pair in [[cancel, KEY_TAB, false, sell], [sell, KEY_TAB, false, combine], [combine, KEY_TAB, false, cancel], [cancel, KEY_TAB, true, combine], [sell, KEY_UP, false, cancel], [cancel, KEY_DOWN, false, sell], [sell, KEY_RIGHT, false, combine], [cancel, KEY_LEFT, false, combine]]:
		(pair[0] as Button).grab_focus()
		await _viewport_key(pair[1] as Key, pair[2] as bool)
		assert_object(get_viewport().gui_get_focus_owner()).is_same(pair[3])
	var before := canonical_snapshot(session, screen.get("_shop") as ShopRuntimeService)
	await _viewport_key(KEY_ESCAPE)
	assert_bool(not screen.has_node("WeaponActionMenu")).is_true()
	assert_dict(canonical_snapshot(session, screen.get("_shop") as ShopRuntimeService)).is_equal(before)
	assert_object(get_viewport().gui_get_focus_owner()).is_same(_weapon_button_for_id(screen, 22))


func test_rendered_menu_pointer_success_and_live_stale_callbacks_publish_once() -> void:
	var fixture := await _rendered_menu_fixture([RANGED, RANGED, RANGED], [1, 1, 2], [11, 22, 33], 1000)
	var screen := fixture.screen as GogoScreenBase
	var session := fixture.session as GameSession
	var menu := await _open_rendered_weapon_menu(screen, 22)
	if menu == null: return
	var combine := menu.get_node("Panel/CombineButton") as Button
	var connections := combine.get_signal_connection_list(&"pressed")
	assert_bool(not connections.is_empty()).is_true()
	var old_action := connections[0].callable as Callable
	assert_bool(old_action.is_valid()).is_true()
	assert_object(old_action.get_object()).is_same(screen)
	_observe(session, screen.get("_shop") as ShopRuntimeService)
	await _viewport_click(combine.get_global_rect().get_center())
	assert_int(session.run_state.player().weapon_inventory.record(22).quality).is_equal(2)
	assert_int(session.run_state.player().weapon_inventory.record(33).quality).is_equal(2)
	assert_dict(_publication_counts).is_equal({"state": 1, "offers": 0})
	var reopened := await _open_rendered_weapon_menu(screen, 22)
	if reopened == null: return
	var before_stale := canonical_snapshot(session, screen.get("_shop") as ShopRuntimeService)
	old_action.call()
	await get_tree().process_frame
	assert_dict(canonical_snapshot(session, screen.get("_shop") as ShopRuntimeService)).is_equal(before_stale)


func test_rendered_menu_same_frame_duplicate_combine_callable_publishes_once() -> void:
	var fixture := await _rendered_menu_fixture([RANGED, RANGED, RANGED], [1, 1, 2], [11, 22, 33], 1000)
	var screen := fixture.screen as GogoScreenBase
	var session := fixture.session as GameSession
	var menu := await _open_rendered_weapon_menu(screen, 22)
	if menu == null: return
	var action := ((menu.get_node("Panel/CombineButton") as Button).get_signal_connection_list(&"pressed")[0].callable as Callable)
	assert_bool(action.is_valid()).is_true()
	assert_object(action.get_object()).is_same(screen)
	_observe(session, screen.get("_shop") as ShopRuntimeService)
	# Two immediate calls model a duplicate same-frame delivery; the first clears the generation.
	action.call()
	action.call()
	await get_tree().process_frame
	assert_int(session.run_state.player().weapon_inventory.record(22).quality).is_equal(2)
	assert_int(session.run_state.player().weapon_inventory.record(33).quality).is_equal(2)
	assert_dict(_publication_counts).is_equal({"state": 1, "offers": 0})


func test_rendered_menu_pointer_sale_and_live_stale_sale_callback_publish_once() -> void:
	var fixture := await _rendered_menu_fixture([RANGED, RANGED], [1, 1], [11, 22], 1000)
	var screen := fixture.screen as GogoScreenBase
	var session := fixture.session as GameSession
	var menu := await _open_rendered_weapon_menu(screen, 22)
	if menu == null: return
	var sell := menu.get_node("Panel/SellButton") as Button
	var old_action := (sell.get_signal_connection_list(&"pressed")[0].callable as Callable)
	assert_bool(old_action.is_valid()).is_true()
	assert_object(old_action.get_object()).is_same(screen)
	var credit: int = QUALITY_RULES.sale_price((session.content_snapshot.definition(RANGED, &"weapon") as GogoWeaponDefinition).price, 1)
	_observe(session, screen.get("_shop") as ShopRuntimeService)
	await _viewport_click(sell.get_global_rect().get_center())
	await get_tree().process_frame
	assert_int(session.run_state.player().materials).is_equal(1000 + credit)
	assert_bool(session.run_state.player().weapon_inventory.record(22).is_empty()).is_true()
	assert_int(int(get_viewport().gui_get_focus_owner().get_meta(&"inventory_instance_id", 0))).is_equal(11)
	assert_dict(_publication_counts).is_equal({"state": 1, "offers": 0})
	var reopened := await _open_rendered_weapon_menu(screen, 11)
	if reopened == null: return
	var before_stale := canonical_snapshot(session, screen.get("_shop") as ShopRuntimeService)
	old_action.call()
	await get_tree().process_frame
	assert_dict(canonical_snapshot(session, screen.get("_shop") as ShopRuntimeService)).is_equal(before_stale)


func test_rendered_menu_successful_reroll_clears_modal_rebuilds_and_focuses_reroll() -> void:
	var fixture := await _rendered_menu_fixture([RANGED, RANGED], [1, 1], [11, 22], 1000)
	var screen := fixture.screen as GogoScreenBase
	var session := fixture.session as GameSession
	var menu := await _open_rendered_weapon_menu(screen, 22)
	if menu == null: return
	_observe(session, screen.get("_shop") as ShopRuntimeService)
	screen.call("_reroll")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_bool(not screen.has_node("WeaponActionMenu")).is_true()
	assert_int(session.run_state.reroll_count).is_equal(1)
	assert_str(String(get_viewport().gui_get_focus_owner().get_meta(&"focus_role", &""))).is_equal("reroll")
	assert_dict(_publication_counts).is_equal({"state": 0, "offers": 1})


func test_rendered_menu_successful_finish_route_clears_modal_and_publishes_settlement() -> void:
	var fixture := await _rendered_menu_fixture([RANGED, RANGED], [1, 1], [11, 22], 1000)
	var app := fixture.app as AppKernel
	var screen := fixture.screen as GogoScreenBase
	var session := fixture.session as GameSession
	var route_host: Node = auto_free(Node.new())
	add_child(route_host)
	var flow := auto_free(SceneFlow.new()) as SceneFlow
	flow.configure(route_host, {FlowRoute.SETTLEMENT: preload("res://game/ui/settlement_screen.tscn")})
	app.configure(flow, null)
	var route_observation := {"count": 0, "current": &""}
	flow.route_changed.connect(func(_previous: StringName, current: StringName) -> void:
		route_observation.count += 1
		route_observation.current = current)
	var menu := await _open_rendered_weapon_menu(screen, 22)
	if menu == null: return
	session.run_state.current_wave = session.run_state.total_waves
	session.run_state.phase = &"shop"
	screen.call("_finish_run")
	await get_tree().process_frame
	assert_bool(not screen.has_node("WeaponActionMenu")).is_true()
	assert_int(route_observation.count).is_equal(1)
	assert_str(String(route_observation.current)).is_equal(String(FlowRoute.SETTLEMENT))
	assert_str(String(flow.current_route())).is_equal(String(FlowRoute.SETTLEMENT))


func test_rendered_menu_iv_disabled_pointer_attempt_preserves_state() -> void:
	var fixture := await _rendered_menu_fixture([RANGED], [4], [11], 1000)
	var screen := fixture.screen as GogoScreenBase
	var session := fixture.session as GameSession
	var menu := await _open_rendered_weapon_menu(screen, 11)
	if menu == null: return
	var combine := menu.get_node("Panel/CombineButton") as Button
	assert_bool(combine.disabled).is_true()
	assert_str((menu.get_node("Panel/CombineDetail") as Label).text).contains("最高品质 IV")
	var before := canonical_snapshot(session, screen.get("_shop") as ShopRuntimeService)
	await _viewport_click(combine.get_global_rect().get_center())
	var cancel := menu.get_node("Panel/CancelButton") as Button
	var sell := menu.get_node("Panel/SellButton") as Button
	cancel.grab_focus()
	await _viewport_key(KEY_TAB)
	assert_object(get_viewport().gui_get_focus_owner()).is_same(sell)
	await _viewport_key(KEY_TAB)
	assert_object(get_viewport().gui_get_focus_owner()).is_same(cancel)
	combine.grab_focus()
	assert_bool(get_viewport().gui_get_focus_owner() != combine).is_true()
	get_viewport().gui_release_focus()
	combine.grab_focus()
	assert_bool(get_viewport().gui_get_focus_owner() == null).is_true()
	await _viewport_key(KEY_ENTER)
	assert_object(screen.get_node("WeaponActionMenu")).is_same(menu)
	cancel.grab_focus()
	assert_dict(canonical_snapshot(session, screen.get("_shop") as ShopRuntimeService)).is_equal(before)


func test_rendered_menu_no_partner_disabled_pointer_attempt_preserves_state() -> void:
	var fixture := await _rendered_menu_fixture([RANGED], [1], [11], 1000)
	var screen := fixture.screen as GogoScreenBase
	var session := fixture.session as GameSession
	var menu := await _open_rendered_weapon_menu(screen, 11)
	if menu == null: return
	var combine := menu.get_node("Panel/CombineButton") as Button
	assert_bool(combine.disabled).is_true()
	assert_str((menu.get_node("Panel/CombineDetail") as Label).text).contains("无同品质合成伙伴")
	var before := canonical_snapshot(session, screen.get("_shop") as ShopRuntimeService)
	await _viewport_click(combine.get_global_rect().get_center())
	var cancel := menu.get_node("Panel/CancelButton") as Button
	var sell := menu.get_node("Panel/SellButton") as Button
	cancel.grab_focus()
	await _viewport_key(KEY_TAB)
	assert_object(get_viewport().gui_get_focus_owner()).is_same(sell)
	await _viewport_key(KEY_TAB, true)
	assert_object(get_viewport().gui_get_focus_owner()).is_same(cancel)
	combine.grab_focus()
	assert_bool(get_viewport().gui_get_focus_owner() != combine).is_true()
	get_viewport().gui_release_focus()
	combine.grab_focus()
	assert_bool(get_viewport().gui_get_focus_owner() == null).is_true()
	await _viewport_key(KEY_ENTER)
	assert_object(screen.get_node("WeaponActionMenu")).is_same(menu)
	cancel.grab_focus()
	assert_dict(canonical_snapshot(session, screen.get("_shop") as ShopRuntimeService)).is_equal(before)


func test_rendered_menu_partner_disappearance_is_stable() -> void:
	var fixture := await _rendered_menu_fixture([RANGED, RANGED], [1, 1], [11, 22], 1000)
	var screen := fixture.screen as GogoScreenBase
	var session := fixture.session as GameSession
	var menu := await _open_rendered_weapon_menu(screen, 22)
	if menu == null: return
	var combine := menu.get_node("Panel/CombineButton") as Button
	var cancel := menu.get_node("Panel/CancelButton") as Button
	var sell := menu.get_node("Panel/SellButton") as Button
	session.run_state.player().weapon_inventory.remove_weapon(11)
	var shop := screen.get("_shop") as ShopRuntimeService
	_observe(session, shop)
	var before := canonical_snapshot(session, shop)
	await _viewport_click(combine.get_global_rect().get_center())
	assert_object(screen.get_node("WeaponActionMenu")).is_same(menu)
	assert_object(menu.get_node("Panel/CombineButton")).is_same(combine)
	assert_object(menu.get_node("Panel/CancelButton")).is_same(cancel)
	assert_object(menu.get_node("Panel/SellButton")).is_same(sell)
	assert_bool(combine.disabled).is_true()
	assert_str((menu.get_node("Panel/CombineDetail") as Label).text).contains("无同品质合成伙伴")
	assert_object(get_viewport().gui_get_focus_owner()).is_same(cancel)
	assert_dict(canonical_snapshot(session, shop)).is_equal(before)
	assert_dict(_publication_counts).is_equal({"state": 0, "offers": 0})


func test_rendered_menu_missing_target_closes_to_legal_focus() -> void:
	var fixture := await _rendered_menu_fixture([RANGED, MELEE], [1, 1], [11, 22], 1000)
	var screen := fixture.screen as GogoScreenBase
	var session := fixture.session as GameSession
	var menu := await _open_rendered_weapon_menu(screen, 22)
	if menu == null: return
	session.run_state.player().weapon_inventory.remove_weapon(22)
	var after_removal := canonical_snapshot(session, screen.get("_shop") as ShopRuntimeService)
	await _viewport_click((menu.get_node("Panel/SellButton") as Button).get_global_rect().get_center())
	assert_bool(not screen.has_node("WeaponActionMenu")).is_true()
	await get_tree().process_frame
	assert_dict(canonical_snapshot(session, screen.get("_shop") as ShopRuntimeService)).is_equal(after_removal)
	assert_int(int(get_viewport().gui_get_focus_owner().get_meta(&"inventory_instance_id", 0))).is_equal(11)
	(fixture.app as AppKernel).remove_from_group(&"gogobro_app")
	screen.queue_free()
	await get_tree().process_frame
	var combine_fixture := await _rendered_menu_fixture([RANGED, RANGED], [1, 1], [11, 22], 1000)
	var combine_screen := combine_fixture.screen as GogoScreenBase
	var combine_session := combine_fixture.session as GameSession
	var combine_menu := await _open_rendered_weapon_menu(combine_screen, 22)
	if combine_menu == null: return
	var combine := combine_menu.get_node("Panel/CombineButton") as Button
	assert_bool(combine.disabled).is_false()
	combine_session.run_state.player().weapon_inventory.remove_weapon(22)
	var combine_after_removal := canonical_snapshot(combine_session, combine_screen.get("_shop") as ShopRuntimeService)
	await _viewport_click(combine.get_global_rect().get_center())
	assert_bool(not combine_screen.has_node("WeaponActionMenu")).is_true()
	await get_tree().process_frame
	assert_dict(canonical_snapshot(combine_session, combine_screen.get("_shop") as ShopRuntimeService)).is_equal(combine_after_removal)
	assert_int(int(get_viewport().gui_get_focus_owner().get_meta(&"inventory_instance_id", 0))).is_equal(11)


func test_rendered_menu_overflow_refusal_retains_tree_target_and_focus() -> void:
	var fixture := await _rendered_menu_fixture([RANGED], [1], [11], 9223372036854775807)
	var screen := fixture.screen as GogoScreenBase
	var session := fixture.session as GameSession
	var menu := await _open_rendered_weapon_menu(screen, 11)
	if menu == null: return
	var sell := menu.get_node("Panel/SellButton") as Button
	sell.grab_focus()
	var before := canonical_snapshot(session, screen.get("_shop") as ShopRuntimeService)
	await _viewport_click(sell.get_global_rect().get_center())
	assert_object(screen.get_node("WeaponActionMenu")).is_same(menu)
	assert_object(get_viewport().gui_get_focus_owner()).is_same(sell)
	assert_str((menu.get_node("Panel/InstanceId") as Label).text).is_equal("实例 ID #11")
	assert_str((menu.get_node("Panel/Failure") as Label).text).is_equal("金币已达上限，无法出售")
	assert_dict(canonical_snapshot(session, screen.get("_shop") as ShopRuntimeService)).is_equal(before)


# Root executes this capture-only case separately; its fixture-local viewport click is allowed, but it never injects OS input.
func test_capture_only_native960_weapon_action_menu_ready_for_root_observation(
	_do_skip := DisplayServer.get_name() == "headless" or OS.get_environment("GOGOBRO_ROOT_OBSERVER_ENABLED") != "1",
	_skip_reason := "requires the windowed 960x540 visual/root-observer runner"
) -> void:
	var fixture := await _rendered_menu_fixture([RANGED, RANGED], [1, 1], [11, 22], 1000)
	var screen := fixture.screen as GogoScreenBase
	var menu := await _open_rendered_weapon_menu(screen, 22)
	if menu == null: return
	var window := get_window()
	var temp_root := OS.get_environment("TEMP")
	var title := "GOGOBRO native960 %s %d" % [temp_root.get_base_dir().get_file(), OS.get_process_id()]
	window.title = title
	window.size = Vector2i(960, 540)
	window.show()
	await RenderingServer.frame_post_draw
	var panel := menu.get_node("Panel") as Control
	var ready := {"marker": "test_capture_only_native960_weapon_action_menu_ready_for_root_observation", "process_id": OS.get_process_id(), "title": title, "window_size": [window.size.x, window.size.y], "visible_rect": [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y], "root_texture_size": [get_viewport().get_texture().get_width(), get_viewport().get_texture().get_height()], "screen_transform": str(get_viewport().get_screen_transform()), "content_scale_mode": window.content_scale_mode, "content_scale_size": [window.content_scale_size.x, window.content_scale_size.y], "content_scale_factor": window.content_scale_factor, "content_scale_stretch": window.content_scale_stretch, "selected_id": 22, "panel_rect": [panel.get_global_rect().position.x, panel.get_global_rect().position.y, panel.get_global_rect().size.x, panel.get_global_rect().size.y], "sell_rect": [(menu.get_node("Panel/SellButton") as Button).get_global_rect().position.x, (menu.get_node("Panel/SellButton") as Button).get_global_rect().position.y, (menu.get_node("Panel/SellButton") as Button).size.x, (menu.get_node("Panel/SellButton") as Button).size.y]}
	var ready_path := temp_root.path_join("submenu-native960-ready.json")
	FileAccess.open(ready_path, FileAccess.WRITE).store_string(JSON.stringify(ready))
	var logical_path := temp_root.path_join("submenu-native960-logical-1280x720.png")
	assert_int(get_viewport().get_texture().get_image().save_png(logical_path)).is_equal(OK)
	print("SUBMENU_NATIVE960_READY title=%s ready=%s logical=%s" % [title, ready_path, logical_path])
	var deadline := Time.get_ticks_msec() + 45000
	while Time.get_ticks_msec() < deadline and not FileAccess.file_exists(temp_root.path_join("submenu-native960-observed.txt")):
		await get_tree().process_frame
	assert_bool(FileAccess.file_exists(temp_root.path_join("submenu-native960-observed.txt"))).is_true()


func _rendered_menu_fixture(content_ids: Array, qualities: Array, ids: Array, materials: int) -> Dictionary:
	var session := _session()
	_set_inventory(session, content_ids, qualities, ids, 50)
	session.run_state.player().materials = materials
	var app := auto_free(AppKernel.new()) as AppKernel
	app.add_to_group(&"gogobro_app")
	app.content_snapshot = session.content_snapshot
	app.current_session = session
	add_child(app)
	var screen := auto_free(SHOP_SCREEN.new()) as GogoScreenBase
	add_child(screen)
	await _rendered_window(Vector2i(1280, 720))
	return {"app": app, "session": session, "screen": screen}


func _weapon_button_for_id(screen: GogoScreenBase, inventory_instance_id: int) -> Button:
	for child in (screen.get_node("LoadoutBar/Weapons") as Control).get_children():
		if child is Button and int(child.get_meta(&"inventory_instance_id", 0)) == inventory_instance_id:
			return child as Button
	return null


func _open_rendered_weapon_menu(screen: GogoScreenBase, inventory_instance_id: int) -> Control:
	var button := _weapon_button_for_id(screen, inventory_instance_id)
	assert_object(button).is_not_null()
	if button == null: return null
	await _viewport_click(button.get_global_rect().get_center())
	await get_tree().process_frame
	var menu := screen.get_node_or_null("WeaponActionMenu") as Control
	assert_object(menu).is_not_null()
	if menu == null: return null
	assert_str((menu.get_node("Panel/InstanceId") as Label).text).is_equal("实例 ID #%d" % inventory_instance_id)
	assert_object(get_viewport().gui_get_focus_owner()).is_same(menu.get_node("Panel/CancelButton"))
	return menu


func _viewport_key(keycode: Key, shift: bool = false) -> void:
	get_viewport().push_input(_key_event(keycode, shift))
	await get_tree().process_frame
	var release := _key_event(keycode, shift)
	release.pressed = false
	get_viewport().push_input(release)
	await get_tree().process_frame


func _key_event(keycode: Key, shift: bool = false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	event.shift_pressed = shift
	return event


func _viewport_click(point: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.position = point
	press.global_position = point
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	get_viewport().push_input(press)
	await get_tree().process_frame
	var release := press.duplicate() as InputEventMouseButton
	release.pressed = false
	get_viewport().push_input(release)
	await get_tree().process_frame


func _viewport_mouse_motion(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	motion.relative = Vector2(1, 0)
	get_viewport().push_input(motion)
	await get_tree().process_frame


func _viewport_click_traced(point: Vector2, trace: Array, screen: GogoScreenBase, menu_instance_id: int) -> void:
	var press := InputEventMouseButton.new()
	press.position = point
	press.global_position = point
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	_append_focus_trace(trace, "before_press", screen, menu_instance_id)
	get_viewport().push_input(press)
	await get_tree().process_frame
	_append_focus_trace(trace, "after_press", screen, menu_instance_id)
	var release := press.duplicate() as InputEventMouseButton
	release.pressed = false
	get_viewport().push_input(release)
	await get_tree().process_frame
	_append_focus_trace(trace, "after_release", screen, menu_instance_id)


func _append_focus_trace(trace: Array, phase: String, screen: GogoScreenBase, menu_instance_id: int) -> void:
	var focus := get_viewport().gui_get_focus_owner()
	var current_menu := screen.get_node_or_null("WeaponActionMenu")
	var current_menu_instance_id := current_menu.get_instance_id() if current_menu != null and is_instance_valid(current_menu) else 0
	trace.append({
		"phase": phase,
		"focus_path": String(focus.get_path()) if focus != null and is_instance_valid(focus) else "",
		"focus_role": String(focus.get_meta(&"focus_role", &"")) if focus != null and is_instance_valid(focus) else "",
		"focus_inventory_id": int(focus.get_meta(&"inventory_instance_id", 0)) if focus != null and is_instance_valid(focus) else 0,
		"menu_valid": current_menu_instance_id == menu_instance_id,
		"menu_instance_id": current_menu_instance_id,
		"menu_target": int(screen.get("_weapon_action_target_id")),
	})


func _rendered_window(size: Vector2i) -> void:
	var window := get_window()
	window.mode = Window.MODE_WINDOWED
	window.size = size
	window.show()
	await get_tree().process_frame
	await get_tree().process_frame


func _session(tier: int = 1) -> GameSession:
	var packs := ValidationContentFactory.create_packs()
	for pack in packs:
		for definition in pack.definitions:
			if definition is GogoWeaponDefinition and definition.content_id in [RANGED, MELEE]:
				definition.damage = 10.0
				definition.projectile_speed = 1000.0
				definition.knockback = 0.0
				definition.tier = tier
	var content := GogoContentRegistry.new().build_snapshot(packs)
	var config := SessionConfig.new()
	config.seed = 83411
	config.character_id = ValidationContentFactory.CHARACTER_ID
	config.starting_weapon_id = RANGED
	config.difficulty_id = ValidationContentFactory.DIFFICULTY_ID
	config.zone_id = ValidationContentFactory.ZONE_ID
	var session := GameSession.new()
	assert_int(session.start(config, content)).is_equal(OK)
	assert_int(session.transition(&"shop")).is_equal(OK)
	session.run_state.player().materials = 1000
	return session


func _set_inventory(session: GameSession, content_ids: Array, qualities: Array, ids: Array, next_id: int) -> void:
	var records := []
	for index in content_ids.size(): records.append({"instance_id": ids[index], "content_id": content_ids[index], "quality": qualities[index]})
	var result := INVENTORY.parse_records(records, next_id, session.content_snapshot)
	assert_int(result.error).is_equal(OK)
	session.run_state.player().weapon_inventory = result.inventory


func _enemy(world: CombatWorld) -> GogoEnemyActor:
	var definition := GogoEnemyDefinition.new()
	definition.max_health = 100.0
	definition.xp_value = 0
	definition.material_value = 0
	var enemy := GogoEnemyActor.new()
	enemy.configure(definition, null, GogoDifficultyDefinition.new(), world, world.allocate_runtime_instance_id(&"enemy"))
	enemy.global_position = Vector2(70, 0)
	world.enemy_layer.add_child(enemy)
	assert_bool(world.register_active_enemy(enemy)).is_true()
	return enemy


func _quoted_shop(session: GameSession) -> ShopRuntimeService:
	var shop := ShopRuntimeService.new()
	shop.offers = [session.content_snapshot.definition(RANGED, &"weapon"), null,
		session.content_snapshot.definition(MELEE, &"weapon"), null]
	session.run_state.shop_offer_ids = [RANGED, &"", MELEE, &""]
	session.run_state.locked_shop_offer_ids = [RANGED]
	session.run_state.shop_offer_wave = session.run_state.current_wave
	session.run_state.shop_offer_initialized = true
	session.run_state.shop_offer_initialization_id = 7
	return shop


func _observe(session: GameSession, shop: ShopRuntimeService) -> void:
	_publication_counts = {"state": 0, "offers": 0}
	if session != null:
		session.state_changed.connect(func() -> void: _publication_counts.state += 1)
	shop.offers_changed.connect(func(_value: Array[GogoContentDefinition]) -> void: _publication_counts.offers += 1)


func canonical_snapshot(session: GameSession, shop: ShopRuntimeService) -> Dictionary:
	return {
		"state": session.run_state.to_dictionary().duplicate(true) if session != null and session.run_state != null else null,
		"rng": session.rng.state if session != null else null,
		"offers": shop.offers.map(func(value): return String(value.content_id) if value != null else ""),
		"publications": _publication_counts.duplicate(true),
	}
