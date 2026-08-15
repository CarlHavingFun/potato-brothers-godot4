class_name GameplayCuePresenter
extends Node


signal cue_presented(cue_id: StringName, resolved: Dictionary)

var _hit_stop_generation := 0


func _ready() -> void:
	if not GameplayCues.cue_emitted.is_connected(handle_cue):
		GameplayCues.cue_emitted.connect(handle_cue)


func handle_cue(cue_id: StringName, context: Dictionary) -> void:
	var resolved := Presentation.resolve_cue(cue_id)
	cue_presented.emit(cue_id, resolved.duplicate(true))
	if DisplayServer.get_name() == "headless":
		return
	_play_audio(str(resolved.get("audio", "")))
	_spawn_particles(str(resolved.get("particle", "")), context)
	_apply_screen_shake(resolved.get("screen_shake", {}) as Dictionary)
	_apply_rumble(resolved.get("rumble", {}) as Dictionary)
	if cue_id == &"hit.critical":
		_request_hit_stop(0.035)


func _play_audio(path: String) -> void:
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	var stream := load(path) as AudioStream
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = &"SFX"
	add_child(player)
	player.finished.connect(func() -> void: player.queue_free())
	player.play()


func _spawn_particles(path: String, context: Dictionary) -> void:
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	var scene := load(path) as PackedScene
	if scene == null:
		return
	var instance := scene.instantiate()
	get_tree().current_scene.add_child(instance)
	if instance is Node2D:
		var world_position: Variant = context.get("world_position", Vector2.ZERO)
		(instance as Node2D).global_position = world_position if world_position is Vector2 else Vector2.ZERO


func _apply_screen_shake(definition: Dictionary) -> void:
	var strength := float(definition.get("strength", 0.0))
	if strength <= 0.0 or get_tree() == null:
		return
	for camera: Node in get_tree().get_nodes_in_group(&"presentation_camera"):
		if camera.has_method("add_trauma"):
			camera.call("add_trauma", strength / 20.0)


func _apply_rumble(definition: Dictionary) -> void:
	var duration := float(definition.get("duration", 0.0))
	if duration <= 0.0:
		return
	for device_id: int in Input.get_connected_joypads():
		Input.start_joy_vibration(
			device_id,
			clampf(float(definition.get("weak", 0.0)), 0.0, 1.0),
			clampf(float(definition.get("strong", 0.0)), 0.0, 1.0),
			duration
		)


func _request_hit_stop(duration: float) -> void:
	_hit_stop_generation += 1
	var generation := _hit_stop_generation
	Engine.time_scale = 0.12
	await get_tree().create_timer(duration, true, false, true).timeout
	if generation == _hit_stop_generation:
		Engine.time_scale = 1.0
