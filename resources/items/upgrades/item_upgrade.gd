extends ItemBase
class_name ItemUpgrade

@export var value: float
@export var description: String
@export var stat_id: String

func apply_upgrade() -> void:
	Global.apply_stat_change(stat_id, value)
