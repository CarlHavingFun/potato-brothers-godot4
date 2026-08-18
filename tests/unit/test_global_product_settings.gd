extends GdUnitTestSuite


const TEST_SETTINGS_ROOT := "user://tests/global_product_settings"
const TEST_PROFILE_ROOT := "user://tests/global_product_settings_profiles"
const TEST_LEGACY_PATH := "user://tests/global_product_settings_legacy/save_v1.json"
const TEST_PROGRESS_PATH := "user://tests/global_product_settings_progress/save_v1.json"
const INPUT_ACTIONS: Array[StringName] = [
	&"move_up", &"move_down", &"move_left", &"move_right", &"dash", &"pause",
	&"aim_up", &"aim_down", &"aim_left", &"aim_right",
]
const AUDIO_BUSES: Array[StringName] = [&"Master", &"Music", &"SFX"]

var _original_product_settings: ProductSettings
var _original_settings_store: SettingsStore
var _original_settings_initialized: bool
var _original_save_provider: SaveProvider
var _original_meta_progress: MetaProgress
var _original_restored_run: RunState
var _original_aim_mode: int
var _original_locale: String
var _original_fps_cap: int
var _original_ui_scale: float
var _original_tree_paused: bool
var _original_input_events: Dictionary = {}
var _original_deadzones: Dictionary = {}
var _original_audio_state: Dictionary = {}


func before_test() -> void:
	_original_product_settings = Global.product_settings.copy()
	_original_settings_store = Global.settings_store
	_original_settings_initialized = Global._settings_initialized
	_original_save_provider = Global.save_provider
	_original_meta_progress = Global.meta_progress
	_original_restored_run = Global.restored_run
	_original_aim_mode = Global.aim_mode
	_original_locale = TranslationServer.get_locale()
	_original_fps_cap = Engine.max_fps
	_original_ui_scale = ThemeDB.fallback_base_scale
	_original_tree_paused = get_tree().paused
	_snapshot_input_state()
	_snapshot_audio_state()
	_cleanup_files()

	get_tree().paused = false
	Global.end_run()
	Global.meta_progress = MetaProgress.new()
	Global.restored_run = null
	Global.save_provider = LocalSaveProvider.new(TEST_PROGRESS_PATH)
	Global.settings_store = SettingsStore.new(TEST_SETTINGS_ROOT)
	Global._settings_initialized = true
	Global._paused_by_focus_loss = false
	Global._muted_by_focus_loss = false
	assert_bool(Global.preview_product_settings(ProductSettings.new())).is_true()


func after_test() -> void:
	get_tree().paused = false
	Global.call("_handle_focus_regained")
	Global.end_run()
	Global.restore_product_settings(_original_product_settings)
	_restore_input_state()
	_restore_audio_state()
	Engine.max_fps = _original_fps_cap
	ThemeDB.fallback_base_scale = _original_ui_scale
	TranslationServer.set_locale(_original_locale)
	get_tree().paused = _original_tree_paused
	Global.product_settings = _original_product_settings
	Global.settings_store = _original_settings_store
	Global._settings_initialized = _original_settings_initialized
	Global.save_provider = _original_save_provider
	Global.meta_progress = _original_meta_progress
	Global.restored_run = _original_restored_run
	Global.aim_mode = _original_aim_mode
	Global._paused_by_focus_loss = false
	Global._muted_by_focus_loss = false
	_cleanup_files()


