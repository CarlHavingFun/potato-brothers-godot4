class_name AppKernel
extends Node

const STATIC_CANDIDATE_PREVIEW_SERVICE := preload(
	"res://game/content/assets/gogobro_static_candidate_preview_service.gd"
)

signal boot_completed(result: BootResult)
signal session_created(session: GameSession)
signal session_closed

var scene_flow: SceneFlow
var content_registry := GogoContentRegistry.new()
var content_catalog := ContentPackCatalog.new()
var content_snapshot: ContentSnapshot
var static_asset_service := GogoStaticAssetRuntimeService.new(
	GogoStaticAssetRuntimeService.MANIFEST_PATH,
	GogoStaticAssetRuntimeService.REGISTRY_PATH,
	GogoStaticAssetRuntimeService.DEFAULT_ASSET_ROOT,
	OS.is_debug_build()
)
var static_candidate_preview_service: RefCounted = STATIC_CANDIDATE_PREVIEW_SERVICE.new()
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
var _settlement_recorded := false


func configure(flow: SceneFlow, audio: GogoAudioService) -> void:
	scene_flow = flow
	audio_service = audio


func boot() -> BootResult:
	var development_preview := OS.is_debug_build()
	var packs := ValidationContentFactory.create_packs(development_preview)
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
	static_asset_service.stage(content_snapshot)
	static_asset_service.activate_staged(&"", null)
	if development_preview:
		var preview_snapshot := static_candidate_preview_service.call(
			"build_overlay",
			static_asset_service.active_snapshot(),
			content_snapshot
		) as GogoStaticAssetSnapshot
		if preview_snapshot != null:
			static_asset_service.activate_development_preview(preview_snapshot, &"", null)
	var profile_error := profile_service.load_profile(content_snapshot)
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
	if current_session != null:
		return ERR_ALREADY_IN_USE
	if profile_service.is_write_blocked():
		_publish_save_error("存档校验失败")
		return ERR_FILE_CORRUPT
	var config := SessionConfig.new()
	config.seed = int(selection_draft.get("seed", 1))
	config.character_id = selection_draft.get("character_id", &"")
	config.starting_weapon_id = selection_draft.get("weapon_id", &"")
	config.difficulty_id = selection_draft.get("difficulty_id", &"")
	config.zone_id = selection_draft.get("zone_id", &"")
	var candidate := GameSession.new()
	candidate.static_asset_snapshot = static_asset_service.active_snapshot()
	var error := candidate.start(config, content_snapshot)
	if error != OK:
		return error
	error = candidate.prepare_checkpoint()
	if error != OK:
		return error
	# Replacing any stale run is part of creating a new session, not a best-effort
	# follow-up. An unconfigured or unwritable profile therefore fails closed before
	# the candidate can become observable.
	error = profile_service.save_checkpoint(candidate.run_state)
	if error != OK:
		_publish_save_error("新局存档失败")
		return error
	current_session = candidate
	_settlement_recorded = false
	candidate.run_ended.connect(_on_session_run_ended)
	session_created.emit(candidate)
	return OK


func close_session(record_result: bool = true) -> void:
	if current_session == null:
		return
	if record_result:
		_record_settlement_once()
	current_session = null
	selection_draft.clear()
	session_closed.emit()


func _on_session_run_ended(_victory: bool) -> void:
	_record_settlement_once()


func _record_settlement_once() -> void:
	if _settlement_recorded or current_session == null or current_session.run_state == null or not current_session.run_state.ended:
		return
	# Commit before any persistence/route publication. Closing settlement is not
	# a second terminal event, nor is a nonterminal disposal a completed run.
	_settlement_recorded = true
	var error := profile_service.record_settlement(current_session.run_state)
	if error != OK:
		_publish_save_error("结算存档失败")
		call_deferred("route", FlowRoute.DIAGNOSTIC, {"message": "结算存档失败", "details": [profile_service.last_error]})


