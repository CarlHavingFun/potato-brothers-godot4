extends GdUnitTestSuite


const Dock = preload("res://addons/character_sprite_authoring/video_sprite_curation_dock.gd")
const Lifecycle = preload("res://addons/character_sprite_authoring/dock_lifecycle.gd")
const Plugin = preload("res://addons/character_sprite_authoring/plugin.gd")


class DropEmitter extends RefCounted:
	signal files_dropped(files: PackedStringArray)


class FakeCancelService extends RefCounted:
	var cancelled: Array[String] = []

	func cancel_job(job_id: String) -> Dictionary:
		cancelled.append(job_id)
		return {"errors": PackedStringArray(), "job_id": job_id, "state": "cancellation_requested"}


var dropped := PackedStringArray()


func before_test() -> void:
	dropped = PackedStringArray()


func test_dock_builds_config_actions_multi_select_candidate_and_final_controls() -> void:
	var dock := auto_free(Dock.new()) as Control
	dock.call("build_ui")
	var source := dock.get_node("Content/Lists/Source") as ItemList
	var final := dock.get_node("Content/Lists/Final") as ItemList
	var actions := dock.get_node("Content/Actions") as Tree
	assert_int(source.select_mode).is_equal(ItemList.SELECT_MULTI)
	assert_int(final.select_mode).is_equal(ItemList.SELECT_MULTI)
	assert_bool(source.allow_reselect).is_true()
	assert_bool(final.allow_reselect).is_true()
	assert_bool(actions.hide_root).is_true()
	assert_str(dock.get_node("Header/Title").text).contains("角色精灵编辑")


func test_external_thumbnail_is_an_image_texture_and_preview_uses_nearest_filter() -> void:
	var path := "user://dock-thumbnail.png"
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color.MAGENTA)
	assert_int(image.save_png(path)).is_equal(OK)
	var texture: Texture2D = Dock.load_external_texture(ProjectSettings.globalize_path(path))
	assert_object(texture).is_instanceof(ImageTexture)
	var dock: Variant = auto_free(Dock.new())
	dock.build_ui()
	var preview := dock.get_node("Content/Preview/Frame") as TextureRect
	assert_int(preview.texture_filter).is_equal(CanvasItem.TEXTURE_FILTER_NEAREST)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_final_list_drag_payload_preserves_multi_selection_and_drop_reorders_stably() -> void:
	var dock: Variant = auto_free(Dock.new())
	dock.build_ui()
	dock.controller.model.set_sequence([0, 1, 2, 3, 4])
	dock.controller.model.select_final(1)
	dock.controller.model.select_final(3, true)
	dock.refresh_lists()
	var final := dock.get_node("Content/Lists/Final") as ItemList
	var payload: Variant = final._get_drag_data(Vector2.ZERO)
	assert_dict(payload).contains_key_value("kind", "curated_frames")
	assert_array(payload["positions"]).is_equal([1, 3])
	assert_bool(final._can_drop_data(Vector2.ZERO, payload)).is_true()
	payload["drop_index"] = 5
	final._drop_data(Vector2.ZERO, payload)
	assert_array(dock.controller.model.sequence).is_equal([0, 2, 4, 1, 3])


func test_files_dropped_lifecycle_connects_once_and_disconnects_on_exit() -> void:
	var emitter := DropEmitter.new()
	var lifecycle := Lifecycle.new()
	var receiver := Callable(self, "_receive_drop")
	assert_bool(lifecycle.connect_files_dropped(emitter, receiver)).is_true()
	assert_bool(lifecycle.connect_files_dropped(emitter, receiver)).is_false()
	assert_int(emitter.get_signal_connection_list("files_dropped").size()).is_equal(1)
	emitter.files_dropped.emit(PackedStringArray(["C:/clip.mp4"]))
	assert_array(dropped).is_equal(["C:/clip.mp4"])
	lifecycle.disconnect_files_dropped()
	assert_int(emitter.get_signal_connection_list("files_dropped").size()).is_zero()


func test_plugin_keeps_legacy_menu_labels_and_adds_a_dock_focus_entry() -> void:
	assert_str(Plugin.IMPORT_LABEL).is_equal("角色精灵/导入 Niko 全部视频")
	assert_str(Plugin.PUBLISH_LABEL).is_equal("角色精灵/发布当前角色动画")
	assert_str(Plugin.STATUS_LABEL).is_equal("角色精灵/显示当前角色状态")
	assert_str(Plugin.DOCK_LABEL).is_equal("角色精灵/打开视频挑帧 Dock")


func test_job_rows_show_each_progress_error_and_cleanup_exact_result() -> void:
	var dock: Variant = auto_free(Dock.new())
	dock.build_ui()
	dock.controller.jobs = {
		"job-1": {"job_id": "job-1", "action": "walk", "take": "one", "state": "running", "progress": 0.25, "errors": PackedStringArray()},
		"job-2": {"job_id": "job-2", "action": "idle", "take": "two", "state": "failed", "progress": 0.5, "error": "worker failed", "errors": PackedStringArray(["bad frame"])},
		"job-3": {"job_id": "job-3", "action": "hit", "take": "three", "state": "cancelled", "progress": 0.4, "errors": PackedStringArray()},
		"job-4": {"job_id": "job-4", "action": "death", "take": "four", "state": "complete_with_errors", "progress": 1.0, "errors": PackedStringArray(["one frame skipped"])},
	}
	dock.refresh_jobs()
	var job_list := dock.get_node("Content/Jobs") as ItemList
	assert_int(job_list.item_count).is_equal(4)
	var job_text := ""
	for index in job_list.item_count:
		job_text += job_list.get_item_text(index)
	assert_str(job_text).contains("25%")
	assert_str(job_text).contains("bad frame")
	assert_str(job_text).contains("worker failed")
	assert_str(job_text).contains("cancelled")
	assert_str(job_text).contains("complete_with_errors")
	dock.show_result("清理结果", {"errors": PackedStringArray(), "removed_path": "C:/stage/job-1", "removed_entries": 21})
	assert_str(dock.get_node("Content/Status").text).contains("C:/stage/job-1")
	assert_str(dock.get_node("Content/Status").text).contains("21")
	assert_int(dock.focus_mode).is_equal(Control.FOCUS_ALL)


