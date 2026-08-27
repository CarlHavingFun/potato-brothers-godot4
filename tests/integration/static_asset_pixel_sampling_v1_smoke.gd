extends SceneTree

const TARGET_WINDOW_SIZE := Vector2i(1280, 720)
const REVIEW_SIZE := Vector2i(64, 64)
const LOGICAL_SIZE := Vector2i(32, 32)
const SAMPLE_COUNT := 6
const DEFAULT_OUTPUT_URI := "user://static-pixel-sampling-v1"
const EXPECTED_SAMPLE_KEYS := [
	"weapon/service_pistol",
	"item/ballistic_liner",
	"upgrade/one_more_round",
	"world/supply_crate",
	"ui_brand/four_state_button_normal",
	"projectile_hit_kit/static_pierce_mark",
]
const LANE_BACKGROUNDS := [
	Color8(24, 31, 42, 255),
	Color8(43, 28, 35, 255),
	Color8(25, 40, 32, 255),
	Color8(42, 37, 23, 255),
	Color8(30, 27, 48, 255),
	Color8(22, 39, 43, 255),
]

var _contract_path := ""
var _output_uri := DEFAULT_OUTPUT_URI
var _contract_sha256 := ""
var _qa_path := ""
var _qa_sha256 := ""
var _failures: Array[Dictionary] = []
var _failure_codes: Array[String] = []
var _assets: Array[Dictionary] = []
var _render_entries: Array[Dictionary] = []
var _roi_results: Array[Dictionary] = []
var _capture_path := ""
var _report_path := ""
var _capture_sha256 := ""
var _capture_size := Vector2i.ZERO
var _window_size := Vector2i.ZERO
var _base_size := Vector2i.ZERO
var _global_scale := 0
var _roi_checks_executed := false


func _initialize() -> void:
	_parse_arguments()
	if not _output_uri.begins_with("user://") or _output_uri.contains(".."):
		push_error("STATIC_ASSET_PIXEL_SAMPLING_V1_FAIL: output must be a traversal-free user:// path")
		quit(2)
		return
	if not _ensure_output_directory():
		push_error("STATIC_ASSET_PIXEL_SAMPLING_V1_FAIL: could not create isolated user:// output")
		quit(2)
		return

	_capture_path = _output_uri.path_join("capture-1280x720.png")
	_report_path = _output_uri.path_join("report.json")
	_window_size = DisplayServer.window_get_size()
	_base_size = Vector2i(
		int(ProjectSettings.get_setting("display/window/size/viewport_width", 0)),
		int(ProjectSettings.get_setting("display/window/size/viewport_height", 0))
	)

	if _contract_path.is_empty():
		_add_failure("missing_contract_argument", "--contract must name the Wave023 category contract")
	else:
		_load_contract_and_assets()

	if not _assets.is_empty() and _base_size.x > 0 and _base_size.y > 0:
		_build_capture_scene()
		await process_frame
		await RenderingServer.frame_post_draw
		await process_frame
		await RenderingServer.frame_post_draw
		_capture_and_validate()
	else:
		_add_failure("capture_prerequisites_failed", "valid assets and a positive project base size are required")

	_write_report()
	if _failures.is_empty():
		print("STATIC_ASSET_PIXEL_SAMPLING_V1_OK evidence=%s" % ProjectSettings.globalize_path(_output_uri))
		quit(0)
	else:
		print("STATIC_ASSET_PIXEL_SAMPLING_V1_FAIL codes=%s evidence=%s" % [
			",".join(_failure_codes),
			ProjectSettings.globalize_path(_output_uri),
		])
		quit(1)


func _parse_arguments() -> void:
	var arguments := OS.get_cmdline_user_args()
	var index := 0
	while index < arguments.size():
		var argument := String(arguments[index])
		if argument == "--contract" and index + 1 < arguments.size():
			_contract_path = _globalize_if_needed(String(arguments[index + 1])).simplify_path()
			index += 2
		elif argument == "--output" and index + 1 < arguments.size():
			_output_uri = String(arguments[index + 1]).trim_suffix("/").trim_suffix("\\")
			index += 2
		else:
			_add_failure("unknown_argument", "unexpected command-line argument", {"argument": argument})
			index += 1


