extends Node2D
class_name Arena

const MAX_EFFECT_ENTITIES_PER_KIND := 6

signal frontend_requested

@export var normal_color: Color
@export var blocked_color: Color
@export var critical_color: Color
@export var hp_color: Color
@export var externally_managed_frontend := false

@onready var wave_index_label: Label = %WaveIndexLabel
@onready var wave_time_label: Label = %WaveTimeLabel

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

func _ready() -> void:
	_apply_skin_presentation()
	add_to_group(GameplayEffectExecutor.ARENA_GROUP)
	Global.on_create_block_text.connect(_on_create_block_text)
	Global.on_create_damage_text.connect(_on_create_damage_text)
	Global.on_upgrade_selected.connect(_on_upgrade_selected)
	Global.on_create_heal_text.connect(_on_create_heal_text)
	Global.on_enemy_died.connect(_on_enemy_died)
	reset_to_title()
	call_deferred("_start_music")


func _apply_skin_presentation() -> void:
	background.texture = Presentation.resolve_texture(
		&"scene", &"scene.arena.background", background.texture
	)
	floor_background.texture = Presentation.resolve_texture(
		&"scene", &"scene.arena.floor", floor_background.texture
	)
	music_player.stream = Presentation.resolve_music(&"combat")


func _start_music() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if is_instance_valid(music_player) and not music_player.playing:
		music_player.play()


func _process(delta: float) -> void:
	if not Global.is_combat_active(): return
	Global.current_run.elapsed_seconds += delta
	wave_index_label.text = spawner.get_wave_text()
	wave_time_label.text = spawner.get_wave_timer_text()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and Global.is_combat_active():
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
	Global.enter_phase(RunPhase.COMBAT)
	Global.save_combat_checkpoint()
	Global.dispatch_gameplay_event(GameplayEvent.Type.WAVE_STARTED, {"wave": spawner.wave_index})
	ecology.setup_wave(spawner.wave_index, Global.current_run.random_seed, Global.player)
	spawner.start_wave()


func clean_arena() -> void:
	if gold_list.size() > 0:
		var target_center_pos := coins_bag.global_position + coins_bag.size / 2.0
		for gold in gold_list:
			if is_instance_valid(gold):
				var gold_item := gold as Coins
				gold_item.set_collection_target(target_center_pos)
	
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
			effect_entities.append(entity)


func spawn_coins(enemy: Enemy) -> void:
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
	text.setup("Blocked!", blocked_color)


func _on_create_damage_text(unit: Node2D, hitbox: HitboxComponent) -> void:
	var text := create_floating_text(unit)
	var color := critical_color if hitbox.critical else normal_color
	text.setup(str(snappedf(hitbox.display_damage, 0.1)), color)
	if is_instance_valid(game_camera):
		game_camera.add_trauma(0.22 if unit is Player else (0.14 if hitbox.critical else 0.04))


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
	shop_panel.project_item(item)


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
		Global.reward_service.queue_enemy_drop(Global.current_run, enemy.definition.tags)
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
	var character := Content.catalog.get_character(checkpoint.character_id)
	var starter := Content.catalog.get_weapon(checkpoint.starting_weapon_id)
	if character == null or starter == null:
		return false
	var repaired := _repair_checkpoint_content(checkpoint, starter)
	if repaired.phase in [RunPhase.VICTORY, RunPhase.DEATH]:
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


func _repair_checkpoint_content(checkpoint: RunState, starter: WeaponDef) -> RunState:
	var repaired := RunState.from_dict(checkpoint.to_dict())
	var sanitized_inventory := InventoryState.new()
	var inventory_data := repaired.inventory.to_dict()
	var raw_weapons: Variant = inventory_data.get("weapons", [])
	if raw_weapons is Array:
		for entry: Variant in raw_weapons:
			if not entry is Dictionary:
				continue
			var weapon_id := StringName(str(entry.get("weapon_id", "")))
			var definition := Content.catalog.get_weapon(weapon_id)
			var tier := int(entry.get("tier", 0))
			if definition == null or Content.catalog.get_weapon_tier(definition.get_stable_id(Content.catalog.pack_id), tier) == null:
				continue
			sanitized_inventory.add_weapon(
				definition.get_stable_id(Content.catalog.pack_id),
				tier,
				int(entry.get("paid_price", 0))
			)
	if sanitized_inventory.weapon_count() == 0:
		sanitized_inventory.add_weapon(starter.get_stable_id(Content.catalog.pack_id), 1, starter.tiers[0].item_cost)
	var raw_passives: Variant = inventory_data.get("passives", {})
	if raw_passives is Dictionary:
		for raw_id: Variant in raw_passives:
			var passive := Content.catalog.get_passive(StringName(str(raw_id)))
			if passive != null:
				sanitized_inventory.add_passive(
					passive.get_stable_id(Content.catalog.pack_id),
					maxi(1, int(raw_passives[raw_id]))
				)
	repaired.inventory = sanitized_inventory
	return repaired


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
	if Global.main_character_selected != null and Global.main_character_selected.rules != null:
		Global.main_character_selected.rules.apply_to_run(Global.current_run)
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
	Global.enter_phase(RunPhase.COMBAT)
	Global.save_combat_checkpoint()
	Global.dispatch_gameplay_event(GameplayEvent.Type.WAVE_STARTED, {"wave": spawner.wave_index})
	ecology.setup_wave(spawner.wave_index, Global.current_run.random_seed, player)
	spawner.start_wave()
	return true


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
