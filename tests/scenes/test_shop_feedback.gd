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
	Global.shop_service.store_offers(Global.current_run, [pistol.tiers[0]], Content.catalog)
	var card: ShopCard = auto_free(load(SHOP_CARD_SCENE).instantiate())
	add_child(card)
	await await_idle_frame()
	card.configure_slot(0, false)
	card.shop_item = pistol.tiers[0]

	assert_str(card.item_description.text).contains("ranged")
	assert_str(card.item_description.text).contains("合成")
	card.call("_on_buy_buttom_pressed")
	assert_str(card.status_label.text).contains("材料不足")


func test_shop_slot_lock_has_visible_independent_feedback() -> void:
	Global.begin_run(809, null, 0)
	var card: ShopCard = auto_free(load(SHOP_CARD_SCENE).instantiate())
	add_child(card)
	await await_idle_frame()
	card.configure_slot(2, true)

	assert_bool(card.lock_button.button_pressed).is_true()
	assert_str(card.status_label.text).contains("已锁定")
