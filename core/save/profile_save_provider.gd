class_name ProfileSaveProvider
extends SaveProvider


var store: ProfileStore
var active_profile_id: int = 1


func _init(profile_store: ProfileStore = null, initial_profile_id: int = 0) -> void:
	store = profile_store if profile_store != null else ProfileStore.new()
	active_profile_id = (
		initial_profile_id
		if initial_profile_id in range(1, ProfileStore.MAX_PROFILES + 1)
		else store.load_active_profile_id()
	)


func load_slot() -> Dictionary:
	return store.load_profile(active_profile_id) if store != null else {}


func save_slot(payload: Variant) -> Error:
	if store == null:
		return ERR_UNAVAILABLE
	if not payload is Dictionary:
		return ERR_INVALID_DATA
	return store.save_profile(active_profile_id, payload)


func is_available() -> bool:
	return store != null


func set_active_profile(profile_id: int) -> bool:
	if profile_id not in range(1, ProfileStore.MAX_PROFILES + 1):
		return false
	if profile_id == active_profile_id:
		return true
	if store == null or store.save_active_profile_id(profile_id) != OK:
		return false
	active_profile_id = profile_id
	return true


func summaries() -> Array[Dictionary]:
	return store.list_profiles() if store != null else []


func migrate_legacy() -> bool:
	return store != null and store.migrate_legacy_to_slot_one()
