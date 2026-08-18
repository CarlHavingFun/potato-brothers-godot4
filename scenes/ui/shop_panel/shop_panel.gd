extends Panel
class_name ShopPanel

signal on_shop_next_wave

const SHOP_CARD_SCENE = preload("uid://csmrkxii0a74i")

@onready var items_container: HBoxContainer = %ItemsContainer
@onready var passives_container: GridContainer = %PassivesContainer
@onready var weapons_container: GridContainer = %WeaponsContainer

@onready var combine_button: Button = %CombineButton
@onready var refresh_button: Button = %RefreshButton

var context_card: ItemCard
var current_wave := 1

func _ready() -> void:
	reset_inventory()


func reset_inventory() -> void:
	_clear_children(passives_container)
	_clear_children(weapons_container)
	_clear_children(items_container)
	context_card = null
	combine_button.disabled = true

func load_shop(wave: int, force_refresh: bool = false) -> void:
	current_wave = wave
	_clear_children(items_container)
	if Global.current_run == null:
		return
	var config := Global.SHOP_PROBABILITY_CONFIG
	var shop_items: Array[ItemBase] = Content.catalog.get_shop_items()
	var occupied_families := {}
	var missing_count := 0
	for slot: ShopSlotState in Global.current_run.shop_slots:
		if not slot.locked and slot.needs_offer():
			missing_count += 1
		elif not slot.is_empty():
			occupied_families[String(slot.offer_id)] = true
	if missing_count > 0:
		var eligible_items: Array[ItemBase] = []
		for candidate: ItemBase in shop_items:
			if not occupied_families.has(String(Content.catalog.get_item_stable_id(candidate))):
				eligible_items.append(candidate)
		var selected_items: Array[ItemBase] = []
		selected_items.assign(Global.select_items_for_offer(
			eligible_items, current_wave, config, missing_count
		))
		Global.shop_service.store_offers(Global.current_run, selected_items, Content.catalog)
	for slot_index in Global.current_run.shop_slots.size():
		var shop_item := Global.shop_service.resolve_slot_offer(
			Global.current_run, slot_index, Content.catalog
		)
		if shop_item == null:
			continue
		var card_instance := SHOP_CARD_SCENE.instantiate() as ShopCard
		card_instance.on_item_purchased.connect(_on_item_purchased)
		card_instance.lock_toggled.connect(_on_slot_lock_toggled)
		items_container.add_child(card_instance)
		card_instance.shop_item = shop_item
		card_instance.configure_slot(slot_index, Global.current_run.shop_slots[slot_index].locked)
	_update_refresh_text()


func _clear_children(container: Node) -> void:
	for child: Node in container.get_children():
		child.free()


func create_item_card() -> ItemCard:
	var item_card := Global.ITEM_CARD_SCENE.instantiate() as ItemCard
	item_card.on_item_card_selected.connect(_on_item_card_selected)
	return item_card


func create_item_weapon(weapon: ItemWeapon) -> void:
	var card := create_item_card()
	weapons_container.add_child(card)
	card.item = weapon


func _on_new_wave_button_pressed() -> void:
	GameplayCues.emit_cue(&"ui.confirm")
	on_shop_next_wave.emit()


func _on_slot_lock_toggled(slot_index: int, pressed: bool) -> void:
	if Global.current_run != null:
		Global.shop_service.set_slot_locked(Global.current_run, slot_index, pressed)
		Global.save_progress()


func _on_refresh_button_pressed() -> void:
	if Global.current_run == null:
		return
	var result := Global.shop_service.try_refresh(Global.current_run, current_wave)
	if result != InventoryService.OK:
		return
	Global.materials_changed.emit(Global.current_run.materials)
	Global.dispatch_gameplay_event(GameplayEvent.Type.SHOP_REFRESHED, {"wave": current_wave})
	load_shop(current_wave, true)
	Global.save_progress()


func _update_refresh_text() -> void:
	if Global.current_run == null:
		return
	var unlocked_count := Global.current_run.shop_slots.filter(
		func(slot: ShopSlotState): return not slot.locked
	).size()
	refresh_button.text = "%s (%s)" % [tr("ui.shop.refresh"), Global.shop_service.refresh_price_for_run(
		Global.current_run, current_wave, unlocked_count
	)]


