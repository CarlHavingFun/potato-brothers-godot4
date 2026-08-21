class_name CharacterSpriteAuthoringDock
extends VBoxContainer


const Controller = preload("res://addons/character_sprite_authoring/video_sprite_curation_controller.gd")
const CurationItemList = preload("res://addons/character_sprite_authoring/curation_item_list.gd")
const CONFIG_PATH := "res://tools/video_sprites/niko_character_sources.json"
const POLL_INTERVAL := 0.5

var controller: CharacterSpriteCurationController = Controller.new()
var action_tree: Tree
var job_list: ItemList
var source_list: ItemList
var final_list: ItemList
var status: RichTextLabel
var dependency_label: Label
var preview_frame: TextureRect
var preview_caption: Label
var fps_spin: SpinBox
var loop_check: CheckBox
var take_edit: LineEdit
var file_dialog: FileDialog
var promotion_dialog: ConfirmationDialog
var cleanup_dialog: ConfirmationDialog
var _textures: Dictionary = {}
var _built := false
var _poll_elapsed := 0.0
var _preview_index := 0
var _preview_elapsed := 0.0
var _preferred_target_action := ""
var _preferred_target_take := ""


func _ready() -> void:
	build_ui()
	refresh_config()
	set_process(true)


func build_ui() -> void:
	if _built:
		return
	_built = true
	custom_minimum_size = Vector2(440, 620)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	focus_mode = Control.FOCUS_ALL
	name = "CharacterSpriteAuthoringDock"

	var header := HBoxContainer.new()
	header.name = "Header"
	add_child(header)
	var title := Label.new()
	title.name = "Title"
	title.text = "角色精灵编辑 / Character Sprite Authoring"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var dependency_button := Button.new()
	dependency_button.text = "检查依赖"
	dependency_button.tooltip_text = "Show Python, PixelMotion, sprite-gen, worker and ffprobe paths"
	dependency_button.pressed.connect(_show_dependencies)
	header.add_child(dependency_button)

	dependency_label = Label.new()
	dependency_label.name = "Dependencies"
	dependency_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(dependency_label)

	var content := VBoxContainer.new()
	content.name = "Content"
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(content)

	action_tree = Tree.new()
	action_tree.name = "Actions"
	action_tree.hide_root = true
	action_tree.custom_minimum_size.y = 150
	action_tree.item_selected.connect(_on_action_selected)
	content.add_child(action_tree)

	var file_bar := HBoxContainer.new()
	file_bar.name = "FileBar"
	content.add_child(file_bar)
	var pick_button := Button.new()
	pick_button.text = "添加视频…"
	pick_button.tooltip_text = "Choose absolute video files; filenames never decide the action"
	pick_button.pressed.connect(_open_file_dialog)
	file_bar.add_child(pick_button)
	var cancel_button := Button.new()
	cancel_button.text = "取消当前任务"
	cancel_button.pressed.connect(_cancel_current_job)
	file_bar.add_child(cancel_button)

	job_list = ItemList.new()
	job_list.name = "Jobs"
	job_list.select_mode = ItemList.SELECT_SINGLE
	job_list.custom_minimum_size.y = 80
	job_list.tooltip_text = "选择已完成任务可继续独立挑帧；取消只作用于选中的活动任务"
	job_list.item_selected.connect(_on_job_selected)
	content.add_child(job_list)

	status = RichTextLabel.new()
	status.name = "Status"
	status.fit_content = true
	status.custom_minimum_size.y = 58
	content.add_child(status)

	var lists := HBoxContainer.new()
	lists.name = "Lists"
	lists.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(lists)
	source_list = _new_frame_list("Source")
	source_list.tooltip_text = "来源候选保持完整；Ctrl/Shift 支持多选"
	source_list.item_clicked.connect(_on_source_clicked)
	lists.add_child(source_list)
	final_list = _new_frame_list("Final")
	final_list.tooltip_text = "最终序列允许重复帧和稳定多项拖动排序"
	final_list.item_clicked.connect(_on_final_clicked)
	lists.add_child(final_list)

	var sequence_bar := HBoxContainer.new()
	sequence_bar.name = "SequenceBar"
	content.add_child(sequence_bar)
	_add_button(sequence_bar, "添加所选", _add_selected)
	_add_button(sequence_bar, "移除所选", _remove_selected)
	_add_button(sequence_bar, "上移", _move_up)
	_add_button(sequence_bar, "下移", _move_down)

	var timing := HBoxContainer.new()
	timing.name = "Timing"
	content.add_child(timing)
	var fps_label := Label.new()
	fps_label.text = "FPS"
	timing.add_child(fps_label)
	fps_spin = SpinBox.new()
	fps_spin.min_value = 0.1
	fps_spin.max_value = 120.0
	fps_spin.step = 0.1
	fps_spin.value = 10.0
	fps_spin.value_changed.connect(_on_fps_changed)
	timing.add_child(fps_spin)
	loop_check = CheckBox.new()
	loop_check.text = "循环"
	loop_check.button_pressed = true
	loop_check.toggled.connect(_on_loop_changed)
	timing.add_child(loop_check)
	take_edit = LineEdit.new()
	take_edit.placeholder_text = "take 名称"
	take_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	timing.add_child(take_edit)

	var preview := VBoxContainer.new()
	preview.name = "Preview"
	content.add_child(preview)
	preview_frame = TextureRect.new()
	preview_frame.name = "Frame"
	preview_frame.custom_minimum_size = Vector2(144, 144)
	preview_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview_frame.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview_frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	preview.add_child(preview_frame)
	preview_caption = Label.new()
	preview_caption.name = "Caption"
	preview_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview.add_child(preview_caption)

	var operations := HFlowContainer.new()
	operations.name = "Operations"
	content.add_child(operations)
	_add_button(operations, "保存挑帧", _save)
	_add_button(operations, "预览并提升", _preview_promotion)
	_add_button(operations, "设为首选", _set_preferred)
	_add_button(operations, "发布运行时", _publish)
	_add_button(operations, "清理外部暂存", _request_cleanup)

	file_dialog = FileDialog.new()
	file_dialog.name = "VideoFileDialog"
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	file_dialog.filters = PackedStringArray(["*.mp4, *.mov, *.mkv, *.webm, *.avi ; 视频文件"])
	file_dialog.files_selected.connect(_on_files_selected)
	add_child(file_dialog)
	promotion_dialog = ConfirmationDialog.new()
	promotion_dialog.name = "PromotionConfirmation"
	promotion_dialog.title = "确认提升挑帧"
	promotion_dialog.confirmed.connect(_confirm_promotion)
	add_child(promotion_dialog)
	cleanup_dialog = ConfirmationDialog.new()
	cleanup_dialog.name = "CleanupConfirmation"
	cleanup_dialog.title = "确认清理外部暂存"
	cleanup_dialog.dialog_text = "只删除当前外部暂存 take；活动任务会被拒绝。"
	cleanup_dialog.confirmed.connect(_confirm_cleanup)
	add_child(cleanup_dialog)


