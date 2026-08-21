extends Node

const TUTORIAL_STATS_ADAPTER = preload("res://core/adapters/tutorial_stats_adapter.gd")
const STAT_REBUILD_SERVICE = preload("res://core/balance/stat_rebuild_service.gd")
const WINDOW_MODE_POLICY = preload("res://core/settings/window_mode_policy.gd")

signal on_create_block_text(unit: Node2D)
signal on_create_damage_text(unit: Node2D, hitbox: HitboxComponent)
signal on_create_heal_text(unit: Node2D, heal: float)

signal on_upgrade_selected
signal on_enemy_died(enemy: Enemy)
signal materials_changed(value: int)
signal run_phase_changed(phase: int)
signal product_settings_changed(settings: ProductSettings)

const FLASH_MATERIAL = preload("uid://coi4nu8ohpgeo")
const FLOATING_TEXT_SCENE = preload("uid://bmy2qb3fuvnts")
const COINS_SCENE = preload("uid://c0gxgyeg3phog")
const ITEM_CARD_SCENE = preload("uid://d4ahqxku4821t")
const SELECTION_CARD_SCENE = preload("uid://dnablojs1s8")
const SPAWN_EFFECT_SCENE = preload("uid://bghlbhbjte68a")

const COMMON_STYLE = preload("uid://dn43vff5bgab1")
const EPIC_STYLE = preload("uid://chxsktowv55wp")
const LEGENDARY_STYLE = preload("uid://omjdrwevlaw8")
const RARE_STYLE = preload("uid://cu7iu2w861ga4")

const UPGRADE_PROBABILITY_CONFIG = {
	"rare": { "start_wave": 2, "base_multi": 0.06, "max_chance": 0.60 },
	"epic": { "start_wave": 4, "base_multi": 0.02, "max_chance": 0.25 },
	"legendary": { "start_wave": 8, "base_multi": 0.0023, "max_chance": 0.08 },
}

const SHOP_PROBABILITY_CONFIG = {
	"rare": { "start_wave": 2, "base_multi": 0.06, "max_chance": 0.60 },
	"epic": { "start_wave": 4, "base_multi": 0.02, "max_chance": 0.25 },
	"legendary": { "start_wave": 8, "base_multi": 0.0023, "max_chance": 0.08 },
}


const TIER_COLORS: Dictionary[UpgradeTier, Color] = {
	UpgradeTier.RARE: Color(0.0, 0.557, 0.741),
	UpgradeTier.EPIC: Color(0.478, 0.251, 0.71),
	UpgradeTier.LEGENDARY: Color(0.906, 0.212, 0.212),
}

enum UpgradeTier{
	COMMON,
	RARE,
	EPIC,
	LEGENDARY
}

const STARTING_MATERIALS := 35
const QUICK_WINDOWED_RESOLUTION := "1280x720"

var current_run: RunState
var run_director: RunDirector
var shop_service: ShopService
var reward_service: RewardService
var combat_resolver: CombatResolver
var gameplay_effects: GameplayEffectRuntime
var gameplay_effect_executor := GameplayEffectExecutor.new()
var meta_progress := MetaProgress.new()
var product_settings := ProductSettings.new()
var settings_store := SettingsStore.new()
var save_provider: SaveProvider = ProfileSaveProvider.new()
var restored_run: RunState
var _combat_checkpoint: RunState
var aim_mode: int = AimMode.AUTO_TARGET
var _settings_initialized := false
var _paused_by_focus_loss := false
var _muted_by_focus_loss := false
var coins: int:
	get:
		return current_run.materials if current_run != null else 0
	set(value):
		_ensure_run()
		current_run.materials = maxi(0, value)
		materials_changed.emit(current_run.materials)
var player: Player
var game_paused: bool:
	get:
		return not is_combat_active()
	set(value):
		if value:
			if current_run != null and current_run.phase == RunPhase.COMBAT:
				enter_phase(RunPhase.UPGRADE)
		else:
			enter_phase(RunPhase.COMBAT)

var main_player_selected: UnitStats
var main_weapon_selected: ItemWeapon
var main_character_selected: CharacterDef
var main_weapon_definition_selected: WeaponDef

var equipped_weapons: Array[ItemWeapon]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if save_provider is ProfileSaveProvider:
		var provider := save_provider as ProfileSaveProvider
		provider.migrate_legacy()
		provider.reload_active_profile()
	load_progress()


func _notification(what: int) -> void:
	if not is_node_ready():
		return
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_handle_focus_lost()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_handle_focus_regained()


func _unhandled_input(event: InputEvent) -> void:
	if not is_fullscreen_toggle_event(event):
		return
	toggle_fullscreen()
	get_viewport().set_input_as_handled()


func is_fullscreen_toggle_event(event: InputEvent) -> bool:
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return false
	var key := key_event.keycode if key_event.keycode != KEY_NONE else key_event.physical_keycode
	return key == KEY_F11 or (key_event.alt_pressed and key in [KEY_ENTER, KEY_KP_ENTER])


func toggle_fullscreen() -> bool:
	var updated := product_settings.copy()
	if updated.display_mode == DisplayMode.WINDOWED:
		updated.display_mode = DisplayMode.BORDERLESS_FULLSCREEN
	else:
		updated.display_mode = DisplayMode.WINDOWED
		updated.resolution = _parse_resolution_string(QUICK_WINDOWED_RESOLUTION)
	apply_product_settings(updated, true)
	return product_settings.display_mode != DisplayMode.WINDOWED


