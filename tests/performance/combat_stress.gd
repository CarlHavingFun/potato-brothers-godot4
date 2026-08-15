extends Node2D


const ENEMY_COUNT := 250
const PROJECTILE_COUNT := 200
const WARMUP_FRAMES := 120
const SAMPLE_FRAMES := 300
const MINIMUM_AVERAGE_FPS := 60.0
const MINIMUM_ONE_PERCENT_LOW_FPS := 55.0
const REPORT_PATH := "res://reports/performance/combat_stress.json"

var measured_frames := 0
var warmup_frames := 0
var sample_started_usec := 0
var previous_frame_usec := 0
var frame_times_usec := PackedFloat64Array()


func _ready() -> void:
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_setup_run()
	_spawn_enemies()
	_spawn_projectiles()
	print("Stress scene ready: %d enemies + %d projectiles" % [ENEMY_COUNT, PROJECTILE_COUNT])


func _process(_delta: float) -> void:
	if warmup_frames < WARMUP_FRAMES:
		warmup_frames += 1
		if warmup_frames == WARMUP_FRAMES:
			sample_started_usec = Time.get_ticks_usec()
			previous_frame_usec = sample_started_usec
		return
	var current_frame_usec := Time.get_ticks_usec()
	frame_times_usec.append(float(current_frame_usec - previous_frame_usec))
	previous_frame_usec = current_frame_usec
	measured_frames += 1
	if measured_frames < SAMPLE_FRAMES:
		return
	var elapsed_seconds := maxf(0.001, float(Time.get_ticks_usec() - sample_started_usec) / 1_000_000.0)
	var average_fps := float(measured_frames) / elapsed_seconds
	var one_percent_low_fps := _one_percent_low_fps(frame_times_usec)
	var result := {
		"resolution": "%dx%d" % [get_viewport_rect().size.x, get_viewport_rect().size.y],
		"enemies": ENEMY_COUNT,
		"projectiles": PROJECTILE_COUNT,
		"sample_frames": measured_frames,
		"elapsed_seconds": elapsed_seconds,
		"average_fps": average_fps,
		"one_percent_low_fps": one_percent_low_fps,
		"minimum_average_fps": MINIMUM_AVERAGE_FPS,
		"minimum_one_percent_low_fps": MINIMUM_ONE_PERCENT_LOW_FPS,
		"passed": (
			average_fps >= MINIMUM_AVERAGE_FPS
			and one_percent_low_fps >= MINIMUM_ONE_PERCENT_LOW_FPS
		),
	}
	_write_report(result)
	print("PERFORMANCE_RESULT %s" % JSON.stringify(result))
	get_tree().quit(OK if result.passed else FAILED)


func _one_percent_low_fps(frame_times: PackedFloat64Array) -> float:
	if frame_times.is_empty():
		return 0.0
	var sorted_times := Array(frame_times)
	sorted_times.sort()
	var slow_frame_count := maxi(1, ceili(sorted_times.size() * 0.01))
	var total_slow_time_usec := 0.0
	for index: int in range(sorted_times.size() - slow_frame_count, sorted_times.size()):
		total_slow_time_usec += float(sorted_times[index])
	var average_slow_time_usec := total_slow_time_usec / slow_frame_count
	return 1_000_000.0 / maxf(1.0, average_slow_time_usec)


func _setup_run() -> void:
	var character := Content.catalog.get_character(&"character/well_rounded")
	Global.begin_run(20260814, character.stats, 12)
	Global.current_run.character_id = character.get_stable_id(Content.catalog.pack_id)
	Global.enter_phase(RunPhase.COMBAT)
	var player_instance: Player = character.scene.instantiate()
	Global.player = player_instance
	player_instance.global_position = Vector2.ZERO
	add_child(player_instance)


func _spawn_enemies() -> void:
	var scene: PackedScene = Content.catalog.get_enemy(&"enemy/chaser_slow").scene
	for index: int in range(ENEMY_COUNT):
		var enemy: Enemy = scene.instantiate()
		var column := index % 25
		var row := index / 25
		enemy.position = Vector2(-900 + column * 75, -430 + row * 95)
		add_child(enemy)


func _spawn_projectiles() -> void:
	var scene := load("res://scenes/projectiles/projectile_pistol.tscn") as PackedScene
	for index: int in range(PROJECTILE_COUNT):
		var projectile: Projectile = scene.instantiate()
		var column := index % 20
		var row := index / 20
		projectile.position = Vector2(-850 + column * 90, -400 + row * 85)
		add_child(projectile)
		projectile.set_projectile(Vector2(20.0, 0.0), 1.0, false, 0.0, Global.player)


func _write_report(result: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(REPORT_PATH.get_base_dir()))
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(result, "\t") + "\n")
