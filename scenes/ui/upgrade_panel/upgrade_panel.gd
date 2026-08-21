extends Panel
class_name UpgradePanel

const UPGRADE_CARD_SCENE = preload("uid://b0nwu1370004c")
const UNAFFORDABLE_PRICE_COLOR := Color(1.0, 0.25, 0.25, 1.0)

@onready var items_container: HBoxContainer = %ItemsContainer
@onready var refresh_button: Button = %RefreshButton
@onready var status_label: Label = %StatusLabel

var current_wave := 1


func _ready() -> void:
	if not Global.materials_changed.is_connected(_on_materials_changed):
		Global.materials_changed.connect(_on_materials_changed)


func _exit_tree() -> void:
	if Global.materials_changed.is_connected(_on_materials_changed):
		Global.materials_changed.disconnect(_on_materials_changed)


func load_upgrades(current_wave: int) -> void:
	self.current_wave = current_wave
	for child in items_container.get_children():
		child.queue_free()
	
	var upgrade_list: Array[ItemUpgrade] = Content.catalog.get_upgrade_items()
	var selected_upgrades := Global.reward_service.select_level_up_offers(
		upgrade_list, Global.current_run, 4, Content.catalog
	)
	for random_upg: ItemUpgrade in selected_upgrades:
		var card_instance := UPGRADE_CARD_SCENE.instantiate() as UpgradeCard
		items_container.add_child(card_instance)
		card_instance.item_data = random_upg
	_update_refresh_feedback()


func _on_refresh_button_pressed() -> void:
	if Global.current_run == null:
		return
	var result := Global.reward_service.try_refresh_upgrades(Global.current_run, current_wave)
	if result != InventoryService.OK:
		status_label.text = LocalizedTextService.resolve(&"ui.upgrade.refresh_insufficient")
		return
	Global.materials_changed.emit(Global.current_run.materials)
	load_upgrades(current_wave)
	Global.save_progress(true)


func _update_refresh_feedback() -> void:
	if Global.current_run == null:
		return
	var price := Global.reward_service.upgrade_refresh_price(Global.current_run, current_wave)
	refresh_button.text = LocalizedTextService.resolve(&"ui.upgrade.refresh", [price])
	refresh_button.add_theme_color_override(
		"font_color", Color.WHITE if Global.current_run.materials >= price else UNAFFORDABLE_PRICE_COLOR
	)
	status_label.text = LocalizedTextService.resolve(&"ui.upgrade.refresh_hint")


func _on_materials_changed(_materials: int) -> void:
	_update_refresh_feedback()
