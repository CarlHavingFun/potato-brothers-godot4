extends Node2D
class_name Arena

const MAX_EFFECT_ENTITIES_PER_KIND := 6
const RUN_HUD_FORMATTER := preload("res://core/presentation/run_hud_formatter.gd")
const EFFECT_PROJECTILE_SCENE := preload("res://scenes/projectiles/projectile_pistol.tscn")
const WAVE_RULES := preload("res://core/directors/core_wave_rules.gd")

signal frontend_requested

@export var normal_color: Color
@export var blocked_color: Color
@export var critical_color: Color
@export var hp_color: Color
@export var externally_managed_frontend := false

@onready var wave_index_label: Label = %WaveIndexLabel
@onready var wave_time_label: Label = %WaveTimeLabel
@onready var encounter_label: Label = %EncounterLabel
@onready var next_wave_label: Label = %NextWaveLabel
@onready var boss_status_label: Label = %BossStatusLabel
@onready var player_status_label: Label = %PlayerStatusLabel
@onready var health_hud_label: Label = %HealthHudLabel
@onready var experience_hud_label: Label = %ExperienceHudLabel
@onready var material_bag_label: Label = %MaterialBagLabel
@onready var health_hud_bar: ProgressBar = %HealthHudBar
@onready var experience_hud_bar: ProgressBar = %ExperienceHudBar

@onready var spawner: Spawner = $Spawner
@onready var ecology: ArenaEcology = %ArenaEcology
@onready var upgrade_panel: UpgradePanel = %UpgradePanel
@onready var shop_panel: ShopPanel = %ShopPanel
@onready var reward_panel: RewardPanel = %RewardPanel
@onready var title_panel: TitlePanel = %TitlePanel
@onready var selection_panel: SelectionPanel = %SelectionPanel
@onready var difficulty_panel: DifficultyPanel = %DifficultyPanel
@onready var pause_panel: PausePanel = %PausePanel
@onready var settlement_panel: SettlementPanel = %SettlementPanel
@onready var settings_panel: SettingsPanel = %SettingsPanel
@onready var coins_bag: CoinsBag = %CoinsBag
@onready var music_player: AudioStreamPlayer = $MusicPlayer
@onready var game_camera: Camera = $Camera2D
@onready var background: Sprite2D = $BlackBG
@onready var floor_background: Sprite2D = $GrassBG

var gold_list: Array[Coins]
var effect_entities: Array[EffectAlly] = []
var gameplay_notices := GameplayNoticeBus.new()
var notice_label: Label
var _last_hud_run_id := 0
var _last_hud_materials := -1
var _last_hud_material_bag := -1
var _material_bag_explained := false

func _ready() -> void:
	_apply_skin_presentation()
	_setup_notice_hud()
	add_to_group(GameplayEffectExecutor.ARENA_GROUP)
	Global.on_create_block_text.connect(_on_create_block_text)
	Global.on_create_damage_text.connect(_on_create_damage_text)
	Global.on_upgrade_selected.connect(_on_upgrade_selected)
	Global.on_create_heal_text.connect(_on_create_heal_text)
	Global.on_enemy_died.connect(_on_enemy_died)
	reset_to_title()
	refresh_presentation_settings()
	call_deferred("_start_music")


func _apply_skin_presentation() -> void:
	background.texture = Presentation.resolve_texture(
		&"scene", &"scene.arena.background", background.texture, &"background"
	)
	floor_background.texture = Presentation.resolve_texture(
		&"scene", &"scene.arena.floor", floor_background.texture, &"floor"
	)
	background.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	floor_background.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	music_player.stream = Presentation.resolve_music(&"combat")


func _start_music() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if is_instance_valid(music_player) and not music_player.playing:
		music_player.play()


