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
	var category := &"weapon" if reward_item is ItemWeapon else &"pickup"
	var stable_id := Content.catalog.get_item_stable_id(reward_item)
	var definition: ContentDef = (
		Content.catalog.get_weapon(stable_id)
		if reward_item is ItemWeapon
		else Content.catalog.get_passive(stable_id)
	)
	item_icon.texture = Presentation.resolve_texture(
		category,
		definition.get_presentation_id(Content.catalog.pack_id) if definition != null else stable_id,
		reward_item.item_icon
	)
	item_name.text = Content.catalog.get_item_display_name(reward_item)
	item_description.text = reward_item.get_description()
	status_label.text = tr("ui.reward.choose")
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
		status_label.text = tr("ui.reward.recycle_failed")
		return
	status_label.text = tr("ui.reward.recycled") % recycled
	_finish_current_reward()


func _finish_current_reward() -> void:
	var next_phase := RunPhase.CHEST if Global.current_run.queued_rewards > 0 else RunPhase.SHOP
	reward_finished.emit(next_phase)


func _result_message(result: int) -> String:
	match result:
		InventoryService.NO_WEAPON_SLOT:
			return tr("ui.reward.weapon_slots_full")
		InventoryService.MAX_PASSIVE_STACK:
			return tr("ui.reward.stack_full")
		_:
			return tr("ui.reward.claim_failed")
