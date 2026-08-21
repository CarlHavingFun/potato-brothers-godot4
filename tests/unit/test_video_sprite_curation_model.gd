extends GdUnitTestSuite


const Model = preload("res://addons/character_sprite_authoring/video_sprite_curation_model.gd")


func test_source_selection_plain_ctrl_shift_and_ctrl_shift_keep_a_deterministic_anchor() -> void:
	var model := Model.new()
	model.set_source_count(8)

	model.select_source(2)
	assert_array(model.selected_source_indices()).is_equal([2])
	assert_int(model.source_anchor).is_equal(2)

	model.select_source(5, true)
	assert_array(model.selected_source_indices()).is_equal([2, 5])
	assert_int(model.source_anchor).is_equal(5)

	model.select_source(3, false, true)
	assert_array(model.selected_source_indices()).is_equal([3, 4, 5])
	assert_int(model.source_anchor).is_equal(5)

	model.select_source(7, true, true)
	assert_array(model.selected_source_indices()).is_equal([3, 4, 5, 6, 7])
	assert_int(model.source_anchor).is_equal(5)

	model.select_source(5, true)
	assert_array(model.selected_source_indices()).is_equal([3, 4, 6, 7])
	assert_int(model.source_anchor).is_equal(5)


func test_plain_click_after_a_range_clears_the_old_selection_and_moves_the_anchor() -> void:
	var model := Model.new()
	model.set_source_count(6)
	model.select_source(1)
	model.select_source(4, false, true)
	model.select_source(0)
	assert_array(model.selected_source_indices()).is_equal([0])
	assert_int(model.source_anchor).is_equal(0)


func test_batch_add_appends_source_order_and_keeps_duplicates_legal() -> void:
	var model := Model.new()
	model.set_source_count(6)
	model.set_sequence([4])
	model.select_source(3)
	model.select_source(1, true)
	model.add_selected_sources()
	assert_array(model.sequence).is_equal([4, 1, 3])

	model.select_source(3)
	model.add_selected_sources()
	assert_array(model.sequence).is_equal([4, 1, 3, 3])


func test_batch_remove_uses_final_positions_so_duplicate_source_indices_are_independent() -> void:
	var model := Model.new()
	model.set_sequence([2, 2, 4, 2])
	model.select_final(1)
	model.select_final(3, true)
	model.remove_selected_final()
	assert_array(model.sequence).is_equal([2, 4])
	assert_array(model.selected_final_positions()).is_empty()


func test_multi_item_move_up_and_down_is_stable_for_contiguous_and_split_selections() -> void:
	var model := Model.new()
	model.set_sequence([0, 1, 2, 3, 4, 5])
	model.select_final(2)
	model.select_final(3, true)
	model.move_selected_up()
	assert_array(model.sequence).is_equal([0, 2, 3, 1, 4, 5])
	assert_array(model.selected_final_positions()).is_equal([1, 2])

	model.clear_final_selection()
	model.select_final(1)
	model.select_final(4, true)
	model.move_selected_down()
	assert_array(model.sequence).is_equal([0, 3, 2, 1, 5, 4])
	assert_array(model.selected_final_positions()).is_equal([2, 5])


func test_drag_reorder_moves_the_selected_block_stably_before_the_original_target() -> void:
	var model := Model.new()
	model.set_sequence([0, 1, 2, 3, 4, 5])
	model.select_final(1)
	model.select_final(3, true)
	model.reorder_selected_before(5)
	assert_array(model.sequence).is_equal([0, 2, 4, 1, 3, 5])
	assert_array(model.selected_final_positions()).is_equal([3, 4])

	model.reorder_selected_before(0)
	assert_array(model.sequence).is_equal([1, 3, 0, 2, 4, 5])
	assert_array(model.selected_final_positions()).is_equal([0, 1])


func test_fps_range_and_loop_state_are_explicit_model_values() -> void:
	var model := Model.new()
	assert_float(model.fps).is_equal_approx(10.0, 0.0001)
	assert_bool(model.loop).is_true()
	assert_bool(model.set_fps(24.0)).is_true()
	assert_bool(model.set_fps(0.0)).is_false()
	assert_bool(model.set_fps(121.0)).is_false()
	assert_float(model.fps).is_equal_approx(24.0, 0.0001)
	model.set_loop(false)
	assert_bool(model.loop).is_false()