func _process(delta: float) -> void:
	if not Global.is_combat_active(): return
	Global.current_run.elapsed_seconds += delta
	var hud := HudState.capture(
		Global.current_run,
		Global.player,
		spawner.wave_timer.time_left,
		Global.reward_service.experience_required_for_level(Global.current_run.level)
	)
	wave_index_label.text = LocalizedTextService.resolve(
		&"ui.hud.wave.endless" if hud.endless else &"ui.hud.wave.standard",
		[hud.wave]
	)
	wave_time_label.text = str(hud.seconds_remaining)
	_track_material_notices(hud)
	_refresh_runtime_hud()


func _refresh_runtime_hud() -> void:
	_refresh_player_vitals()
	var current := spawner.current_wave_definition
	encounter_label.text = (
		LocalizedTextService.resolve(RUN_HUD_FORMATTER.encounter_key(current))
		if current != null
		else ""
	)
	var next_wave := Content.catalog.get_wave(StringName("wave/%02d" % (spawner.wave_index + 1)))
	if next_wave != null:
		next_wave_label.text = LocalizedTextService.resolve(&"ui.hud.next_wave", [
			LocalizedTextService.resolve(RUN_HUD_FORMATTER.encounter_key(next_wave)),
		])
	else:
		next_wave_label.text = ""
	_refresh_player_status()
	_refresh_boss_status()


func _refresh_player_vitals() -> void:
	health_hud_label.visible = GameplayCuePresenter.runtime_bool(
		&"show_player_health_bar", true
	)
	if Global.current_run == null or not is_instance_valid(Global.player):
		health_hud_label.text = ""
		experience_hud_label.text = ""
		material_bag_label.text = ""
		health_hud_bar.value = 0.0
		experience_hud_bar.value = 0.0
		return
	var health := Global.player.health_component
	health_hud_label.text = LocalizedTextService.resolve(&"ui.hud.health", [
		roundi(health.current_health), roundi(health.max_health),
	])
	health_hud_bar.max_value = maxf(1.0, health.max_health)
	health_hud_bar.value = clampf(health.current_health, 0.0, health_hud_bar.max_value)
	var required := Global.reward_service.experience_required_for_level(Global.current_run.level)
	experience_hud_label.text = LocalizedTextService.resolve(&"ui.hud.experience", [
		Global.current_run.level, Global.current_run.experience, required,
	])
	experience_hud_bar.max_value = maxi(1, required)
	experience_hud_bar.value = clampi(
		Global.current_run.experience, 0, int(experience_hud_bar.max_value)
	)
	material_bag_label.text = LocalizedTextService.resolve(
		&"ui.hud.material_bag", [Global.current_run.material_bag]
	)


func _refresh_player_status() -> void:
	if not is_instance_valid(Global.player):
		player_status_label.text = ""
		return
	var parts: Array[String] = []
	for entry: Dictionary in RUN_HUD_FORMATTER.status_entries(Global.player.active_effect_statuses):
		var status_id := str(entry.get("status_id", ""))
		parts.append("%s ×%d" % [
			LocalizedTextService.resolve(StringName("status.%s" % status_id)),
			int(entry.get("stacks", 1)),
		])
	player_status_label.text = "  ".join(parts)


func _refresh_boss_status() -> void:
	boss_status_label.visible = GameplayCuePresenter.runtime_bool(
		&"show_boss_health_bar", true
	)
	if not boss_status_label.visible:
		boss_status_label.text = ""
		return
	var snapshot := RUN_HUD_FORMATTER.boss_snapshot(spawner.spawned_enemies)
	if snapshot.is_empty():
		boss_status_label.text = ""
		return
	var phase_key := "ui.hud.boss_phase.%s" % str(snapshot.get("phase", "base"))
	boss_status_label.text = LocalizedTextService.resolve(&"ui.hud.boss_status", [
		int(snapshot.get("count", 1)),
		LocalizedTextService.resolve(StringName(phase_key)),
		roundi(float(snapshot.get("health", 0.0))),
		roundi(float(snapshot.get("maximum_health", 0.0))),
	])


