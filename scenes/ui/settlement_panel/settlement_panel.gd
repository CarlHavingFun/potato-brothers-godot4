extends Panel
class_name SettlementPanel

signal retry_requested
signal title_requested

@onready var result_label: Label = %ResultLabel
@onready var details_label: Label = %DetailsLabel

var result_key := ""


func show_result(run_state: RunState, victory: bool) -> void:
	result_key = "victory" if victory else "death"
	result_label.text = (
		LocalizedTextService.resolve(&"ui.settlement.victory")
		if victory
		else LocalizedTextService.resolve(&"ui.settlement.death")
	)
	if run_state == null:
		details_label.text = LocalizedTextService.resolve(&"ui.settlement.no_data")
		return
	var character := Content.catalog.get_character(run_state.character_id)
	var character_name := ItemDescriptionFormatter.character_display_name(character)
	if run_state.run_mode == RunMode.ENDLESS:
		details_label.text = LocalizedTextService.resolve(&"ui.settlement.endless_details", [
			character_name,
			run_state.difficulty,
			maxi(run_state.wave, run_state.highest_wave_reached),
			run_state.kill_count,
			run_state.boss_kill_count,
			run_state.materials,
			_format_time(run_state.elapsed_seconds),
		])
	else:
		details_label.text = LocalizedTextService.resolve(&"ui.settlement.standard_details", [
			character_name,
			run_state.difficulty,
			run_state.wave,
			run_state.materials,
			_format_time(run_state.elapsed_seconds),
		])


func _format_time(seconds: float) -> String:
	var total := maxi(0, floori(seconds))
	return "%02d:%02d" % [total / 60, total % 60]


func _on_retry_button_pressed() -> void:
	retry_requested.emit()


func _on_title_button_pressed() -> void:
	title_requested.emit()
