extends GdUnitTestSuite


func test_shop_right_rail_keeps_fixed_stats_and_controls_in_separate_rectangles() -> void:
	# Break caught: controls overlap the fixed 16-row stats panel at a 16:9 output.
	var panel := auto_free((load("res://scenes/ui/shop_panel/shop_panel.tscn") as PackedScene).instantiate()) as ShopPanel
	add_child(panel)
	await await_idle_frame()
	var stats := panel.get_node_or_null("MarginContainer/Control/StatsContainer") as Control
	var controls := panel.get_node_or_null("MarginContainer/Control/RightRailControls") as Control
	assert_object(stats).is_not_null()
	assert_object(controls).is_not_null()
	if stats == null or controls == null:
		return
	assert_float(stats.size.x).is_equal(400.0)
	assert_float(stats.size.y).is_equal(700.0)
	assert_bool(not stats.get_global_rect().intersects(controls.get_global_rect())).is_true()
	for output_width: float in [1280.0, 1600.0, 1920.0]:
		var scale := output_width / 1920.0
		var scaled_stats := Rect2(stats.position * scale, stats.size * scale)
		var scaled_controls := Rect2(controls.position * scale, controls.size * scale)
		assert_bool(not scaled_stats.intersects(scaled_controls)).is_true()


func test_shop_wallet_matches_the_combat_material_row_without_covering_health() -> void:
	# Break caught: the shop's oversized wallet is drawn over the snapshotted health bar.
	var shop := auto_free((load("res://scenes/ui/shop_panel/shop_panel.tscn") as PackedScene).instantiate()) as ShopPanel
	add_child(shop)
	await await_idle_frame()
	var wallet := shop.get_node("MarginContainer/Control/CoinsBag") as Control
	var backdrop := shop.get_node_or_null("MarginContainer/Control/WalletBackdrop") as Control
	var icon := wallet.get_node("TextureRect") as TextureRect
	var value := wallet.get_node("Coins") as Label
	var material_rect := CombatHudMetrics.logical_rect(CombatHudMetrics.MATERIALS_REFERENCE_RECT)
	var health_rect := CombatHudMetrics.logical_rect(CombatHudMetrics.HEALTH_REFERENCE_RECT)

	assert_vector(wallet.position).is_equal(material_rect.position)
	assert_vector(wallet.custom_minimum_size).is_equal(material_rect.size)
	assert_object(backdrop).is_not_null()
	if backdrop != null:
		assert_vector(backdrop.position).is_equal(material_rect.position)
		assert_vector(backdrop.size).is_equal(Vector2(150.0, material_rect.size.y))
		assert_bool(backdrop.get_index() < wallet.get_index()).is_true()
	assert_vector(icon.custom_minimum_size).is_equal(Vector2(39.0, 39.0))
	assert_int(value.label_settings.font_size).is_equal(31)
	assert_bool(not Rect2(wallet.position, wallet.custom_minimum_size).intersects(health_rect)).is_true()


const TEST_PROFILE_ROOT := "user://tests/shop_panel_profiles"

var panel: ShopPanel
var _original_provider: SaveProvider


func before_test() -> void:
	_original_provider = Global.save_provider
	var store := ProfileStore.new(TEST_PROFILE_ROOT, "")
	store.save_profile(1, {"meta_progress": MetaProgress.new().to_dict()})
	Global.save_provider = ProfileSaveProvider.new(store, 1)
	Global.end_run()
	Global.begin_run(202, null, 500)
	panel = auto_free(load("res://scenes/ui/shop_panel/shop_panel.tscn").instantiate())
	add_child(panel)
	await await_idle_frame()
	await await_idle_frame()


func after_test() -> void:
	Global.end_run()
	Global.save_provider = _original_provider
	for slot: int in range(1, ProfileStore.MAX_PROFILES + 1):
		ProfileStore.new(TEST_PROFILE_ROOT, "").delete_profile(slot)


func test_shop_card_keeps_the_legacy_purchase_signal_and_adds_detailed_metadata_separately() -> void:
	# Break caught: changing the public two-argument signal breaks old content-pack listeners.
	var card := auto_free((load("res://scenes/ui/shop_card/shop_card.tscn") as PackedScene).instantiate()) as ShopCard
	add_child(card)
	await await_idle_frame()
	assert_int(_signal_argument_count(card, &"on_item_purchased")).is_equal(2)
	assert_int(_signal_argument_count(card, &"on_item_purchased_detailed")).is_equal(3)