func _setup_notice_hud() -> void:
	notice_label = Label.new()
	notice_label.name = "GameplayNoticeLabel"
	notice_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	notice_label.position = Vector2(-360.0, 132.0)
	notice_label.size = Vector2(720.0, 46.0)
	notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice_label.add_theme_font_size_override(&"font_size", 24)
	notice_label.add_theme_color_override(&"font_color", Color(1.0, 0.84, 0.34))
	notice_label.add_theme_color_override(&"font_outline_color", Color(0.04, 0.06, 0.05, 0.95))
	notice_label.add_theme_constant_override(&"outline_size", 6)
	notice_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notice_label.modulate.a = 0.0
	$GameUI.add_child(notice_label)
	gameplay_notices.notice_emitted.connect(_on_gameplay_notice)


func _track_material_notices(hud: HudState) -> void:
	var run_id := Global.current_run.get_instance_id() if Global.current_run != null else 0
	if run_id != _last_hud_run_id:
		_last_hud_run_id = run_id
		_last_hud_materials = hud.materials
		_last_hud_material_bag = hud.material_bag
		_material_bag_explained = false
		return
	if _last_hud_materials < 0 or _last_hud_material_bag < 0:
		_last_hud_materials = hud.materials
		_last_hud_material_bag = hud.material_bag
		return
	var material_gain := hud.materials - _last_hud_materials
	var bag_delta := hud.material_bag - _last_hud_material_bag
	if bag_delta > 0:
		gameplay_notices.materials_banked(bag_delta, not _material_bag_explained)
		_material_bag_explained = true
	elif material_gain > 0:
		gameplay_notices.material_pickup(material_gain, maxi(0, -bag_delta))
	_last_hud_materials = hud.materials
	_last_hud_material_bag = hud.material_bag


func _on_gameplay_notice(text_id: StringName, args: Array, priority: int) -> void:
	if not is_instance_valid(notice_label):
		return
	notice_label.text = LocalizedTextService.resolve(text_id, args)
	notice_label.add_theme_color_override(
		&"font_color",
		Color(1.0, 0.84, 0.34) if priority == GameplayNoticeBus.Priority.IMPORTANT else Color.WHITE
	)
	notice_label.modulate.a = 1.0
	var tween := notice_label.create_tween()
	tween.tween_interval(1.35)
	tween.tween_property(notice_label, "modulate:a", 0.0, 0.35)


func _unhandled_input(event: InputEvent) -> void:
	var pause_pressed := (
		event.is_action_pressed(&"pause")
		if InputMap.has_action(&"pause")
		else event.is_action_pressed(&"ui_cancel")
	)
	if pause_pressed and Global.is_combat_active():
		_pause_game()
		get_viewport().set_input_as_handled()


func create_floating_text(unit: Node2D) -> FloatingText:
	var instance := Global.FLOATING_TEXT_SCENE.instantiate() as FloatingText
	get_tree().root.add_child(instance)
	var random_pos := randf_range(0, TAU) * 35
	var spawn_pos := unit.global_position + Vector2.RIGHT.rotated(random_pos)
	instance.global_position = spawn_pos
	return instance


func show_upgrades() -> void:
	upgrade_panel.load_upgrades(spawner.wave_index)
	upgrade_panel.show()


func start_new_wave() -> void:
	Global.player.update_player_new_wave()
	Global.shop_service.prepare_next_wave(Global.current_run)
	spawner.wave_index += 1
	Global.current_run.wave = spawner.wave_index
	Global.current_run.highest_wave_reached = maxi(
		Global.current_run.highest_wave_reached, spawner.wave_index
	)
	Global.current_run.endless_cycle = (
		floori(float(spawner.wave_index - 21) / 5.0) + 1
		if Global.current_run.run_mode == RunMode.ENDLESS and spawner.wave_index > 20
		else 0
	)
	_apply_wave_start_character_rules()
	Global.enter_phase(RunPhase.COMBAT)
	Global.save_combat_checkpoint()
	Global.dispatch_gameplay_event(GameplayEvent.Type.WAVE_STARTED, {"wave": spawner.wave_index})
	ecology.setup_wave(spawner.wave_index, Global.current_run.random_seed, Global.player)
	spawner.start_wave()
	_refresh_runtime_hud()