func _ensure_output_directory() -> bool:
	var absolute := ProjectSettings.globalize_path(_output_uri)
	return DirAccess.make_dir_recursive_absolute(absolute) == OK


func _load_contract_and_assets() -> void:
	if not FileAccess.file_exists(_contract_path):
		_add_failure("missing_contract", "Wave023 category contract does not exist", {"path": _contract_path})
		return
	_contract_sha256 = FileAccess.get_sha256(_contract_path).to_upper()
	var contract_variant: Variant = JSON.parse_string(FileAccess.get_file_as_string(_contract_path))
	if not contract_variant is Dictionary:
		_add_failure("invalid_contract_json", "Wave023 category contract is not a JSON object")
		return
	var contract := contract_variant as Dictionary
	if String(contract.get("kind", "")) != "gogobro-wave023-six-category-crisp-calibration":
		_add_failure("wrong_contract_kind", "contract kind is not the Wave023 crisp calibration kind")
	if int(contract.get("schema_version", 0)) != 1:
		_add_failure("wrong_contract_schema", "contract schema_version must be 1")

	var shared: Variant = contract.get("shared_review_contract", {})
	if not shared is Dictionary:
		_add_failure("missing_shared_review_contract", "shared_review_contract must be an object")
	else:
		var shared_contract := shared as Dictionary
		if not _is_int_pair(shared_contract.get("review_canvas_px", []), 64, 64):
			_add_failure("wrong_review_canvas", "review_canvas_px must be [64, 64]")
		if not _is_int_pair(shared_contract.get("logical_canvas_px", []), 32, 32):
			_add_failure("wrong_logical_canvas", "logical_canvas_px must be [32, 32]")
		if String(shared_contract.get("alpha", "")) != "binary 0 or 255":
			_add_failure("wrong_alpha_contract", "shared alpha contract must require binary 0 or 255")

	var batch_root := _contract_path.get_base_dir().get_base_dir()
	_validate_qa(contract, batch_root)
	var samples_variant: Variant = contract.get("samples", [])
	if not samples_variant is Array:
		_add_failure("invalid_samples", "contract samples must be an array")
		return
	var samples := samples_variant as Array
	if samples.size() != SAMPLE_COUNT:
		_add_failure("wrong_sample_count", "contract must contain exactly six samples", {"actual": samples.size()})

	var seen_keys: Array[String] = []
	for sample_variant in samples:
		if not sample_variant is Dictionary:
			_add_failure("invalid_sample_entry", "every sample entry must be an object")
			continue
		var sample := sample_variant as Dictionary
		var category := String(sample.get("category", ""))
		var asset_id := String(sample.get("asset_id", ""))
		var key := "%s/%s" % [category, asset_id]
		if key in seen_keys:
			_add_failure("duplicate_sample", "sample key is duplicated", {"key": key})
			continue
		seen_keys.append(key)
		if key not in EXPECTED_SAMPLE_KEYS:
			_add_failure("unexpected_sample", "sample is outside the fixed six-category calibration set", {"key": key})

		var review_file := String(sample.get("review_file", ""))
		var path := _resolve_batch_path(batch_root, review_file)
		var expected_sha := String(sample.get("sha256", "")).to_upper()
		var record := {
			"category": category,
			"asset_id": asset_id,
			"key": key,
			"path": path,
			"declared_sha256": expected_sha,
			"actual_sha256": "",
			"size": [0, 0],
			"binary_alpha": false,
			"transparent_rgb_zero": false,
			"exact_2x2": false,
			"preflight_ok": false,
		}
		if not FileAccess.file_exists(path):
			_add_failure("missing_sample_file", "sample review_file does not exist", {"key": key, "path": path})
			_assets.append(record)
			continue
		var actual_sha := FileAccess.get_sha256(path).to_upper()
		record["actual_sha256"] = actual_sha
		if expected_sha.length() != 64 or actual_sha != expected_sha:
			_add_failure("sample_sha256_mismatch", "sample sha256 does not match the contract", {
				"key": key,
				"expected": expected_sha,
				"actual": actual_sha,
			})

		var image := Image.load_from_file(path)
		if image == null or image.is_empty():
			_add_failure("sample_decode_failed", "sample PNG could not be decoded", {"key": key, "path": path})
			_assets.append(record)
			continue
		image.convert(Image.FORMAT_RGBA8)
		record["size"] = [image.get_width(), image.get_height()]
		if image.get_size() != REVIEW_SIZE:
			_add_failure("sample_size_mismatch", "sample must be exactly 64x64", {
				"key": key,
				"actual": [image.get_width(), image.get_height()],
			})
			_assets.append(record)
			continue

		var alpha_result := _validate_alpha(image)
		record["binary_alpha"] = bool(alpha_result["binary_alpha"])
		record["transparent_rgb_zero"] = bool(alpha_result["transparent_rgb_zero"])
		if not bool(alpha_result["binary_alpha"]):
			_add_failure("sample_non_binary_alpha", "sample alpha contains values other than 0 and 255", {
				"key": key,
				"first_pixel": alpha_result.get("first_non_binary_pixel", []),
				"first_alpha": alpha_result.get("first_non_binary_alpha", -1),
			})
		if not bool(alpha_result["transparent_rgb_zero"]):
			_add_failure("sample_transparent_rgb_nonzero", "transparent sample pixels must have zero RGB", {
				"key": key,
				"first_pixel": alpha_result.get("first_nonzero_transparent_pixel", []),
			})

		var logical := _recover_exact_32(image, key)
		record["exact_2x2"] = logical != null
		record["preflight_ok"] = (
			actual_sha == expected_sha
			and bool(record["binary_alpha"])
			and bool(record["transparent_rgb_zero"])
			and logical != null
		)
		record["image64"] = image
		record["image32"] = logical
		_assets.append(record)

	seen_keys.sort()
	var expected_sorted := EXPECTED_SAMPLE_KEYS.duplicate()
	expected_sorted.sort()
	if seen_keys != expected_sorted:
		_add_failure("sample_set_mismatch", "contract does not contain the exact six expected category samples", {
			"expected": expected_sorted,
			"actual": seen_keys,
		})


