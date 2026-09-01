class_name ShopRuntimeService
extends RefCounted

const GogoWeaponInventory := preload("res://game/session/weapon_inventory.gd")
const GogoWeaponQualityRules := preload("res://game/gameplay/weapons/weapon_quality_rules.gd")
signal offers_changed(offers: Array[GogoContentDefinition])

var item_pool := ItemPoolService.new()
var build_service := PlayerBuildService.new()
var offers: Array[GogoContentDefinition] = []
var last_failure_reason := ""


func open_shop(session: GameSession, count: int = 4) -> Array[GogoContentDefinition]:
	var state := session.run_state
	if state.phase != &"shop":
		# A shop scene is only valid between waves. Refusing to initialize from
		# another phase keeps those calls from consuming this wave's canonical
		# shop identity or acting as a free quote reroll.
		return offers
	if _has_current_wave_cache(state):
		offers = _restore_cached_offers(session)
		return offers
	var created := _generate_offers(session, count)
	_apply_first_shop_weapon_guarantee(session, created)
	offers = created
	_store_canonical_offers(state, offers)
	# Store the canonical result before publication: listeners may synchronously
	# reopen the shop, but a cache hit deliberately emits nothing.
	offers_changed.emit(offers)
	return offers


func _generate_offers(session: GameSession, count: int) -> Array[GogoContentDefinition]:
	var state := session.run_state
	var player := state.player()
	var locked: Array[GogoContentDefinition] = []
	var valid_locked_ids: Array[StringName] = []
	for id in state.locked_shop_offer_ids:
		if valid_locked_ids.has(id) or locked.size() >= count:
			continue
		var definition := _shop_definition_by_id(session.content_snapshot, id)
		if (
			definition == null
			or _item_is_at_max_count(player, definition)
			or not _definition_is_available(session, player, definition)
		):
			continue
		valid_locked_ids.append(id)
		locked.append(definition)
	# The run-state IDs are canonical. Compact stale/corrupt entries while rebuilding
	# offers so a newly constructed service can restore locks without old object refs.
	state.locked_shop_offer_ids = valid_locked_ids
	var generated := item_pool.generate_shop_offers(
		session.content_snapshot,
		player,
		state.current_wave,
		maxi(count - locked.size(), 0),
		session.rng,
		state.locked_shop_offer_ids
	)
	offers = locked
	for definition in generated:
		if offers.size() < count:
			offers.append(definition)
	while offers.size() < count:
		offers.append(null)
	return offers


func _has_current_wave_cache(state: GogoRunState) -> bool:
	return (
		state != null
		and state.shop_offer_initialized
		and state.shop_offer_wave == state.current_wave
	)


func _restore_cached_offers(session: GameSession) -> Array[GogoContentDefinition]:
	var state := session.run_state
	var player := state.player()
	var restored: Array[GogoContentDefinition] = []
	var normalized_ids: Array[StringName] = []
	var valid_locked_ids: Array[StringName] = []
	for content_id in state.shop_offer_ids:
		var definition := _shop_definition_by_id(session.content_snapshot, content_id)
		if (
			content_id.is_empty()
			or definition == null
			or _item_is_at_max_count(player, definition)
			or not _definition_is_available(session, player, definition)
		):
			restored.append(null)
			normalized_ids.append(&"")
			continue
		restored.append(definition)
		normalized_ids.append(definition.content_id)
		if state.locked_shop_offer_ids.has(definition.content_id):
			valid_locked_ids.append(definition.content_id)
	state.shop_offer_ids = normalized_ids
	state.locked_shop_offer_ids = valid_locked_ids
	return restored


func _store_canonical_offers(state: GogoRunState, next_offers: Array[GogoContentDefinition]) -> void:
	state.shop_offer_wave = state.current_wave
	state.shop_offer_initialized = true
	state.shop_offer_initialization_id += 1
	state.shop_offer_ids.clear()
	for definition in next_offers:
		state.shop_offer_ids.append(definition.content_id if definition != null else &"")