func test_apply_persists_while_preview_and_restore_are_transactional() -> void:
	var applied := ProductSettings.new()
	applied.master_volume = 0.55
	applied.music_volume = 0.4
	applied.sfx_volume = 0.65
	applied.fps_cap = 120
	applied.aim_mode = AimMode.MANUAL_MOUSE
	applied.locale = "en"
	applied.enemy_health_scale = 0.75

	assert_bool(Global.apply_product_settings(applied, true)).is_true()
	assert_bool(Global.product_settings.is_equal_to(applied)).is_true()
	assert_bool(Global.settings_store.load_settings().is_equal_to(applied)).is_true()
	assert_int(Global.aim_mode).is_equal(AimMode.MANUAL_MOUSE)
	assert_str(TranslationServer.get_locale()).is_equal("en")
	assert_int(Engine.max_fps).is_equal(120)
	var music_bus := AudioServer.get_bus_index(&"Music")
	assert_float(db_to_linear(AudioServer.get_bus_volume_db(music_bus))).is_equal_approx(0.4, 0.001)

	var preview := applied.copy()
	preview.master_volume = 0.2
	preview.locale = "zh_CN"
	preview.enemy_health_scale = 1.5
	assert_bool(Global.preview_product_settings(preview)).is_true()
	assert_float(Global.product_settings.master_volume).is_equal(0.2)
	assert_float(Global.product_settings.enemy_health_scale).is_equal(1.5)
	assert_str(TranslationServer.get_locale()).is_equal("zh_CN")
	assert_bool(Global.settings_store.load_settings().is_equal_to(applied)).is_true()

	assert_bool(Global.restore_product_settings(applied)).is_true()
	assert_bool(Global.product_settings.is_equal_to(applied)).is_true()
	assert_bool(Global.settings_store.load_settings().is_equal_to(applied)).is_true()


func test_switching_profiles_does_not_replace_global_settings() -> void:
	var shared := ProductSettings.new()
	shared.music_volume = 0.42
	shared.enemy_damage_scale = 0.8
	assert_bool(Global.apply_product_settings(shared, true)).is_true()

	var store := ProfileStore.new(TEST_PROFILE_ROOT, TEST_LEGACY_PATH)
	assert_int(store.save_profile(1, {"meta_progress": {
		"highest_unlocked_difficulty": 2,
		"music_volume": 0.1,
		"enemy_damage_scale": 1.5,
	}})).is_equal(OK)
	assert_int(store.save_profile(2, {"meta_progress": {
		"highest_unlocked_difficulty": 4,
		"music_volume": 0.9,
		"enemy_damage_scale": 1.75,
	}})).is_equal(OK)
	Global.save_provider = ProfileSaveProvider.new(store, 1)

	assert_bool(Global.load_progress()).is_true()
	assert_int(Global.meta_progress.highest_unlocked_difficulty).is_equal(2)
	assert_float(Global.product_settings.music_volume).is_equal(0.42)
	assert_bool(Global.switch_profile(2)).is_true()

	assert_int(Global.meta_progress.highest_unlocked_difficulty).is_equal(4)
	assert_float(Global.product_settings.music_volume).is_equal(0.42)
	assert_float(Global.product_settings.enemy_damage_scale).is_equal(0.8)
	assert_float(Global.settings_store.load_settings().music_volume).is_equal(0.42)


func test_enemy_assists_scale_combat_numbers_without_disabling_unlocks() -> void:
	var assisted := ProductSettings.new()
	assisted.enemy_health_scale = 0.5
	assisted.enemy_damage_scale = 0.75
	assisted.enemy_speed_scale = 0.8
	assert_bool(Global.apply_product_settings(assisted, true)).is_true()

	var base_stats := UnitStats.new()
	base_stats.health = 100
	base_stats.health_increase_per_wave = 0.0
	base_stats.damage = 10.0
	base_stats.damage_increase_per_wave = 0.0
	base_stats.speed = 200
	var scaled := Spawner.build_enemy_stats_for_wave(
		base_stats,
		1,
		1,
		[],
		null,
		{
			"health": Global.product_settings.enemy_health_scale,
			"damage": Global.product_settings.enemy_damage_scale,
			"speed": Global.product_settings.enemy_speed_scale,
		}
	)
	assert_int(scaled.health).is_equal(50)
	assert_float(scaled.damage).is_equal(7.5)
	assert_int(scaled.speed).is_equal(160)
	assert_int(Global.meta_progress.highest_unlocked_difficulty).is_equal(1)

	Global.begin_run(20260818)
	Global.current_run.character_id = &"core:character/well_rounded"
	Global.current_run.difficulty = 1
	assert_bool(Global.record_victory()).is_true()
	assert_int(Global.meta_progress.highest_unlocked_difficulty).is_equal(2)
	assert_int(Global.meta_progress.highest_clear_for(
		&"core:character/well_rounded"
	)).is_equal(1)