func clean_arena() -> void:
	if gold_list.size() > 0:
		var uncollected_value := 0
		for gold in gold_list:
			if is_instance_valid(gold) and not gold.is_queued_for_deletion():
				uncollected_value += maxi(0, gold.value)
				gold.queue_free()
		if Global.current_run != null and Global.reward_service != null:
			var banked := Global.reward_service.bank_materials(
				Global.current_run, uncollected_value
			)
			if banked > 0:
				gameplay_notices.materials_banked(banked, not _material_bag_explained)
				_material_bag_explained = true
				# The wave has already left COMBAT, so `_process` cannot observe this
				# transition until the next wave. Advance the baseline now to prevent
				# a delayed duplicate notice on that next combat frame.
				_last_hud_materials = Global.current_run.materials
				_last_hud_material_bag = Global.current_run.material_bag
	
	gold_list.clear()
	for entity: EffectAlly in effect_entities:
		if is_instance_valid(entity):
			entity.queue_free()
	effect_entities.clear()
	spawner.clear_enemies()


func spawn_effect_entities(
	kind: StringName,
	commands: Array[Dictionary],
	_context: GameplayEventContext
) -> void:
	effect_entities.assign(effect_entities.filter(func(entity: EffectAlly): return is_instance_valid(entity)))
	for command: Dictionary in commands:
		for _entity_index in maxi(0, int(command.get("count", 0))):
			var same_kind_count := effect_entities.filter(
				func(existing: EffectAlly): return existing.entity_kind == kind
			).size()
			if same_kind_count >= MAX_EFFECT_ENTITIES_PER_KIND:
				break
			var entity := EffectAlly.new()
			add_child(entity)
			var index := effect_entities.size()
			var anchor := Global.player as Node2D
			entity.global_position = (
				anchor.global_position + Vector2.RIGHT.rotated(index * 1.9) * 90.0
				if is_instance_valid(anchor)
				else Vector2.ZERO
			)
			entity.setup(kind, StringName(str(command.get("content_id", ""))), anchor, index)
			entity.projectile_requested.connect(_on_effect_ally_projectile_requested)
			effect_entities.append(entity)


func _on_effect_ally_projectile_requested(
	origin: Vector2,
	target: Node2D,
	damage_amount: float,
	source: Node2D,
	metadata: Dictionary
) -> void:
	if not is_instance_valid(target) or not is_instance_valid(source):
		return
	var projectile := EFFECT_PROJECTILE_SCENE.instantiate() as Projectile
	if projectile == null:
		return
	get_tree().root.add_child(projectile)
	projectile.global_position = origin
	var direction := origin.direction_to(target.global_position)
	if direction.is_zero_approx():
		direction = Vector2.RIGHT
	var entity_kind := StringName(str(metadata.get("entity_kind", "building")))
	var effect_tags: Array[StringName] = [&"engineering", entity_kind]
	var presentation_id := (
		&"weapon.drone_beacon" if entity_kind == &"summon" else &"weapon.turret_kit"
	)
	projectile.set_projectile(
		direction * maxf(1.0, float(metadata.get("projectile_speed", 600.0))),
		maxf(0.0, damage_amount),
		false,
		1.5,
		Global.player if is_instance_valid(Global.player) else source,
		source,
		effect_tags,
		0,
		0,
		presentation_id
	)
	if bool(metadata.get("homing", false)):
		projectile.configure_homing(target)
	GameplayCues.emit_cue(&"weapon.fire", {
		"content_id": str(metadata.get("content_id", "")),
		"world_position": origin,
		"entity_kind": String(entity_kind),
	})


