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


func test_selection_card_has_a_persistent_selected_indicator() -> void:
	var card: SelectionCard = auto_free(load("res://scenes/ui/selection_panel/selection_card.tscn").instantiate() as SelectionCard)
	var indicator := card.get_node_or_null("SelectedIndicator") as Control

	assert_object(indicator).is_not_null()
	if indicator == null:
		return
	assert_bool(card.toggle_mode).is_true()
	card.call("_on_toggled", true)
	assert_bool(indicator.visible).is_true()
	card.call("_on_toggled", false)
	assert_bool(indicator.visible).is_false()


func test_character_and_weapon_rows_are_mutually_exclusive_groups() -> void:
	var panel: SelectionPanel = auto_free(load("res://scenes/ui/selection_panel/selection_panel.tscn").instantiate() as SelectionPanel)
	add_child(panel)
	await get_tree().process_frame

	var player_cards: Array[Node] = panel.player_container.get_children()
	var weapon_cards: Array[Node] = panel.weapon_container.get_children()
	assert_bool(player_cards.size() >= 2).is_true()
	assert_bool(weapon_cards.size() >= 2).is_true()
	if player_cards.size() < 2 or weapon_cards.size() < 2:
		return

	var player_group := (player_cards[0] as BaseButton).button_group
	var weapon_group := (weapon_cards[0] as BaseButton).button_group
	assert_object(player_group).is_not_null()
	assert_object(weapon_group).is_not_null()
	assert_bool(player_group == weapon_group).is_false()
	for node: Node in player_cards:
		var card := node as BaseButton
		assert_bool(card.toggle_mode).is_true()
		assert_object(card.button_group).is_same(player_group)
	for node: Node in weapon_cards:
		var card := node as BaseButton
		assert_bool(card.toggle_mode).is_true()
		assert_object(card.button_group).is_same(weapon_group)


func _on_selection_completed() -> void:
	_completion_count += 1
