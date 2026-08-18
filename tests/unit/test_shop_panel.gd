extends GdUnitTestSuite


var panel: ShopPanel


func before_test() -> void:
	Global.end_run()
	Global.begin_run(202, null, 500)
	panel = auto_free(load("res://scenes/ui/shop_panel/shop_panel.tscn").instantiate())
	add_child(panel)
	await await_idle_frame()
	await await_idle_frame()


func after_test() -> void:
	Global.end_run()


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