func spawn_coins(enemy: Enemy) -> void:
	if enemy == null or enemy.stats == null or enemy.stats.gold_drop <= 0:
		return
	if Global.current_run != null and not WAVE_RULES.should_drop_material(
		Global.current_run.random_seed,
		Global.current_run.wave,
		Global.current_run.kill_count
	):
		return
	var random_angle := randf_range(0, TAU)
	var offset := Vector2.RIGHT.rotated(random_angle) * 35 
	var spawn_pos := enemy.global_position + offset
	
	var gold_instance := Global.COINS_SCENE.instantiate() as Coins
	gold_list.append(gold_instance)
	
	gold_instance.global_position = spawn_pos
	gold_instance.value = enemy.stats.gold_drop
	call_deferred("add_child", gold_instance)


func _on_create_block_text(unit: Node2D) -> void:
	var text := create_floating_text(unit)
	text.setup(LocalizedTextService.resolve(&"ui.combat.blocked"), blocked_color)


func _on_create_damage_text(unit: Node2D, hitbox: HitboxComponent) -> void:
	if GameplayCuePresenter.runtime_bool(&"show_damage_numbers", true):
		var text := create_floating_text(unit)
		var color := critical_color if hitbox.critical else normal_color
		text.setup(str(snappedf(hitbox.display_damage, 0.1)), color)
	if is_instance_valid(game_camera):
		var base_trauma := 0.22 if unit is Player else (0.14 if hitbox.critical else 0.04)
		game_camera.add_trauma(
			base_trauma * GameplayCuePresenter.screen_shake_multiplier()
		)


func _on_create_heal_text(unit: Node2D, heal: float) -> void:
	var text := create_floating_text(unit)
	text.setup("+ %s" % heal, hp_color)


func _on_upgrade_selected() -> void:
	if Global.current_run == null or Global.current_run.queued_level_ups <= 0:
		return
	var next_phase := Global.reward_service.claim_level_up_and_get_next_phase(Global.current_run)
	if next_phase != RunPhase.UPGRADE and not Global.enter_phase(next_phase):
		return
	Global.save_progress(true)
	if next_phase == RunPhase.UPGRADE:
		upgrade_panel.load_upgrades(spawner.wave_index)
		return
	upgrade_panel.hide()
	if next_phase == RunPhase.CHEST:
		_show_reward()
	else:
		_show_shop()


func _on_spawner_on_wave_completed() -> void:
	if not Global.player: return
	clean_arena()
	Global.dispatch_gameplay_event(GameplayEvent.Type.WAVE_ENDED, {"wave": spawner.wave_index})
	var next_phase := RunPhase.UPGRADE
	if Global.current_run.queued_level_ups <= 0:
		next_phase = RunPhase.CHEST if Global.current_run.queued_rewards > 0 else RunPhase.SHOP
	if not _enter_post_wave_phase(next_phase):
		return
	# Persist the target phase before any upgrade/reward roll consumes RNG so
	# continuing reconstructs the same choices instead of replaying combat.
	Global.save_progress(true)
	await get_tree().create_timer(1.0).timeout
	if Global.current_run == null:
		return
	match next_phase:
		RunPhase.UPGRADE:
			show_upgrades()
		RunPhase.CHEST:
			_show_reward()
		RunPhase.SHOP:
			_show_shop()
	clean_arena()


func _enter_post_wave_phase(target_phase: int) -> bool:
	if Global.current_run == null:
		return false
	if Global.current_run.phase == RunPhase.COMBAT and not Global.enter_phase(RunPhase.UPGRADE):
		return false
	return target_phase == RunPhase.UPGRADE or Global.enter_phase(target_phase)


func _show_reward() -> void:
	if reward_panel.load_reward(spawner.wave_index):
		reward_panel.show()
	else:
		Global.current_run.queued_rewards = 0
		Global.enter_phase(RunPhase.SHOP)
		_show_shop()


func _show_shop() -> void:
	shop_panel.load_shop(spawner.wave_index)
	shop_panel.show()
	Global.save_progress()


func _on_reward_panel_reward_claimed(item: ItemBase) -> void:
	# RewardPanel already applies a passive after the inventory claim succeeds.
	# Project it into the inventory UI without applying its stats a second time.
	shop_panel.project_item(item, false)