func _validate_qa(contract: Dictionary, batch_root: String) -> void:
	var submission_variant: Variant = contract.get("review_submission", {})
	if not submission_variant is Dictionary:
		_add_failure("missing_review_submission", "review_submission must be an object")
		return
	var submission := submission_variant as Dictionary
	_qa_path = _resolve_batch_path(batch_root, String(submission.get("qa", "")))
	var expected_qa_sha := String(submission.get("qa_sha256", "")).to_upper()
	if not FileAccess.file_exists(_qa_path):
		_add_failure("missing_qa", "Wave023 QA file does not exist", {"path": _qa_path})
		return
	_qa_sha256 = FileAccess.get_sha256(_qa_path).to_upper()
	if expected_qa_sha.length() != 64 or _qa_sha256 != expected_qa_sha:
		_add_failure("qa_sha256_mismatch", "Wave023 QA sha256 does not match review_submission", {
			"expected": expected_qa_sha,
			"actual": _qa_sha256,
		})
	var qa_variant: Variant = JSON.parse_string(FileAccess.get_file_as_string(_qa_path))
	if not qa_variant is Dictionary:
		_add_failure("invalid_qa_json", "Wave023 QA file is not a JSON object")
		return
	var qa := qa_variant as Dictionary
	if String(qa.get("kind", "")) != "gogobro-wave023-six-category-crisp-verification":
		_add_failure("wrong_qa_kind", "Wave023 QA kind is invalid")
	if not bool(qa.get("ok", false)) or int(qa.get("asset_count", 0)) != SAMPLE_COUNT:
		_add_failure("qa_not_passed", "Wave023 QA must pass exactly six assets")
	var records_variant: Variant = qa.get("records", [])
	if not records_variant is Array or (records_variant as Array).size() != SAMPLE_COUNT:
		_add_failure("qa_record_count_mismatch", "Wave023 QA must contain six records")
		return
	for record_variant in records_variant as Array:
		if not record_variant is Dictionary:
			_add_failure("invalid_qa_record", "every Wave023 QA record must be an object")
			continue
		var record := record_variant as Dictionary
		var key := "%s/%s" % [String(record.get("category", "")), String(record.get("asset_id", ""))]
		if key not in EXPECTED_SAMPLE_KEYS:
			_add_failure("unexpected_qa_record", "Wave023 QA contains an unexpected sample", {"key": key})
		var gates_variant: Variant = record.get("gates", {})
		if not gates_variant is Dictionary:
			_add_failure("missing_qa_gates", "Wave023 QA record gates must be an object", {"key": key})
			continue
		var gates := gates_variant as Dictionary
		for gate in ["size_64", "exact_32_to_64_nearest", "binary_alpha", "transparent_rgb_zero"]:
			if not bool(gates.get(gate, false)):
				_add_failure("qa_gate_not_passed", "required Wave023 QA gate is not true", {"key": key, "gate": gate})