func begin_run(seed_value: int = 0, source_stats: UnitStats = null, starting_materials: int = STARTING_MATERIALS) -> RunState:
	_combat_checkpoint = null
	var player_stats: PlayerStats = TUTORIAL_STATS_ADAPTER.to_player_stats(source_stats)
	current_run = RunState.new(seed_value, player_stats)
	STAT_REBUILD_SERVICE.new().stamp_current_versions(
		current_run,
		Content.catalog.balance_pack if Content.catalog != null else null
	)
	run_director = RunDirector.new(current_run)
	shop_service = ShopService.new(seed_value)
	reward_service = RewardService.new(seed_value)
	combat_resolver = CombatResolver.new(seed_value, _active_stat_rules())
	gameplay_effects = GameplayEffectRuntime.new(seed_value)
	current_run.materials = maxi(0, starting_materials)
	player = null
	equipped_weapons.clear()
	materials_changed.emit(current_run.materials)
	run_phase_changed.emit(current_run.phase)
	return current_run


func begin_selected_run(seed_value: int = 0) -> bool:
	if main_player_selected == null or main_weapon_selected == null:
		return false
	if (
		main_character_selected != null
		and main_character_selected.rules != null
		and main_weapon_definition_selected != null
		and not main_character_selected.rules.allows_weapon(
			main_weapon_definition_selected.tags
		)
	):
		return false
	begin_run(seed_value, main_player_selected, STARTING_MATERIALS)
	if main_character_selected != null and main_character_selected.rules != null:
		main_character_selected.rules.apply_to_run(current_run)
	current_run.character_id = (
		main_character_selected.get_stable_id(Content.catalog.pack_id)
		if main_character_selected != null
		else main_player_selected.get_stable_id()
	)
	current_run.starting_weapon_id = (
		main_weapon_definition_selected.get_stable_id(Content.catalog.pack_id)
		if main_weapon_definition_selected != null
		else main_weapon_selected.get_stable_id()
	)
	var slot := current_run.inventory.add_weapon(
		current_run.starting_weapon_id,
		int(main_weapon_selected.item_tier) + 1,
		main_weapon_selected.item_cost
	)
	if slot < 0:
		return false
	meta_progress.mark_discovered(current_run.character_id)
	meta_progress.mark_discovered(current_run.starting_weapon_id)
	meta_progress.unlock_character(current_run.character_id)
	_register_definition_effects(main_character_selected)
	_register_definition_effects(main_weapon_definition_selected)
	dispatch_gameplay_event(GameplayEvent.Type.RUN_STARTED)
	GameLog.info(&"run", "run_started", {
		"profile_id": active_profile_id(),
		"character_id": String(current_run.character_id),
		"weapon_id": String(current_run.starting_weapon_id),
		"difficulty": current_run.difficulty,
		"run_mode": current_run.run_mode,
	})
	return true


func resume_run_state(checkpoint: RunState) -> bool:
	if checkpoint == null or not checkpoint.is_resumable_checkpoint():
		return false
	current_run = RunState.from_dict(checkpoint.to_dict())
	var restored_character := Content.catalog.get_character(current_run.character_id)
	if restored_character != null and restored_character.rules != null:
		restored_character.rules.hydrate_runtime_rules(current_run)
	if not STAT_REBUILD_SERVICE.new().rebuild_if_required(
		current_run,
		Content.catalog,
		Content.catalog.balance_pack if Content.catalog != null else null
	):
		current_run = null
		return false
	run_director = RunDirector.new(current_run)
	shop_service = ShopService.new(current_run.random_seed)
	reward_service = RewardService.new(current_run.random_seed)
	combat_resolver = CombatResolver.new(current_run.random_seed, _active_stat_rules())
	gameplay_effects = GameplayEffectRuntime.new(current_run.random_seed)
	_restore_rng_states()
	player = null
	equipped_weapons.clear()
	restored_run = RunState.from_dict(current_run.to_dict())
	_combat_checkpoint = (
		RunState.from_dict(current_run.to_dict())
		if current_run.phase == RunPhase.COMBAT
		else null
	)
	materials_changed.emit(current_run.materials)
	run_phase_changed.emit(current_run.phase)
	GameLog.info(&"run", "checkpoint_resumed", {
		"profile_id": active_profile_id(),
		"character_id": String(current_run.character_id),
		"difficulty": current_run.difficulty,
		"phase": current_run.phase,
	})
	return true


func end_run() -> void:
	if current_run != null:
		GameLog.info(&"run", "run_state_cleared", {
			"character_id": String(current_run.character_id),
			"difficulty": current_run.difficulty,
			"phase": current_run.phase,
			"highest_wave": current_run.highest_wave_reached,
		})
	current_run = null
	run_director = null
	shop_service = null
	reward_service = null
	combat_resolver = null
	gameplay_effects = null
	player = null
	equipped_weapons.clear()
	main_player_selected = null
	main_weapon_selected = null
	main_character_selected = null
	main_weapon_definition_selected = null


func enter_phase(next_phase: int) -> bool:
	if current_run == null or not RunPhase.is_valid(next_phase):
		return false
	if run_director == null or run_director.run_state != current_run:
		run_director = RunDirector.new(current_run)
	if not run_director.transition_to(next_phase):
		return false
	run_phase_changed.emit(current_run.phase)
	return true