func _on_reward_panel_reward_finished(next_phase: int) -> void:
	if next_phase == RunPhase.CHEST:
		Global.save_progress(true)
		reward_panel.load_reward(spawner.wave_index)
		return
	reward_panel.hide()
	if not Global.enter_phase(RunPhase.SHOP):
		return
	_show_shop()


func _on_shop_panel_on_shop_next_wave() -> void:
	shop_panel.hide()
	start_new_wave()


func _on_enemy_died(enemy: Enemy) -> void:
	if Global.current_run != null:
		Global.current_run.kill_count += 1
		if is_final_boss_enemy(enemy):
			Global.current_run.boss_kill_count += 1
	spawn_coins(enemy)
	if enemy.definition != null:
		var drop_kind := Global.reward_service.resolve_enemy_drop(
			Global.current_run, enemy.definition.tags
		)
		if drop_kind == RewardService.DROP_HEAL:
			ecology.spawn_world_drop(enemy.global_position, drop_kind)
	if is_final_boss_enemy(enemy):
		spawner.complete_boss_victory()


static func is_final_boss_enemy(enemy: Enemy) -> bool:
	return enemy != null and enemy.definition != null and &"boss" in enemy.definition.tags


func _on_player_died() -> void:
	finish_run(false)


func _on_selection_panel_on_selection_completed() -> void:
	selection_panel.hide()
	difficulty_panel.load_difficulties(Global.meta_progress.highest_unlocked_difficulty)
	difficulty_panel.show()


func _on_difficulty_panel_difficulty_selected(level: int) -> void:
	if is_instance_valid(Global.player) or Global.is_combat_active():
		difficulty_panel.hide()
		return
	_begin_selected_combat(level, 0)


func launch_run(request: RunLaunchRequest) -> bool:
	if request == null or not request.is_valid() or is_instance_valid(Global.player):
		return false
	if request.profile_id != Global.active_profile_id() and not Global.switch_profile(request.profile_id):
		return false
	var character := Content.catalog.get_character(request.character_id)
	var weapon := Content.catalog.get_weapon(request.weapon_id)
	if character == null or weapon == null or not _is_starter_weapon_allowed(character, weapon):
		return false
	_reset_runtime_run()
	if not Global.select_character(character) or not Global.select_starting_weapon(weapon):
		return false
	Global.set_aim_mode(request.aim_mode)
	return _begin_selected_combat(request.difficulty, request.random_seed, request.run_mode)


func resume_checkpoint(checkpoint: RunState) -> bool:
	if checkpoint == null or is_instance_valid(Global.player):
		return false
	var sanitizer := CheckpointContentSanitizer.new()
	var repaired := sanitizer.sanitize(checkpoint, Content.catalog)
	_append_checkpoint_repair_notices(sanitizer.repair_notice_keys)
	if repaired == null or not repaired.is_resumable_checkpoint():
		return false
	if repaired.phase in [RunPhase.VICTORY, RunPhase.DEATH]:
		return false
	var character := Content.catalog.get_character(repaired.character_id)
	var starter := Content.catalog.get_weapon(repaired.starting_weapon_id)
	if character == null or starter == null:
		return false
	_reset_runtime_run()
	if not Global.select_character(character) or not Global.select_starting_weapon(starter):
		return false
	if not Global.resume_run_state(repaired):
		return false
	Global.rebuild_run_effects()
	var player := Global.get_selected_player()
	if player == null:
		Global.end_run()
		return false
	add_child(player)
	player.health_component.on_unit_died.connect(_on_player_died, CONNECT_ONE_SHOT)
	_restore_inventory_visuals(repaired)
	if not sanitizer.repair_notice_keys.is_empty():
		# Persist both the sanitized checkpoint and its user-facing, localized
		# repair summary. No content IDs are placed in profile UI notices.
		Global.save_progress(true)
	spawner.wave_index = repaired.wave
	Global.current_run.wave = repaired.wave
	title_panel.hide()
	selection_panel.hide()
	difficulty_panel.hide()
	upgrade_panel.hide()
	reward_panel.hide()
	shop_panel.hide()
	match repaired.phase:
		RunPhase.UPGRADE:
			show_upgrades()
		RunPhase.CHEST:
			_show_reward()
		RunPhase.SHOP:
			_show_shop()
		_:
			Global.current_run.phase = RunPhase.COMBAT
			Global.run_director = RunDirector.new(Global.current_run)
			Global.save_combat_checkpoint()
			Global.dispatch_gameplay_event(GameplayEvent.Type.WAVE_STARTED, {"wave": spawner.wave_index})
			ecology.setup_wave(spawner.wave_index, Global.current_run.random_seed, player)
			spawner.start_wave()
	return true