func _apply_first_shop_weapon_guarantee(
	session: GameSession,
	next_offers: Array[GogoContentDefinition]
) -> void:
	var state := session.run_state
	var player := state.player()
	if (
		state.phase != &"shop"
		or state.current_wave < 1
		or state.current_wave > 3
		or player.weapon_ids.size() >= 6
	):
		return
	if _has_affordable_weapon_offer(session, next_offers):
		return
	var target_slot := _first_unlocked_slot(state, next_offers)
	if target_slot < 0:
		return
	var candidates := _affordable_weapon_candidates(session, next_offers)
	if candidates.is_empty():
		return
	# This is the sole additional random draw and only happens on the real
	# missing-affordable-weapon branch.
	next_offers[target_slot] = candidates[session.rng.randi_range(0, candidates.size() - 1)]


func _has_affordable_weapon_offer(
	session: GameSession,
	next_offers: Array[GogoContentDefinition]
) -> bool:
	for definition in next_offers:
		if _is_current_wave_affordable_weapon(session, definition):
			return true
	return false


func _is_current_wave_affordable_weapon(
	session: GameSession,
	definition: GogoContentDefinition
) -> bool:
	if not definition is GogoWeaponDefinition:
		return false
	var state := session.run_state
	return (
		float(ItemPoolService.rarity_weights_for_wave(state.current_wave).get(
			(definition as GogoWeaponDefinition).tier, 0.0
		)) > 0.0
		and _definition_is_available(session, state.player(), definition)
		and item_pool.price_for(definition, state.current_wave, state.reroll_count)
			<= state.player().materials
	)


func _first_unlocked_slot(state: GogoRunState, next_offers: Array[GogoContentDefinition]) -> int:
	for index in next_offers.size():
		var definition := next_offers[index]
		if definition == null or not state.locked_shop_offer_ids.has(definition.content_id):
			return index
	return -1


func _affordable_weapon_candidates(
	session: GameSession,
	next_offers: Array[GogoContentDefinition]
) -> Array[GogoWeaponDefinition]:
	var state := session.run_state
	var offered_locked_ids: Array[StringName] = state.locked_shop_offer_ids.duplicate()
	for definition in next_offers:
		if definition != null and state.locked_shop_offer_ids.has(definition.content_id):
			if not offered_locked_ids.has(definition.content_id):
				offered_locked_ids.append(definition.content_id)
	var candidates: Array[GogoWeaponDefinition] = []
	for raw_definition in session.content_snapshot.all(&"weapon"):
		var weapon := raw_definition as GogoWeaponDefinition
		if (
			weapon == null
			or offered_locked_ids.has(weapon.content_id)
			or not _is_current_wave_affordable_weapon(session, weapon)
		):
			continue
		candidates.append(weapon)
	candidates.sort_custom(func(a: GogoWeaponDefinition, b: GogoWeaponDefinition) -> bool:
		return String(a.content_id) < String(b.content_id)
	)
	return candidates


static func _shop_definition_by_id(
	snapshot: ContentSnapshot,
	content_id: StringName
) -> GogoContentDefinition:
	if snapshot == null or content_id.is_empty():
		return null
	var item := snapshot.definition(content_id, &"item")
	if item != null:
		return item
	return snapshot.definition(content_id, &"weapon")


func toggle_lock(session: GameSession, offer_index: int) -> bool:
	if offer_index < 0 or offer_index >= offers.size():
		return false
	var definition := offers[offer_index]
	if definition == null:
		return false
	var id := definition.content_id
	if session.run_state.locked_shop_offer_ids.has(id):
		session.run_state.locked_shop_offer_ids.erase(id)
		return false
	session.run_state.locked_shop_offer_ids.append(id)
	return true


