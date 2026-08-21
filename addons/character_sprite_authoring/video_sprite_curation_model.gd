class_name CharacterSpriteCurationModel
extends RefCounted


const MIN_FPS := 0.1
const MAX_FPS := 120.0

var source_count := 0
var source_anchor := -1
var final_anchor := -1
var sequence: Array[int] = []
var fps := 10.0
var loop := true

var _source_selection: Dictionary = {}
var _final_selection: Dictionary = {}


func set_source_count(value: int) -> void:
	source_count = maxi(value, 0)
	for index: Variant in _source_selection.keys():
		if int(index) >= source_count:
			_source_selection.erase(index)
	if source_anchor >= source_count:
		source_anchor = -1


func set_sequence(value: Array) -> void:
	sequence.clear()
	for entry: Variant in value:
		sequence.append(int(entry))
	clear_final_selection()


func select_source(index: int, ctrl := false, shift := false) -> void:
	if index < 0 or index >= source_count:
		return
	source_anchor = _apply_gesture(_source_selection, index, source_anchor, ctrl, shift)


func select_final(index: int, ctrl := false, shift := false) -> void:
	if index < 0 or index >= sequence.size():
		return
	final_anchor = _apply_gesture(_final_selection, index, final_anchor, ctrl, shift)


func selected_source_indices() -> Array[int]:
	return _sorted_selection(_source_selection)


func selected_final_positions() -> Array[int]:
	return _sorted_selection(_final_selection)


func clear_source_selection() -> void:
	reset_source_selection()


func reset_source_selection() -> void:
	_source_selection.clear()
	source_anchor = -1


func clear_final_selection() -> void:
	_final_selection.clear()
	final_anchor = -1


func add_selected_sources() -> void:
	for index: int in selected_source_indices():
		sequence.append(index)


func remove_selected_final() -> void:
	var selected := selected_final_positions()
	selected.reverse()
	for position: int in selected:
		sequence.remove_at(position)
	clear_final_selection()


func move_selected_up() -> void:
	var selected := selected_final_positions()
	for position: int in selected:
		if position <= 0 or _final_selection.has(position - 1):
			continue
		var value := sequence[position]
		sequence[position] = sequence[position - 1]
		sequence[position - 1] = value
		_final_selection.erase(position)
		_final_selection[position - 1] = true
		if final_anchor == position:
			final_anchor = position - 1


func move_selected_down() -> void:
	var selected := selected_final_positions()
	selected.reverse()
	for position: int in selected:
		if position >= sequence.size() - 1 or _final_selection.has(position + 1):
			continue
		var value := sequence[position]
		sequence[position] = sequence[position + 1]
		sequence[position + 1] = value
		_final_selection.erase(position)
		_final_selection[position + 1] = true
		if final_anchor == position:
			final_anchor = position + 1


func reorder_selected_before(target_position: int) -> void:
	var selected := selected_final_positions()
	if selected.is_empty():
		return
	var moved: Array[int] = []
	var remaining: Array[int] = []
	for position in sequence.size():
		if _final_selection.has(position):
			moved.append(sequence[position])
		else:
			remaining.append(sequence[position])
	var insertion := clampi(target_position, 0, sequence.size())
	for position: int in selected:
		if position < target_position:
			insertion -= 1
	insertion = clampi(insertion, 0, remaining.size())
	var reordered: Array[int] = []
	for position in remaining.size() + 1:
		if position == insertion:
			reordered.append_array(moved)
		if position < remaining.size():
			reordered.append(remaining[position])
	sequence = reordered
	_final_selection.clear()
	for offset in moved.size():
		_final_selection[insertion + offset] = true
	final_anchor = insertion


func set_fps(value: float) -> bool:
	if not is_finite(value) or value < MIN_FPS or value > MAX_FPS:
		return false
	fps = value
	return true


func set_loop(value: bool) -> void:
	loop = value


static func _apply_gesture(
	selection: Dictionary,
	index: int,
	anchor: int,
	ctrl: bool,
	shift: bool
) -> int:
	if shift:
		if anchor < 0:
			anchor = index
		if not ctrl:
			selection.clear()
		for value in range(mini(anchor, index), maxi(anchor, index) + 1):
			selection[value] = true
		return anchor
	if ctrl:
		if selection.has(index):
			selection.erase(index)
		else:
			selection[index] = true
		return index
	selection.clear()
	selection[index] = true
	return index


static func _sorted_selection(selection: Dictionary) -> Array[int]:
	var result: Array[int] = []
	for index: Variant in selection:
		result.append(int(index))
	result.sort()
	return result
