extends RefCounted


const REFERENCE_COMPATIBLE_IDS: Array[String] = [
	"core:weapon/axe",
	"core:weapon/chainsaw",
	"core:weapon/mace",
	"core:weapon/punch",
	"core:weapon/sword",
	"core:weapon/laser",
	"core:weapon/pistol",
	"core:weapon/smg",
	"core:weapon/spear",
	"core:weapon/cleaver",
]


# Selective, neutral gameplay corrections for stable weapon IDs whose semantic
# identity changed while retaining the copied reference economy. Fields omitted
# here continue to come from reference_weapon_baseline.gd (cost, life steal,
# critical rules, and other values that still fit the new identity).
static func values() -> Dictionary:
	return {
		# Zeus-style close electrical sidearm: the former wand range was too long.
		"core:weapon/wand": _tiers(
			[12.0, 18.0, 28.0, 45.0], [1.20, 1.08, 0.94, 0.80],
			[150.0, 165.0, 180.0, 200.0],
			[{"elemental_damage": 1.0}, {"elemental_damage": 1.2},
			{"elemental_damage": 1.4}, {"elemental_damage": 1.6}]
		),
		# Heavy precision sidearm. The reused revolver row fired like an SMG.
		"core:weapon/revolver": _tiers(
			[18.0, 28.0, 42.0, 66.0], [1.25, 1.15, 1.05, 0.90],
			[400.0, 420.0, 440.0, 460.0],
			[{"ranged_damage": 1.2}, {"ranged_damage": 1.4},
			{"ranged_damage": 1.6}, {"ranged_damage": 1.8}], 1,
			{"crit_chance": [0.12, 0.16, 0.20, 0.25]}
		),
		# Automatic rifle: one projectile per burst step, never legacy pellets.
		"core:weapon/shotgun": _tiers(
			[10.0, 15.0, 22.0, 34.0], [0.48, 0.45, 0.42, 0.38],
			[370.0, 390.0, 410.0, 440.0],
			[{"ranged_damage": 0.8}, {"ranged_damage": 0.9},
			{"ranged_damage": 1.0}, {"ranged_damage": 1.1}], 1
		),
		# High-damage rifle with recoil ramp supplied by AttackPatternDef.
		"core:weapon/carbine": _tiers(
			[12.0, 18.0, 27.0, 42.0], [0.72, 0.68, 0.63, 0.57],
			[360.0, 380.0, 400.0, 420.0],
			[{"ranged_damage": 1.0}, {"ranged_damage": 1.2},
			{"ranged_damage": 1.4}, {"ranged_damage": 1.7}]
		),
		# Accurate silenced rifle rather than the former charged range-scaler.
		"core:weapon/railbow": _tiers(
			[10.0, 15.0, 22.0, 34.0], [0.60, 0.56, 0.52, 0.47],
			[420.0, 440.0, 460.0, 480.0],
			[{"ranged_damage": 0.8}, {"ranged_damage": 0.9},
			{"ranged_damage": 1.0}, {"ranged_damage": 1.1}], 1,
			{"crit_chance": [0.05, 0.07, 0.10, 0.12]}
		),
		# Heavy SMG: slower than the rapid SMGs, with useful knockback.
		"core:weapon/shrapnel_launcher": _tiers(
			[9.0, 14.0, 21.0, 32.0], [0.72, 0.68, 0.63, 0.58],
			[340.0, 360.0, 380.0, 400.0],
			[{"ranged_damage": 0.8}, {"ranged_damage": 0.9},
			{"ranged_damage": 1.0}, {"ranged_damage": 1.2}], 1,
			{"knockback": [8.0, 9.0, 10.0, 12.0]}
		),
		# Compact rapid firearm. Remove the inherited melee scaling.
		"core:weapon/needler": _tiers(
			[3.0, 4.0, 6.0, 9.0], [0.70, 0.65, 0.60, 0.54],
			[300.0, 320.0, 340.0, 360.0],
			[{"ranged_damage": 0.45}, {"ranged_damage": 0.55},
			{"ranged_damage": 0.65}, {"ranged_damage": 0.75}], 1,
			{"crit_chance": [0.03, 0.04, 0.06, 0.08]}
		),
		# Mobile wide-spread SMG; bounce remains an AttackPatternDef concern.
		"core:weapon/boomerang": _tiers(
			[4.0, 6.0, 9.0, 14.0], [0.33, 0.31, 0.29, 0.26],
			[300.0, 315.0, 330.0, 350.0],
			[{"ranged_damage": 0.45}, {"ranged_damage": 0.55},
			{"ranged_damage": 0.65}, {"ranged_damage": 0.75}]
		),
		# Persistent fire zone. Damage is the source value for burn ticks.
		"core:weapon/ember_staff": _tiers(
			[6.0, 10.0, 16.0, 25.0], [2.20, 2.05, 1.88, 1.70],
			[380.0, 400.0, 420.0, 440.0],
			[{"elemental_damage": 0.6}, {"elemental_damage": 0.8},
			{"elemental_damage": 1.0}, {"elemental_damage": 1.2}]
		),
		# Smoke controls enemies/projectiles and intentionally deals no damage.
		"core:weapon/frost_orb": _tiers(
			[0.0, 0.0, 0.0, 0.0], [2.40, 2.18, 1.98, 1.80],
			[400.0, 420.0, 440.0, 460.0], [{}, {}, {}, {}]
		),
		# Flash is control-first, with only token impact damage.
		"core:weapon/storm_coil": _tiers(
			[1.0, 2.0, 3.0, 5.0], [2.10, 1.94, 1.78, 1.60],
			[400.0, 420.0, 440.0, 460.0],
			[{"elemental_damage": 0.2}, {"elemental_damage": 0.3},
			{"elemental_damage": 0.4}, {"elemental_damage": 0.5}]
		),
		# Thrown explosive, replacing inherited melee scaling and short range.
		"core:weapon/void_prism": _tiers(
			[18.0, 30.0, 48.0, 75.0], [2.30, 2.10, 1.92, 1.75],
			[400.0, 420.0, 440.0, 460.0],
			[{"ranged_damage": 0.7, "elemental_damage": 0.4},
			{"ranged_damage": 0.9, "elemental_damage": 0.5},
			{"ranged_damage": 1.1, "elemental_damage": 0.6},
			{"ranged_damage": 1.4, "elemental_damage": 0.8}]
		),
		# Delayed deployable explosive; arming and active-limit semantics remain in
		# AttackPatternDef and are deliberately absent from this tier table.
		"core:weapon/turret_kit": _tiers(
			[35.0, 55.0, 85.0, 130.0], [4.50, 4.10, 3.70, 3.20],
			[300.0, 330.0, 360.0, 390.0],
			[{"engineering": 1.0, "elemental_damage": 0.5},
			{"engineering": 1.2, "elemental_damage": 0.6},
			{"engineering": 1.5, "elemental_damage": 0.8},
			{"engineering": 1.8, "elemental_damage": 1.0}]
		),
		# Precise silenced sidearm. Remove inherited summon/engineering scaling.
		"core:weapon/drone_beacon": _tiers(
			[8.0, 12.0, 18.0, 28.0], [0.75, 0.70, 0.64, 0.57],
			[430.0, 450.0, 475.0, 500.0],
			[{"ranged_damage": 0.8}, {"ranged_damage": 0.9},
			{"ranged_damage": 1.0}, {"ranged_damage": 1.2}]
		),
	}


static func reviewed_ids() -> PackedStringArray:
	var result := PackedStringArray(REFERENCE_COMPATIBLE_IDS)
	for raw_id: Variant in values():
		result.append(str(raw_id))
	result.sort()
	return result


static func _tiers(
	damages: Array,
	cooldowns: Array,
	ranges: Array,
	scalings: Array,
	projectile_count: int = 1,
	extra_series: Dictionary = {}
) -> Array:
	var result: Array = []
	for tier_index: int in 4:
		var tier := {
			"damage": float(damages[tier_index]),
			"cooldown": float(cooldowns[tier_index]),
			"range": float(ranges[tier_index]),
			"scaling_coefficients": (scalings[tier_index] as Dictionary).duplicate(true),
			"projectile_count": projectile_count,
		}
		for raw_field: Variant in extra_series:
			var series: Variant = extra_series[raw_field]
			if series is Array and tier_index < series.size():
				tier[str(raw_field)] = series[tier_index]
		result.append(tier)
	return result
