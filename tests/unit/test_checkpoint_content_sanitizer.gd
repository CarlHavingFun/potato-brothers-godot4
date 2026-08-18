extends GdUnitTestSuite


func test_locked_deleted_shop_offer_is_cleared_unlocked_and_fillable() -> void:
	var checkpoint := _valid_checkpoint()
	var valid_item := Content.catalog.get_shop_items()[0]
	checkpoint.shop_slots[0].set_offer(
		&"core:weapon/deleted_family",
		1,
		ItemBase.ItemType.WEAPON
	)
	checkpoint.shop_slots[0].locked = true
	checkpoint.shop_slots[1].set_offer(
		Content.catalog.get_item_stable_id(valid_item),
		int(valid_item.item_tier) + 1,
		int(valid_item.item_type)
	)
	checkpoint.shop_slots[1].locked = true
	var valid_slot_snapshot := checkpoint.shop_slots[1].to_dict()
	var sanitizer := CheckpointContentSanitizer.new()

	var repaired := sanitizer.sanitize(checkpoint, Content.catalog)

	assert_object(repaired).is_not_null()
	assert_bool(repaired.shop_slots[0].locked).is_false()
	assert_bool(repaired.shop_slots[0].purchased).is_false()
	assert_bool(repaired.shop_slots[0].needs_offer()).is_true()
	assert_dict(repaired.shop_slots[1].to_dict()).is_equal(valid_slot_snapshot)
	assert_array(sanitizer.repair_notice_keys).contains_exactly([
		CheckpointContentSanitizer.NOTICE_SHOP,
	])


func test_missing_character_starter_and_inventory_refs_use_safe_localized_fallbacks() -> void:
	var checkpoint := _valid_checkpoint()
	checkpoint.character_id = &"retired_skin:character/deleted"
	checkpoint.starting_weapon_id = &"retired_skin:weapon/deleted"
	checkpoint.inventory = InventoryState.new()
	checkpoint.inventory.weapon_slot_limit = 3
	checkpoint.inventory.add_weapon(&"retired_skin:weapon/deleted", 4, 777)
	checkpoint.inventory.add_passive(&"retired_skin:passive/deleted", 2)
	var sanitizer := CheckpointContentSanitizer.new()

	var repaired := sanitizer.sanitize(checkpoint, Content.catalog)

	assert_object(repaired).is_not_null()
	assert_object(Content.catalog.get_character(repaired.character_id)).is_not_null()
	assert_object(Content.catalog.get_weapon(repaired.starting_weapon_id)).is_not_null()
	assert_int(repaired.inventory.weapon_slot_limit).is_equal(3)
	assert_int(repaired.inventory.weapon_count()).is_equal(1)
	assert_str(str(repaired.inventory.weapon_at(0).get("weapon_id", ""))).is_equal(
		str(repaired.starting_weapon_id)
	)
	assert_array(sanitizer.repair_notice_keys).contains_exactly([
		CheckpointContentSanitizer.NOTICE_CHARACTER,
		CheckpointContentSanitizer.NOTICE_INVENTORY,
		CheckpointContentSanitizer.NOTICE_STARTER,
	])
	for notice_key: StringName in sanitizer.repair_notice_keys:
		assert_str(String(notice_key)).starts_with("ui.profile.repair.")
		assert_str(LocalizedTextService.resolve(notice_key)).is_not_equal(String(notice_key))


func test_valid_checkpoint_is_preserved_byte_for_byte() -> void:
	var checkpoint := _valid_checkpoint()
	# Local catalog aliases are valid references too. Resume repair must not act
	# as an implicit ID migration when no referenced content was removed.
	var starter_local_id := StringName(
		str(checkpoint.starting_weapon_id).split(":", true, 1)[1]
	)
	checkpoint.starting_weapon_id = starter_local_id
	checkpoint.inventory = InventoryState.new()
	checkpoint.inventory.add_weapon(starter_local_id, 1, 20)
	var shop_item := Content.catalog.get_shop_items()[0]
	checkpoint.shop_slots[2].set_offer(
		Content.catalog.get_item_stable_id(shop_item),
		int(shop_item.item_tier) + 1,
		int(shop_item.item_type)
	)
	checkpoint.shop_slots[2].locked = true
	var expected := checkpoint.to_dict()
	var sanitizer := CheckpointContentSanitizer.new()

	var repaired := sanitizer.sanitize(checkpoint, Content.catalog)

	assert_dict(repaired.to_dict()).is_equal(expected)
	assert_array(sanitizer.repair_notice_keys).is_empty()


func _valid_checkpoint() -> RunState:
	var character := Content.catalog.get_character(&"character/well_rounded")
	if character == null:
		character = Content.catalog.get_characters()[0]
	var starter := Content.catalog.get_weapon(character.starter_weapon_ids[0])
	var checkpoint := RunState.new(7041)
	checkpoint.character_id = character.get_stable_id(Content.catalog.pack_id)
	checkpoint.starting_weapon_id = starter.get_stable_id(Content.catalog.pack_id)
	checkpoint.phase = RunPhase.SHOP
	checkpoint.wave = 7
	checkpoint.highest_wave_reached = 7
	checkpoint.inventory.add_weapon(checkpoint.starting_weapon_id, 1, starter.tiers[0].item_cost)
	return checkpoint
