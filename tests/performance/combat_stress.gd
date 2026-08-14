extends Node2D


const ENEMY_COUNT := 250
const PROJECTILE_COUNT := 200
const WARMUP_FRAMES := 120
const SAMPLE_FRAMES := 300
const MINIMUM_AVERAGE_FPS := 55.0
const REPORT_PATH := "res://reports/performance/combat_stress.json"

var measured_frames := 0
var warmup_frames := 0
var sample_started_usec := 0


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
		return
	measured_frames += 1
	if measured_frames < SAMPLE_FRAMES:
		return
	var elapsed_seconds := maxf(0.001, float(Time.get_ticks_usec() - sample_started_usec) / 1_000_000.0)
	var average_fps := float(measured_frames) / elapsed_seconds
	var result := {
		"resolution": "%dx%d" % [get_viewport_rect().size.x, get_viewport_rect().size.y],
		"enemies": ENEMY_COUNT,
		"projectiles": PROJECTILE_COUNT,
		"sample_frames": measured_frames,
		"elapsed_seconds": elapsed_seconds,
		"average_fps": average_fps,
		"minimum_fps": MINIMUM_AVERAGE_FPS,
		"passed": average_fps >= MINIMUM_AVERAGE_FPS,
	}
	_write_report(result)
	print("PERFORMANCE_RESULT %s" % JSON.stringify(result))
	get_tree().quit(OK if result.passed else FAILED)


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
