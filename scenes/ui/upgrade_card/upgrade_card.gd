extends Panel
class_name UpgradeCard

@export var item_data: ItemUpgrade: set = _set_data

@onready var item_icon: TextureRect = %Icon
@onready var item_name: Label = %Name
@onready var item_description: RichTextLabel = %Description

func _set_data(value: ItemUpgrade) -> void:
	item_data = value
	var definition := Content.catalog.get_upgrade_definition_for_item(item_data)
	item_icon.texture = Presentation.resolve_texture(
		&"pickup",
		definition.get_presentation_id(Content.catalog.pack_id) if definition != null else Content.catalog.get_item_stable_id(item_data),
		item_data.item_icon
	)
	item_name.text = ItemDescriptionFormatter.upgrade_display_name(item_data)
	item_description.text = ItemDescriptionFormatter.format_upgrade(item_data)
	
	var style := Global.get_tier_style(item_data.item_tier)
	add_theme_stylebox_override("panel", style)

func _on_custom_buttom_pressed() -> void:
	if (
		item_data
		and is_instance_valid(Global.player)
		and Global.current_run != null
		and Global.current_run.phase == RunPhase.UPGRADE
		and Global.current_run.queued_level_ups > 0
	):
		Global.apply_upgrade_item(item_data)
		GameplayCues.emit_cue(&"ui.confirm")
		Global.on_upgrade_selected.emit()
