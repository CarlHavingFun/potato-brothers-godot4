extends Panel
class_name ShopCard

signal on_item_purchased(item: ItemBase, slot_index: int)
signal on_item_purchased_detailed(item: ItemBase, slot_index: int, result: Dictionary)
signal lock_toggled(slot_index: int, locked: bool)

const UNAFFORDABLE_PRICE_COLOR := Color(1.0, 0.25, 0.25, 1.0)

@export var shop_item: ItemBase: set = _set_shop_item
var slot_index := -1

@onready var item_icon: TextureRect = %ItemIcon
@onready var item_name: Label = %ItemName
@onready var item_type: Label = %ItemType
@onready var item_description: RichTextLabel = %ItemDescription
@onready var coins_label: Label = %CoinsLabel
@onready var lock_button: Button = %LockButton
@onready var status_label: Label = %StatusLabel
@onready var material_icon: TextureRect = $MarginContainer/Control/BuyButtom/HBoxContainer/TextureRect


func _ready() -> void:
	item_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	material_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	material_icon.texture = Presentation.resolve_texture(&"pickup", &"pickup.material")
	if not Global.materials_changed.is_connected(_on_materials_changed):
		Global.materials_changed.connect(_on_materials_changed)
	_update_price_feedback()


func _exit_tree() -> void:
	if Global.materials_changed.is_connected(_on_materials_changed):
		Global.materials_changed.disconnect(_on_materials_changed)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready() and shop_item != null:
		_set_shop_item(shop_item)
		status_label.text = (
			LocalizedTextService.resolve(&"ui.shop.slot_locked")
			if lock_button.button_pressed
			else ""
		)


func configure_slot(index: int, locked: bool) -> void:
	slot_index = index
	lock_button.set_pressed_no_signal(locked)
	status_label.text = LocalizedTextService.resolve(&"ui.shop.slot_locked") if locked else ""

func _set_shop_item(value: ItemBase) -> void:
	shop_item = value
	var definition := Content.catalog.get_item_definition(value)
	item_icon.texture = Presentation.resolve_content_texture(
		definition,
		value.item_icon,
		&"icon",
		Content.catalog.pack_id
	)
	item_name.text = ItemDescriptionFormatter.item_display_name(value)
	item_type.text = ItemDescriptionFormatter.item_type_display_name(value.item_type)
	item_description.text = _build_detail_text(value)
	_update_price_feedback()
	
	var style := Global.get_tier_style(value.item_tier)
	add_theme_stylebox_override("panel", style)


func _on_buy_buttom_pressed() -> void:
	GameplayCues.emit_cue(&"ui.purchase")

	var result := Global.try_purchase_shop_slot_detailed(slot_index)
	if int(result.get("code", InventoryService.INVALID_REQUEST)) != InventoryService.OK:
		status_label.text = _purchase_failure_message(int(result.get("code", InventoryService.INVALID_REQUEST)))
		return
	on_item_purchased.emit(shop_item, slot_index)
	on_item_purchased_detailed.emit(shop_item, slot_index, result)
	queue_free()


func _on_lock_button_toggled(pressed: bool) -> void:
	status_label.text = (
		LocalizedTextService.resolve(&"ui.shop.slot_locked")
		if pressed
		else LocalizedTextService.resolve(&"ui.shop.slot_unlocked")
	)
	lock_toggled.emit(slot_index, pressed)


func _build_detail_text(value: ItemBase) -> String:
	var lines: Array[String] = [ItemDescriptionFormatter.format_item(
		value, Global.current_run.player_stats if Global.current_run != null else null
	)]
	var stable_id := Content.catalog.get_item_stable_id(value)
	if value is ItemWeapon and Global.current_run != null:
		var tier := int(value.item_tier) + 1
		if Global.current_run.inventory.find_auto_merge_slot(stable_id, tier) >= 0:
			lines.append(LocalizedTextService.resolve(&"ui.shop.merge_preview", [tier + 1]))
	return "\n".join(lines)


func _on_materials_changed(_materials: int) -> void:
	_update_price_feedback()


func refresh_purchase_context() -> void:
	if shop_item == null or not is_node_ready():
		return
	item_description.text = _build_detail_text(shop_item)
	_update_price_feedback()


func _update_price_feedback() -> void:
	if not is_instance_valid(coins_label) or shop_item == null:
		return
	var price := (
		Global.shop_service.purchase_price(Global.current_run, shop_item)
		if Global.shop_service != null
		else shop_item.item_cost
	)
	coins_label.text = str(price)
	var materials := Global.current_run.materials if Global.current_run != null else 0
	coins_label.modulate = Color.WHITE if materials >= price else UNAFFORDABLE_PRICE_COLOR


func _purchase_failure_message(result: int) -> String:
	match result:
		InventoryService.INSUFFICIENT_MATERIALS:
			return LocalizedTextService.resolve(&"ui.shop.failure.materials")
		InventoryService.NO_WEAPON_SLOT:
			return LocalizedTextService.resolve(&"ui.shop.failure.weapon_slots")
		InventoryService.MAX_PASSIVE_STACK:
			return LocalizedTextService.resolve(&"ui.shop.failure.stack")
		_:
			return LocalizedTextService.resolve(&"ui.shop.failure.generic")