func refresh_config() -> void:
	var selected_before := controller.selected_action
	var result := controller.load_config(CONFIG_PATH)
	if not _errors(result).is_empty():
		show_result("读取配置失败", result)
		return
	action_tree.clear()
	var root := action_tree.create_item()
	var selected_item: TreeItem = null
	for action: String in controller.action_names():
		var overview := controller.action_overview(action)
		var item := action_tree.create_item(root)
		item.set_text(0, "%s  · 首选：%s" % [action, str(overview.get("preferred_take", "—"))])
		item.set_metadata(0, {"action": action})
		if action == selected_before:
			selected_item = item
		for take_value: Variant in overview.get("takes", []) as Array:
			var take := take_value as Dictionary
			var child := action_tree.create_item(item)
			var marker := " ★" if str(take.get("name", "")) == str(overview.get("preferred_take", "")) else ""
			child.set_text(0, "%s%s" % [take.get("name", ""), marker])
			child.set_metadata(0, {"action": action, "take": str(take.get("name", ""))})
	if selected_item != null:
		selected_item.select(0)
		action_tree.scroll_to_item(selected_item)
	show_result("配置", {
		"errors": PackedStringArray(),
		"message": "已加载 %d 个必需动作" % controller.action_names().size(),
	})


func handle_files_dropped(files: PackedStringArray) -> Dictionary:
	var hovered := ""
	var item := action_tree.get_item_at_position(action_tree.get_local_mouse_position())
	if item != null:
		var metadata: Variant = item.get_metadata(0)
		if metadata is Dictionary:
			hovered = str((metadata as Dictionary).get("action", ""))
	var result := controller.accept_video_files(files, hovered)
	show_result("添加视频", result)
	refresh_jobs()
	return result


