extends Node

const TUTORIAL_STATS_ADAPTER = preload("res://core/adapters/tutorial_stats_adapter.gd")

signal on_create_block_text(unit: Node2D)
signal on_create_damage_text(unit: Node2D, hitbox: HitboxComponent)
signal on_create_heal_text(unit: Node2D, heal: float)

signal on_upgrade_selected
signal on_enemy_died(enemy: Enemy)
signal materials_changed(value: int)
signal run_phase_changed(phase: int)

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
	"rare": { "start_wave": 2, "base_multi": 0.06 },
	"epic": { "start_wave": 4, "base_multi": 0.02 },
	"legendary": { "start_wave": 7, "base_multi": 0.0023 },
}

const SHOP_PROBABILITY_CONFIG = {
	"rare": { "start_wave": 2, "base_multi": 0.10 },
	"epic": { "start_wave": 4, "base_multi": 0.06 },
	"legendary": { "start_wave": 7, "base_multi": 0.01 },
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

const STARTING_MATERIALS := 500

var current_run: RunState
var run_director: RunDirector
var shop_service: ShopService
var reward_service: RewardService
var combat_resolver: CombatResolver
var aim_mode: int = AimMode.AUTO_TARGET
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


func _init() -> void:
	begin_run(0, null, STARTING_MATERIALS)


func begin_run(seed_value: int = 0, source_stats: UnitStats = null, starting_materials: int = STARTING_MATERIALS) -> RunState:
	var player_stats: PlayerStats = TUTORIAL_STATS_ADAPTER.to_player_stats(source_stats)
	current_run = RunState.new(seed_value, player_stats)
	run_director = RunDirector.new(current_run)
	shop_service = ShopService.new(seed_value)
	reward_service = RewardService.new(seed_value)
	combat_resolver = CombatResolver.new(seed_value)
	current_run.materials = maxi(0, starting_materials)
	player = null
	equipped_weapons.clear()
	materials_changed.emit(current_run.materials)
	run_phase_changed.emit(current_run.phase)
	return current_run


func begin_selected_run(seed_value: int = 0) -> bool:
	if main_player_selected == null or main_weapon_selected == null:
		return false
	begin_run(seed_value, main_player_selected, STARTING_MATERIALS)
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
	return slot >= 0


func end_run() -> void:
	current_run = null
	run_director = null
	shop_service = null
	reward_service = null
	combat_resolver = null
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


func is_combat_active() -> bool:
	return current_run != null and current_run.phase == RunPhase.COMBAT


func add_materials(amount: int) -> void:
	if amount <= 0:
		return
	_ensure_run()
	current_run.materials += amount
	materials_changed.emit(current_run.materials)


func try_spend_materials(amount: int) -> bool:
	if amount < 0:
		return false
	_ensure_run()
	if current_run.materials < amount:
		return false
	current_run.materials -= amount
	materials_changed.emit(current_run.materials)
	return true


func try_purchase_item(item: ItemBase) -> int:
	if item == null:
		return InventoryService.INVALID_REQUEST
	_ensure_run()
	if shop_service == null:
		shop_service = ShopService.new(current_run.random_seed)
	var result := shop_service.try_purchase(current_run, item, Content.catalog)
	if result == InventoryService.OK:
		materials_changed.emit(current_run.materials)
	return result


func try_combine_weapon(weapon: ItemWeapon) -> int:
	if current_run == null or weapon == null:
		return InventoryService.INVALID_REQUEST
	if shop_service == null:
		shop_service = ShopService.new(current_run.random_seed)
	return shop_service.try_combine_item(current_run, weapon, Content.catalog)


func try_sell_weapon(weapon: ItemWeapon) -> int:
	if current_run == null or weapon == null:
		return InventoryService.INVALID_REQUEST
	if shop_service == null:
		shop_service = ShopService.new(current_run.random_seed)
	var result := shop_service.try_sell_item(current_run, weapon, Content.catalog)
	if result == InventoryService.OK:
		materials_changed.emit(current_run.materials)
	return result


func apply_stat_change(unit_property: String, amount: float) -> bool:
	if current_run == null:
		return false
	var stat_id: int = TUTORIAL_STATS_ADAPTER.stat_id_for_property(unit_property)
	if not StatId.is_valid(stat_id) or not current_run.player_stats.add_stat(stat_id, amount):
		push_warning("Unsupported tutorial stat '%s'; migration mapping is required." % unit_property)
		return false
	if is_instance_valid(player) and player.stats != null:
		TUTORIAL_STATS_ADAPTER.apply_stat_to_unit(current_run.player_stats, player.stats, stat_id)
	return true


func apply_passive_item(item: ItemPassive) -> bool:
	if current_run == null or item == null:
		return false
	var definition := Content.catalog.get_passive_definition_for_item(item)
	if definition == null or definition.stat_modifiers.is_empty():
		item.apply_passive()
		return true
	var applied := false
	for stat_key: Variant in definition.stat_modifiers:
		var stat_id := StatId.from_key(str(stat_key))
		if not StatId.is_valid(stat_id):
			push_warning("Unsupported passive stat '%s'." % stat_key)
			continue
		var amount := float(definition.stat_modifiers[stat_key])
		current_run.player_stats.add_stat(stat_id, amount)
		_sync_runtime_stat(stat_id)
		applied = true
	return applied


func apply_upgrade_item(item: ItemUpgrade) -> bool:
	if current_run == null or item == null:
		return false
	var definition := Content.catalog.get_upgrade_definition_for_item(item)
	if definition == null or not StatId.is_valid(definition.stat_id):
		item.apply_upgrade()
		return true
	current_run.player_stats.add_stat(definition.stat_id, definition.value)
	_sync_runtime_stat(definition.stat_id)
	return true


func _sync_runtime_stat(stat_id: int) -> void:
	if is_instance_valid(player) and player.stats != null:
		TUTORIAL_STATS_ADAPTER.apply_stat_to_unit(current_run.player_stats, player.stats, stat_id)


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
	add_materials(combat_resolver.harvesting_materials(current_run.player_stats))


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
		combat_resolver = CombatResolver.new(current_run.random_seed)

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


func select_items_for_offer(item_pool: Array, current_wave: int, config: Dictionary) -> Array:
	_ensure_run()
	if shop_service == null:
		shop_service = ShopService.new(current_run.random_seed)
	return shop_service.select_offers(
		item_pool, current_wave, get_stat_value("luck"), config, 4
	)
