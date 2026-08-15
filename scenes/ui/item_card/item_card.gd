extends Button
class_name ItemCard

signal on_item_card_selected(card: ItemCard)

@export var item: ItemBase: set = _set_item

@onready var item_icon: TextureRect = $ItemIcon

func _set_item(value: ItemBase) -> void:
	item = value
	var definition := Content.catalog.get_item_definition(item)
	item_icon.texture = Presentation.resolve_texture(
		&"weapon" if item is ItemWeapon else &"pickup",
		definition.get_presentation_id(Content.catalog.pack_id) if definition != null else Content.catalog.get_item_stable_id(item),
		item.item_icon
	)
	
	var style := Global.get_tier_style(item.item_tier)
	add_theme_stylebox_override("normal", style)


func _on_pressed() -> void:
	GameplayCues.emit_cue(&"ui.confirm")
	if item.item_type == ItemBase.ItemType.WEAPON:
		on_item_card_selected.emit(self)