func refresh_lists() -> void:
	if source_list == null or final_list == null:
		return
	source_list.clear()
	for frame: Dictionary in controller.source_frames:
		var text := "#%03d\n%.3fs" % [int(frame.get("source_frame", 0)), float(frame.get("timestamp_seconds", 0.0))]
		var index := source_list.add_item(text, _texture_for(str(frame.get("png_path", ""))))
		source_list.set_item_metadata(index, int(frame.get("index", index)))
	final_list.clear()
	for position in controller.model.sequence.size():
		var source_index := controller.model.sequence[position]
		var frame := controller.source_frames[source_index] if source_index < controller.source_frames.size() else {}
		var text := "%d · #%03d" % [position + 1, int(frame.get("source_frame", source_index + 1))]
		final_list.add_item(text, _texture_for(str(frame.get("png_path", ""))))
	_apply_item_selection(source_list, controller.model.selected_source_indices())
	_apply_item_selection(final_list, controller.model.selected_final_positions())
	fps_spin.set_value_no_signal(controller.model.fps)
	loop_check.set_pressed_no_signal(controller.model.loop)
	refresh_preview()


func refresh_jobs() -> void:
	if job_list == null:
		return
	var selected_job := _selected_job_id()
	job_list.clear()
	var ordered_ids: Array[String] = controller.job_order.duplicate()
	for job_id_value: Variant in controller.jobs.keys():
		var untracked_id := str(job_id_value)
		if untracked_id not in ordered_ids:
			ordered_ids.append(untracked_id)
	for job_id: String in ordered_ids:
		if not controller.jobs.has(job_id):
			continue
		var row := controller.jobs[job_id] as Dictionary
		var errors := _errors(row)
		var details := ""
		if not errors.is_empty():
			details = " · %s" % "；".join(errors)
		var active_marker := "▶ " if job_id == controller.current_job_id else ""
		var text := "%s%s/%s · %s · %d%%%s" % [
			active_marker,
			str(row.get("action", "—")), str(row.get("take", "—")),
			str(row.get("state", "queued")), roundi(float(row.get("progress", 0.0)) * 100.0),
			details,
		]
		var index := job_list.add_item(text)
		job_list.set_item_metadata(index, job_id)
		if job_id == selected_job or (selected_job.is_empty() and job_id == controller.current_job_id):
			job_list.select(index)


func focus_dock_tab() -> void:
	show()
	var parent := get_parent()
	if parent is TabContainer:
		(parent as TabContainer).current_tab = get_index()
	if is_instance_valid(action_tree):
		action_tree.grab_focus()
	else:
		grab_focus()


func refresh_preview() -> void:
	var sequence := controller.preview_sequence()
	if sequence.is_empty():
		preview_frame.texture = null
		preview_caption.text = "最终序列为空"
		_preview_index = 0
		return
	_preview_index = clampi(_preview_index, 0, sequence.size() - 1)
	var frame := sequence[_preview_index]
	preview_frame.texture = _texture_for(str(frame.get("png_path", "")))
	preview_caption.text = "%d / %d · 来源 #%03d · %.3fs" % [
		_preview_index + 1, sequence.size(), int(frame.get("source_frame", 0)),
		float(frame.get("timestamp_seconds", 0.0)),
	]


func show_result(label: String, result: Dictionary) -> void:
	if status == null:
		return
	var errors := _errors(result)
	if errors.is_empty():
		if result.has("removed_path"):
			status.text = "%s：已清理 %s；移除 %d 项" % [
				label, str(result.get("removed_path", "")), int(result.get("removed_entries", 0)),
			]
		else:
			status.text = "%s：%s" % [label, str(result.get("message", result.get("state", "完成")))]
	else:
		status.text = "%s：%s" % [label, "；".join(errors)]


static func load_external_texture(path: String) -> Texture2D:
	if path.is_empty() or not path.is_absolute_path():
		return null
	var image := Image.load_from_file(path)
	if image == null or image.is_empty():
		return null
	return ImageTexture.create_from_image(image)


