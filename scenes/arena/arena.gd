extends Node2D
class_name Arena

@export var normal_color: Color
@export var blocked_color: Color
@export var critical_color: Color
@export var hp_color: Color

@onready var wave_index_label: Label = %WaveIndexLabel
@onready var wave_time_label: Label = %WaveTimeLabel

@onready var spawner: Spawner = $Spawner
@onready var upgrade_panel: UpgradePanel = %UpgradePanel
@onready var shop_panel: ShopPanel = %ShopPanel
@onready var reward_panel: RewardPanel = %RewardPanel
@onready var coins_bag: CoinsBag = %CoinsBag
@onready var music_player: AudioStreamPlayer = $MusicPlayer

var gold_list: Array[Coins]

func _ready() -> void:
	Global.on_create_block_text.connect(_on_create_block_text)
	Global.on_create_damage_text.connect(_on_create_damage_text)
	Global.on_upgrade_selected.connect(_on_upgrade_selected)
	Global.on_create_heal_text.connect(_on_create_heal_text)
	Global.on_enemy_died.connect(_on_enemy_died)
	call_deferred("_start_music")


func _start_music() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if is_instance_valid(music_player) and not music_player.playing:
		music_player.play()


func _process(delta: float) -> void:
	if not Global.is_combat_active(): return
	wave_index_label.text = spawner.get_wave_text()
	wave_time_label.text = spawner.get_wave_timer_text()


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
	Global.current_run.shop_refresh_count = 0
	if not Global.current_run.shop_locked:
		Global.current_run.shop_offer_ids.clear()
	spawner.wave_index += 1
	Global.current_run.wave = spawner.wave_index
	Global.enter_phase(RunPhase.COMBAT)
	spawner.start_wave()


func clean_arena() -> void:
	if gold_list.size() > 0:
		var target_center_pos := coins_bag.global_position + coins_bag.size / 2.0
		for gold in gold_list:
			if is_instance_valid(gold):
				var gold_item := gold as Coins
				gold_item.set_collection_target(target_center_pos)
	
	gold_list.clear()
	spawner.clear_enemies()


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


func _on_create_heal_text(unit: Node2D, heal: float) -> void:
	var text := create_floating_text(unit)
	text.setup("+ %s" % heal, hp_color)


func _on_upgrade_selected() -> void:
	var next_phase := Global.reward_service.claim_level_up_and_get_next_phase(Global.current_run)
	if next_phase == RunPhase.UPGRADE:
		upgrade_panel.load_upgrades(spawner.wave_index)
		return
	upgrade_panel.hide()
	Global.enter_phase(next_phase)
	if next_phase == RunPhase.CHEST:
		_show_reward()
	else:
		_show_shop()


func _on_spawner_on_wave_completed() -> void:
	if not Global.player: return
	clean_arena()
	await get_tree().create_timer(1.0).timeout
	if Global.current_run.queued_level_ups <= 0:
		Global.reward_service.queue_level_ups(Global.current_run, 1)
	Global.reward_service.queue_rewards(Global.current_run, 1)
	show_upgrades()
	clean_arena()


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


func _on_reward_panel_reward_claimed(item: ItemBase) -> void:
	shop_panel.project_item(item)


func _on_reward_panel_reward_finished(next_phase: int) -> void:
	if next_phase == RunPhase.CHEST:
		reward_panel.load_reward(spawner.wave_index)
		return
	reward_panel.hide()
	Global.enter_phase(RunPhase.SHOP)
	_show_shop()


func _on_shop_panel_on_shop_next_wave() -> void:
	shop_panel.hide()
	start_new_wave()


func _on_enemy_died(enemy: Enemy) -> void:
	spawn_coins(enemy)
	if enemy is MouseDogBoss:
		spawner.complete_boss_victory()


func _on_player_died() -> void:
	if Global.current_run == null or Global.current_run.phase != RunPhase.COMBAT:
		return
	Global.enter_phase(RunPhase.DEATH)
	if is_instance_valid(spawner):
		if is_instance_valid(spawner.spawn_timer):
			spawner.spawn_timer.stop()
		if is_instance_valid(spawner.wave_timer):
			spawner.wave_timer.stop()
		spawner.clear_enemies()


func _on_selection_panel_on_selection_completed() -> void:
	if not Global.begin_selected_run():
		return
	var player := Global.get_selected_player()
	add_child(player)
	player.health_component.on_unit_died.connect(_on_player_died, CONNECT_ONE_SHOT)
	player.add_weapon(Global.main_weapon_selected)
	shop_panel.create_item_weapon(Global.main_weapon_selected)
	Global.equipped_weapons.append(Global.main_weapon_selected)
	
	Global.current_run.wave = spawner.wave_index
	Global.enter_phase(RunPhase.COMBAT)
	spawner.start_wave()