func load_progress() -> bool:
	if save_provider == null or not save_provider.is_available():
		_ensure_product_settings({})
		apply_product_settings(product_settings, false)
		return false
	var payload := save_provider.load_slot()
	var meta_data: Variant = payload.get("meta_progress", {})
	var legacy_meta: Dictionary = meta_data if meta_data is Dictionary else {}
	_ensure_product_settings(legacy_meta)
	meta_progress = MetaProgress.from_dict(legacy_meta)
	var run_data: Variant = payload.get("run_state", null)
	restored_run = RunState.from_dict(run_data) if run_data is Dictionary else null
	if restored_run != null and not restored_run.is_resumable_checkpoint():
		restored_run = null
	_combat_checkpoint = (
		RunState.from_dict(restored_run.to_dict())
		if restored_run != null and restored_run.phase == RunPhase.COMBAT
		else null
	)
	apply_product_settings(product_settings, false)
	return not payload.is_empty()


func save_progress(include_run: bool = true) -> Error:
	if save_provider == null or not save_provider.is_available():
		return ERR_UNAVAILABLE
	var payload := {"meta_progress": meta_progress.to_dict()}
	if include_run and current_run != null:
		var snapshot: RunState
		if current_run.phase == RunPhase.COMBAT and _combat_checkpoint != null:
			snapshot = RunState.from_dict(_combat_checkpoint.to_dict())
		else:
			_capture_rng_states()
			snapshot = RunState.from_dict(current_run.to_dict())
		payload["run_state"] = snapshot.to_dict()
		var save_result := save_provider.save_slot(payload)
		if save_result == OK:
			restored_run = RunState.from_dict(snapshot.to_dict())
			_combat_checkpoint = (
				RunState.from_dict(snapshot.to_dict())
				if snapshot.phase == RunPhase.COMBAT
				else null
			)
		else:
			GameLog.warning(&"save", "profile_save_failed", {
				"profile_id": active_profile_id(),
				"error": error_string(save_result),
				"include_run": true,
			})
		return save_result
	var save_result := save_provider.save_slot(payload)
	if save_result == OK:
		restored_run = null
		_combat_checkpoint = null
	else:
		GameLog.warning(&"save", "profile_save_failed", {
			"profile_id": active_profile_id(),
			"error": error_string(save_result),
			"include_run": false,
		})
	return save_result


func save_combat_checkpoint() -> Error:
	if current_run == null or current_run.phase != RunPhase.COMBAT:
		return ERR_INVALID_DATA
	if save_provider == null or not save_provider.is_available():
		return ERR_UNAVAILABLE
	_capture_rng_states()
	var snapshot := RunState.from_dict(current_run.to_dict())
	var payload := {
		"meta_progress": meta_progress.to_dict(),
		"run_state": snapshot.to_dict(),
	}
	var save_result := save_provider.save_slot(payload)
	if save_result == OK:
		restored_run = RunState.from_dict(snapshot.to_dict())
		_combat_checkpoint = RunState.from_dict(snapshot.to_dict())
	else:
		GameLog.warning(&"save", "combat_checkpoint_failed", {
			"profile_id": active_profile_id(),
			"error": error_string(save_result),
			"phase": current_run.phase,
		})
	return save_result


func _capture_rng_states() -> void:
	if current_run == null:
		return
	var states: Dictionary = {}
	if shop_service != null:
		states["shop"] = shop_service.rng.state
	if reward_service != null:
		states["reward"] = reward_service.rng.state
	if combat_resolver != null:
		states["combat"] = combat_resolver.rng.state
	if gameplay_effects != null:
		states["effects"] = gameplay_effects.rng.state
	current_run.rng_states = states


func _restore_rng_states() -> void:
	if current_run == null:
		return
	var states := current_run.rng_states
	if shop_service != null and states.has("shop"):
		shop_service.rng.state = int(states["shop"])
	if reward_service != null and states.has("reward"):
		reward_service.rng.state = int(states["reward"])
	if combat_resolver != null and states.has("combat"):
		combat_resolver.rng.state = int(states["combat"])
	if gameplay_effects != null and states.has("effects"):
		gameplay_effects.rng.state = int(states["effects"])


func switch_profile(profile_id: int) -> bool:
	var provider := save_provider as ProfileSaveProvider
	if provider == null or profile_id not in range(1, ProfileStore.MAX_PROFILES + 1):
		return false
	if profile_id == provider.active_profile_id:
		return true
	if current_run != null:
		var save_result := save_progress(true)
		if save_result != OK:
			GameLog.warning(&"save", "profile_switch_aborted", {
				"profile_id": provider.active_profile_id,
				"target_profile_id": profile_id,
				"error": error_string(save_result),
			})
			return false
	if not provider.set_active_profile(profile_id):
		return false
	end_run()
	restored_run = null
	_combat_checkpoint = null
	meta_progress = MetaProgress.new()
	load_progress()
	return true


func stage_profile_for_new_run(profile_id: int) -> bool:
	var provider := save_provider as ProfileSaveProvider
	if provider == null or not provider.stage_profile(profile_id):
		return false
	end_run()
	restored_run = null
	_combat_checkpoint = null
	meta_progress = MetaProgress.new()
	return true


func activate_profile_for_run(profile_id: int) -> bool:
	var provider := save_provider as ProfileSaveProvider
	if provider == null or profile_id not in range(1, ProfileStore.MAX_PROFILES + 1):
		return false
	if profile_id == provider.active_profile_id:
		return true
	var profile_exists := false
	for summary: Dictionary in provider.summaries():
		if int(summary.get("profile_id", 0)) == profile_id:
			profile_exists = bool(summary.get("exists", false))
			break
	if profile_exists:
		return switch_profile(profile_id)
	return stage_profile_for_new_run(profile_id)