func test_focus_loss_temporarily_pauses_and_mutes_without_overriding_manual_pause() -> void:
	var settings := ProductSettings.new()
	settings.master_volume = 0.6
	settings.mute_on_focus_lost = true
	settings.pause_on_focus_lost = true
	assert_bool(Global.preview_product_settings(settings)).is_true()
	Global.begin_run(7)
	Global.current_run.phase = RunPhase.COMBAT
	var master_bus := AudioServer.get_bus_index(&"Master")

	Global.call("_handle_focus_lost")
	assert_bool(get_tree().paused).is_true()
	assert_bool(Global._paused_by_focus_loss).is_true()
	assert_bool(AudioServer.is_bus_mute(master_bus)).is_true()
	Global.call("_handle_focus_regained")
	assert_bool(get_tree().paused).is_false()
	assert_bool(AudioServer.is_bus_mute(master_bus)).is_false()
	assert_float(db_to_linear(AudioServer.get_bus_volume_db(master_bus))).is_equal_approx(0.6, 0.001)

	get_tree().paused = true
	Global.call("_handle_focus_lost")
	assert_bool(Global._paused_by_focus_loss).is_false()
	Global.call("_handle_focus_regained")
	assert_bool(get_tree().paused).is_true()
	get_tree().paused = false


func _snapshot_input_state() -> void:
	_original_input_events.clear()
	_original_deadzones.clear()
	for action: StringName in INPUT_ACTIONS:
		if not InputMap.has_action(action):
			continue
		var events: Array[InputEvent] = []
		for event: InputEvent in InputMap.action_get_events(action):
			events.append(event.duplicate(true) as InputEvent)
		_original_input_events[action] = events
		_original_deadzones[action] = InputMap.action_get_deadzone(action)


func _restore_input_state() -> void:
	for raw_action: Variant in _original_input_events:
		var action := StringName(raw_action)
		InputMap.action_erase_events(action)
		for event: InputEvent in _original_input_events[raw_action]:
			InputMap.action_add_event(action, event)
		InputMap.action_set_deadzone(action, float(_original_deadzones[raw_action]))


func _snapshot_audio_state() -> void:
	_original_audio_state.clear()
	for bus_name: StringName in AUDIO_BUSES:
		var bus_index := AudioServer.get_bus_index(bus_name)
		if bus_index < 0:
			continue
		_original_audio_state[bus_name] = {
			"mute": AudioServer.is_bus_mute(bus_index),
			"volume_db": AudioServer.get_bus_volume_db(bus_index),
		}


func _restore_audio_state() -> void:
	for raw_bus_name: Variant in _original_audio_state:
		var bus_index := AudioServer.get_bus_index(StringName(raw_bus_name))
		var state: Dictionary = _original_audio_state[raw_bus_name]
		AudioServer.set_bus_mute(bus_index, bool(state.mute))
		AudioServer.set_bus_volume_db(bus_index, float(state.volume_db))


func _cleanup_files() -> void:
	for path: String in [
		"%s/settings_v1.json" % TEST_SETTINGS_ROOT,
		TEST_PROGRESS_PATH,
		TEST_LEGACY_PATH,
	]:
		for suffix: String in ["", ".tmp", ".bak"]:
			var target := path + suffix
			if FileAccess.file_exists(target):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(target))
	for slot: int in range(1, ProfileStore.MAX_PROFILES + 1):
		for suffix: String in ["", ".tmp", ".bak"]:
			var profile_path := "%s/%d/save_v3.json%s" % [TEST_PROFILE_ROOT, slot, suffix]
			if FileAccess.file_exists(profile_path):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(profile_path))
