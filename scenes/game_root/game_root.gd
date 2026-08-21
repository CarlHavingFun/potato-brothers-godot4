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
	if not Presentation.skin_loaded.is_connected(_on_skin_loaded):
		Presentation.skin_loaded.connect(_on_skin_loaded)
	_apply_active_ui_theme()
	_hide_legacy_frontend()
	_set_combat_hud_visible(false)
	frontend.show()


func _on_skin_loaded(_skin_id: StringName) -> void:
	_apply_active_ui_theme()


func _apply_active_ui_theme() -> void:
	if Presentation.active_skin == null or Presentation.active_skin.theme == null:
		return
	var active_theme := Presentation.active_skin.theme.duplicate(true) as Theme
	if Presentation.active_skin.font != null:
		active_theme.default_font = Presentation.active_skin.font
	var roots: Array[Control] = [frontend, codex]
	for child: Node in arena.get_node("GameUI").get_children():
		if child is Control:
			roots.append(child as Control)
	for control: Control in roots:
		control.theme = active_theme


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
	arena.combat_hud.visible = value


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