func active_profile_id() -> int:
	var provider := save_provider as ProfileSaveProvider
	return provider.active_profile_id if provider != null else 0


func profile_summaries() -> Array[Dictionary]:
	var provider := save_provider as ProfileSaveProvider
	return provider.summaries() if provider != null else []


func rename_profile(profile_id: int, profile_name: String) -> Error:
	var provider := save_provider as ProfileSaveProvider
	if provider == null or provider.store == null:
		return ERR_UNAVAILABLE
	return provider.store.rename_profile(profile_id, profile_name)


func delete_profile(profile_id: int) -> Error:
	var provider := save_provider as ProfileSaveProvider
	if provider == null or provider.store == null:
		return ERR_UNAVAILABLE
	var result := provider.store.delete_profile(profile_id)
	if result == OK and profile_id == provider.active_profile_id:
		var clear_result := provider.store.clear_active_profile_id()
		if clear_result != OK:
			return clear_result
		provider.reload_active_profile()
		end_run()
		restored_run = null
		_combat_checkpoint = null
		meta_progress = MetaProgress.new()
		load_progress()
	return result


func record_victory() -> bool:
	if current_run == null:
		return false
	var unlocked := meta_progress.record_victory(current_run.character_id, current_run.difficulty)
	save_progress(false)
	return unlocked


func record_standard_victory_once() -> bool:
	if current_run == null or current_run.standard_victory_recorded:
		return false
	current_run.standard_victory_recorded = true
	meta_progress.record_victory(current_run.character_id, current_run.difficulty)
	return true


func record_endless_progress() -> bool:
	if current_run == null or current_run.run_mode != RunMode.ENDLESS:
		return false
	return meta_progress.record_endless_wave(
		current_run.character_id,
		current_run.difficulty,
		maxi(current_run.wave, current_run.highest_wave_reached)
	)


func record_run_summary(victory: bool) -> void:
	if current_run == null:
		return
	meta_progress.recent_run_summary = {
		"victory": victory,
		"standard_victory_recorded": current_run.standard_victory_recorded,
		"run_mode": current_run.run_mode,
		"character_id": String(current_run.character_id),
		"weapon_id": String(current_run.starting_weapon_id),
		"difficulty": current_run.difficulty,
		"wave": current_run.wave,
		"highest_wave_reached": current_run.highest_wave_reached,
		"kills": current_run.kill_count,
		"boss_kills": current_run.boss_kill_count,
		"elapsed_seconds": current_run.elapsed_seconds,
		"materials": current_run.materials,
	}


func discover_content(content_id: StringName) -> bool:
	return meta_progress.mark_discovered(content_id)


func update_product_settings(
	music: float,
	sfx: float,
	use_fullscreen: bool,
	resolution_value: String,
	aim_value: int,
	locale_value: String,
	enemy_health_scale: float = -1.0,
	enemy_damage_scale: float = -1.0,
	enemy_speed_scale: float = -1.0
) -> bool:
	if not AimMode.is_valid(aim_value) or locale_value not in ["zh_CN", "en"]:
		return false
	var updated := product_settings.copy()
	updated.music_volume = clampf(music, 0.0, 1.0)
	updated.sfx_volume = clampf(sfx, 0.0, 1.0)
	updated.display_mode = (
		DisplayMode.BORDERLESS_FULLSCREEN if use_fullscreen else DisplayMode.WINDOWED
	)
	updated.resolution = _parse_resolution_string(resolution_value)
	updated.aim_mode = aim_value
	updated.locale = locale_value
	if enemy_health_scale >= 0.0:
		updated.enemy_health_scale = clampf(enemy_health_scale, 0.25, 2.0)
	if enemy_damage_scale >= 0.0:
		updated.enemy_damage_scale = clampf(enemy_damage_scale, 0.25, 2.0)
	if enemy_speed_scale >= 0.0:
		updated.enemy_speed_scale = clampf(enemy_speed_scale, 0.25, 2.0)
	return apply_product_settings(updated, true)


func apply_meta_settings() -> void:
	_ensure_product_settings(meta_progress.to_dict())
	apply_product_settings(product_settings, false)


func apply_product_settings(settings: ProductSettings, persist: bool = true) -> bool:
	if settings == null:
		return false
	var normalized := settings.copy().sanitize()
	if (
		normalized.display_mode == DisplayMode.WINDOWED
		and DisplayServer.get_name() != "headless"
		and "--wid" not in OS.get_cmdline_args()
	):
		var usable_rect := DisplayServer.screen_get_usable_rect(
			DisplayServer.SCREEN_OF_MAIN_WINDOW
		)
		normalized.resolution = WINDOW_MODE_POLICY.resolved_windowed_size(
			normalized.resolution,
			usable_rect.size,
			ProductSettings.MIN_RESOLUTION,
		)
	if persist and settings_store.save_settings(normalized) != OK:
		return false
	product_settings = normalized
	aim_mode = product_settings.aim_mode
	if not product_settings.input_bindings.is_empty():
		InputRemapService.new().apply_actions(product_settings.input_bindings)
	_apply_input_deadzone(product_settings.gamepad_deadzone)
	TranslationServer.set_locale(product_settings.locale)
	_set_bus_linear_volume(&"Master", product_settings.master_volume)
	_set_bus_linear_volume(&"Music", product_settings.music_volume)
	_set_bus_linear_volume(&"SFX", product_settings.sfx_volume)
	ThemeDB.fallback_base_scale = product_settings.ui_scale
	Engine.max_fps = product_settings.fps_cap
	_apply_display_settings()
	product_settings_changed.emit(product_settings.copy())
	return true


