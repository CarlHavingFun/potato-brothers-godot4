extends Panel
class_name UpgradePanel

const UPGRADE_CARD_SCENE = preload("uid://b0nwu1370004c")

@onready var items_container: HBoxContainer = %ItemsContainer
@onready var refresh_button: Button = %RefreshButton
@onready var status_label: Label = %StatusLabel

var current_wave := 1


func load_upgrades(current_wave: int) -> void:
	self.current_wave = current_wave
	for child in items_container.get_children():
		child.queue_free()
	
	var upgrade_list: Array[ItemUpgrade] = Content.catalog.get_upgrade_items()
	var selected_upgrades := Global.reward_service.select_unique(upgrade_list, 4)
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
		status_label.text = tr("ui.upgrade.refresh_insufficient")
		return
	Global.materials_changed.emit(Global.current_run.materials)
	load_upgrades(current_wave)
	Global.save_progress(true)


func _update_refresh_feedback() -> void:
	if Global.current_run == null:
		return
	refresh_button.text = tr("ui.upgrade.refresh") % Global.reward_service.upgrade_refresh_price(
		Global.current_run, current_wave
	)
	status_label.text = tr("ui.upgrade.refresh_hint")
