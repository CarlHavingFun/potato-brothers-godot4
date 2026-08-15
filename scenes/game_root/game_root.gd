class_name GameRoot
extends Node


@onready var arena: Arena = $Arena
@onready var frontend: FrontendShell = $FrontendLayer/FrontendShell
@onready var codex: CodexPanel = $FrontendLayer/CodexPanel


func _ready() -> void:
	frontend.run_requested.connect(launch_run)
	frontend.continue_requested.connect(_continue_run)
	frontend.settings_requested.connect(_show_settings)
	frontend.quit_requested.connect(_quit_game)
	frontend.codex_requested.connect(_show_codex)
	codex.closed.connect(_on_codex_closed)
	arena.frontend_requested.connect(_show_frontend)
	arena.settings_panel.closed.connect(_on_settings_closed)
	_hide_legacy_frontend()
	_set_combat_hud_visible(false)
	frontend.show()


func launch_run(request: RunLaunchRequest) -> bool:
	if not arena.launch_run(request):
		return false
	frontend.hide()
	_set_combat_hud_visible(true)
	return true


func return_to_frontend() -> void:
	arena.reset_to_title()


func _show_frontend() -> void:
	_hide_legacy_frontend()
	_set_combat_hud_visible(false)
	frontend.reset_to_title()
	frontend.show()


func _hide_legacy_frontend() -> void:
	for panel: Control in [arena.title_panel, arena.selection_panel, arena.difficulty_panel]:
		panel.hide()


func _set_combat_hud_visible(value: bool) -> void:
	arena.wave_index_label.visible = value
	arena.wave_time_label.visible = value
	arena.coins_bag.visible = value


func _continue_run() -> void:
	Global.load_progress()
	if Global.restored_run == null:
		frontend.begin_new_run()
		return
	if bool(arena.call("resume_checkpoint", Global.restored_run)):
		frontend.hide()
		_set_combat_hud_visible(true)


func _show_settings() -> void:
	frontend.hide()
	arena._on_settings_requested()


func _on_settings_closed() -> void:
	if not Global.is_combat_active():
		frontend.show()


func _show_codex() -> void:
	frontend.hide()
	codex.open_codex()


func _on_codex_closed() -> void:
	frontend.show()


func _quit_game() -> void:
	get_tree().quit()
