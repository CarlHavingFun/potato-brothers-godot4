extends Resource
class_name ItemBase

enum ItemType {
	WEAPON,
	UPGRADE,
	PASSIVE
}

@export var item_name: String
@export var content_id: StringName
@export var item_icon: Texture2D
@export var item_tier: Global.UpgradeTier
@export var item_type: ItemType
@export var item_cost: int

func get_description() -> String:
	return ""


func get_stable_id() -> StringName:
	if not content_id.is_empty():
		return content_id
	if not resource_path.is_empty():
		return StringName(resource_path)
	return StringName(item_name.to_snake_case())