func _on_item_purchased(item: ItemBase, slot_index: int = -1) -> void:
	if Global.current_run != null and slot_index < 0:
		Global.shop_service.consume_offer(Global.current_run, item, Content.catalog)
	project_item(item)
	var purchase_tags: Array[StringName] = []
	purchase_tags.append(&"purchase/weapon" if item is ItemWeapon else &"purchase/passive")
	Global.dispatch_gameplay_event(
		GameplayEvent.Type.PURCHASED,
		{"cost": item.item_cost},
		purchase_tags
	)
	_update_refresh_text()
	Global.save_progress()


func project_item(item: ItemBase) -> void:
	var item_card := create_item_card()
	
	if item.item_type == ItemBase.ItemType.WEAPON:
		weapons_container.add_child(item_card)
		var weapon := item as ItemWeapon
		if is_instance_valid(Global.player):
			Global.player.add_weapon(weapon)
		Global.equipped_weapons.append(weapon)
	
	elif item.item_type == ItemBase.ItemType.PASSIVE:
		passives_container.add_child(item_card)
		var passive := item as ItemPassive
		Global.apply_passive_item(passive)
	
	item_card.item = item


func _on_item_card_selected(card: ItemCard) -> void:
	context_card = card
	
	var can_merge := false
	if card.item.item_type == ItemBase.ItemType.WEAPON:
		var clicked_weapon := card.item as ItemWeapon
		var count := 0
		for weapon: ItemWeapon in Global.equipped_weapons:
			if _same_weapon_family_and_tier(weapon, clicked_weapon):
				count += 1
		
		if count >= 2:
			can_merge = true
	
	combine_button.disabled = not can_merge


func _on_combine_button_pressed() -> void:
	GameplayCues.emit_cue(&"ui.confirm")
	
	if not context_card:
		return
	
	var clicked_weapon := context_card.item as ItemWeapon
	if not clicked_weapon.upgrade_to:
		return
	
	var weapons_to_remove: Array[Weapon] = Global.player.current_weapons.filter(
		func(weapon: Weapon): return _same_weapon_family_and_tier(weapon.data, clicked_weapon)
	).slice(0, 2)
	
	var card_to_remove = weapons_container.get_children().filter(
		func(card: ItemCard):
			return card.item is ItemWeapon and _same_weapon_family_and_tier(
				card.item,
				clicked_weapon
			)
	).slice(0, 2)
	
	if weapons_to_remove.size() < 2 or card_to_remove.size() < 2:
		return
	if Global.try_combine_weapon(clicked_weapon) != InventoryService.OK:
		return
	
	# Delete weapons
	for weapon: Weapon in weapons_to_remove:
		Global.player.current_weapons.erase(weapon)
		Global.equipped_weapons.erase(weapon.data)
		weapon.queue_free()
	
	# Delete cards
	for card: ItemCard in card_to_remove:
		card.queue_free()
	
	# Create new Weapon
	var upgraded_weapon: ItemWeapon = load(clicked_weapon.upgrade_to.resource_path)
	Global.player.add_weapon(upgraded_weapon)
	Global.equipped_weapons.append(upgraded_weapon)
	
	# Create new Item Card
	var new_card := create_item_card()
	weapons_container.add_child(new_card)
	new_card.item = upgraded_weapon
	
	context_card = null
	Global.save_progress()


func _on_sell_button_pressed() -> void:
	GameplayCues.emit_cue(&"ui.confirm")
	
	if not context_card:
		return
	
	var clicked_weapon := context_card.item as ItemWeapon
	var matching_weapons: Array[Weapon] = Global.player.current_weapons.filter(
		func(weapon: Weapon): return _same_weapon_family_and_tier(
			weapon.data,
			clicked_weapon
		)
	)
	var weapon_to_remove: Weapon = matching_weapons.front() if not matching_weapons.is_empty() else null
	if weapon_to_remove == null:
		return
	if Global.try_sell_weapon(clicked_weapon) != InventoryService.OK:
		return
	
	if weapon_to_remove:
		Global.player.current_weapons.erase(weapon_to_remove)
		Global.equipped_weapons.erase(weapon_to_remove.data)
		weapon_to_remove.queue_free()
	
	context_card.queue_free()
	context_card = null
	Global.save_progress()


func _same_weapon_family_and_tier(first: ItemWeapon, second: ItemWeapon) -> bool:
	return (
		first != null
		and second != null
		and Content.catalog.get_item_stable_id(first) == Content.catalog.get_item_stable_id(second)
		and first.item_tier == second.item_tier
	)
