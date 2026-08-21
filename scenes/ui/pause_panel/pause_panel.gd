extends Panel
class_name PausePanel

signal resume_requested
signal settings_requested
signal title_requested

@onready var weapons_label: Label = %WeaponsLabel
@onready var items_label: Label = %ItemsLabel
@onready var progress_label: Label = %ProgressLabel
@onready var stats_container: StatsContainer = %StatsContainer
@onready var weapons_title: Label = $Content/Loadout/WeaponsTitle
@onready var items_title: Label = $Content/Loadout/ItemsTitle
@onready var progress_title: Label = $Content/RunProgress/Title


func _ready() -> void:
	_refresh_static_text()


func refresh_from_run(run: RunState) -> void:
	_refresh_static_text()
	if run == null:
		weapons_label.text = "—"
		items_label.text = "—"
		progress_label.text = "—"
		return
	var weapons: Array[String] = []
	for entry: Dictionary in run.inventory.to_dict().get("weapons", []):
		var weapon_id := StringName(str(entry.get("weapon_id", "")))
		var tier := int(entry.get("tier", 1))
		var item := Content.catalog.get_weapon_tier(weapon_id, tier)
		var display_name := (
			ItemDescriptionFormatter.item_display_name(item)
			if item != null
			else LocalizedTextService.resolve(&"ui.item.unnamed")
		)
		weapons.append(LocalizedTextService.resolve(&"ui.pause.weapon_entry", [display_name, tier]))
	weapons_label.text = (
		"\n".join(weapons)
		if not weapons.is_empty()
		else LocalizedTextService.resolve(&"ui.pause.no_weapons")
	)
	var items: Array[String] = []
	var passives: Variant = run.inventory.to_dict().get("passives", {})
	if passives is Dictionary:
		for passive_id: Variant in passives:
			var definition := Content.catalog.get_passive(StringName(str(passive_id)))
			var display_name := (
				ItemDescriptionFormatter.item_display_name(definition.item)
				if definition != null and definition.item != null
				else LocalizedTextService.resolve(&"ui.item.unnamed")
			)
			items.append(LocalizedTextService.resolve(
				&"ui.pause.item_entry", [display_name, int(passives[passive_id])]
			))
	items_label.text = (
		"\n".join(items)
		if not items.is_empty()
		else LocalizedTextService.resolve(&"ui.pause.no_items")
	)
	progress_label.text = LocalizedTextService.resolve(
		&"ui.pause.progress.endless" if run.run_mode == RunMode.ENDLESS else &"ui.hud.wave.standard",
		[run.wave]
	)
	stats_container.refresh_stats()


func _refresh_static_text() -> void:
	weapons_title.text = LocalizedTextService.resolve(&"ui.pause.weapons")
	items_title.text = LocalizedTextService.resolve(&"ui.pause.items")
	progress_title.text = LocalizedTextService.resolve(&"ui.pause.progress")


func _on_resume_button_pressed() -> void:
	resume_requested.emit()


func _on_settings_button_pressed() -> void:
	settings_requested.emit()


func _on_title_button_pressed() -> void:
	title_requested.emit()