func _append_checkpoint_repair_notices(notice_keys: Array[StringName]) -> void:
	for notice_key: StringName in notice_keys:
		var serialized := String(notice_key)
		if serialized not in Global.meta_progress.repair_notices:
			Global.meta_progress.repair_notices.append(serialized)


func _restore_inventory_visuals(checkpoint: RunState) -> void:
	shop_panel.reset_inventory()
	var data := checkpoint.inventory.to_dict()
	for entry: Dictionary in data.get("weapons", []):
		var item := Content.catalog.get_weapon_tier(
			StringName(str(entry.get("weapon_id", ""))),
			int(entry.get("tier", 0))
		)
		if item == null:
			continue
		Global.player.add_weapon(item)
		Global.equipped_weapons.append(item)
		shop_panel.create_item_weapon(item)
	var passives: Variant = data.get("passives", {})
	if passives is Dictionary:
		for raw_id: Variant in passives:
			var definition := Content.catalog.get_passive(StringName(str(raw_id)))
			if definition == null or definition.item == null:
				continue
			for copy_index in int(passives[raw_id]):
				var card := shop_panel.create_item_card()
				shop_panel.passives_container.add_child(card)
				card.item = definition.item


func _begin_selected_combat(
	level: int,
	seed_value: int,
	run_mode: int = RunMode.STANDARD
) -> bool:
	if not Global.begin_selected_run(seed_value):
		return false
	Global.current_run.difficulty = clampi(level, 1, 5)
	Global.current_run.run_mode = run_mode if RunMode.is_valid(run_mode) else RunMode.STANDARD
	var player := Global.get_selected_player()
	if player == null:
		Global.end_run()
		difficulty_panel.show()
		return false
	difficulty_panel.hide()
	selection_panel.hide()
	title_panel.hide()
	add_child(player)
	player.health_component.on_unit_died.connect(_on_player_died, CONNECT_ONE_SHOT)
	player.add_weapon(Global.main_weapon_selected)
	shop_panel.create_item_weapon(Global.main_weapon_selected)
	Global.equipped_weapons.append(Global.main_weapon_selected)
	
	Global.current_run.wave = spawner.wave_index
	Global.current_run.highest_wave_reached = spawner.wave_index
	_apply_wave_start_character_rules()
	Global.enter_phase(RunPhase.COMBAT)
	Global.save_combat_checkpoint()
	Global.dispatch_gameplay_event(GameplayEvent.Type.WAVE_STARTED, {"wave": spawner.wave_index})
	ecology.setup_wave(spawner.wave_index, Global.current_run.random_seed, player)
	spawner.start_wave()
	return true


func _apply_wave_start_character_rules() -> int:
	if Global.current_run == null:
		return 0
	var removed := Global.current_run.apply_wave_start_character_rules()
	if removed > 0:
		Global.materials_changed.emit(Global.current_run.materials)
	return removed


func _is_starter_weapon_allowed(character: CharacterDef, weapon: WeaponDef) -> bool:
	if character.rules != null and not character.rules.allows_weapon(weapon.tags):
		return false
	if character.starter_weapon_ids.is_empty():
		return true
	var stable_id := weapon.get_stable_id(Content.catalog.pack_id)
	for allowed_id: StringName in character.starter_weapon_ids:
		var allowed := Content.catalog.get_weapon(allowed_id)
		if allowed != null and allowed.get_stable_id(Content.catalog.pack_id) == stable_id:
			return true
	return false


