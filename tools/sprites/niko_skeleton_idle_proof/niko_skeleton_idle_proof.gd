extends Node2D

## Local-only Skeleton2D proof built from the canonical Niko front mother frame.
## The source is split deterministically into three complementary rigid layers.

const SOURCE_IMAGE := "E:/01_gobro/pixel/niko/seed-front-300.png"
const OUTPUT_DIR := "res://tools/sprites/niko_skeleton_idle_proof/output"
const PARTS_DIR := "res://tools/sprites/niko_skeleton_idle_proof/parts"

@export_file("*.json") var action_file := "res://tools/sprites/niko_skeleton_idle_proof/actions/idle_front.json"

var _animation_name: StringName = &"idle_front"
var _frame_time := 0.2
var _frame_count := 8

@onready var _feet_sprite: Sprite2D = $Character/Skeleton2D/Root/Feet/FeetSprite
@onready var _torso_sprite: Sprite2D = $Character/Skeleton2D/Root/Torso/TorsoSprite
@onready var _head_sprite: Sprite2D = $Character/Skeleton2D/Root/Torso/Head/HeadSprite
@onready var _root_bone: Bone2D = $Character/Skeleton2D/Root
@onready var _feet_bone: Bone2D = $Character/Skeleton2D/Root/Feet
@onready var _torso_bone: Bone2D = $Character/Skeleton2D/Root/Torso
@onready var _head_bone: Bone2D = $Character/Skeleton2D/Root/Torso/Head
@onready var _arm_left_bone: Bone2D = $Character/Skeleton2D/Root/Torso/ArmLeft
@onready var _arm_right_bone: Bone2D = $Character/Skeleton2D/Root/Torso/ArmRight
@onready var _animation_player: AnimationPlayer = $AnimationPlayer


func _enter_tree() -> void:
	# Disable leaf-bone auto measurement before Skeleton2D enters the tree. The
	# proof uses explicit pixel pivots, so child-derived lengths are undesirable.
	var lengths := {
		"Character/Skeleton2D/Root": 24.0,
		"Character/Skeleton2D/Root/Feet": 16.0,
		"Character/Skeleton2D/Root/Torso": 52.0,
		"Character/Skeleton2D/Root/Torso/Head": 70.0,
		"Character/Skeleton2D/Root/Torso/ArmLeft": 30.0,
		"Character/Skeleton2D/Root/Torso/ArmRight": 30.0,
	}
	for path in lengths:
		var bone := get_node_or_null(NodePath(path)) as Bone2D
		if bone != null:
			bone.set_autocalculate_length_and_angle(false)
			bone.set_length(lengths[path])
			bone.set_bone_angle(0.0)


func _ready() -> void:
	if not FileAccess.file_exists(SOURCE_IMAGE):
		push_error("Missing Niko mother frame: %s" % SOURCE_IMAGE)
		get_tree().quit(2)
		return
	_build_rigid_parts()
	_store_rest_pose()
	_build_action_animation()
	_animation_player.play(_animation_name)
	if "--capture-proof" in OS.get_cmdline_user_args():
		call_deferred("_capture_proof")


func _build_rigid_parts() -> void:
	var source := Image.load_from_file(SOURCE_IMAGE)
	if source == null or source.is_empty():
		push_error("Could not decode Niko mother frame: %s" % SOURCE_IMAGE)
		get_tree().quit(3)
		return
	source.convert(Image.FORMAT_RGBA8)
	var head := Image.create(source.get_width(), source.get_height(), false, Image.FORMAT_RGBA8)
	var torso := Image.create(source.get_width(), source.get_height(), false, Image.FORMAT_RGBA8)
	var feet := Image.create(source.get_width(), source.get_height(), false, Image.FORMAT_RGBA8)
	head.fill(Color.TRANSPARENT)
	torso.fill(Color.TRANSPARENT)
	feet.fill(Color.TRANSPARENT)

	for y in source.get_height():
		for x in source.get_width():
			var pixel := source.get_pixel(x, y)
			if pixel.a <= 0.0:
				continue
			if _belongs_to_head(x, y):
				head.set_pixel(x, y, pixel)
			else:
				# A ten-pixel overlap hides the rigid torso/feet joint while the
				# torso breathes by two pixels. Identical opaque pixels overlap in
				# the rest pose, so the visible result still matches the source.
				if y >= 262 and y < 272 and pixel.a >= 0.999:
					# Only fully opaque pixels are duplicated; duplicating a soft
					# alpha edge would darken it in the rest pose.
					torso.set_pixel(x, y, pixel)
					feet.set_pixel(x, y, pixel)
				elif y < 267:
					torso.set_pixel(x, y, pixel)
				else:
					feet.set_pixel(x, y, pixel)

	_head_sprite.texture = ImageTexture.create_from_image(head)
	_torso_sprite.texture = ImageTexture.create_from_image(torso)
	_feet_sprite.texture = ImageTexture.create_from_image(feet)

	if "--capture-proof" in OS.get_cmdline_user_args():
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PARTS_DIR))
		head.save_png(PARTS_DIR.path_join("head.png"))
		torso.save_png(PARTS_DIR.path_join("torso.png"))
		feet.save_png(PARTS_DIR.path_join("feet.png"))


