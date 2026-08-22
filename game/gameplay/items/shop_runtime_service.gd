class_name ShopRuntimeService
extends RefCounted

signal offers_changed(offers: Array[GogoContentDefinition])

var item_pool := ItemPoolService.new()
var build_service := PlayerBuildService.new()
var offers: Array[GogoContentDefinition] = []


func open_shop(session: GameSession, count: int = 4) -> Array[GogoContentDefinition]:
	var state := session.run_state
	var player := state.player()
	var locked: Array[GogoContentDefinition] = []
	for id in state.locked_shop_offer_ids:
		for previous in offers:
			if previous.content_id == id:
				locked.append(previous)
	var generated := item_pool.generate_shop_offers(session.content_snapshot, player, state.current_wave, maxi(count - locked.size(), 0), session.rng)
	offers = locked
	for definition in generated:
		if offers.size() < count:
			offers.append(definition)
	offers_changed.emit(offers)
	return offers


func toggle_lock(session: GameSession, offer_index: int) -> bool:
	if offer_index < 0 or offer_index >= offers.size():
		return false
	var id := offers[offer_index].content_id
	if session.run_state.locked_shop_offer_ids.has(id):
		session.run_state.locked_shop_offer_ids.erase(id)
		return false
	session.run_state.locked_shop_offer_ids.append(id)
	return true


func reroll(session: GameSession) -> Error:
	var player := session.run_state.player()
	var price := item_pool.reroll_price(session.run_state.current_wave, session.run_state.reroll_count)
	if not player.try_spend(price):
		return ERR_UNAUTHORIZED
	session.run_state.reroll_count += 1
	open_shop(session)
	return OK


func buy(session: GameSession, offer_index: int) -> Error:
	if offer_index < 0 or offer_index >= offers.size():
		return ERR_INVALID_PARAMETER
	var definition := offers[offer_index]
	var player := session.run_state.player()
	var price := item_pool.price_for(definition, session.run_state.current_wave, session.run_state.reroll_count)
	if definition is GogoWeaponDefinition and player.weapon_ids.size() >= 6:
		return ERR_OUT_OF_MEMORY
	if not player.try_spend(price):
		return ERR_UNAUTHORIZED
	if definition is GogoItemDefinition:
		build_service.apply_item(session, player, definition.content_id)
	elif definition is GogoWeaponDefinition:
		player.weapon_ids.append(definition.content_id)
		if not player.weapon_levels.has(String(definition.content_id)):
			player.weapon_levels[String(definition.content_id)] = 1
	else:
		return ERR_INVALID_DATA
	session.run_state.locked_shop_offer_ids.erase(definition.content_id)
	offers.remove_at(offer_index)
	session.state_changed.emit()
	offers_changed.emit(offers)
	return OK


func sell_weapon(session: GameSession, slot: int) -> Error:
	var player := session.run_state.player()
	if slot < 0 or slot >= player.weapon_ids.size():
		return ERR_INVALID_PARAMETER
	var definition := session.content_snapshot.definition(player.weapon_ids[slot], &"weapon") as GogoWeaponDefinition
	player.weapon_ids.remove_at(slot)
	player.add_materials(maxi(1, int(round(float(definition.price) * 0.35))))
	session.state_changed.emit()
	return OK


func combine_weapon(session: GameSession, content_id: StringName) -> Error:
	var player := session.run_state.player()
	if player.weapon_ids.count(content_id) < 2:
		return ERR_UNAVAILABLE
	var removed := false
	for index in range(player.weapon_ids.size() - 1, -1, -1):
		if player.weapon_ids[index] == content_id:
			if removed:
				player.weapon_ids.remove_at(index)
				break
			removed = true
	var key := String(content_id)
	player.weapon_levels[key] = mini(int(player.weapon_levels.get(key, 1)) + 1, 4)
	session.state_changed.emit()
	return OK