func _on_title_panel_start_requested() -> void:
	Global.end_run()
	title_panel.hide()
	selection_panel.show()


func finish_run(victory: bool) -> void:
	if Global.current_run == null:
		return
	var target_phase := RunPhase.VICTORY if victory else RunPhase.DEATH
	if Global.current_run.phase != target_phase:
		if Global.current_run.phase != RunPhase.COMBAT or not Global.enter_phase(target_phase):
			return
	if is_instance_valid(settlement_panel) and settlement_panel.visible:
		return
	if is_instance_valid(spawner):
		if is_instance_valid(spawner.spawn_timer):
			spawner.spawn_timer.stop()
		if is_instance_valid(spawner.wave_timer):
			spawner.wave_timer.stop()
		spawner.clear_enemies()
	GameLog.info(&"run", "run_finished", {
		"victory": victory,
		"run_mode": Global.current_run.run_mode,
		"difficulty": Global.current_run.difficulty,
		"highest_wave": Global.current_run.highest_wave_reached,
		"kills": Global.current_run.kill_count,
		"boss_kills": Global.current_run.boss_kill_count,
		"elapsed_seconds": snappedf(Global.current_run.elapsed_seconds, 0.1),
	})
	Global.record_run_summary(victory)
	if Global.current_run.run_mode == RunMode.ENDLESS:
		Global.record_endless_progress()
	if victory:
		Global.record_victory()
	else:
		Global.save_progress(false)
	if is_instance_valid(settlement_panel):
		settlement_panel.show_result(Global.current_run, victory)
		settlement_panel.show()


func _on_spawner_on_run_victory() -> void:
	finish_run(true)


func _pause_game() -> void:
	if not Global.is_combat_active():
		return
	pause_panel.show()
	get_tree().paused = true


func _on_pause_panel_resume_requested() -> void:
	get_tree().paused = false
	pause_panel.hide()


func _on_pause_panel_title_requested() -> void:
	get_tree().paused = false
	reset_to_title()


func _on_settings_requested() -> void:
	settings_panel.load_settings()
	settings_panel.show()


func _on_settings_panel_closed() -> void:
	settings_panel.hide()
	refresh_presentation_settings()


func refresh_presentation_settings() -> void:
	if is_instance_valid(Global.player):
		Global.player.refresh_presentation_settings()
	if is_instance_valid(spawner):
		for enemy: Enemy in spawner.spawned_enemies:
			if is_instance_valid(enemy):
				enemy.refresh_presentation_settings()
	if get_tree() != null:
		for projectile: Node in get_tree().get_nodes_in_group(&"presentation_projectiles"):
			if projectile.has_method("refresh_presentation_settings"):
				projectile.call("refresh_presentation_settings")
	if is_instance_valid(health_hud_label) and is_instance_valid(boss_status_label):
		_refresh_runtime_hud()


func _on_settlement_panel_retry_requested() -> void:
	if externally_managed_frontend:
		reset_to_title()
	else:
		_reset_runtime_run()
		title_panel.hide()
		selection_panel.show()


func reset_to_title() -> void:
	_reset_runtime_run()
	if externally_managed_frontend:
		title_panel.hide()
		frontend_requested.emit()
	else:
		title_panel.show()


func _reset_runtime_run() -> void:
	get_tree().paused = false
	for panel: Control in [selection_panel, difficulty_panel, upgrade_panel, reward_panel, shop_panel, pause_panel, settlement_panel, settings_panel]:
		panel.hide()
	if is_instance_valid(spawner):
		if is_instance_valid(spawner.spawn_timer):
			spawner.spawn_timer.stop()
		if is_instance_valid(spawner.wave_timer):
			spawner.wave_timer.stop()
		spawner.clear_enemies()
	if is_instance_valid(Global.player):
		Global.player.queue_free()
	gold_list.clear()
	shop_panel.reset_inventory()
	spawner.wave_index = 1
	Global.end_run()
	selection_panel.reset_selection()
