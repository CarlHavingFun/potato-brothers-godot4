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
	player = null
	equipped_weapons.clear()
	main_player_selected = null
	main_weapon_selected = null
	main_character_selected = null
	main_weapon_definition_selected = null


func enter_phase(next_phase: int) -> bool:
	if current_run == null or not RunPhase.is_valid(next_phase):
		return false
	if current_run.phase == next_phase:
		return true
	if not current_run.try_transition(next_phase):
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
	var result := InventoryService.INVALID_REQUEST
	if item is ItemWeapon:
		var weapon := item as ItemWeapon
		result = InventoryService.try_purchase_weapon(
			current_run,
			Content.catalog.get_item_stable_id(weapon),
			int(weapon.item_tier) + 1,
			weapon.item_cost
		)
	elif item is ItemPassive:
		var passive := item as ItemPassive
		result = InventoryService.try_purchase_passive(
			current_run,
			Content.catalog.get_item_stable_id(passive),
			passive.item_cost,
			passive.max_stack
		)
	if result == InventoryService.OK:
		materials_changed.emit(current_run.materials)
	return result


func try_combine_weapon(weapon: ItemWeapon) -> int:
	if current_run == null or weapon == null:
		return InventoryService.INVALID_REQUEST
	var slots := current_run.inventory.find_weapon_slots(
		Content.catalog.get_item_stable_id(weapon),
		int(weapon.item_tier) + 1
	)
	if slots.size() < 2:
		return InventoryService.WEAPONS_NOT_COMBINABLE
	return InventoryService.try_combine_weapons(current_run, slots[0], slots[1])


func try_sell_weapon(weapon: ItemWeapon) -> int:
	if current_run == null or weapon == null:
		return InventoryService.INVALID_REQUEST
	var slots := current_run.inventory.find_weapon_slots(
		Content.catalog.get_item_stable_id(weapon),
		int(weapon.item_tier) + 1
	)
	if slots.is_empty():
		return InventoryService.INVALID_WEAPON_SLOT
	var result := InventoryService.try_sell_weapon(current_run, slots[0])
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


func get_stat_value(unit_property: String) -> float:
	if current_run == null:
		return 0.0
	var stat_id: int = TUTORIAL_STATS_ADAPTER.stat_id_for_property(unit_property)
	return current_run.player_stats.get_stat(stat_id)


func _ensure_run() -> void:
	if current_run == null:
		begin_run(0, null, 0)

func get_harvesting_coins() -> void:
	add_materials(roundi(get_stat_value("harvesting")))


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
	var random := randf_range(0, 1.0)
	if random < chance:
		return true
	return false

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
	var common_chance := 0.0
	var rare_chance := 0.0
	var epic_chance := 0.0
	var legendary_chance := 0.0
	
	# RARE: Starts increasing from wave 2 (0% at wave 1)
	if current_wave >= config.rare.start_wave:
		rare_chance = min(1.0, (current_wave - 1) * config.rare.base_multi)
	
	# EPIC: Starts increasing from wave 4 (0% at wave 3)
	if current_wave >= config.epic.start_wave:
		epic_chance = min(1.0, (current_wave - 3) * config.epic.base_multi)
	
	# LEGENDARY: Starts increasing from wave 7 (0% at wave 6)
	if current_wave >= config.legendary.start_wave:
		legendary_chance = min(1.0, (current_wave - 6) * config.legendary.base_multi)
	
	# Player luck increases the chance of finding higher tiers.
	# Example: 10 luck = 10% chance = 1.1 multi
	var luck := get_stat_value("luck")
	var luck_factor := 1.0 + (luck / 100.0)
	rare_chance *= luck_factor
	epic_chance *= luck_factor
	legendary_chance *= luck_factor
	
	# Normalize probabilities
	var total_non_common_chances := rare_chance + epic_chance + legendary_chance
	if total_non_common_chances > 1.0:
		var scale_down := 1.0 / total_non_common_chances
		rare_chance *= scale_down
		epic_chance *= scale_down
		legendary_chance *= scale_down
		total_non_common_chances = 1.0
	
	# Common takes the remaining probability
	common_chance = 1.0 - total_non_common_chances
	
	# Debug print
	print("Wave: %d, Luck: %.1f => Chances: C:%.2f R:%.2f E:%.2f L:%.2f" % 
	[current_wave, luck, common_chance, rare_chance, epic_chance, legendary_chance])
	
	return [
		max(0.0, common_chance),
		max(0.0, rare_chance),
		max(0.0, epic_chance),
		max(0.0, legendary_chance),
	]


func select_items_for_offer(item_pool: Array, current_wave: int, config: Dictionary) -> Array:
	
	# [ 0.7 , 0.2 , 0.08 , 0.02 ]  
	var tier_chances := calculate_tier_probability(current_wave, config)
	
	var legendary_limit = tier_chances[3]
	var epic_limit = legendary_limit + tier_chances[2]
	var rare_limit = epic_limit + tier_chances[1]
	
	var offered_items: Array = []
	while offered_items.size() < 4:
		var roll := randf()
		var chosen_tier_index := 0
		if roll < legendary_limit:
			chosen_tier_index = 3 # Legendary
		elif roll < epic_limit:
			chosen_tier_index = 2 # Epic
		elif roll < rare_limit:
			chosen_tier_index = 1 # Rare
		
		var potential_items: Array = []
		var current_search_tier_index := chosen_tier_index
		
		while potential_items.is_empty() and current_search_tier_index >= 0:
			potential_items = item_pool.filter(func(item: ItemBase): return item.item_tier == current_search_tier_index)
			
			if potential_items.is_empty():
				current_search_tier_index -= 1
			else:
				break
		
		if not potential_items.is_empty():
			var selected_item = potential_items.pick_random()
			
			if not offered_items.has(selected_item):
				offered_items.append(selected_item)
	
	return offered_items