func preview_product_settings(settings: ProductSettings) -> bool:
	return apply_product_settings(settings, false)


func restore_product_settings(settings: ProductSettings) -> bool:
	return apply_product_settings(settings, false)


func available_resolutions() -> Array[Vector2i]:
	var candidates: Array[Vector2i] = [
		Vector2i(1024, 576),
		Vector2i(1152, 648),
		Vector2i(1280, 720),
		Vector2i(1600, 900),
		Vector2i(1920, 1080),
		Vector2i(2560, 1440),
		Vector2i(3840, 2160),
	]
	var screen_size := ProductSettings.DEFAULT_RESOLUTION
	if DisplayServer.get_name() != "headless":
		screen_size = DisplayServer.screen_get_size(DisplayServer.SCREEN_OF_MAIN_WINDOW)
	var result: Array[Vector2i] = []
	for candidate: Vector2i in candidates:
		if candidate.x <= screen_size.x and candidate.y <= screen_size.y:
			result.append(candidate)
	for required: Vector2i in [product_settings.resolution, screen_size]:
		if (
			required.x >= ProductSettings.MIN_RESOLUTION.x
			and required.y >= ProductSettings.MIN_RESOLUTION.y
			and required not in result
		):
			result.append(required)
	result.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x * a.y < b.x * b.y)
	return result


func _ensure_product_settings(legacy_meta: Dictionary) -> void:
	if _settings_initialized:
		return
	product_settings = (
		settings_store.load_settings()
		if settings_store.has_saved_settings()
		else settings_store.migrate_from_legacy_meta(legacy_meta)
	)
	_settings_initialized = true


func _apply_display_settings() -> void:
	if DisplayServer.get_name() == "headless" or "--wid" in OS.get_cmdline_args():
		return
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED
		if product_settings.vsync_enabled
		else DisplayServer.VSYNC_DISABLED
	)
	var contract: Dictionary = WINDOW_MODE_POLICY.native_contract(
		product_settings.display_mode
	)
	var target_mode := int(contract.mode)
	# Fullscreen and borderless flags are independent in Godot. On Windows the
	# borderless flag can survive a mode transition, so enter windowed mode before
	# restoring normal decorations and an adjustable sizing frame.
	if target_mode == DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(
		DisplayServer.WINDOW_FLAG_EXTEND_TO_TITLE,
		bool(contract.extend_to_title)
	)
	DisplayServer.window_set_flag(
		DisplayServer.WINDOW_FLAG_RESIZE_DISABLED,
		bool(contract.resize_disabled)
	)
	DisplayServer.window_set_flag(
		DisplayServer.WINDOW_FLAG_BORDERLESS,
		bool(contract.borderless)
	)
	DisplayServer.window_set_mode(target_mode)
	if product_settings.display_mode == DisplayMode.WINDOWED:
		_apply_windowed_geometry()
		call_deferred("_apply_windowed_geometry")


func _apply_windowed_geometry() -> void:
	if (
		DisplayServer.get_name() == "headless"
		or product_settings.display_mode != DisplayMode.WINDOWED
		or "--wid" in OS.get_cmdline_args()
	):
		return
	var usable_rect := DisplayServer.screen_get_usable_rect(DisplayServer.SCREEN_OF_MAIN_WINDOW)
	var window_size := WINDOW_MODE_POLICY.resolved_windowed_size(
		product_settings.resolution,
		usable_rect.size,
		ProductSettings.MIN_RESOLUTION,
	)
	DisplayServer.window_set_size(window_size)
	var centered_position := usable_rect.position + (usable_rect.size - window_size) / 2
	DisplayServer.window_set_position(centered_position)


func _apply_input_deadzone(value: float) -> void:
	for action: StringName in [
		&"move_left", &"move_right", &"move_up", &"move_down",
		&"aim_left", &"aim_right", &"aim_up", &"aim_down",
	]:
		if InputMap.has_action(action):
			InputMap.action_set_deadzone(action, value)


func _parse_resolution_string(value: String) -> Vector2i:
	var parts := value.to_lower().split("x", false, 1)
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return ProductSettings.DEFAULT_RESOLUTION
	return Vector2i(
		maxi(ProductSettings.MIN_RESOLUTION.x, int(parts[0])),
		maxi(ProductSettings.MIN_RESOLUTION.y, int(parts[1])),
	)


func _handle_focus_lost() -> void:
	if product_settings.mute_on_focus_lost and not _muted_by_focus_loss:
		var master_index := AudioServer.get_bus_index(&"Master")
		if master_index >= 0:
			AudioServer.set_bus_mute(master_index, true)
			_muted_by_focus_loss = true
	if (
		product_settings.pause_on_focus_lost
		and is_combat_active()
		and not get_tree().paused
	):
		get_tree().paused = true
		_paused_by_focus_loss = true


func _handle_focus_regained() -> void:
	if _muted_by_focus_loss:
		_set_bus_linear_volume(&"Master", product_settings.master_volume)
		_muted_by_focus_loss = false
	if _paused_by_focus_loss:
		get_tree().paused = false
		_paused_by_focus_loss = false


func translate_text(key: StringName, english_fallback: String) -> String:
	return LocalizedTextService.resolve(key, [], english_fallback)


func _set_bus_linear_volume(bus_name: StringName, linear_value: float) -> void:
	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index < 0:
		return
	var value := clampf(linear_value, 0.0, 1.0)
	AudioServer.set_bus_mute(bus_index, value <= 0.0)
	AudioServer.set_bus_volume_db(bus_index, linear_to_db(maxf(value, 0.0001)))