func _process(delta: float) -> void:
	_poll_elapsed += delta
	if _poll_elapsed >= POLL_INTERVAL:
		_poll_elapsed = 0.0
		var active_before := controller.current_job_id
		var results := controller.poll_jobs()
		if not results.is_empty():
			_activate_selected_completed_job()
			var selected_job := _selected_job_id()
			if not selected_job.is_empty() and controller.jobs.has(selected_job):
				show_result("任务", controller.jobs[selected_job])
			elif not controller.current_job_id.is_empty() and controller.jobs.has(controller.current_job_id):
				show_result("任务", controller.jobs[controller.current_job_id])
			refresh_jobs()
			if controller.current_job_id != active_before:
				refresh_lists()
	_preview_elapsed += delta
	if controller.model.fps > 0.0 and _preview_elapsed >= 1.0 / controller.model.fps:
		_preview_elapsed = 0.0
		_advance_preview()


func _get_drag_data(_at_position: Vector2) -> Variant:
	var positions := controller.model.selected_final_positions()
	if positions.is_empty():
		return null
	var payload := {"kind": "curated_frames", "positions": positions}
	if is_inside_tree():
		var drag_preview := Label.new()
		drag_preview.text = "移动 %d 帧" % positions.size()
		set_drag_preview(drag_preview)
	return payload


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and str((data as Dictionary).get("kind", "")) == "curated_frames"


func _drop_data(at_position: Vector2, data: Variant) -> void:
	if not _can_drop_data(at_position, data):
		return
	var payload := data as Dictionary
	var target := int(payload.get("drop_index", -1))
	if target < 0:
		target = final_list.get_item_at_position(final_list.get_local_mouse_position(), true)
	if target < 0:
		target = controller.model.sequence.size()
	controller.model.reorder_selected_before(target)
	refresh_lists()


func _new_frame_list(node_name: String) -> ItemList:
	var list: ItemList
	if node_name == "Final":
		var draggable := CurationItemList.new()
		draggable.drag_owner = self
		list = draggable
	else:
		list = ItemList.new()
	list.name = node_name
	list.select_mode = ItemList.SELECT_MULTI
	list.allow_reselect = true
	list.icon_mode = ItemList.ICON_MODE_TOP
	list.fixed_icon_size = Vector2i(72, 72)
	list.max_columns = 0
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return list


