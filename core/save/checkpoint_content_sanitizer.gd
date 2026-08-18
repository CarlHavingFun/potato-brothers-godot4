class_name CheckpointContentSanitizer
extends RefCounted


const NOTICE_CHARACTER := &"ui.profile.repair.checkpoint_character"
const NOTICE_STARTER := &"ui.profile.repair.checkpoint_starter"
const NOTICE_INVENTORY := &"ui.profile.repair.checkpoint_inventory"
const NOTICE_SHOP := &"ui.profile.repair.checkpoint_shop"
const NOTICE_UNAVAILABLE := &"ui.profile.repair.checkpoint_unavailable"

var repair_notice_keys: Array[StringName] = []


## Returns an owned, repaired copy. Valid checkpoint fields are copied without
## normalization so a content-pack update cannot silently change a live build.
## A null result means the active catalog has no usable character or weapon to
## provide the minimum runtime scene contract.
func sanitize(checkpoint: RunState, catalog: ContentCatalog) -> RunState:
	repair_notice_keys.clear()
	if checkpoint == null or catalog == null:
		_notice(NOTICE_UNAVAILABLE)
		return null

	var repaired := RunState.from_dict(checkpoint.to_dict())
	var character := catalog.get_character(repaired.character_id)
	if not _is_usable_character(character):
		character = _fallback_character(catalog)
		if character == null:
			_notice(NOTICE_UNAVAILABLE)
			return null
		repaired.character_id = character.get_stable_id(catalog.pack_id)
		_notice(NOTICE_CHARACTER)

	var inventory_result := _sanitize_inventory(repaired.inventory, catalog)
	repaired.inventory = inventory_result.get("inventory") as InventoryState
	if bool(inventory_result.get("changed", false)):
		_notice(NOTICE_INVENTORY)

	var starter := catalog.get_weapon(repaired.starting_weapon_id)
	if not _is_usable_weapon(starter):
		starter = _fallback_weapon(repaired.inventory, character, catalog)
		if starter == null:
			_notice(NOTICE_UNAVAILABLE)
			return null
		repaired.starting_weapon_id = starter.get_stable_id(catalog.pack_id)
		_notice(NOTICE_STARTER)

	# Only replace weapons when deleted/invalid entries left the build empty.
	# A deliberately weaponless checkpoint remains weaponless.
	if (
		bool(inventory_result.get("removed_weapon", false))
		and repaired.inventory.weapon_count() == 0
	):
		repaired.inventory.add_weapon(
			starter.get_stable_id(catalog.pack_id),
			1,
			starter.tiers[0].item_cost
		)

	if _sanitize_shop_slots(repaired, catalog):
		_notice(NOTICE_SHOP)
	return repaired


func _sanitize_inventory(inventory: InventoryState, catalog: ContentCatalog) -> Dictionary:
	var source := inventory if inventory != null else InventoryState.new()
	var source_data := source.to_dict()
	var sanitized := InventoryState.new()
	sanitized.weapon_slot_limit = clampi(
		int(source_data.get("weapon_slot_limit", InventoryState.MAX_WEAPON_SLOTS)),
		1,
		InventoryState.MAX_WEAPON_SLOTS
	)
	var changed := inventory == null
	var removed_weapon := false
	var raw_weapons: Variant = source_data.get("weapons", [])
	if raw_weapons is Array:
		for raw_entry: Variant in raw_weapons:
			if not raw_entry is Dictionary:
				changed = true
				removed_weapon = true
				continue
			var entry := raw_entry as Dictionary
			var weapon_id := StringName(str(entry.get("weapon_id", "")))
			var tier := int(entry.get("tier", 0))
			var definition := catalog.get_weapon(weapon_id)
			if definition == null or catalog.get_weapon_tier(weapon_id, tier) == null:
				changed = true
				removed_weapon = true
				continue
			sanitized.add_weapon(
				# Keep an already-valid serialized ID exactly as stored. Content ID
				# canonicalization belongs to version migration, not resume repair.
				weapon_id,
				tier,
				int(entry.get("paid_price", 0))
			)

	var raw_passives: Variant = source_data.get("passives", {})
	if raw_passives is Dictionary:
		for raw_id: Variant in raw_passives:
			var passive := catalog.get_passive(StringName(str(raw_id)))
			if passive == null or passive.item == null:
				changed = true
				continue
			sanitized.add_passive(StringName(str(raw_id)), maxi(1, int(raw_passives[raw_id])))
	return {
		"inventory": sanitized,
		"changed": changed,
		"removed_weapon": removed_weapon,
	}