func save_checkpoint() -> Error:
	if current_session == null or current_session.run_state == null:
		return ERR_UNAVAILABLE
	var error := current_session.prepare_checkpoint()
	if error == OK:
		error = profile_service.save_checkpoint(current_session.run_state)
	if error != OK:
		_publish_save_error("存档保存失败")
	return error


func can_resume_checkpoint() -> bool:
	return current_session == null and _checkpoint_candidate().error == OK


func resume_checkpoint() -> Error:
	if current_session != null:
		return ERR_ALREADY_IN_USE
	var prepared := _checkpoint_candidate()
	if prepared.error != OK:
		return prepared.error
	var candidate := prepared.session as GameSession
	current_session = candidate
	_settlement_recorded = false
	candidate.run_ended.connect(_on_session_run_ended)
	# Observers must see the exact detached disk state before a routed scene's
	# synchronous _ready() can consume RNG or initialize a phase cache.
	session_created.emit(candidate)
	var route_error := route(prepared.route)
	if route_error != OK:
		candidate.run_ended.disconnect(_on_session_run_ended)
		current_session = null
		session_closed.emit()
		return route_error
	return OK


func _checkpoint_candidate() -> Dictionary:
	if profile_service.is_write_blocked():
		return {"error": ERR_FILE_CORRUPT, "session": null, "route": &""}
	if content_snapshot == null:
		return {"error": ERR_UNCONFIGURED, "session": null, "route": &""}
	var parsed := profile_service.parse_checkpoint(content_snapshot)
	if parsed.error != OK:
		return {"error": parsed.error, "session": null, "route": &""}
	var candidate := GameSession.new()
	candidate.static_asset_snapshot = static_asset_service.active_snapshot()
	var restore_error := candidate.restore_from_checkpoint(parsed.state, content_snapshot)
	if restore_error != OK:
		return {"error": restore_error, "session": null, "route": &""}
	var routes := {
		&"combat": FlowRoute.COMBAT,
		&"upgrade": FlowRoute.UPGRADE,
		&"shop": FlowRoute.SHOP,
	}
	return {
		"error": OK,
		"session": candidate,
		"route": routes[candidate.run_state.phase],
	}


func _publish_save_error(message: String) -> void:
	boot_result = BootResult.failure(BootResult.Status.SAVE_ERROR, message, [profile_service.last_error])


func route(route_id: StringName, payload: Dictionary = {}) -> Error:
	if route_id != FlowRoute.DIAGNOSTIC and profile_service.is_write_blocked():
		_publish_save_error("存档校验失败")
		return ERR_FILE_CORRUPT
	if scene_flow == null:
		return ERR_UNCONFIGURED
	var canonical := FlowRoute.CHARACTER_SELECT if route_id in [FlowRoute.WEAPON_SELECT, FlowRoute.DIFFICULTY_SELECT] else route_id
	return scene_flow.open(canonical, payload)


func apply_pending_content_packs() -> Error:
	if current_session != null or scene_flow == null or scene_flow.current_route() != FlowRoute.MAIN_MENU:
		return ERR_BUSY
	var current_error := profile_service.validate_content_context(content_snapshot)
	if current_error != OK:
		_publish_save_error("存档校验失败")
		return current_error
	var prepared := content_catalog.prepare_at_main_menu(content_registry, scene_flow.current_route())
	if prepared.is_empty():
		return ERR_INVALID_DATA
	var next_snapshot: ContentSnapshot = prepared.snapshot
	var context_error := profile_service.validate_content_context(next_snapshot)
	if context_error != OK: return context_error
	var stage_error := static_asset_service.stage(next_snapshot)
	if stage_error != OK:
		return stage_error
	var activate_error := static_asset_service.activate_staged(scene_flow.current_route(), current_session)
	if activate_error != OK:
		static_asset_service.discard_staged()
		return activate_error
	content_snapshot = next_snapshot
	profile_service.publish_content_context(next_snapshot)
	# Catalog observers see matching app/profile context. Static activation's own earlier
	# events retain their existing timing and are not claimed to be globally atomic.
	return content_catalog.commit_prepared(prepared)