func _validate_alpha(image: Image) -> Dictionary:
	var result := {
		"binary_alpha": true,
		"transparent_rgb_zero": true,
		"first_non_binary_pixel": [],
		"first_non_binary_alpha": -1,
		"first_nonzero_transparent_pixel": [],
	}
	for y in image.get_height():
		for x in image.get_width():
			var color := image.get_pixel(x, y)
			var alpha := roundi(color.a * 255.0)
			if alpha != 0 and alpha != 255 and bool(result["binary_alpha"]):
				result["binary_alpha"] = false
				result["first_non_binary_pixel"] = [x, y]
				result["first_non_binary_alpha"] = alpha
			if (
				alpha == 0
				and (
					roundi(color.r * 255.0) != 0
					or roundi(color.g * 255.0) != 0
					or roundi(color.b * 255.0) != 0
				)
				and bool(result["transparent_rgb_zero"])
			):
				result["transparent_rgb_zero"] = false
				result["first_nonzero_transparent_pixel"] = [x, y]
	return result


func _recover_exact_32(image: Image, key: String) -> Image:
	var logical := Image.create(LOGICAL_SIZE.x, LOGICAL_SIZE.y, false, Image.FORMAT_RGBA8)
	for logical_y in LOGICAL_SIZE.y:
		for logical_x in LOGICAL_SIZE.x:
			var source_x := logical_x * 2
			var source_y := logical_y * 2
			var expected := image.get_pixel(source_x, source_y)
			var expected_rgba := expected.to_rgba32()
			for offset_y in 2:
				for offset_x in 2:
					var actual := image.get_pixel(source_x + offset_x, source_y + offset_y)
					if actual.to_rgba32() != expected_rgba:
						_add_failure("sample_not_exact_2x2", "sample is not an exact nearest-neighbor 32-to-64 upscale", {
							"key": key,
							"logical_pixel": [logical_x, logical_y],
							"review_pixel": [source_x + offset_x, source_y + offset_y],
							"expected": expected.to_html(true),
							"actual": actual.to_html(true),
						})
						return null
			logical.set_pixel(logical_x, logical_y, expected)
	return logical


func _build_capture_scene() -> void:
	var canvas := Node2D.new()
	canvas.name = "StaticPixelSamplingCanvas"
	get_root().add_child(canvas)

	var full_background := ColorRect.new()
	full_background.name = "CaptureBackground"
	full_background.position = Vector2.ZERO
	full_background.size = Vector2(_base_size)
	full_background.color = Color8(12, 15, 20, 255)
	full_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	full_background.z_index = -100
	canvas.add_child(full_background)

	var cell_width := floori(float(_base_size.x) / 3.0)
	var cell_height := floori(float(_base_size.y) / 2.0)
	var lane_gap := 12
	var pair_width := REVIEW_SIZE.x * 2 + lane_gap
	for index in _assets.size():
		var asset := _assets[index]
		if not bool(asset.get("preflight_ok", false)):
			continue
		var column := index % 3
		var row := index / 3
		var origin_x := column * cell_width + maxi(4, (cell_width - pair_width) / 2)
		var origin_y := row * cell_height + maxi(4, (cell_height - REVIEW_SIZE.y) / 2)
		var review_origin := Vector2i(origin_x, origin_y)
		var logical_origin := Vector2i(origin_x + REVIEW_SIZE.x + lane_gap, origin_y)
		var background: Color = LANE_BACKGROUNDS[index % LANE_BACKGROUNDS.size()]
		_add_lane(canvas, review_origin, asset["image64"] as Image, 1, background, "review64")
		_add_lane(canvas, logical_origin, asset["image32"] as Image, 2, background, "logical32")
		_render_entries.append({
			"key": String(asset["key"]),
			"review_origin": review_origin,
			"logical_origin": logical_origin,
			"background": background,
			"image64": asset["image64"],
			"image32": asset["image32"],
		})