func _sanitize_shop_slots(run_state: RunState, catalog: ContentCatalog) -> bool:
	var changed := false
	for slot: ShopSlotState in run_state.shop_slots:
		if slot.offer_id.is_empty():
			# An empty locked slot cannot be populated by load_shop or a reroll.
			if slot.locked:
				slot.clear_offer(false)
				changed = true
			continue
		if _is_valid_shop_offer(slot, catalog):
			continue
		# Reset purchased as well as locked: the missing offer is no longer a
		# meaningful consumed slot and should be eligible for deterministic fill.
		slot.clear_offer(false)
		changed = true
	if changed:
		_sync_legacy_shop_fields(run_state)
	return changed


func _is_valid_shop_offer(slot: ShopSlotState, catalog: ContentCatalog) -> bool:
	match slot.item_type:
		ItemBase.ItemType.WEAPON:
			return catalog.get_weapon_tier(slot.offer_id, slot.tier) != null
		ItemBase.ItemType.PASSIVE:
			var passive := catalog.get_passive(slot.offer_id)
			return passive != null and passive.item != null
	return false


func _sync_legacy_shop_fields(run_state: RunState) -> void:
	run_state.shop_offer_ids.clear()
	var occupied := 0
	var locked := 0
	for slot: ShopSlotState in run_state.shop_slots:
		if slot.is_empty():
			continue
		occupied += 1
		if slot.locked:
			locked += 1
		run_state.shop_offer_ids.append({
			"id": String(slot.offer_id),
			"tier": slot.tier,
			"type": slot.item_type,
		})
	run_state.shop_locked = occupied > 0 and locked == occupied


func _fallback_character(catalog: ContentCatalog) -> CharacterDef:
	var preferred := catalog.get_character(&"character/well_rounded")
	if _is_usable_character(preferred):
		return preferred
	for candidate: CharacterDef in catalog.get_characters():
		if _is_usable_character(candidate):
			return candidate
	return null


func _fallback_weapon(
	inventory: InventoryState,
	character: CharacterDef,
	catalog: ContentCatalog
) -> WeaponDef:
	# Prefer a surviving equipped family so repairing metadata does not alter the
	# build. Then use the replacement character's declared starter list.
	if inventory != null:
		for entry: Dictionary in inventory.to_dict().get("weapons", []):
			var owned := catalog.get_weapon(StringName(str(entry.get("weapon_id", ""))))
			if _is_usable_weapon(owned):
				return owned
	if character != null:
		for starter_id: StringName in character.starter_weapon_ids:
			var declared := catalog.get_weapon(starter_id)
			if _is_usable_weapon(declared):
				return declared
	for candidate: WeaponDef in catalog.get_weapons():
		if (
			_is_usable_weapon(candidate)
			and (character.rules == null or character.rules.allows_weapon(candidate.tags))
		):
			return candidate
	for candidate: WeaponDef in catalog.get_weapons():
		if _is_usable_weapon(candidate):
			return candidate
	return null


func _is_usable_character(definition: CharacterDef) -> bool:
	return definition != null and definition.stats != null and definition.scene != null


func _is_usable_weapon(definition: WeaponDef) -> bool:
	return (
		definition != null
		and not definition.tiers.is_empty()
		and definition.tiers[0] != null
	)


func _notice(key: StringName) -> void:
	if key not in repair_notice_keys:
		repair_notice_keys.append(key)