func _belongs_to_head(x: int, y: int) -> bool:
	# A tapered hard mask follows the beard/chin silhouette. The three output
	# layers are complementary, so their rest pose reconstructs the source.
	if y <= 202:
		return true
	if y <= 223:
		var inset := y - 202
		return x >= 70 + inset and x <= 229 - inset
	if y <= 247:
		var inset := int(round(float(y - 223) * 0.42))
		return x >= 92 + inset and x <= 207 - inset
	return false


func _store_rest_pose() -> void:
	for bone in [_root_bone, _feet_bone, _torso_bone, _head_bone, _arm_left_bone, _arm_right_bone]:
		bone.rest = bone.transform


func _build_action_animation() -> void:
	var action_text := FileAccess.get_file_as_string(action_file)
	var action: Variant = JSON.parse_string(action_text)
	if not action is Dictionary:
		push_error("Invalid action JSON: %s" % action_file)
		get_tree().quit(5)
		return
	_animation_name = StringName(str(action.get("name", "idle_front")))
	var fps := float(action.get("fps", 5.0))
	_frame_count = int(action.get("frameCount", 8))
	if fps <= 0.0 or _frame_count <= 0:
		push_error("Action fps and frameCount must be positive")
		get_tree().quit(6)
		return
	_frame_time = 1.0 / fps

	var animation := Animation.new()
	animation.resource_name = str(_animation_name)
	animation.length = _frame_time * _frame_count
	animation.loop_mode = Animation.LOOP_LINEAR if bool(action.get("loop", true)) else Animation.LOOP_NONE
	for track_spec in action.get("tracks", []):
		if not track_spec is Dictionary:
			continue
		var values: Array = []
		match str(track_spec.get("valueType", "")):
			"Vector2":
				for pair in track_spec.get("values", []):
					values.append(Vector2(float(pair[0]), float(pair[1])))
			"float":
				for value in track_spec.get("values", []):
					values.append(float(value))
			_:
				push_error("Unsupported action valueType: %s" % track_spec.get("valueType", ""))
				get_tree().quit(7)
				return
		if values.size() != _frame_count:
			push_error("Action track must contain %d values: %s" % [_frame_count, track_spec.get("path", "")])
			get_tree().quit(8)
			return
		_add_discrete_track(animation, NodePath(str(track_spec.get("path", ""))), values)
	# Head stays rigidly attached to the torso in this first proof. Its named
	# Bone2D remains available for later nod/talk clips after hidden neck pixels
	# are completed; moving it now would expose pixels absent from one front PNG.

	var library := AnimationLibrary.new()
	var error := library.add_animation(_animation_name, animation)
	if error != OK:
		push_error("Could not add %s animation: %s" % [_animation_name, error_string(error)])
		return
	_animation_player.add_animation_library(&"", library)


func _add_discrete_track(animation: Animation, path: NodePath, values: Array) -> void:
	var track := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track, path)
	animation.track_set_interpolation_type(track, Animation.INTERPOLATION_NEAREST)
	for index in values.size():
		animation.track_insert_key(track, _frame_time * index, values[index])


func _capture_proof() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	_animation_player.pause()
	await get_tree().process_frame
	for index in _frame_count:
		_animation_player.seek(_frame_time * index, true)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		var path := OUTPUT_DIR.path_join("idle_front_%02d.png" % index)
		var error := image.save_png(path)
		if error != OK:
			push_error("Could not save proof frame %d: %s" % [index, error_string(error)])
			get_tree().quit(4)
			return
	print("niko_skeleton_idle_proof_frames=%s" % ProjectSettings.globalize_path(OUTPUT_DIR))
	get_tree().quit()