func test_offer_merge_preview_refreshes_when_purchase_fills_the_last_slot_and_sale_frees_it() -> void:
	# Break caught: offer text is only computed at assignment and becomes stale as slots change.
	Global.coins = 500
	var pistol := Content.catalog.get_weapon(&"weapon/pistol")
	var filler := Content.catalog.get_weapon(&"weapon/axe")
	var pistol_id := pistol.get_stable_id(Content.catalog.pack_id)
	Global.current_run.inventory.add_weapon(pistol_id, 1, 5)
	for weapon_id: StringName in [&"weapon/wand", &"weapon/spear", &"weapon/smg", &"weapon/punch"]:
		Global.current_run.inventory.add_weapon(weapon_id, 1, 5)
	Global.shop_service.store_offers(
		Global.current_run, [filler.tiers[0], pistol.tiers[0]], Content.catalog
	)
	panel.load_shop(2)
	var filler_offer := _offer_card_for_item(filler.tiers[0])
	var pistol_offer := _offer_card_for_item(pistol.tiers[0])
	assert_object(filler_offer).is_not_null()
	assert_object(pistol_offer).is_not_null()
	if filler_offer == null or pistol_offer == null:
		return
	var preview := LocalizedTextService.resolve(&"ui.shop.merge_preview", [2])
	assert_str(pistol_offer.item_description.text).not_contains(preview)

	filler_offer._on_buy_buttom_pressed()

	assert_str(pistol_offer.item_description.text).contains(preview)
	var filler_inventory_card: ItemCard
	for child: Node in panel.weapons_container.get_children():
		if child is ItemCard and (child as ItemCard).item == filler.tiers[0]:
			filler_inventory_card = child as ItemCard
			break
	assert_object(filler_inventory_card).is_not_null()
	if filler_inventory_card == null:
		return
	panel._on_item_card_selected(filler_inventory_card)
	panel._on_sell_button_pressed()

	assert_str(pistol_offer.item_description.text).not_contains(preview)


func test_purchased_weapon_projects_to_ui_without_requiring_a_runtime_player() -> void:
	var pistol := Content.catalog.get_weapon(&"weapon/pistol")
	var purchase_effect := EffectDef.new()
	purchase_effect.effect_id = &"effect/test/shop_panel_weapon_purchase"
	purchase_effect.trigger_events = [GameplayEvent.Type.PURCHASED]
	purchase_effect.conditions = [EffectConditionDef.event_has_tag(&"purchase/weapon")]
	purchase_effect.operations = [EffectOperationDef.add_stat(StatId.DAMAGE, 77.0)]
	var damage_before := Global.current_run.player_stats.get_stat(StatId.DAMAGE)
	assert_int(Global.try_purchase_item(pistol.tiers[0])).is_equal(InventoryService.OK)
	Global.gameplay_effects.register_effect(purchase_effect)

	panel._on_item_purchased(pistol.tiers[0])

	assert_int(panel.weapons_container.get_child_count()).is_equal(1)
	assert_int(Global.equipped_weapons.size()).is_equal(1)
	assert_float(Global.current_run.player_stats.get_stat(StatId.DAMAGE)).is_equal(
		damage_before + 77.0
	)


func test_auto_merge_rebuilds_weapon_cards_and_equipped_order_from_inventory() -> void:
	var pistol := Content.catalog.get_weapon(&"weapon/pistol")
	var pistol_id := pistol.get_stable_id(Content.catalog.pack_id)
	Global.current_run.inventory.add_weapon(pistol_id, 1, 20)
	for weapon_id in [&"weapon/axe", &"weapon/wand", &"weapon/spear", &"weapon/smg", &"weapon/punch"]:
		Global.current_run.inventory.add_weapon(weapon_id, 1, 5)
	Global.shop_service.store_offers(Global.current_run, [pistol.tiers[0]], Content.catalog)

	var result: Variant = Global.call("try_purchase_shop_slot_detailed", 0)

	assert_bool(result is Dictionary).is_true()
	if result is Dictionary:
		assert_str(str(result.get("mode", ""))).is_equal("auto_merge")
	panel.call("_on_item_purchased", pistol.tiers[0], 0, result)
	assert_int(panel.weapons_container.get_child_count()).is_equal(InventoryState.MAX_WEAPON_SLOTS)
	assert_int(Global.equipped_weapons.size()).is_equal(InventoryState.MAX_WEAPON_SLOTS)
	assert_int(int(Global.current_run.inventory.weapon_at(0).get("tier", 0))).is_equal(2)
	assert_int(int((panel.weapons_container.get_child(0) as ItemCard).item.item_tier)).is_equal(1)


