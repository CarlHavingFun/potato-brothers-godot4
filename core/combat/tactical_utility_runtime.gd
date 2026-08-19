class_name TacticalUtilityRuntime
extends Node2D


const PIXEL_ART_WORLD_SCALE := 0.14


enum Phase {
	TRAVELLING,
	ARMING,
	ZONE,
	DONE,
}

var utility_kind: StringName
var damage := 0.0
var radius := 0.0
var arming_delay := 0.0
var travel_duration := 0.0
var throw_arc_height := 72.0
var zone_duration := 0.0
var zone_tick_interval := 0.25
var zone_speed_multiplier := 0.7
var status_duration := 0.0
var status_damage_scale := 0.0
var interrupt_ranged := false
var max_active := 1
var gameplay_tags: Array[StringName] = []
var gameplay_source: Object
var is_critical := false

var phase := Phase.ARMING
var _phase_remaining := 0.0
var _zone_tick_remaining := 0.0
var _travel_origin := Vector2.ZERO
var _travel_target := Vector2.ZERO
var _travel_elapsed := 0.0
var _presentation_id: StringName


func _ready() -> void:
	add_to_group(&"tactical_utilities")
	queue_redraw()


func _process(delta: float) -> void:
	advance_simulation(delta)


func configure(
	pattern: AttackPatternDef,
	origin: Vector2,
	target: Vector2,
	base_damage: float,
	source: Object,
	tags: Array[StringName],
	presentation_id: StringName,
	critical_hit := false
) -> void:
	if pattern == null:
		return
	utility_kind = pattern.utility_kind
	damage = maxf(0.0, base_damage * pattern.damage_multiplier)
	radius = maxf(pattern.explosion_radius, pattern.zone_radius)
	arming_delay = maxf(0.0, pattern.arming_delay)
	travel_duration = maxf(0.0, pattern.travel_duration)
	throw_arc_height = maxf(0.0, pattern.throw_arc_height)
	zone_duration = maxf(0.0, pattern.zone_duration)
	zone_tick_interval = maxf(0.05, pattern.zone_tick_interval)
	zone_speed_multiplier = clampf(pattern.zone_speed_multiplier, 0.1, 1.0)
	status_duration = maxf(0.0, pattern.status_duration)
	status_damage_scale = maxf(0.0, pattern.status_damage_scale)
	interrupt_ranged = pattern.interrupt_ranged
	max_active = maxi(1, pattern.max_active)
	gameplay_source = source
	gameplay_tags = tags.duplicate()
	is_critical = critical_hit
	_presentation_id = presentation_id
	_travel_origin = origin
	_travel_target = target
	global_position = origin
	_install_visual()
	if pattern.kind == AttackPatternDef.Kind.THROWN and travel_duration > 0.0:
		phase = Phase.TRAVELLING
		_phase_remaining = travel_duration
	else:
		global_position = target
		start_armed_phase()


func configure_for_test(
	kind: StringName,
	base_damage: float,
	area_radius: float,
	source: Object = null
) -> void:
	utility_kind = kind
	damage = maxf(0.0, base_damage)
	radius = maxf(0.0, area_radius)
	gameplay_source = source
	status_duration = 1.0
	zone_tick_interval = 0.25
	zone_speed_multiplier = 0.7


func presentation_id() -> StringName:
	return _presentation_id


func retire_for_replacement() -> void:
	_finish()


func start_armed_phase() -> void:
	phase = Phase.ARMING
	_phase_remaining = maxf(0.0, arming_delay)
	queue_redraw()
	if is_zero_approx(_phase_remaining):
		detonate_now()


func advance_simulation(delta: float) -> void:
	if phase == Phase.DONE or delta <= 0.0:
		return
	match phase:
		Phase.TRAVELLING:
			_travel_elapsed = minf(travel_duration, _travel_elapsed + delta)
			var progress := 1.0 if travel_duration <= 0.0 else _travel_elapsed / travel_duration
			global_position = _travel_origin.lerp(_travel_target, clampf(progress, 0.0, 1.0))
			var visual := get_node_or_null("Sprite2D") as Sprite2D
			if visual != null:
				# The gameplay origin follows a deterministic straight interpolation;
				# only the presentation sprite follows the familiar grenade parabola.
				visual.position.y = -4.0 * throw_arc_height * progress * (1.0 - progress)
			_phase_remaining -= delta
			if _phase_remaining <= 0.0:
				global_position = _travel_target
				if visual != null:
					visual.position = Vector2.ZERO
				start_armed_phase()
		Phase.ARMING:
			_phase_remaining -= delta
			if _phase_remaining <= 0.0:
				detonate_now()
		Phase.ZONE:
			_phase_remaining -= delta
			_zone_tick_remaining -= delta
			while _zone_tick_remaining <= 0.0 and phase == Phase.ZONE:
				tick_zone_now()
				_zone_tick_remaining += zone_tick_interval
			if _phase_remaining <= 0.0:
				_finish()


