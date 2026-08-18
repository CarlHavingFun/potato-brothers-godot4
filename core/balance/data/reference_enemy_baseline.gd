extends RefCounted


## Neutral ID mapping for the base combat-pressure profile. Values are kept
## separate from scenes so a later product balance pack can replace them.
static var VALUES: Dictionary = {
	"core:enemy/chaser_slow": _entry(3, 2.0, 250, 1.0, 0.60, 1, 200, 300),
	"core:enemy/chaser_mid": _entry(1, 1.0, 380, 1.0, 0.60, 1),
	"core:enemy/shooter": _entry(8, 1.0, 200, 1.0, 0.60, 1, 200, 200, {"projectile_damage_per_wave": 0.75}),
	"core:enemy/charger": _entry(4, 2.5, 400, 1.0, 0.85, 1, 400, 400, {"charge_cooldown_min": 2.5, "charge_cooldown_max": 3.5}),
	"core:enemy/chaser_fast": _entry(10, 24.0, 150, 1.0, 1.20, 3, 150, 600),
	"core:enemy/bulwark": _entry(20, 11.0, 300, 2.0, 0.85, 3),
	"core:enemy/war_drummer": _entry(20, 3.0, 150, 1.0, 0.60, 2, 150, 150, {"ally_health_multiplier": 1.5, "ally_damage_multiplier": 1.25, "ally_speed_multiplier": 1.5}),
	"core:enemy/flanker": _entry(15, 4.0, 350, 1.0, 0.85, 1, 325, 375, {"ranged_retaliation_chance": 0.5, "projectile_damage_per_wave": 1.0}),
	"core:enemy/medic_spore": _entry(10, 8.0, 400, 1.0, 0.85, 2, 400, 400, {"heal_base": 100.0, "heal_per_wave": 10.0}),
	"core:enemy/scrap_thief": _entry(5, 30.0, 350, 1.0, 0.85, 8, 300, 400, {"crate_drop_chance": 1.0}),
	"core:enemy/shellback": _entry(8, 4.0, 250, 1.0, 1.00, 1, 225, 275),
	"core:enemy/swarm_mite": _entry(12, 2.0, 400, 1.0, 1.00, 1),
	"core:enemy/brood_pod": _entry(10, 1.0, 120, 1.0, 0.85, 1, 120, 120, {"spawn_on_death_count": 3}),
	"core:enemy/hex_slinger": _entry(5, 5.0, 350, 1.0, 1.00, 1, 350, 350, {"projectile_damage_per_wave": 1.0}),
	"core:enemy/dapan": _entry(30, 22.0, 300, 1.0, 1.15, 3, 300, 300, {"charge_cooldown_min": 2.5, "charge_cooldown_max": 3.5}),
	"core:enemy/xiami": _entry(12, 5.0, 425, 1.0, 1.10, 1, 425, 425, {"charge_cooldown_min": 2.5, "charge_cooldown_max": 3.5}),
	"core:enemy/blink_rat": _entry(5, 3.0, 0, 1.0, 0.60, 1, 0, 0, {"hatch_seconds": 5.0}),
	"core:enemy/hazard_weaver": _entry(50, 25.0, 275, 1.0, 1.15, 3, 250, 300, {"slash_damage_per_wave": 1.0}),
	"core:enemy/iron_maw": _entry(1, 750.0, 250, 1.0, 1.50, 10),
	"core:enemy/volt_stalker": _entry(1, 750.0, 200, 1.0, 1.50, 10),
	"core:enemy/mouse_dog": _entry(29250, 0.0, 300, 30.0, 0.0, 0, 300, 300, {"projectile_damage": 23.0}),
	"core:enemy/scrap_titan": _entry(29250, 0.0, 200, 30.0, 0.0, 0, 200, 500, {"projectile_damage": 23.0}),
}


static func values() -> Dictionary:
	return VALUES.duplicate(true)


static func _entry(
	health: int,
	health_per_wave: float,
	speed: int,
	damage: float,
	damage_per_wave: float,
	material_drop: int,
	speed_min: int = -1,
	speed_max: int = -1,
	behavior_values: Dictionary = {}
) -> Dictionary:
	return {
		"health": health,
		"health_per_wave": health_per_wave,
		"speed": speed,
		"speed_min": speed if speed_min < 0 else speed_min,
		"speed_max": speed if speed_max < 0 else speed_max,
		"damage": damage,
		"damage_per_wave": damage_per_wave,
		"material_drop": material_drop,
		"behavior_values": behavior_values.duplicate(true),
	}