func test_shop_refresh_price_color_updates_when_materials_change() -> void:
	Global.coins = 0
	panel.load_shop(3)

	assert_object(panel.refresh_button.get_theme_color("font_color")).is_equal(Color(1.0, 0.25, 0.25, 1.0))
	Global.add_materials(Global.shop_service.refresh_price_for_run(Global.current_run, 3))
	assert_object(panel.refresh_button.get_theme_color("font_color")).is_equal(Color.WHITE)


func test_each_shop_card_controls_only_its_own_lock() -> void:
	panel.load_shop(2)
	assert_int(panel.items_container.get_child_count()).is_equal(RunState.SHOP_SLOT_COUNT)
	var second_card := panel.items_container.get_child(1) as ShopCard
	assert_object(second_card).is_not_null()

	second_card.lock_button.button_pressed = true
	second_card.lock_button.toggled.emit(true)

	assert_bool(Global.current_run.shop_slots[0].locked).is_false()
	assert_bool(Global.current_run.shop_slots[1].locked).is_true()
	assert_bool(Global.current_run.shop_slots[2].locked).is_false()
	assert_bool(Global.current_run.shop_slots[3].locked).is_false()


func test_refresh_keeps_locked_card_in_the_same_slot() -> void:
	panel.load_shop(3)
	var locked_id := Global.current_run.shop_slots[2].offer_id
	var third_card := panel.items_container.get_child(2) as ShopCard
	third_card.lock_button.button_pressed = true
	third_card.lock_button.toggled.emit(true)

	panel._on_refresh_button_pressed()

	assert_str(String(Global.current_run.shop_slots[2].offer_id)).is_equal(String(locked_id))
	assert_bool(Global.current_run.shop_slots[2].locked).is_true()
	assert_int(panel.items_container.get_child_count()).is_equal(RunState.SHOP_SLOT_COUNT)


func test_clicking_weapon_opens_context_and_sells_the_exact_inventory_slot() -> void:
	var pistol := Content.catalog.get_weapon(&"weapon/pistol")
	var stable_id := pistol.get_stable_id(Content.catalog.pack_id)
	Global.current_run.inventory.add_weapon(stable_id, 1, 100)
	Global.current_run.inventory.add_weapon(stable_id, 1, 200)
	Global.equipped_weapons.assign([pistol.tiers[0], pistol.tiers[0]])
	panel.create_item_weapon(pistol.tiers[0], 0)
	panel.create_item_weapon(pistol.tiers[0], 1)
	var second_card := panel.weapons_container.get_child(1) as ItemCard
	var materials_before := Global.current_run.materials

	panel._on_item_card_selected(second_card)

	assert_bool(panel.weapon_context_panel.visible).is_true()
	assert_int(second_card.inventory_slot).is_equal(1)
	assert_str(panel.context_name_label.text).is_equal(
		ItemDescriptionFormatter.item_display_name(pistol.tiers[0])
	)
	assert_str(panel.context_refund_label.text).contains("150")
	panel._on_sell_button_pressed()

	assert_int(Global.current_run.inventory.weapon_count()).is_equal(1)
	assert_int(int(Global.current_run.inventory.weapon_at(0).get("paid_price", 0))).is_equal(100)
	assert_int(Global.current_run.materials).is_equal(materials_before + 150)
	assert_bool(panel.weapon_context_panel.visible).is_false()
	assert_int(panel.weapons_container.get_child_count()).is_equal(1)


func _signal_argument_count(object: Object, signal_name: StringName) -> int:
	for signal_data: Dictionary in object.get_signal_list():
		if StringName(signal_data.get("name", &"")) == signal_name:
			return (signal_data.get("args", []) as Array).size()
	return -1


func _offer_card_for_item(item: ItemBase) -> ShopCard:
	for child: Node in panel.items_container.get_children():
		if child is ShopCard and (child as ShopCard).shop_item == item:
			return child as ShopCard
	return null