func is_combat_active() -> bool:
	return current_run != null and current_run.phase == RunPhase.COMBAT


func add_materials(amount: int) -> void:
	if amount <= 0:
		return
	_ensure_run()
	current_run.materials += amount
	materials_changed.emit(current_run.materials)


func collect_materials(amount: int) -> int:
	if amount <= 0:
		return 0
	_ensure_run()
	if reward_service == null:
		reward_service = RewardService.new(current_run.random_seed)
	var level_before := current_run.level
	reward_service.collect_material_pickup(current_run, amount)
	materials_changed.emit(current_run.materials)
	return current_run.level - level_before


func try_spend_materials(amount: int) -> bool:
	if amount < 0:
		return false
	_ensure_run()
	if current_run.materials < amount:
		return false
	current_run.materials -= amount
	materials_changed.emit(current_run.materials)
	return true


func try_purchase_item_detailed(item: ItemBase) -> Dictionary:
	if item == null:
		return _invalid_purchase_result()
	_ensure_run()
	if shop_service == null:
		shop_service = ShopService.new(current_run.random_seed)
	var result := shop_service.try_purchase_detailed(current_run, item, Content.catalog)
	_finalize_purchase(item, result)
	return result


func try_purchase_item(item: ItemBase) -> int:
	return int(try_purchase_item_detailed(item).get("code", InventoryService.INVALID_REQUEST))


func try_purchase_shop_slot_detailed(slot_index: int) -> Dictionary:
	_ensure_run()
	if shop_service == null:
		shop_service = ShopService.new(current_run.random_seed)
	var item := shop_service.resolve_slot_offer(current_run, slot_index, Content.catalog)
	if item == null:
		return _invalid_purchase_result()
	var result := shop_service.try_purchase_offer_detailed(current_run, slot_index, Content.catalog)
	_finalize_purchase(item, result)
	return result


func try_purchase_shop_slot(slot_index: int) -> int:
	return int(try_purchase_shop_slot_detailed(slot_index).get(
		"code", InventoryService.INVALID_REQUEST
	))


func _invalid_purchase_result() -> Dictionary:
	return {
		"code": InventoryService.INVALID_REQUEST,
		"mode": InventoryService.PURCHASE_MODE_NONE,
		"target_slot": -1,
		"resulting_tier": 0,
	}


func _finalize_purchase(item: ItemBase, result: Dictionary) -> void:
	if int(result.get("code", InventoryService.INVALID_REQUEST)) != InventoryService.OK:
		return
	meta_progress.mark_discovered(Content.catalog.get_item_stable_id(item))
	rebuild_run_effects()
	if result.get("mode", InventoryService.PURCHASE_MODE_NONE) == InventoryService.PURCHASE_MODE_AUTO_MERGE:
		sync_equipped_weapons_from_inventory()
	materials_changed.emit(current_run.materials)


func sync_equipped_weapons_from_inventory() -> void:
	equipped_weapons.clear()
	if current_run == null:
		return
	var resolved: Array[ItemWeapon] = []
	for slot in current_run.inventory.weapon_count():
		var entry := current_run.inventory.weapon_at(slot)
		var weapon := Content.catalog.get_weapon_tier(
			StringName(str(entry.get("weapon_id", ""))), int(entry.get("tier", 0))
		)
		if weapon != null:
			resolved.append(weapon)
	equipped_weapons.assign(resolved)
	if not is_instance_valid(player):
		return
	for weapon: Weapon in player.current_weapons:
		weapon.queue_free()
	player.current_weapons.clear()
	for weapon: ItemWeapon in equipped_weapons:
		player.add_weapon(weapon)


func try_claim_reward_item(item: ItemBase) -> int:
	if current_run == null or item == null:
		return InventoryService.INVALID_REQUEST
	if reward_service == null:
		reward_service = RewardService.new(current_run.random_seed)
	var result := reward_service.try_claim_item(current_run, item, Content.catalog)
	if result == InventoryService.OK:
		rebuild_run_effects()
		materials_changed.emit(current_run.materials)
	return result


func recycle_reward_item(item: ItemBase) -> int:
	if current_run == null or item == null:
		return 0
	if reward_service == null:
		reward_service = RewardService.new(current_run.random_seed)
	var materials := reward_service.recycle_item(current_run, item)
	if materials > 0:
		materials_changed.emit(current_run.materials)
	return materials


func try_combine_weapon(weapon: ItemWeapon) -> int:
	if current_run == null or weapon == null:
		return InventoryService.INVALID_REQUEST
	if shop_service == null:
		shop_service = ShopService.new(current_run.random_seed)
	var result := shop_service.try_combine_item(current_run, weapon, Content.catalog)
	if result == InventoryService.OK:
		rebuild_run_effects()
	return result


func try_sell_weapon(weapon: ItemWeapon) -> int:
	if current_run == null or weapon == null:
		return InventoryService.INVALID_REQUEST
	if shop_service == null:
		shop_service = ShopService.new(current_run.random_seed)
	var result := shop_service.try_sell_item(current_run, weapon, Content.catalog)
	if result == InventoryService.OK:
		rebuild_run_effects()
		materials_changed.emit(current_run.materials)
	return result


func try_sell_weapon_slot(slot: int) -> int:
	if current_run == null:
		return InventoryService.INVALID_WEAPON_SLOT
	var result := InventoryService.try_sell_weapon(current_run, slot)
	if result == InventoryService.OK:
		rebuild_run_effects()
		materials_changed.emit(current_run.materials)
	return result