func _add_lane(
	canvas: Node2D,
	origin: Vector2i,
	image: Image,
	local_scale: int,
	background: Color,
	label: String
) -> void:
	var keyline := ColorRect.new()
	keyline.name = "%sKeyline" % label
	keyline.position = Vector2(origin - Vector2i.ONE)
	keyline.size = Vector2(REVIEW_SIZE + Vector2i(2, 2))
	keyline.color = Color8(231, 235, 239, 255)
	keyline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	keyline.z_index = -20
	canvas.add_child(keyline)

	var lane_background := ColorRect.new()
	lane_background.name = "%sBackground" % label
	lane_background.position = Vector2(origin)
	lane_background.size = Vector2(REVIEW_SIZE)
	lane_background.color = background
	lane_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lane_background.z_index = -10
	canvas.add_child(lane_background)

	var sprite := Sprite2D.new()
	sprite.name = "%sSprite" % label
	sprite.texture = ImageTexture.create_from_image(image)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.centered = false
	sprite.position = Vector2(origin)
	sprite.scale = Vector2(local_scale, local_scale)
	sprite.z_index = 0
	canvas.add_child(sprite)


func _capture_and_validate() -> void:
	var capture := get_root().get_texture().get_image()
	if capture == null or capture.is_empty():
		_add_failure("capture_empty", "root viewport returned an empty image")
		return
	capture.convert(Image.FORMAT_RGBA8)
	_capture_size = capture.get_size()
	var capture_error := capture.save_png(ProjectSettings.globalize_path(_capture_path))
	if capture_error != OK:
		_add_failure("capture_save_failed", "capture PNG could not be saved", {"error": capture_error})
	else:
		_capture_sha256 = FileAccess.get_sha256(ProjectSettings.globalize_path(_capture_path)).to_upper()

	if _window_size != TARGET_WINDOW_SIZE:
		_add_failure("window_size_mismatch", "actual DisplayServer window must be 1280x720", {
			"expected": [TARGET_WINDOW_SIZE.x, TARGET_WINDOW_SIZE.y],
			"actual": [_window_size.x, _window_size.y],
		})
	if _capture_size != TARGET_WINDOW_SIZE:
		_add_failure("capture_size_mismatch", "captured root viewport must be the actual 1280x720 output", {
			"expected": [TARGET_WINDOW_SIZE.x, TARGET_WINDOW_SIZE.y],
			"actual": [_capture_size.x, _capture_size.y],
		})
	if _base_size.x <= 0 or _base_size.y <= 0:
		_add_failure("invalid_base_size", "project viewport base size must be positive")
		return

	var scale_x := float(TARGET_WINDOW_SIZE.x) / float(_base_size.x)
	var scale_y := float(TARGET_WINDOW_SIZE.y) / float(_base_size.y)
	var rounded_scale := roundi(scale_x)
	if (
		rounded_scale < 1
		or not is_equal_approx(scale_x, scale_y)
		or not is_equal_approx(scale_x, float(rounded_scale))
	):
		_add_failure("non_integer_global_scale", "project base-to-window scale must be one positive uniform integer", {
			"base_size": [_base_size.x, _base_size.y],
			"window_size": [TARGET_WINDOW_SIZE.x, TARGET_WINDOW_SIZE.y],
			"scale_x": scale_x,
			"scale_y": scale_y,
		})
		return
	_global_scale = rounded_scale
	if _capture_size != TARGET_WINDOW_SIZE:
		return
	_roi_checks_executed = true
	for entry in _render_entries:
		_validate_entry_rois(capture, entry)


