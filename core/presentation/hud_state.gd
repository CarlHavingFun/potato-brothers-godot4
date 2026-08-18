class_name HudState
extends RefCounted


var wave := 1
var standard_wave_count := 20
var endless := false
var seconds_remaining := 0
var materials := 0
var material_bag := 0
var level := 1
var experience := 0
var experience_required := 10
var health := 0
var max_health := 0


static func capture(
	run_state: RunState,
	player: Player,
	seconds: float,
	experience_target: int
) -> HudState:
	var result := HudState.new()
	if run_state != null:
		result.wave = maxi(1, run_state.wave)
		result.endless = run_state.run_mode == RunMode.ENDLESS
		result.materials = maxi(0, run_state.materials)
		result.material_bag = maxi(0, run_state.material_bag)
		result.level = maxi(1, run_state.level)
		result.experience = maxi(0, run_state.experience)
	result.experience_required = maxi(1, experience_target)
	result.seconds_remaining = maxi(0, ceili(seconds))
	if is_instance_valid(player) and player.health_component != null:
		result.health = maxi(0, roundi(player.health_component.current_health))
		result.max_health = maxi(1, roundi(player.health_component.max_health))
	return result
