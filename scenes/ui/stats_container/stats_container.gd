extends Panel
class_name StatsContainer

@onready var health_label: Label = %HealthLabel
@onready var hp_regen_label: Label = %HPRegenLabel
@onready var life_steal_label: Label = %LifeStealLabel
@onready var damage_label: Label = %DamageLabel
@onready var luck_label: Label = %LuckLabel
@onready var speed_label: Label = %SpeedLabel
@onready var block_label: Label = %BlockLabel
@onready var harvesting_label: Label = %HarvestingLabel

func _process(delta: float) -> void:
	if Global.current_run == null:
		return
	
	health_label.text = str(Global.get_stat_value("health"))
	hp_regen_label.text = str(Global.get_stat_value("hp_regen"))
	life_steal_label.text = str(Global.get_stat_value("life_steal")) + "%"
	damage_label.text = str(Global.get_stat_value("damage"))
	luck_label.text = str(Global.get_stat_value("luck"))
	speed_label.text = str(Global.get_stat_value("speed"))
	block_label.text = str(Global.get_stat_value("block_chance")) + "%"
	harvesting_label.text = str(Global.get_stat_value("harvesting"))
