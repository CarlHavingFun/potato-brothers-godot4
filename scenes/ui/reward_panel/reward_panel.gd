extends Panel
class_name RewardPanel

signal reward_claimed(item: ItemBase)
signal reward_finished(next_phase: int)

@onready var item_icon: TextureRect = %ItemIcon
@onready var item_name: Label = %ItemName
@onready var item_description: RichTextLabel = %ItemDescription
@onready var status_label: Label = %StatusLabel

var reward_item: ItemBase


func load_reward(current_wave: int) -> bool:
	if Global.current_run == null or Global.current_run.queued_rewards <= 0:
		return false
	reward_item = Global.reward_service.select_reward(Content.catalog.get_shop_items(), current_wave)
	if reward_item == null:
		return false
	item_icon.texture = reward_item.item_icon
	item_name.text = reward_item.item_name
	item_description.text = reward_item.get_description()
	status_label.text = "Choose: claim or recycle"
	return true


func _on_claim_button_pressed() -> void:
	var result := Global.try_claim_reward_item(reward_item)
	if result != InventoryService.OK:
		status_label.text = _result_message(result)
		return
	if reward_item is ItemPassive:
		Global.apply_passive_item(reward_item as ItemPassive)
	reward_claimed.emit(reward_item)
	_finish_current_reward()


func _on_recycle_button_pressed() -> void:
	var recycled := Global.recycle_reward_item(reward_item)
	if recycled <= 0:
		status_label.text = "Reward could not be recycled"
		return
	status_label.text = "Recycled for %s materials" % recycled
	_finish_current_reward()


func _finish_current_reward() -> void:
	var next_phase := RunPhase.CHEST if Global.current_run.queued_rewards > 0 else RunPhase.SHOP
	reward_finished.emit(next_phase)


func _result_message(result: int) -> String:
	match result:
		InventoryService.NO_WEAPON_SLOT:
			return "Weapon slots are full; recycle this reward"
		InventoryService.MAX_PASSIVE_STACK:
			return "Item stack is full; recycle this reward"
		_:
			return "Reward could not be claimed"
