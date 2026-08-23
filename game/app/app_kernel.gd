class_name AppKernel
extends Node

signal boot_completed(result: BootResult)
signal session_created(session: GameSession)
signal session_closed

var scene_flow: SceneFlow
var content_registry := GogoContentRegistry.new()
var content_catalog := ContentPackCatalog.new()
var content_snapshot: ContentSnapshot
var profile_service := ProfileService.new()
var settings_service := GogoSettingsService.new()
var unlock_service := UnlockService.new()
var platform_service := PlatformService.new()
var achievement_service := AchievementService.new()
var codex_service := CodexService.new()
var workshop_service := WorkshopService.new()
var mod_loader := GogoModLoaderAdapter.new()
var audio_service: GogoAudioService
var current_session: GameSession
var selection_draft: Dictionary = {}
var boot_result: BootResult


func configure(flow: SceneFlow, audio: GogoAudioService) -> void:
	scene_flow = flow
	audio_service = audio


func boot() -> BootResult:
	var packs := ValidationContentFactory.create_packs()
	for pack in packs:
		var install_error := content_catalog.install(pack)
		if install_error != OK:
			boot_result = BootResult.failure(BootResult.Status.CONTENT_ERROR, "内容包注册失败", [String(pack.pack_id)])
			boot_completed.emit(boot_result)
			return boot_result
	content_snapshot = content_catalog.apply_at_main_menu(content_registry, &"")
	if content_snapshot == null:
		boot_result = BootResult.failure(BootResult.Status.CONTENT_ERROR, "内容加载失败", content_registry.last_errors)
		boot_completed.emit(boot_result)
		return boot_result
	var settings_error := settings_service.load_settings()
	if settings_error != OK:
		boot_result = BootResult.failure(BootResult.Status.SERVICE_ERROR, "设置加载失败", [error_string(settings_error)])
		boot_completed.emit(boot_result)
		return boot_result
	settings_service.apply_display_settings()
	var profile_error := profile_service.load_profile()
	if profile_error != OK:
		boot_result = BootResult.failure(BootResult.Status.SAVE_ERROR, "存档加载失败", [profile_service.last_error])
		boot_completed.emit(boot_result)
		return boot_result
	if audio_service != null:
		audio_service.apply_settings(settings_service)
	platform_service.initialize()
	mod_loader.initialize(&"")
	boot_result = BootResult.success()
	boot_completed.emit(boot_result)
	return boot_result


func begin_selection() -> void:
	selection_draft = {
		"seed": int(Time.get_unix_time_from_system()) & 0x7fffffff,
		"character_id": &"",
		"weapon_id": &"",
		"difficulty_id": ValidationContentFactory.DIFFICULTY_ID,
		"zone_id": ValidationContentFactory.ZONE_ID,
	}


func create_session_from_draft() -> Error:
	var config := SessionConfig.new()
	config.seed = int(selection_draft.get("seed", 1))
	config.character_id = selection_draft.get("character_id", &"")
	config.starting_weapon_id = selection_draft.get("weapon_id", &"")
	config.difficulty_id = selection_draft.get("difficulty_id", &"")
	config.zone_id = selection_draft.get("zone_id", &"")
	var candidate := GameSession.new()
	var error := candidate.start(config, content_snapshot)
	if error != OK:
		return error
	current_session = candidate
	session_created.emit(candidate)
	return OK


func close_session(record_result: bool = true) -> void:
	if current_session != null and record_result and current_session.run_state != null:
		profile_service.record_settlement(current_session.run_state)
	current_session = null
	selection_draft.clear()
	session_closed.emit()


func save_checkpoint() -> Error:
	if current_session == null or current_session.run_state == null:
		return ERR_UNAVAILABLE
	return profile_service.save_checkpoint(current_session.run_state)


func route(route_id: StringName, payload: Dictionary = {}) -> Error:
	if scene_flow == null:
		return ERR_UNCONFIGURED
	return scene_flow.open(route_id, payload)


func apply_pending_content_packs() -> Error:
	if current_session != null or scene_flow == null or scene_flow.current_route() != FlowRoute.MAIN_MENU:
		return ERR_BUSY
	var next_snapshot := content_catalog.apply_at_main_menu(content_registry, scene_flow.current_route())
	if next_snapshot == null:
		return ERR_INVALID_DATA
	content_snapshot = next_snapshot
	return OK
