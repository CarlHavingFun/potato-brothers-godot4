extends Panel
class_name ShopPanel

signal on_shop_next_wave

const SHOP_CARD_SCENE = preload("uid://csmrkxii0a74i")
const UNAFFORDABLE_PRICE_COLOR := Color(1.0, 0.25, 0.25, 1.0)

@onready var items_container: HBoxContainer = %ItemsContainer
@onready var passives_container: GridContainer = %PassivesContainer
@onready var weapons_container: GridContainer = %WeaponsContainer

@onready var combine_button: Button = %CombineButton
@onready var sell_button: Button = %SellButton
@onready var close_button: Button = %CloseButton
@onready var refresh_button: Button = %RefreshButton
@onready var weapon_context_panel: PanelContainer = %WeaponContextPanel
@onready var context_name_label: Label = %ContextName
@onready var context_details_label: RichTextLabel = %ContextDetails
@onready var context_refund_label: Label = %ContextRefund

var context_card: ItemCard
var current_wave := 1

func _ready() -> void:
	combine_button.focus_neighbor_right = sell_button.get_path()
	sell_button.focus_neighbor_left = combine_button.get_path()
	sell_button.focus_neighbor_right = close_button.get_path()
	close_button.focus_neighbor_left = sell_button.get_path()
	if not Global.materials_changed.is_connected(_on_materials_changed):
		Global.materials_changed.connect(_on_materials_changed)
	reset_inventory()


func _exit_tree() -> void:
	if Global.materials_changed.is_connected(_on_materials_changed):
		Global.materials_changed.disconnect(_on_materials_changed)


func reset_inventory() -> void:
	_clear_children(passives_container)
	_clear_children(weapons_container)
	_clear_children(items_container)
	context_card = null
	combine_button.disabled = true
	weapon_context_panel.hide()

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
		card_instance.on_item_purchased_detailed.connect(_on_item_purchased)
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


func create_item_weapon(weapon: ItemWeapon, inventory_slot: int = -1) -> void:
	var card := create_item_card()
	weapons_container.add_child(card)
	card.inventory_slot = (
		inventory_slot if inventory_slot >= 0 else weapons_container.get_child_count() - 1
	)
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
	var price := Global.shop_service.refresh_price_for_run(
		Global.current_run, current_wave, unlocked_count
	)
	refresh_button.text = "%s (%s)" % [LocalizedTextService.resolve(&"ui.shop.refresh"), price]
	refresh_button.add_theme_color_override(
		"font_color", Color.WHITE if Global.current_run.materials >= price else UNAFFORDABLE_PRICE_COLOR
	)


func _on_materials_changed(_materials: int) -> void:
	_update_refresh_text()


func _on_item_purchased(item: ItemBase, slot_index: int = -1, result: Dictionary = {}) -> void:
	if Global.current_run != null and slot_index < 0:
		Global.shop_service.consume_offer(Global.current_run, item, Content.catalog)
	if result.get("mode", InventoryService.PURCHASE_MODE_NONE) == InventoryService.PURCHASE_MODE_AUTO_MERGE:
		_rebuild_weapon_cards_from_inventory()
	else:
		project_item(item)
		_refresh_offer_card_purchase_context()
	var purchase_tags: Array[StringName] = []
	purchase_tags.append(&"purchase/weapon" if item is ItemWeapon else &"purchase/passive")
	Global.dispatch_gameplay_event(
		GameplayEvent.Type.PURCHASED,
		{"cost": item.item_cost},
		purchase_tags
	)
	_update_refresh_text()
	Global.save_progress()


func project_item(item: ItemBase, apply_passive_effects := true) -> void:
	if item.item_type == ItemBase.ItemType.WEAPON:
		var weapon := item as ItemWeapon
		create_item_weapon(
			weapon,
			Global.current_run.inventory.weapon_count() - 1 if Global.current_run != null else -1
		)
		if is_instance_valid(Global.player):
			Global.player.add_weapon(weapon)
		Global.equipped_weapons.append(weapon)
	
	elif item.item_type == ItemBase.ItemType.PASSIVE:
		var item_card := create_item_card()
		passives_container.add_child(item_card)
		var passive := item as ItemPassive
		if apply_passive_effects:
			Global.apply_passive_item(passive)
		item_card.item = item


