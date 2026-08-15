extends GdUnitTestSuite


const SETTINGS_SCENE := "res://scenes/ui/settings_panel/settings_panel.tscn"

var _original_bindings: Dictionary


func before_test() -> void:
	_original_bindings = InputRemapService.new().serialize_actions()
	Global.meta_progress.input_bindings = _original_bindings.duplicate(true)


func after_test() -> void:
	InputRemapService.new().apply_actions(_original_bindings)
	Global.meta_progress.input_bindings = _original_bindings.duplicate(true)


func test_cancel_restores_staged_key_remap_without_persisting_it() -> void:
	var panel: SettingsPanel = auto_free(load(SETTINGS_SCENE).instantiate()) as SettingsPanel
	add_child(panel)
	await await_idle_frame()
	panel.show()
	var before := InputRemapService.new().serialize_actions([&"dash"])
	var replacement := InputEventKey.new()
	var replacement_key := KEY_F8
	for raw_event: Variant in before.get("dash", []):
		if raw_event is Dictionary and int((raw_event as Dictionary).get("physical_keycode", 0)) == KEY_F8:
			replacement_key = KEY_F9
			break
	replacement.physical_keycode = replacement_key
	panel.awaiting_action = &"dash"

	panel.call("_commit_rebind", replacement)

	assert_bool(InputRemapService.new().serialize_actions([&"dash"]) == before).is_false()
	assert_dict(Global.meta_progress.input_bindings).is_equal(_original_bindings)
	panel.call("_on_cancel_button_pressed")
	assert_dict(InputRemapService.new().serialize_actions([&"dash"])).is_equal(before)
