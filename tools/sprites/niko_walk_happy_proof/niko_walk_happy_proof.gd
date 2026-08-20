extends Node2D


const OUTPUT_DIR := "res://tools/sprites/niko_walk_happy_proof/output"
const ANIMATION := &"walk_down"
const CHECKER_SIZE := 48
const ROOT_Y := 750.0

@onready var _sprite: AnimatedSprite2D = $Character


func _ready() -> void:
	queue_redraw()
	if _sprite.sprite_frames == null or not _sprite.sprite_frames.has_animation(ANIMATION):
		push_error("Niko Happy proof is missing the walk_down SpriteFrames resource")
		get_tree().quit(2)
		return
	if _sprite.sprite_frames.get_frame_count(ANIMATION) != 8:
		push_error("Niko Happy proof must contain exactly eight frames")
		get_tree().quit(3)
		return
	_sprite.play(ANIMATION)
	if "--capture-proof" in OS.get_cmdline_user_args():
		call_deferred("_capture_proof")


func _draw() -> void:
	var viewport_size := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, viewport_size), Color("#e9edf2"))
	var columns := int(ceil(viewport_size.x / CHECKER_SIZE))
	var rows := int(ceil(viewport_size.y / CHECKER_SIZE))
	for y in rows:
		for x in columns:
			var colour := Color("#dce2e9") if (x + y) % 2 == 0 else Color("#f4f6f8")
			draw_rect(
				Rect2(Vector2(x, y) * CHECKER_SIZE, Vector2.ONE * CHECKER_SIZE),
				colour
			)
	draw_line(Vector2(80.0, ROOT_Y), Vector2(viewport_size.x - 80.0, ROOT_Y), Color("#9aa7b4"), 2.0)


func _capture_proof() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	_sprite.pause()
	await get_tree().process_frame
	for index in 8:
		_sprite.frame = index
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		var path := OUTPUT_DIR.path_join("walk_down_%02d.png" % index)
		var error := image.save_png(path)
		if error != OK:
			push_error("Could not save Happy proof frame %d: %s" % [index, error_string(error)])
			get_tree().quit(4)
			return
	print("niko_walk_happy_proof_frames=%s" % ProjectSettings.globalize_path(OUTPUT_DIR))
	get_tree().quit()