func _validate_entry_rois(capture: Image, entry: Dictionary) -> void:
	var key := String(entry["key"])
	var background := entry["background"] as Color
	var physical_size := REVIEW_SIZE * _global_scale
	var review_origin := (entry["review_origin"] as Vector2i) * _global_scale
	var logical_origin := (entry["logical_origin"] as Vector2i) * _global_scale
	var review_rect := Rect2i(review_origin, physical_size)
	var logical_rect := Rect2i(logical_origin, physical_size)
	if not _rect_fits(review_rect, capture.get_size()) or not _rect_fits(logical_rect, capture.get_size()):
		_add_failure("roi_out_of_bounds", "rendered sample ROI is outside the captured frame", {"key": key})
		return

	var expected_review := _expected_composite(entry["image64"] as Image, _global_scale, background)
	var expected_logical := _expected_composite(entry["image32"] as Image, 2 * _global_scale, background)
	var actual_review := capture.get_region(review_rect)
	var actual_logical := capture.get_region(logical_rect)
	var review_comparison := _compare_images(expected_review, actual_review)
	var logical_comparison := _compare_images(expected_logical, actual_logical)
	var lane_comparison := _compare_images(actual_review, actual_logical)
	var result := {
		"key": key,
		"physical_size": [physical_size.x, physical_size.y],
		"review_roi": [review_rect.position.x, review_rect.position.y, review_rect.size.x, review_rect.size.y],
		"logical_roi": [logical_rect.position.x, logical_rect.position.y, logical_rect.size.x, logical_rect.size.y],
		"review_exact": bool(review_comparison["ok"]),
		"logical_exact": bool(logical_comparison["ok"]),
		"lanes_identical": bool(lane_comparison["ok"]),
		"review_first_mismatch": review_comparison.get("first_mismatch", {}),
		"logical_first_mismatch": logical_comparison.get("first_mismatch", {}),
		"lane_first_mismatch": lane_comparison.get("first_mismatch", {}),
	}
	_roi_results.append(result)
	if not bool(review_comparison["ok"]):
		_add_failure("review64_roi_mismatch", "64px@1x ROI differs byte-for-byte from nearest expected output", {
			"key": key,
			"first_mismatch": review_comparison.get("first_mismatch", {}),
		})
	if not bool(logical_comparison["ok"]):
		_add_failure("logical32_roi_mismatch", "32px@2x ROI differs byte-for-byte from nearest expected output", {
			"key": key,
			"first_mismatch": logical_comparison.get("first_mismatch", {}),
		})
	if not bool(lane_comparison["ok"]):
		_add_failure("sample_lanes_differ", "64px@1x and recovered 32px@2x runtime ROIs are not identical", {
			"key": key,
			"first_mismatch": lane_comparison.get("first_mismatch", {}),
		})


func _expected_composite(source: Image, scale: int, background: Color) -> Image:
	var scaled := source.duplicate() as Image
	scaled.resize(source.get_width() * scale, source.get_height() * scale, Image.INTERPOLATE_NEAREST)
	scaled.convert(Image.FORMAT_RGBA8)
	var expected := Image.create(scaled.get_width(), scaled.get_height(), false, Image.FORMAT_RGBA8)
	expected.fill(background)
	for y in scaled.get_height():
		for x in scaled.get_width():
			var color := scaled.get_pixel(x, y)
			if roundi(color.a * 255.0) == 255:
				expected.set_pixel(x, y, color)
	return expected


func _compare_images(expected: Image, actual: Image) -> Dictionary:
	if expected.get_size() != actual.get_size():
		return {
			"ok": false,
			"first_mismatch": {
				"reason": "size",
				"expected": [expected.get_width(), expected.get_height()],
				"actual": [actual.get_width(), actual.get_height()],
			},
		}
	for y in expected.get_height():
		for x in expected.get_width():
			var expected_color := expected.get_pixel(x, y)
			var actual_color := actual.get_pixel(x, y)
			if expected_color.to_rgba32() != actual_color.to_rgba32():
				return {
					"ok": false,
					"first_mismatch": {
						"pixel": [x, y],
						"expected": expected_color.to_html(true),
						"actual": actual_color.to_html(true),
					},
				}
	return {"ok": true, "first_mismatch": {}}