func reroll(session: GameSession) -> Error:
	var player := _action_player(session)
	if player == null:
		return ERR_UNAVAILABLE
	var state := session.run_state
	var canonical_offers := offers
	if canonical_offers.is_empty() and _has_current_wave_cache(state):
		canonical_offers = _cached_offers_without_normalization(session)
	if _all_offers_locked(session, canonical_offers):
		last_failure_reason = "all_offers_locked"
		return ERR_UNAVAILABLE
	var price := item_pool.reroll_price(state.current_wave, state.reroll_count)
	if not player.try_spend(price):
		last_failure_reason = "insufficient_materials"
		return ERR_UNAUTHORIZED
	state.reroll_count += 1
	offers = _generate_offers(session, _canonical_slot_count(state, canonical_offers))
	_store_canonical_offers(state, offers)
	offers_changed.emit(offers)
	last_failure_reason = ""
	return OK


func _cached_offers_without_normalization(session: GameSession) -> Array[GogoContentDefinition]:
	var result: Array[GogoContentDefinition] = []
	for content_id in session.run_state.shop_offer_ids:
		result.append(_shop_definition_by_id(session.content_snapshot, content_id))
	return result


func _canonical_slot_count(state: GogoRunState, current_offers: Array[GogoContentDefinition]) -> int:
	if _has_current_wave_cache(state):
		return state.shop_offer_ids.size()
	return current_offers.size() if not current_offers.is_empty() else 4


func _all_offers_locked(
	session: GameSession,
	current_offers: Array[GogoContentDefinition]
) -> bool:
	if session == null or current_offers.is_empty():
		return false
	for definition: GogoContentDefinition in current_offers:
		if (
			definition == null
			or not session.run_state.locked_shop_offer_ids.has(definition.content_id)
		):
			return false
	return true


func buy(session: GameSession, offer_index: int) -> Error:
	var player := _action_player(session)
	if player == null:
		return ERR_UNAVAILABLE
	if offer_index < 0 or offer_index >= offers.size():
		last_failure_reason = "invalid_offer"
		return ERR_INVALID_PARAMETER
	var definition := offers[offer_index]
	if definition == null:
		last_failure_reason = "invalid_offer"
		return ERR_INVALID_PARAMETER
	var price := item_pool.price_for(definition, session.run_state.current_wave, session.run_state.reroll_count)
	if definition is GogoWeaponDefinition and player.weapon_ids.size() >= 6:
		last_failure_reason = "weapon_slots_full"
		return ERR_OUT_OF_MEMORY
	if _item_is_at_max_count(player, definition):
		last_failure_reason = "item_limit_reached"
		return ERR_OUT_OF_MEMORY
	if not _definition_is_available(session, player, definition):
		last_failure_reason = "unavailable_content"
		return ERR_INVALID_DATA
	if not (definition is GogoItemDefinition or definition is GogoWeaponDefinition):
		last_failure_reason = "invalid_offer"
		return ERR_INVALID_DATA
	if not session.content_snapshot.has_definition(definition.content_id, definition.kind):
		last_failure_reason = "unavailable_content"
		return ERR_INVALID_DATA
	if definition is GogoWeaponDefinition:
		var allocation_error := player.weapon_inventory.validate_add(definition.content_id, session.content_snapshot)
		if allocation_error != OK:
			last_failure_reason = "inventory_id_exhausted"
			return allocation_error
	if price < 0 or player.materials < price:
		last_failure_reason = "insufficient_materials"
		return ERR_UNAUTHORIZED
	var item_candidate: SessionPlayerState
	if definition is GogoItemDefinition:
		item_candidate = player.duplicate_state()
		var build_error := build_service.apply_item(session, item_candidate, definition.content_id)
		if build_error != OK:
			last_failure_reason = "unavailable_content"
			return build_error
	elif definition is GogoWeaponDefinition:
		var allocation := player.weapon_inventory.add_weapon(definition.content_id, session.content_snapshot)
		if allocation.error != OK:
			last_failure_reason = "inventory_id_exhausted"
			return allocation.error
	player.materials -= price
	if item_candidate != null:
		player.item_ids = item_candidate.item_ids
		player.base_stats = item_candidate.base_stats
		player.final_stats = item_candidate.final_stats
		player.max_health = item_candidate.max_health
		player.current_health = item_candidate.current_health
	session.run_state.locked_shop_offer_ids.erase(definition.content_id)
	# Keep four stable visual slots. A purchase clears only its authored position;
	# later cards never slide left and the empty footprint has no UI descendants.
	offers[offer_index] = null
	if (
		_has_current_wave_cache(session.run_state)
		and offer_index < session.run_state.shop_offer_ids.size()
	):
		session.run_state.shop_offer_ids[offer_index] = &""
	session.state_changed.emit()
	offers_changed.emit(offers)
	last_failure_reason = ""
	return OK


