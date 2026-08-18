class_name BalanceProfileRegistry
extends RefCounted


const ACTIVE_PROFILE_SETTING := "balance/active_profile"
const DEFAULT_PROFILE_ID := "baseline_parity_1_1_15_4"
const REFERENCE_WEAPON_BASELINE := preload(
	"res://core/balance/data/reference_weapon_baseline.gd"
)
const REFERENCE_PASSIVE_BASELINE := preload(
	"res://core/balance/data/reference_passive_baseline.gd"
)
const REFERENCE_ENEMY_BASELINE := preload(
	"res://core/balance/data/reference_enemy_baseline.gd"
)
const PROFILE_PATHS := {
	DEFAULT_PROFILE_ID: "res://core/balance/profiles/baseline_parity_1_1_15_4.tres",
}


static func active_profile_id() -> String:
	return str(ProjectSettings.get_setting(ACTIVE_PROFILE_SETTING, DEFAULT_PROFILE_ID))


static func load_active(pack: ContentPackDef = null) -> BalancePackDef:
	var profile_id := active_profile_id()
	var path := str(PROFILE_PATHS.get(profile_id, ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	# Script class names are not native ResourceLoader type hints in an exported
	# runtime. Load first, then validate the attached script type below.
	var source := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
	if not source is BalancePackDef:
		return null
	var result := (source as BalancePackDef).duplicate(true) as BalancePackDef
	if result.stat_rules == null:
		result.stat_rules = StatRulesDef.baseline()
	if pack != null:
		result.bind_content(pack)
		# The profile owns the formulas while these neutral-ID tables own the
		# temporary base values. Keeping the overlay here makes a later product
		# balance swap independent from scenes and presentation packs.
		result.merge_weapon_values(REFERENCE_WEAPON_BASELINE.values())
		result.merge_passive_values(REFERENCE_PASSIVE_BASELINE.values())
		result.merge_enemy_values(REFERENCE_ENEMY_BASELINE.values())
		result.apply_to_content(pack)
	return result