func _rect_fits(rect: Rect2i, size: Vector2i) -> bool:
	return (
		rect.position.x >= 0
		and rect.position.y >= 0
		and rect.end.x <= size.x
		and rect.end.y <= size.y
	)


func _is_int_pair(value: Variant, expected_x: int, expected_y: int) -> bool:
	if not value is Array:
		return false
	var pair := value as Array
	return pair.size() == 2 and int(pair[0]) == expected_x and int(pair[1]) == expected_y


func _write_report() -> void:
	var asset_records: Array[Dictionary] = []
	for asset in _assets:
		asset_records.append({
			"category": String(asset.get("category", "")),
			"asset_id": String(asset.get("asset_id", "")),
			"key": String(asset.get("key", "")),
			"path": String(asset.get("path", "")),
			"declared_sha256": String(asset.get("declared_sha256", "")),
			"actual_sha256": String(asset.get("actual_sha256", "")),
			"size": asset.get("size", [0, 0]),
			"binary_alpha": bool(asset.get("binary_alpha", false)),
			"transparent_rgb_zero": bool(asset.get("transparent_rgb_zero", false)),
			"exact_2x2": bool(asset.get("exact_2x2", false)),
			"preflight_ok": bool(asset.get("preflight_ok", false)),
		})
	var failure_records: Array[Dictionary] = []
	for failure in _failures:
		failure_records.append(failure.duplicate(true))
	var report := {
		"schema_version": 1,
		"kind": "gogobro-static-asset-pixel-sampling-v1",
		"ok": _failures.is_empty(),
		"contract": {
			"path": _contract_path,
			"sha256": _contract_sha256,
		},
		"wave023_qa": {
			"path": _qa_path,
			"sha256": _qa_sha256,
		},
		"renderer": {
			"display_server": DisplayServer.get_name(),
			"rendering_method": String(ProjectSettings.get_setting("rendering/renderer/rendering_method", "")),
			"rendering_driver": RenderingServer.get_current_rendering_driver_name(),
		},
		"project_output_contract": {
			"base_size": [_base_size.x, _base_size.y],
			"window_size": [_window_size.x, _window_size.y],
			"target_window_size": [TARGET_WINDOW_SIZE.x, TARGET_WINDOW_SIZE.y],
			"stretch_mode": String(ProjectSettings.get_setting("display/window/stretch/mode", "disabled")),
			"stretch_scale_mode": String(ProjectSettings.get_setting("display/window/stretch/scale_mode", "fractional(default)")),
			"global_integer_scale": _global_scale,
		},
		"asset_preflight": {
			"expected_count": SAMPLE_COUNT,
			"loaded_count": _assets.size(),
			"records": asset_records,
		},
		"capture": {
			"path": _capture_path,
			"absolute_path": ProjectSettings.globalize_path(_capture_path),
			"sha256": _capture_sha256,
			"size": [_capture_size.x, _capture_size.y],
		},
		"roi_validation": {
			"executed": _roi_checks_executed,
			"results": _roi_results,
		},
		"failure_codes": _failure_codes,
		"failures": failure_records,
	}
	var output := FileAccess.open(ProjectSettings.globalize_path(_report_path), FileAccess.WRITE)
	if output == null:
		push_error("STATIC_ASSET_PIXEL_SAMPLING_V1_FAIL: could not write report.json")
		return
	output.store_string(JSON.stringify(report, "\t"))
	output.close()


func _resolve_batch_path(batch_root: String, declared_path: String) -> String:
	if declared_path.begins_with("res://") or declared_path.begins_with("user://"):
		return ProjectSettings.globalize_path(declared_path).simplify_path()
	if declared_path.is_absolute_path():
		return declared_path.simplify_path()
	return batch_root.path_join(declared_path).simplify_path()


func _globalize_if_needed(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	return path


func _add_failure(code: String, message: String, details := {}) -> void:
	if code not in _failure_codes:
		_failure_codes.append(code)
	var record := {"code": code, "message": message}
	if details is Dictionary and not (details as Dictionary).is_empty():
		record["details"] = (details as Dictionary).duplicate(true)
	_failures.append(record)