static func _item_is_at_max_count(
	player: SessionPlayerState,
	definition: GogoContentDefinition
) -> bool:
	return (
		definition is GogoItemDefinition
		and player.item_ids.count(definition.content_id)
			>= (definition as GogoItemDefinition).max_count
	)


static func _definition_is_available(
	session: GameSession,
	player: SessionPlayerState,
	definition: GogoContentDefinition
) -> bool:
	if session == null or session.content_snapshot == null or player == null:
		return false
	if definition is GogoItemDefinition:
		return (definition as GogoItemDefinition).is_shop_offerable_to(player.character_id)
	if definition is GogoWeaponDefinition:
		var character := session.content_snapshot.definition(
			player.character_id, &"character"
		) as CharacterDefinition
		return character != null and character.allows_weapon(
			definition as GogoWeaponDefinition
		)
	return false


func sell_weapon(session: GameSession, inventory_instance_id: int) -> Error:
	var player := _action_player(session)
	if player == null: return ERR_UNAVAILABLE
	var record := player.weapon_inventory.record(inventory_instance_id)
	if record.is_empty():
		last_failure_reason = "invalid_weapon_instance"
		return ERR_INVALID_PARAMETER
	var definition := session.content_snapshot.definition(record.content_id, &"weapon") as GogoWeaponDefinition
	if definition == null:
		last_failure_reason = "unavailable_content"
		return ERR_INVALID_DATA
	var price := GogoWeaponQualityRules.sale_price(definition.price, record.quality)
	if player.materials > 9223372036854775807 - price:
		last_failure_reason = "sale_credit_overflow"
		return ERR_UNAVAILABLE
	var error := player.weapon_inventory.remove_weapon(inventory_instance_id)
	if error != OK: return error
	player.add_materials(price)
	last_failure_reason = ""
	session.state_changed.emit()
	return OK


func combine_weapon(session: GameSession, inventory_instance_id: int) -> Error:
	var player := _action_player(session)
	if player == null: return ERR_UNAVAILABLE
	if player.weapon_inventory.combination_partner(inventory_instance_id) == 0:
		last_failure_reason = "no_matching_weapon"
		return ERR_UNAVAILABLE
	var error := player.weapon_inventory.combine_weapon(inventory_instance_id)
	if error != OK: return error
	last_failure_reason = ""
	session.state_changed.emit()
	return OK


func _action_player(session: GameSession) -> SessionPlayerState:
	if session == null or session.run_state == null or session.content_snapshot == null:
		last_failure_reason = "unavailable_session"
		return null
	var state := session.run_state
	var player := state.player()
	if state.phase != &"shop" or state.ended or player == null or player.weapon_inventory == null:
		last_failure_reason = "unavailable_session"
		return null
	if not session.content_snapshot.has_definition(player.character_id, &"character"):
		last_failure_reason = "unavailable_content"
		return null
	var inventory_check := GogoWeaponInventory.parse_records(player.weapon_inventory.records(), player.next_weapon_instance_id, session.content_snapshot)
	if inventory_check.error != OK:
		last_failure_reason = "unavailable_content"
		return null
	return player
