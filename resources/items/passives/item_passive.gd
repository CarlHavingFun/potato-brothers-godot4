extends ItemBase
class_name ItemPassive

@export var add_value: float
@export var add_stats: String
@export var remove_value: float
@export var remove_stats: String
@export_range(1, 99, 1) var max_stack := 99

func get_description() -> String:
	var description := "[code]"
	
	if add_value != 0:
		description += "[color=green]+%s %s[/color]\n" % [add_value, add_stats]
	
	if remove_value != 0:
		description += "[color=red]-%s %s[/color]" % [remove_value, remove_stats]
	
	description += "[/code]"
	return description

func apply_passive() -> void:
	if add_value != 0:
		Global.apply_stat_change(add_stats, add_value)
	
	if remove_value != 0:
		Global.apply_stat_change(remove_stats, -remove_value)