func apply_stat_change(unit_property: String, amount: float) -> bool:
	if current_run == null:
		return false
	var stat_id: int = TUTORIAL_STATS_ADAPTER.stat_id_for_property(unit_property)
	var adjusted_amount := amount * _character_stat_gain_multiplier(stat_id)
	if not StatId.is_valid(stat_id) or not current_run.player_stats.add_stat(
		stat_id, adjusted_amount
	):
		push_warning("Unsupported tutorial stat '%s'; migration mapping is required." % unit_property)
		return false
	if is_instance_valid(player) and player.stats != null:
		TUTORIAL_STATS_ADAPTER.apply_stat_to_unit(current_run.player_stats, player.stats, stat_id)
	return true


func apply_passive_item(item: ItemPassive) -> bool:
	if current_run == null or item == null:
		return false
	var definition := Content.catalog.get_passive_definition_for_item(item)
	if definition != null and current_run.inventory.passive_count(
		definition.get_stable_id(Content.catalog.pack_id)
	) == 0:
		_register_definition_effects(definition)
	if definition == null or definition.stat_modifiers.is_empty():
		item.apply_passive()
		return true
	var applied := false
	for stat_key: Variant in definition.stat_modifiers:
		var stat_id := StatId.from_key(str(stat_key))
		if not StatId.is_valid(stat_id):
			push_warning("Unsupported passive stat '%s'." % stat_key)
			continue
		var amount := (
			float(definition.stat_modifiers[stat_key])
			* _character_stat_gain_multiplier(stat_id)
		)
		current_run.player_stats.add_stat(stat_id, amount)
		_sync_runtime_stat(stat_id)
		applied = true
	return applied


func dispatch_gameplay_event(
	event_type: int,
	values: Dictionary = {},
	event_tags: Array[StringName] = [],
	source: Object = null,
	target: Object = null,
	source_tags: Array[StringName] = [],
	target_tags: Array[StringName] = []
) -> EffectResult:
	if gameplay_effects == null:
		gameplay_effects = GameplayEffectRuntime.new(current_run.random_seed if current_run != null else 0)
	var context := GameplayEventContext.new(event_type)
	context.values = values.duplicate(true)
	context.tags = event_tags.duplicate()
	context.source = source
	context.target = target
	context.source_tags = source_tags.duplicate()
	context.target_tags = target_tags.duplicate()
	var result := gameplay_effects.dispatch(context)
	if current_run != null:
		for raw_stat_id: Variant in result.stat_changes:
			var stat_id := int(raw_stat_id)
			if StatId.is_valid(stat_id):
				current_run.player_stats.add_stat(
					stat_id,
					float(result.stat_changes[raw_stat_id])
					* _character_stat_gain_multiplier(stat_id)
				)
				_sync_runtime_stat(stat_id)
	if result.healing > 0.0 and is_instance_valid(player):
		player.health_component.heal(result.healing)
		on_create_heal_text.emit(player, result.healing)
	gameplay_effect_executor.apply_result(result, context, get_tree())
	return result


func rebuild_run_effects() -> void:
	var previous_rng_state := (
		gameplay_effects.rng.state
		if gameplay_effects != null
		else int(current_run.rng_states.get("effects", 0)) if current_run != null else 0
	)
	gameplay_effects = GameplayEffectRuntime.new(current_run.random_seed if current_run != null else 0)
	_register_definition_effects(main_character_selected)
	if main_character_selected != null and main_character_selected.rules != null:
		gameplay_effects.register_effects(main_character_selected.rules.permanent_effects)
	if current_run == null:
		return
	var inventory_data := current_run.inventory.to_dict()
	var weapons: Variant = inventory_data.get("weapons", [])
	if weapons is Array:
		for entry: Variant in weapons:
			if entry is Dictionary:
				_register_definition_effects(Content.catalog.get_weapon(
					StringName(str(entry.get("weapon_id", "")))
				))
	var passives: Variant = inventory_data.get("passives", {})
	if passives is Dictionary:
		for raw_id: Variant in passives:
			_register_definition_effects(
				Content.catalog.get_passive(StringName(str(raw_id))),
				maxi(1, int(passives[raw_id]))
			)
	if previous_rng_state != 0:
		gameplay_effects.rng.state = previous_rng_state


func _register_definition_effects(definition: ContentDef, stack_count: int = 1) -> void:
	if definition != null and gameplay_effects != null:
		gameplay_effects.register_effects(definition.effects, stack_count)


func apply_upgrade_item(item: ItemUpgrade) -> bool:
	if current_run == null or item == null:
		return false
	var definition := Content.catalog.get_upgrade_definition_for_item(item)
	if definition == null or not StatId.is_valid(definition.stat_id):
		item.apply_upgrade()
		return true
	var applied_value := definition.value * _character_stat_gain_multiplier(definition.stat_id)
	current_run.player_stats.add_stat(definition.stat_id, applied_value)
	current_run.record_applied_upgrade(
		definition.get_stable_id(Content.catalog.pack_id),
		definition.stat_id,
		applied_value
	)
	_sync_runtime_stat(definition.stat_id)
	return true


func _sync_runtime_stat(stat_id: int) -> void:
	if is_instance_valid(player) and player.stats != null:
		TUTORIAL_STATS_ADAPTER.apply_stat_to_unit(current_run.player_stats, player.stats, stat_id)


func _character_stat_gain_multiplier(stat_id: int) -> float:
	if (
		main_character_selected == null
		or main_character_selected.rules == null
		or not StatId.is_valid(stat_id)
	):
		return 1.0
	return float(main_character_selected.rules.stat_modification_multipliers.get(
		StatId.key(stat_id), 1.0
	))


