extends GdUnitTestSuite


const SHOP_CARD_SCENE := "res://scenes/ui/shop_card/shop_card.tscn"


func after_test() -> void:
	Global.end_run()


func test_shop_card_shows_failure_reason_build_tags_and_merge_preview() -> void:
	Global.begin_run(808, null, 0)
	Global.current_run.materials = 0
	var pistol := Content.catalog.get_weapon(&"weapon/pistol")
	Global.current_run.inventory.add_weapon(
		pistol.get_stable_id(Content.catalog.pack_id), 1, pistol.tiers[0].item_cost
	)
	for weapon_id in [&"axe", &"wand", &"spear", &"smg", &"punch"]:
		Global.current_run.inventory.add_weapon(weapon_id, 1, 5)
	Global.shop_service.store_offers(Global.current_run, [pistol.tiers[0]], Content.catalog)
	var card: ShopCard = auto_free(load(SHOP_CARD_SCENE).instantiate())
	add_child(card)
	await await_idle_frame()
	card.configure_slot(0, false)
	card.shop_item = pistol.tiers[0]

	assert_str(card.item_description.text).contains(Content.catalog.get_tag_display_name(&"ranged"))
	assert_str(card.item_description.text).contains(tr("ui.shop.merge_preview") % 2)
	card.call("_on_buy_buttom_pressed")
	assert_str(card.status_label.text).is_equal(tr("ui.shop.failure.materials"))


func test_shop_card_shows_merge_preview_only_for_a_valid_full_inventory_merge() -> void:
	Global.begin_run(810, null, 200)
	var pistol := Content.catalog.get_weapon(&"weapon/pistol")
	Global.current_run.inventory.add_weapon(
		pistol.get_stable_id(Content.catalog.pack_id), 1, pistol.tiers[0].item_cost
	)
	var card: ShopCard = auto_free(load(SHOP_CARD_SCENE).instantiate())
	add_child(card)
	await await_idle_frame()
	card.shop_item = pistol.tiers[0]

	assert_bool(card.item_description.text.contains(tr("ui.shop.merge_preview") % 2)).is_false()


func test_shop_card_price_color_updates_immediately_when_materials_change() -> void:
	Global.begin_run(811, null, 0)
	var pistol := Content.catalog.get_weapon(&"weapon/pistol")
	Global.shop_service.store_offers(Global.current_run, [pistol.tiers[0]], Content.catalog)
	var card: ShopCard = auto_free(load(SHOP_CARD_SCENE).instantiate())
	add_child(card)
	await await_idle_frame()
	card.configure_slot(0, false)
	card.shop_item = pistol.tiers[0]

	assert_object(card.coins_label.modulate).is_equal(Color(1.0, 0.25, 0.25, 1.0))
	Global.add_materials(Global.shop_service.purchase_price(Global.current_run, pistol.tiers[0]))
	assert_object(card.coins_label.modulate).is_equal(Color.WHITE)


func test_shop_slot_lock_has_visible_independent_feedback() -> void:
	Global.begin_run(809, null, 0)
	var card: ShopCard = auto_free(load(SHOP_CARD_SCENE).instantiate())
	add_child(card)
	await await_idle_frame()
	card.configure_slot(2, true)

	assert_bool(card.lock_button.button_pressed).is_true()
	assert_str(card.status_label.text).is_equal(tr("ui.shop.slot_locked"))
