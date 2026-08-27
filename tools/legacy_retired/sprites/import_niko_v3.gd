extends Node


const DEFAULT_OUTPUT_DIR := "res://content_packs/default/assets/sprites/players/niko_v3"
const BASE_PLAYER_SCENE := "res://scenes/unit/players/player_well_rounded.tscn"
const BASE_CHARACTER_ID := &"character/well_rounded"
const DEFAULT_PACK_PATH := "res://content_packs/default/pack.tres"
const VISUAL_SCRIPT := "res://core/presentation/directional_sprite_visual.gd"


func _ready() -> void:
	_run()


func _run() -> void:
	var arguments := OS.get_cmdline_user_args()
	var manifest_path := _argument(arguments, "--manifest", "")
	var output_dir := _argument(arguments, "--output-dir", DEFAULT_OUTPUT_DIR).trim_suffix("/")
	if manifest_path.is_empty():
		_fail("usage: --manifest <res://path/to/sprite_manifest.json> [--output-dir <res://dir>]")
		return
	if not manifest_path.begins_with("res://"):
		_fail("manifest must be inside the Godot project and use a res:// path")
		return
	if not output_dir.begins_with("res://") or output_dir.contains(".."):
		_fail("output-dir must resolve inside res://")
		return

	var parsed := DirectionalSpriteManifestImporter.parse_manifest_file(manifest_path)
	var errors := parsed.get("errors", PackedStringArray()) as PackedStringArray
	if not errors.is_empty():
		_fail("manifest validation failed:\n%s" % "\n".join(errors))
		return
	var manifest := parsed["manifest"] as Dictionary
	var build_result := DirectionalSpriteManifestImporter.build_sprite_frames(manifest)
	errors = build_result.get("errors", PackedStringArray()) as PackedStringArray
	if not errors.is_empty():
		_fail("sprite frame import failed:\n%s" % "\n".join(errors))
		return

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	var frames_path := output_dir.path_join("niko_v3_sprite_frames.tres")
	var scene_path := output_dir.path_join("player_niko_v3.tscn")
	var character_path := output_dir.path_join("character_niko_v3.tres")
	var save_result := ResourceSaver.save(build_result["sprite_frames"] as SpriteFrames, frames_path)
	if save_result != OK:
		_fail("could not save SpriteFrames: %s" % error_string(save_result))
		return
	if _write_scene(scene_path, frames_path, manifest) != OK:
		return
	var scene := ResourceLoader.load(scene_path, "PackedScene", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	if scene == null:
		_fail("generated scene could not be loaded: %s" % scene_path)
		return
	if _write_character_definition(character_path, scene) != OK:
		return
	print("Generated Niko v3 Godot resources:")
	print("  %s" % frames_path)
	print("  %s" % scene_path)
	print("  %s" % character_path)
	if output_dir == DEFAULT_OUTPUT_DIR:
		print("The optional character will be discovered on the next project start.")
	else:
		print("Custom output directories are not auto-registered by the bootstrap loader.")
	get_tree().quit(OK)


func _write_scene(path: String, frames_path: String, manifest: Dictionary) -> int:
	var frame_size := manifest["frame_size"] as Dictionary
	var pivot := manifest["pivot"] as Dictionary
	var visual_position := Vector2(
		float(frame_size["width"]) * 0.5 - float(pivot["x"]),
		float(frame_size["height"]) * 0.5 - float(pivot["y"])
	)
	var visual_scale := float(manifest.get("godot_visual_scale", 0.7))
	var source := """[gd_scene load_steps=4 format=3]

[ext_resource type=\"PackedScene\" path=\"%s\" id=\"1_base\"]
[ext_resource type=\"SpriteFrames\" path=\"%s\" id=\"2_frames\"]
[ext_resource type=\"Script\" path=\"%s\" id=\"3_visual\"]

[node name=\"PlayerNikoV3\" instance=ExtResource(\"1_base\")]

[node name=\"Sprite\" parent=\"Visuals\" index=\"2\"]
visible = false

[node name=\"DirectionalSpriteVisual\" type=\"AnimatedSprite2D\" parent=\"Visuals\" index=\"3\"]
unique_name_in_owner = true
texture_filter = 1
z_index = 1
position = Vector2(%s, %s)
scale = Vector2(%s, %s)
sprite_frames = ExtResource(\"2_frames\")
script = ExtResource(\"3_visual\")
""" % [
		BASE_PLAYER_SCENE,
		frames_path,
		VISUAL_SCRIPT,
		visual_position.x,
		visual_position.y,
		visual_scale,
		visual_scale,
	]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("could not write scene: %s" % path)
		return FileAccess.get_open_error()
	file.store_string(source)
	return OK


func _write_character_definition(path: String, scene: PackedScene) -> int:
	var pack := ResourceLoader.load(
		DEFAULT_PACK_PATH, "ContentPackDef", ResourceLoader.CACHE_MODE_REPLACE
	) as ContentPackDef
	if pack == null:
		_fail("default content pack could not be loaded")
		return ERR_INVALID_DATA
	var base_character: CharacterDef
	for candidate: CharacterDef in pack.characters:
		if candidate.content_id == BASE_CHARACTER_ID:
			base_character = candidate
			break
	if base_character == null or base_character.stats == null:
		_fail("base character is missing: %s" % BASE_CHARACTER_ID)
		return ERR_DOES_NOT_EXIST
	var niko_icon := _extract_niko_icon(scene)
	if niko_icon == null:
		_fail("generated scene is missing idle_down frame 0 for the Niko icon")
		return ERR_INVALID_DATA

	var definition := CharacterDef.new()
	definition.content_id = &"character/niko_v3"
	definition.presentation_id = &"character.niko_v3"
	definition.display_name_key = &"character.niko_v3.name"
	definition.description_key = &"character.niko_v3.description"
	definition.tags = [&"balanced", &"eight_direction", &"niko"]
	definition.scene = scene
	definition.stats = base_character.stats.duplicate(true) as UnitStats
	definition.stats.name = "Niko"
	definition.stats.icon = niko_icon
	definition.starter_weapon_ids = base_character.starter_weapon_ids.duplicate()
	definition.unlock_difficulty = 1
	definition.rules = (
		base_character.rules.duplicate(true) as CharacterRuleDef
		if base_character.rules != null
		else null
	)
	var result := ResourceSaver.save(definition, path)
	if result != OK:
		_fail("could not save CharacterDef: %s" % error_string(result))
	return result


func _extract_niko_icon(scene: PackedScene) -> Texture2D:
	var instance := scene.instantiate()
	if instance == null:
		return null
	var visual := instance.get_node_or_null("Visuals/DirectionalSpriteVisual") as AnimatedSprite2D
	var icon: Texture2D
	if visual != null and visual.sprite_frames != null \
	and visual.sprite_frames.has_animation(&"idle_down") \
	and visual.sprite_frames.get_frame_count(&"idle_down") > 0:
		icon = visual.sprite_frames.get_frame_texture(&"idle_down", 0)
	instance.free()
	return icon


func _argument(arguments: PackedStringArray, name: String, fallback: String) -> String:
	var index := arguments.find(name)
	return arguments[index + 1] if index >= 0 and index + 1 < arguments.size() else fallback


func _fail(message: String) -> void:
	printerr(message)
	get_tree().quit(ERR_INVALID_DATA)
