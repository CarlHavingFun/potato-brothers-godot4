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
	assert_int(Global.try_purchase_item(pistol.tiers[0])).is_equal(InventoryService.OK)

	panel._on_item_purchased(pistol.tiers[0])

	assert_int(panel.weapons_container.get_child_count()).is_equal(1)
	assert_int(Global.equipped_weapons.size()).is_equal(1)
