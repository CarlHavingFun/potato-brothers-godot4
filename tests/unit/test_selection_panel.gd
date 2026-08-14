extends GdUnitTestSuite


var _panel: SelectionPanel
var _completion_count := 0


func before_test() -> void:
	_panel = auto_free(SelectionPanel.new())
	_completion_count = 0
	_panel.on_selection_completed.connect(_on_selection_completed)
	Global.main_player_selected = null
	Global.main_weapon_selected = null


func after_test() -> void:
	Global.main_player_selected = null
	Global.main_weapon_selected = null


func test_continue_is_blocked_when_weapon_is_missing() -> void:
	Global.main_player_selected = UnitStats.new()

	_panel._on_continue_buttom_pressed()

	assert_int(_completion_count).is_zero()


func test_continue_is_blocked_when_player_is_missing() -> void:
	Global.main_weapon_selected = ItemWeapon.new()

	_panel._on_continue_buttom_pressed()

	assert_int(_completion_count).is_zero()


func test_continue_emits_once_when_both_selections_exist() -> void:
	Global.main_player_selected = UnitStats.new()
	Global.main_weapon_selected = ItemWeapon.new()

	_panel._on_continue_buttom_pressed()

	assert_int(_completion_count).is_equal(1)


func _on_selection_completed() -> void:
	_completion_count += 1
