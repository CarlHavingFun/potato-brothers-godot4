extends Panel
class_name SettlementPanel

signal retry_requested
signal title_requested

@onready var result_label: Label = %ResultLabel
@onready var details_label: Label = %DetailsLabel

var result_key := ""


func show_result(run_state: RunState, victory: bool) -> void:
	result_key = "victory" if victory else "death"
	result_label.text = "VICTORY" if victory else "RUN ENDED"
	if run_state == null:
		details_label.text = "No run data"
		return
	details_label.text = "Character: %s\nDifficulty: %s\nWave: %s / 10\nMaterials: %s\nTime: %s" % [
		String(run_state.character_id),
		run_state.difficulty,
		run_state.wave,
		run_state.materials,
		_format_time(run_state.elapsed_seconds),
	]


func _format_time(seconds: float) -> String:
	var total := maxi(0, floori(seconds))
	return "%02d:%02d" % [total / 60, total % 60]


func _on_retry_button_pressed() -> void:
	retry_requested.emit()


func _on_title_button_pressed() -> void:
	title_requested.emit()