func _add_button(parent: Control, label: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = label
	button.pressed.connect(callback)
	parent.add_child(button)


func _show_dependencies() -> void:
	var result := controller.dependency_diagnostics()
	var lines := PackedStringArray()
	for dependency in ["python", "pixelmotion", "sprite_gen", "worker_script", "ffprobe"]:
		var value := result.get(dependency, {}) as Dictionary
		lines.append("%s：%s · %s" % [dependency, "就绪" if value.get("resolved", false) else "缺失", value.get("path", "")])
	dependency_label.text = "\n".join(lines)


func _on_action_selected() -> void:
	var item := action_tree.get_selected()
	if item == null:
		return
	var metadata: Variant = item.get_metadata(0)
	if metadata is Dictionary:
		var action := str((metadata as Dictionary).get("action", ""))
		var take := str((metadata as Dictionary).get("take", ""))
		controller.select_action(action)
		if take.is_empty():
			_preferred_target_action = ""
			_preferred_target_take = ""
		else:
			_preferred_target_action = action
			_preferred_target_take = take


func _open_file_dialog() -> void:
	file_dialog.popup_centered_ratio(0.75)


func _on_files_selected(files: PackedStringArray) -> void:
	show_result("添加视频", controller.accept_video_files(files))
	refresh_jobs()


func _cancel_current_job() -> void:
	var job_id := _selected_job_id()
	if job_id.is_empty():
		show_result("取消", {"errors": PackedStringArray(["请先选择一个活动任务"])})
		return
	show_result("取消", controller.cancel_job(job_id))
	refresh_jobs()


func _on_job_selected(index: int) -> void:
	if index < 0 or index >= job_list.item_count:
		return
	var job_id := str(job_list.get_item_metadata(index))
	var row := controller.jobs.get(job_id, {}) as Dictionary
	if (row.get("curation", {}) as Dictionary).is_empty():
		show_result("任务", row)
		return
	var result := controller.activate_job(job_id)
	show_result("打开挑帧", result)
	if _errors(result).is_empty():
		take_edit.text = controller.current_take
		refresh_lists()


func _activate_selected_completed_job() -> void:
	var job_id := _selected_job_id()
	if job_id.is_empty() or job_id == controller.current_job_id or not controller.jobs.has(job_id):
		return
	var row := controller.jobs[job_id] as Dictionary
	if (row.get("curation", {}) as Dictionary).is_empty():
		return
	var result := controller.activate_job(job_id)
	if _errors(result).is_empty():
		take_edit.text = controller.current_take


func _on_source_clicked(index: int, _position: Vector2, _button: int) -> void:
	controller.model.select_source(index, Input.is_key_pressed(KEY_CTRL), Input.is_key_pressed(KEY_SHIFT))
	refresh_lists()


func _on_final_clicked(index: int, _position: Vector2, _button: int) -> void:
	controller.model.select_final(index, Input.is_key_pressed(KEY_CTRL), Input.is_key_pressed(KEY_SHIFT))
	refresh_lists()


func _add_selected() -> void:
	controller.model.add_selected_sources()
	refresh_lists()


func _remove_selected() -> void:
	controller.model.remove_selected_final()
	refresh_lists()


func _move_up() -> void:
	controller.model.move_selected_up()
	refresh_lists()


func _move_down() -> void:
	controller.model.move_selected_down()
	refresh_lists()


func _on_fps_changed(value: float) -> void:
	show_result("FPS", controller.set_fps(value))
	refresh_preview()


func _on_loop_changed(value: bool) -> void:
	controller.set_loop(value)
	refresh_preview()


func _save() -> void:
	show_result("保存挑帧", controller.save_curation())


func _preview_promotion() -> void:
	var result := controller.preview_promotion()
	if not _errors(result).is_empty():
		show_result("提升预览失败", result)
		return
	promotion_dialog.dialog_text = "将创建唯一 take：%s\n路径：%s\n仅所选帧会进入项目。" % [result.get("take", ""), result.get("output_path", "")]
	promotion_dialog.popup_centered()


func _confirm_promotion() -> void:
	show_result("提升结果", controller.confirm_promotion())
	refresh_config()


func _set_preferred() -> void:
	var action := _preferred_target_action
	var take := _preferred_target_take
	if action.is_empty() or take.is_empty():
		action = controller.current_action
		take = controller.current_take
	show_result("设为首选", controller.set_preferred_take(action, take))
	refresh_config()


func _publish() -> void:
	show_result("发布运行时", controller.publish_runtime())


func _request_cleanup() -> void:
	cleanup_dialog.popup_centered()


func _confirm_cleanup() -> void:
	var result := controller.cleanup_current(true)
	show_result("清理结果", result)
	if _errors(result).is_empty():
		_textures.clear()
	refresh_jobs()
	refresh_lists()


func _texture_for(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if not _textures.has(path):
		_textures[path] = load_external_texture(path)
	return _textures[path] as Texture2D


func _advance_preview() -> void:
	var sequence := controller.preview_sequence()
	if sequence.size() <= 1:
		return
	if _preview_index >= sequence.size() - 1:
		if not controller.model.loop:
			return
		_preview_index = 0
	else:
		_preview_index += 1
	refresh_preview()


static func _apply_item_selection(list: ItemList, indices: Array[int]) -> void:
	list.deselect_all()
	for index: int in indices:
		if index >= 0 and index < list.item_count:
			list.select(index, false)


static func _errors(result: Dictionary) -> PackedStringArray:
	var value: Variant = result.get("errors", PackedStringArray())
	var errors := PackedStringArray()
	if value is PackedStringArray:
		errors = (value as PackedStringArray).duplicate()
	elif value is Array:
		for item: Variant in value:
			errors.append(str(item))
	var singular := str(result.get("error", ""))
	if not singular.is_empty() and singular not in errors:
		errors.append(singular)
	return errors


func _selected_job_id() -> String:
	if job_list == null:
		return ""
	var selected := job_list.get_selected_items()
	if selected.is_empty():
		return ""
	return str(job_list.get_item_metadata(selected[0]))
