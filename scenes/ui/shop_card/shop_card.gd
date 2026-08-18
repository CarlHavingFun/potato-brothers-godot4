extends Panel
class_name ShopCard

signal on_item_purchased(item: ItemBase, slot_index: int)
signal lock_toggled(slot_index: int, locked: bool)

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
	material_icon.texture = Presentation.resolve_texture(&"pickup", &"pickup.material")


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready() and shop_item != null:
		_set_shop_item(shop_item)
		status_label.text = tr("ui.shop.slot_locked") if lock_button.button_pressed else ""


func configure_slot(index: int, locked: bool) -> void:
	slot_index = index
	lock_button.set_pressed_no_signal(locked)
	status_label.text = tr("ui.shop.slot_locked") if locked else ""

func _set_shop_item(value: ItemBase) -> void:
	shop_item = value
	var definition: WeaponDef = (
		Content.catalog.get_weapon(Content.catalog.get_item_stable_id(value))
		if value is ItemWeapon
		else null
	)
	item_icon.texture = Presentation.resolve_texture(
		&"weapon" if value is ItemWeapon else &"pickup",
		definition.get_presentation_id(Content.catalog.pack_id) if definition != null else Content.catalog.get_item_stable_id(value),
		value.item_icon
	)
	item_name.text = Content.catalog.get_item_display_name(value)
	item_type.text = Content.catalog.get_item_type_display_name(value.item_type)
	item_description.text = _build_detail_text(value)
	coins_label.text = str(
		Global.shop_service.purchase_price(Global.current_run, value)
		if Global.shop_service != null
		else value.item_cost
	)
	
	var style := Global.get_tier_style(value.item_tier)
	add_theme_stylebox_override("panel", style)


func _on_buy_buttom_pressed() -> void:
	GameplayCues.emit_cue(&"ui.purchase")

	var result := Global.try_purchase_shop_slot(slot_index)
	if result != InventoryService.OK:
		status_label.text = _purchase_failure_message(result)
		return
	on_item_purchased.emit(shop_item, slot_index)
	queue_free()


func _on_lock_button_toggled(pressed: bool) -> void:
	status_label.text = tr("ui.shop.slot_locked") if pressed else tr("ui.shop.slot_unlocked")
	lock_toggled.emit(slot_index, pressed)


func _build_detail_text(value: ItemBase) -> String:
	var lines: Array[String] = []
	var description := value.get_description()
	if not description.is_empty():
		lines.append(description)
	var stable_id := Content.catalog.get_item_stable_id(value)
	var definition: ContentDef = (
		Content.catalog.get_weapon(stable_id)
		if value is ItemWeapon
		else Content.catalog.get_passive(stable_id)
	)
	if definition != null and not definition.tags.is_empty():
		lines.append(tr("ui.shop.tags") % " / ".join(definition.tags.map(
			func(tag: StringName): return Content.catalog.get_tag_display_name(tag)
		)))
	if value is ItemWeapon and Global.current_run != null:
		var tier := int(value.item_tier) + 1
		if not Global.current_run.inventory.find_weapon_slots(stable_id, tier).is_empty() and tier < InventoryState.MAX_WEAPON_TIER:
			lines.append(tr("ui.shop.merge_preview") % (tier + 1))
		var weapon := value as ItemWeapon
		if weapon.stats != null:
			lines.append(tr("ui.shop.weapon_stats") % [
				weapon.stats.damage, weapon.stats.cooldown, weapon.stats.max_range,
			])
	return "\n".join(lines)


func _purchase_failure_message(result: int) -> String:
	match result:
		InventoryService.INSUFFICIENT_MATERIALS:
			return tr("ui.shop.failure.materials")
		InventoryService.NO_WEAPON_SLOT:
			return tr("ui.shop.failure.weapon_slots")
		InventoryService.MAX_PASSIVE_STACK:
			return tr("ui.shop.failure.stack")
		_:
			return tr("ui.shop.failure.generic")