func test_completed_job_row_activates_its_independent_curation_snapshot() -> void:
	var dock: Variant = auto_free(Dock.new())
	dock.build_ui()
	dock.controller.jobs = {
		"job-1": {
			"job_id": "job-1", "action": "walk", "take": "one", "state": "complete",
			"curation": {
				"manifest_path": "C:/stage/job-1/manifest.json",
				"staging_directory": "C:/stage/job-1", "action": "walk", "take": "one",
				"source_frames": [], "selection": [], "fps": 12.0, "loop": false,
			},
		},
	}
	dock.controller.job_order.assign(["job-1"])
	dock.refresh_jobs()
	dock.call("_on_job_selected", 0)
	assert_str(dock.controller.current_job_id).is_equal("job-1")
	assert_str(dock.controller.current_action).is_equal("walk")
	assert_float(dock.controller.model.fps).is_equal_approx(12.0, 0.001)
	assert_bool(dock.controller.model.loop).is_false()


func test_files_dropped_lifecycle_works_with_a_real_window_signal() -> void:
	var window: Window = auto_free(Window.new())
	var lifecycle := Lifecycle.new()
	assert_bool(lifecycle.connect_files_dropped(window, Callable(self, "_receive_drop"))).is_true()
	window.files_dropped.emit(PackedStringArray(["C:/real-window.mp4"]))
	assert_array(dropped).is_equal(["C:/real-window.mp4"])
	lifecycle.disconnect_files_dropped()
	assert_int(window.get_signal_connection_list("files_dropped").size()).is_zero()


func test_focus_dock_tab_raises_its_real_tab() -> void:
	var tabs: TabContainer = auto_free(TabContainer.new())
	add_child(tabs)
	var sibling := Control.new()
	tabs.add_child(sibling)
	var dock: Variant = Dock.new()
	dock.build_ui()
	tabs.add_child(dock)
	tabs.current_tab = 0
	dock.focus_dock_tab()
	assert_int(tabs.current_tab).is_equal(1)


func test_cancel_targets_only_the_selected_active_job() -> void:
	var dock: Variant = auto_free(Dock.new())
	dock.build_ui()
	var service := FakeCancelService.new()
	dock.controller.job_service = service
	dock.controller.jobs = {
		"job-1": {"job_id": "job-1", "action": "walk", "take": "one", "state": "running"},
		"job-2": {"job_id": "job-2", "action": "idle", "take": "two", "state": "running"},
	}
	dock.controller.job_order.assign(["job-1", "job-2"])
	dock.refresh_jobs()
	var jobs := dock.get_node("Content/Jobs") as ItemList
	jobs.select(0)
	dock.call("_cancel_current_job")
	assert_array(service.cancelled).is_equal(["job-1"])


func test_a_selected_running_job_activates_when_its_curation_completes() -> void:
	var dock: Variant = auto_free(Dock.new())
	dock.build_ui()
	dock.controller.jobs = {
		"job-1": {"job_id": "job-1", "action": "walk", "take": "one", "state": "complete", "curation": _snapshot("walk", "one")},
		"job-2": {"job_id": "job-2", "action": "idle", "take": "two", "state": "running"},
	}
	dock.controller.job_order.assign(["job-1", "job-2"])
	dock.controller.activate_job("job-1")
	dock.refresh_jobs()
	var jobs := dock.get_node("Content/Jobs") as ItemList
	jobs.select(1)
	(dock.controller.jobs["job-2"] as Dictionary)["state"] = "complete"
	(dock.controller.jobs["job-2"] as Dictionary)["curation"] = _snapshot("idle", "two")
	dock.call("_activate_selected_completed_job")
	assert_str(dock.controller.current_job_id).is_equal("job-2")
	assert_str(dock.controller.current_action).is_equal("idle")


func test_terminal_job_polling_does_not_rebuild_unchanged_frame_lists() -> void:
	var dock: Variant = auto_free(Dock.new())
	dock.build_ui()
	dock.controller.jobs = {
		"job-1": {"job_id": "job-1", "action": "walk", "take": "one", "state": "complete"},
	}
	var source := dock.get_node("Content/Lists/Source") as ItemList
	source.add_item("scroll-and-drag-sentinel")
	dock.call("_process", Dock.POLL_INTERVAL)
	assert_int(source.item_count).is_equal(1)
	assert_str(source.get_item_text(0)).is_equal("scroll-and-drag-sentinel")


func _snapshot(action: String, take: String) -> Dictionary:
	return {
		"manifest_path": "C:/stage/%s/manifest.json" % take,
		"staging_directory": "C:/stage/%s" % take, "action": action, "take": take,
		"source_frames": [], "selection": [], "fps": 12.0, "loop": true,
	}


func _receive_drop(files: PackedStringArray) -> void:
	dropped = files