func detonate_now() -> void:
	if phase == Phase.DONE:
		return
	if utility_kind in [&"smoke", &"molotov"]:
		phase = Phase.ZONE
		_phase_remaining = maxf(zone_tick_interval, zone_duration)
		_zone_tick_remaining = zone_tick_interval
		tick_zone_now()
		queue_redraw()
		return
	_apply_instant_effects()
	GameplayCues.emit_cue(&"weapon.utility", {
		"utility_kind": utility_kind,
		"world_position": global_position,
	})
	_finish()


func tick_zone_now() -> void:
	for enemy: Node2D in _targets_in_radius():
		match utility_kind:
			&"smoke":
				_apply_status(enemy, &"smoke", maxf(status_duration, zone_tick_interval * 2.0), 0.0)
			&"molotov":
				_apply_status(
					enemy,
					&"burn",
					maxf(status_duration, zone_tick_interval * 2.0),
					damage * maxf(0.0, status_damage_scale)
				)
	if utility_kind == &"smoke":
		_slow_enemy_projectiles()


func _apply_instant_effects() -> void:
	for enemy: Node2D in _targets_in_radius():
		if damage > 0.0:
			# A tactical detonation is the weapon's primary hit, not recursive
			# effect damage. Route it through Unit's typed hit entry so armor,
			# critical/HIT triggers, damage text, kill ownership and the weapon's
			# confirmed-hit hook (including life steal) stay identical to bullets.
			if enemy.has_method("receive_typed_damage"):
				enemy.call(
					"receive_typed_damage",
					damage,
					gameplay_source,
					gameplay_tags,
					is_critical
				)
			elif enemy.has_method("apply_effect_damage"):
				# Keep lightweight non-Unit test/extension targets compatible. Burn
				# and explosion procs still use apply_effect_damage separately, which
				# prevents those secondary effects from recursively emitting HIT.
				enemy.call("apply_effect_damage", damage, gameplay_source)
		if utility_kind == &"flash":
			_apply_status(enemy, &"blind", maxf(0.1, status_duration), 0.0)


func _apply_status(target: Node2D, status_id: StringName, duration: float, amount: float) -> void:
	if not target.has_method("apply_effect_status"):
		return
	target.call("apply_effect_status", {
		"status_id": String(status_id),
		"duration": maxf(0.0, duration),
		"stacks": 1,
		"amount": maxf(0.0, amount),
		"speed_multiplier": zone_speed_multiplier,
		"interrupt_ranged": interrupt_ranged,
		"refresh_only": true,
	}, gameplay_source)


func _targets_in_radius() -> Array[Node2D]:
	var result: Array[Node2D] = []
	var tree := get_tree()
	if tree == null:
		return result
	var radius_squared := radius * radius
	for candidate: Node in tree.get_nodes_in_group(GameplayEffectExecutor.ENEMY_GROUP):
		if candidate is not Node2D:
			continue
		var target := candidate as Node2D
		if global_position.distance_squared_to(target.global_position) <= radius_squared:
			result.append(target)
	result.sort_custom(func(first: Node2D, second: Node2D) -> bool:
		var first_distance := global_position.distance_squared_to(first.global_position)
		var second_distance := global_position.distance_squared_to(second.global_position)
		if not is_equal_approx(first_distance, second_distance):
			return first_distance < second_distance
		return first.get_instance_id() < second.get_instance_id()
	)
	return result


func _slow_enemy_projectiles() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var radius_squared := radius * radius
	for candidate: Node in tree.get_nodes_in_group(&"presentation_projectiles"):
		if candidate is not Projectile:
			continue
		var projectile := candidate as Projectile
		if not projectile.is_enemy_projectile():
			continue
		if global_position.distance_squared_to(projectile.global_position) > radius_squared:
			continue
		projectile.apply_temporary_speed_multiplier(
			zone_speed_multiplier,
			zone_tick_interval * 2.0
		)


func _install_visual() -> void:
	var visual := get_node_or_null("Sprite2D") as Sprite2D
	if visual == null:
		visual = Sprite2D.new()
		visual.name = "Sprite2D"
		add_child(visual)
	visual.texture = Presentation.resolve_texture(&"projectile", _presentation_id, null, &"world")
	visual.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if visual.texture != null and maxf(
		visual.texture.get_width(), visual.texture.get_height()
	) >= 128.0:
		# Skin v2 stores 64 logical pixels as 256 physical pixels. Tactical
		# throws should read at combat scale, not cover a quarter of the arena.
		visual.scale = Vector2.ONE * PIXEL_ART_WORLD_SCALE


func _finish() -> void:
	phase = Phase.DONE
	queue_free()


func _draw() -> void:
	if radius <= 0.0:
		return
	var color := Color(0.95, 0.22, 0.12, 0.20)
	if utility_kind == &"smoke":
		color = Color(0.38, 0.48, 0.52, 0.18)
	elif utility_kind == &"flash":
		color = Color(1.0, 0.94, 0.56, 0.18)
	elif utility_kind == &"molotov":
		color = Color(1.0, 0.32, 0.08, 0.20)
	draw_circle(Vector2.ZERO, radius, color)
	draw_arc(
		Vector2.ZERO,
		radius,
		0.0,
		TAU,
		64,
		Color(color.r, color.g, color.b, 0.85),
		2.0
	)