func get_stat_value(unit_property: String) -> float:
	if current_run == null:
		return 0.0
	var stat_id: int = TUTORIAL_STATS_ADAPTER.stat_id_for_property(unit_property)
	return current_run.player_stats.get_stat(stat_id)


func get_stat_value_by_id(stat_id: int) -> float:
	if current_run == null or not StatId.is_valid(stat_id):
		return 0.0
	return current_run.player_stats.get_stat(stat_id)


func set_aim_mode(value: int) -> bool:
	if not AimMode.is_valid(value):
		return false
	aim_mode = value
	return true


func _ensure_run() -> void:
	if current_run == null:
		begin_run(0, null, 0)

func get_harvesting_coins() -> void:
	_ensure_combat_resolver()
	var result := combat_resolver.harvesting_result(
		current_run.player_stats,
		current_run.wave,
		current_run.run_mode == RunMode.ENDLESS
	)
	var materials_delta := int(result.get("materials_delta", 0))
	var experience_delta := int(result.get("experience_delta", 0))
	current_run.materials = maxi(0, current_run.materials + materials_delta)
	if reward_service == null:
		reward_service = RewardService.new(current_run.random_seed)
	if experience_delta > 0:
		reward_service.add_experience(current_run, experience_delta)
	elif experience_delta < 0:
		current_run.experience = maxi(0, current_run.experience + experience_delta)
	current_run.player_stats.set_stat(
		StatId.HARVESTING,
		float(result.get("next_harvesting", 0.0))
	)
	_sync_runtime_stat(StatId.HARVESTING)
	materials_changed.emit(current_run.materials)


func get_selected_player() -> Player:
	var definition := main_character_selected
	if definition == null:
		for candidate: CharacterDef in Content.catalog.get_characters():
			if candidate.stats == main_player_selected:
				definition = candidate
				break
	if definition == null or definition.scene == null:
		push_error("Selected character is not registered in the content catalog.")
		return null
	var player_instance := definition.scene.instantiate() as Player
	player_instance.stats = main_player_selected.duplicate(true)
	if current_run != null:
		TUTORIAL_STATS_ADAPTER.apply_to_unit_stats(current_run.player_stats, player_instance.stats)
	player = player_instance
	return player


func select_character(definition: CharacterDef) -> bool:
	if definition == null or definition.stats == null or definition.scene == null:
		return false
	main_character_selected = definition
	main_player_selected = definition.stats
	return true


func select_starting_weapon(definition: WeaponDef) -> bool:
	if definition == null or definition.tiers.is_empty() or definition.tiers[0] == null:
		return false
	main_weapon_definition_selected = definition
	main_weapon_selected = definition.tiers[0]
	return true


func get_chance_sucess(chance: float) -> bool:
	_ensure_run()
	_ensure_combat_resolver()
	return combat_resolver.roll_chance(chance)


func _ensure_combat_resolver() -> void:
	_ensure_run()
	if combat_resolver == null:
		combat_resolver = CombatResolver.new(current_run.random_seed, _active_stat_rules())


func _active_stat_rules() -> StatRulesDef:
	if Content.catalog != null and Content.catalog.balance_pack != null:
		return Content.catalog.balance_pack.stat_rules
	return null

func get_tier_style(tier: UpgradeTier) -> StyleBoxFlat:
	match tier:
		UpgradeTier.COMMON:
			return COMMON_STYLE
		UpgradeTier.RARE:
			return RARE_STYLE
		UpgradeTier.EPIC:
			return EPIC_STYLE
		_:
			return LEGENDARY_STYLE

func calculate_tier_probability(current_wave: int, config: Dictionary) -> Array[float]:
	_ensure_run()
	if shop_service == null:
		shop_service = ShopService.new(current_run.random_seed)
	return shop_service.calculate_tier_probabilities(
		current_wave, get_stat_value("luck"), config
	)


func select_items_for_offer(
	item_pool: Array,
	current_wave: int,
	config: Dictionary,
	requested_count: int = 4
) -> Array:
	_ensure_run()
	if shop_service == null:
		shop_service = ShopService.new(current_run.random_seed)
	return shop_service.select_offers(
		item_pool,
		current_wave,
		get_stat_value("luck"),
		config,
		requested_count,
		Content.catalog,
		_owned_build_tags(),
		current_run
	)


func _owned_build_tags() -> Array[StringName]:
	var result: Array[StringName] = []
	for definition: ContentDef in [main_character_selected, main_weapon_definition_selected]:
		if definition == null:
			continue
		for tag: StringName in definition.tags:
			if tag not in result:
				result.append(tag)
	if current_run == null:
		return result
	for tag: StringName in current_run.shop_bias_tags:
		if tag not in result:
			result.append(tag)
	var inventory_data := current_run.inventory.to_dict()
	for weapon_slot: Dictionary in inventory_data.get("weapons", []):
		var weapon_def := Content.catalog.get_weapon(StringName(weapon_slot.get("weapon_id", "")))
		if weapon_def != null:
			for tag: StringName in weapon_def.tags:
				if tag not in result:
					result.append(tag)
	var passive_counts: Dictionary = inventory_data.get("passives", {})
	for passive_key: Variant in passive_counts:
		var passive_def := Content.catalog.get_passive(StringName(str(passive_key)))
		if passive_def != null:
			for tag: StringName in passive_def.tags:
				if tag not in result:
					result.append(tag)
	return result