func _on_item_card_selected(card: ItemCard) -> void:
	context_card = card
	if card == null or not card.item is ItemWeapon:
		_close_weapon_context()
		return
	var can_merge := false
	var clicked_weapon := card.item as ItemWeapon
	var count := 0
	for weapon: ItemWeapon in Global.equipped_weapons:
		if _same_weapon_family_and_tier(weapon, clicked_weapon):
			count += 1
	can_merge = count >= 2 and clicked_weapon.upgrade_to != null
	combine_button.disabled = not can_merge
	context_name_label.text = ItemDescriptionFormatter.item_display_name(clicked_weapon)
	context_details_label.text = ItemDescriptionFormatter.format_weapon(
		clicked_weapon,
		Global.current_run.player_stats if Global.current_run != null else null
	)
	context_refund_label.text = LocalizedTextService.resolve(
		&"ui.shop.context.refund", [_sell_refund_for_slot(card.inventory_slot)]
	)
	weapon_context_panel.show()
	_position_weapon_context(card)
	sell_button.grab_focus()


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
	
	if weapons_to_remove.size() < 2:
		return
	if Global.try_combine_weapon(clicked_weapon) != InventoryService.OK:
		return
	
	# Delete weapons
	for weapon: Weapon in weapons_to_remove:
		Global.player.current_weapons.erase(weapon)
		Global.equipped_weapons.erase(weapon.data)
		weapon.queue_free()
	
	# Create new Weapon
	var upgraded_weapon: ItemWeapon = load(clicked_weapon.upgrade_to.resource_path)
	Global.player.add_weapon(upgraded_weapon)
	Global.equipped_weapons.append(upgraded_weapon)
	_close_weapon_context(false)
	_rebuild_weapon_cards_from_inventory()
	Global.save_progress()


func _on_sell_button_pressed() -> void:
	GameplayCues.emit_cue(&"ui.confirm")
	
	if not context_card:
		return
	
	var inventory_slot := context_card.inventory_slot
	var weapon_to_remove: Weapon
	if is_instance_valid(Global.player) and inventory_slot >= 0 and inventory_slot < Global.player.current_weapons.size():
		weapon_to_remove = Global.player.current_weapons[inventory_slot]
	if Global.try_sell_weapon_slot(inventory_slot) != InventoryService.OK:
		return
	if is_instance_valid(weapon_to_remove):
		Global.player.current_weapons.erase(weapon_to_remove)
		weapon_to_remove.queue_free()
	if inventory_slot >= 0 and inventory_slot < Global.equipped_weapons.size():
		Global.equipped_weapons.remove_at(inventory_slot)
	_close_weapon_context(false)
	_rebuild_weapon_cards_from_inventory()
	Global.save_progress()


func _close_weapon_context(restore_card_focus := true) -> void:
	var restore_focus := context_card
	weapon_context_panel.hide()
	context_card = null
	combine_button.disabled = true
	if restore_card_focus and is_instance_valid(restore_focus):
		restore_focus.grab_focus.call_deferred()


func _position_weapon_context(card: ItemCard) -> void:
	if not is_instance_valid(card):
		return
	var viewport_rect := get_viewport_rect()
	var desired := card.global_position + Vector2(card.size.x + 12.0, -80.0)
	var panel_size := weapon_context_panel.size
	weapon_context_panel.global_position = Vector2(
		clampf(desired.x, 12.0, maxf(12.0, viewport_rect.size.x - panel_size.x - 12.0)),
		clampf(desired.y, 12.0, maxf(12.0, viewport_rect.size.y - panel_size.y - 12.0))
	)


func _sell_refund_for_slot(slot: int) -> int:
	if Global.current_run == null:
		return 0
	var entry := Global.current_run.inventory.weapon_at(slot)
	return floori(
		int(entry.get("paid_price", 0))
		* 0.75
		* Global.current_run.recycle_value_multiplier
	)


func _rebuild_weapon_cards_from_inventory() -> void:
	_clear_children(weapons_container)
	if Global.current_run == null:
		return
	for slot: int in Global.current_run.inventory.weapon_count():
		var entry := Global.current_run.inventory.weapon_at(slot)
		var item := Content.catalog.get_weapon_tier(
			StringName(str(entry.get("weapon_id", ""))), int(entry.get("tier", 0))
		)
		if item != null:
			create_item_weapon(item, slot)
	_refresh_offer_card_purchase_context()


func _refresh_offer_card_purchase_context() -> void:
	for child: Node in items_container.get_children():
		if child is ShopCard and not child.is_queued_for_deletion():
			(child as ShopCard).refresh_purchase_context()


func _unhandled_input(event: InputEvent) -> void:
	if weapon_context_panel.visible and event.is_action_pressed(&"ui_cancel"):
		_close_weapon_context()
		get_viewport().set_input_as_handled()
	elif (
		weapon_context_panel.visible
		and event is InputEventMouseButton
		and (event as InputEventMouseButton).pressed
		and not weapon_context_panel.get_global_rect().has_point(
			(event as InputEventMouseButton).position
		)
	):
		_close_weapon_context(false)


func _same_weapon_family_and_tier(first: ItemWeapon, second: ItemWeapon) -> bool:
	return (
		first != null
		and second != null
		and Content.catalog.get_item_stable_id(first) == Content.catalog.get_item_stable_id(second)
		and first.item_tier == second.item_tier
	)
