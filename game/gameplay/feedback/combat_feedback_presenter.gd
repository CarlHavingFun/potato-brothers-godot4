class_name GogoCombatFeedbackPresenter
extends Node2D

signal feedback_spawned(kind: StringName, integer_global_position: Vector2i, event_key: StringName)

const MAX_ACTIVE_EFFECTS := 96
const MAX_PRIMITIVES_PER_EFFECT := 9
const VALID_PROFILES: Array[StringName] = [&"rapid", &"rifle", &"heavy", &"suppressed"]
const VALID_IMPACTS: Array[StringName] = [&"normal", &"critical", &"pierce_exit", &"explosion"]
const DIRECTIONS_8: Array[Vector2i] = [
	Vector2i.RIGHT,
	Vector2i(1, 1),
	Vector2i.DOWN,
	Vector2i(-1, 1),
	Vector2i.LEFT,
	Vector2i(-1, -1),
	Vector2i.UP,
	Vector2i(1, -1),
]
const PROFILE_SETTINGS := {
	&"rapid": {"duration": 0.050, "muzzle_size": 16.0, "hit_size": 18.0, "shot_impulse": 1.0, "hit_impulse": 1.0, "color": Color("ffd166")},
	&"rifle": {"duration": 0.070, "muzzle_size": 24.0, "hit_size": 24.0, "shot_impulse": 2.0, "hit_impulse": 1.5, "color": Color("ffe082")},
	&"heavy": {"duration": 0.100, "muzzle_size": 36.0, "hit_size": 32.0, "shot_impulse": 4.0, "hit_impulse": 3.0, "color": Color("ff9f43")},
	&"suppressed": {"duration": 0.045, "muzzle_size": 14.0, "hit_size": 18.0, "shot_impulse": 0.5, "hit_impulse": 0.75, "color": Color("c8d6a5")},
}
const IMPACT_SETTINGS := {
	&"normal": {"duration": 0.085, "scale": 1.0, "impulse_scale": 1.0, "color": Color("ffcf6e")},
	&"critical": {"duration": 0.14, "scale": 1.40, "impulse_scale": 1.55, "color": Color("fff0a8")},
	&"pierce_exit": {"duration": 0.09, "scale": 0.90, "impulse_scale": 0.65, "color": Color("8bd3dd")},
	&"explosion": {"duration": 0.20, "scale": 1.75, "impulse_scale": 2.10, "color": Color("ff714b")},
}
const MELEE_CONTACT_VISUAL_SCALE := 0.45
const STATIC_IMPACT_SELECTORS := {
	&"normal": &"static_hit_mark",
	&"critical": &"static_critical_mark",
	&"pierce_exit": &"static_pierce_mark",
	&"explosion": &"static_explosion_mark",
}
const STATIC_IMPACT_ASSET_ID: StringName = &"projectile_hit_kit"
const STATIC_IMPACT_ROLE: StringName = &"impact_sprite"
const STATIC_MUZZLE_ASSET_ID: StringName = &"projectile_hit_kit"
const STATIC_MUZZLE_ROLE: StringName = &"muzzle_flash"
const STATIC_MUZZLE_SELECTORS := {
	&"rapid": &"rapid_muzzle_flash",
	&"rifle": &"rifle_muzzle_flash",
	&"heavy": &"heavy_muzzle_flash",
	&"suppressed": &"rapid_muzzle_flash",
}
const STATIC_FEEDBACK_ASSET_ID: StringName = &"projectile_hit_kit"
const STATIC_FEEDBACK_ROLE: StringName = &"feedback_sprite"
const STATIC_FEEDBACK_SELECTORS := {
	# The old beige puff read as a white smoke cloud at gameplay scale and hid
	# short melee weapons. Reuse the compact red starburst already shipped in
	# this atlas; it matches Brotato's small red/black defeat punctuation.
	&"death": &"player_damage_burst",
	&"player_hit": &"player_damage_burst",
	&"pickup": &"gold_pickup_flash",
}
const STATIC_ONLY_KINDS: Array[StringName] = [&"muzzle", &"death", &"player_hit", &"pickup"]
const DEATH_BASE_SIZE_PX := 24.0
const DEATH_REWARD_SIZE_PER_POINT_PX := 0.5
const DEATH_REWARD_SIZE_CAP_PX := 8.0


class FeedbackSlot:
	var active := false
	var activation_serial := 0
	var event_key: StringName = &""
	var kind: StringName = &""
	var profile: StringName = &""
	var impact: StringName = &""
	var damage_kind: StringName = &""
	var visual_source: StringName = &"procedural_fallback"
	var visual_selector: StringName = &""
	var texture: Texture2D
	var texture_size := Vector2i.ZERO
	var texture_pivot := Vector2i.ZERO
	var texture_rotation_radians := 0.0
	var texture_mirror_x := false
	var position := Vector2i.ZERO
	var direction := Vector2i.RIGHT
	var age := 0.0
	var duration := 0.08
	var size_px := 8
	var color := Color.WHITE
	var render_phase := -1
	var primitive_count := 0
	var primitive_rects: Array[Rect2i] = []
	var primitive_colors: Array[Color] = []


	func _init() -> void:
		primitive_rects.resize(9)
		primitive_colors.resize(9)


var combat_camera: GogoCombatCamera
var _static_asset_snapshot: GogoStaticAssetSnapshot
var _slots: Array[FeedbackSlot] = []
var _next_slot := 0
var _activation_serial := 0
var _active_count := 0
var _shot_highest_sequence: Dictionary = {}
var _melee_highest_sequence: Dictionary = {}
var _contact_highest_sequence: Dictionary = {}
var _contact_target_by_sequence: Dictionary = {}
var _death_highest_sequence: Dictionary = {}
var _player_hit_highest_sequence := 0
var _pickup_highest_sequence: Dictionary = {}


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for index in MAX_ACTIVE_EFFECTS:
		_slots.append(FeedbackSlot.new())


func configure(
	next_camera: GogoCombatCamera,
	next_static_asset_snapshot: GogoStaticAssetSnapshot = null
) -> void:
	combat_camera = next_camera
	_static_asset_snapshot = next_static_asset_snapshot


func clear_feedback() -> void:
	for slot: FeedbackSlot in _slots:
		slot.active = false
	_active_count = 0
	_next_slot = 0
	_shot_highest_sequence.clear()
	_melee_highest_sequence.clear()
	_contact_highest_sequence.clear()
	_contact_target_by_sequence.clear()
	_death_highest_sequence.clear()
	_player_hit_highest_sequence = 0
	_pickup_highest_sequence.clear()
	if combat_camera != null:
		combat_camera.clear_visual_impulses()
	queue_redraw()


func present_weapon_fired(
	weapon_instance_id: int,
	feedback_profile_id: StringName,
	integer_muzzle_global_position: Vector2i,
	shot_direction: Vector2,
	projectile_count: int,
	shot_sequence: int
) -> bool:
	if (
		weapon_instance_id <= 0
		or shot_sequence <= 0
		or projectile_count <= 0
		or not VALID_PROFILES.has(feedback_profile_id)
		or not shot_direction.is_finite()
		or shot_direction.is_zero_approx()
		or not _accept_monotonic(_shot_highest_sequence, weapon_instance_id, shot_sequence)
	):
		return false
	var event_key := StringName("shot/%d/%d" % [weapon_instance_id, shot_sequence])
	var settings := _profile_settings(feedback_profile_id)
	_activate_slot(
		event_key,
		&"muzzle",
		feedback_profile_id,
		&"",
		&"ballistic",
		integer_muzzle_global_position,
		_quantize_direction_8(shot_direction),
		float(settings.duration),
		_even_px(float(settings.muzzle_size) * minf(1.0 + 0.12 * float(projectile_count - 1), 1.5)),
		settings.color as Color
	)
	if combat_camera != null:
		combat_camera.add_visual_impulse(-shot_direction, float(settings.shot_impulse))
	feedback_spawned.emit(&"muzzle", integer_muzzle_global_position, event_key)
	return true


func present_melee_contact(
	weapon_instance_id: int,
	target_instance_id: int,
	feedback_profile_id: StringName,
	integer_contact_global_position: Vector2i,
	contact_normal: Vector2,
	damage_kind: StringName,
	impact_kind: StringName,
	melee_sequence: int
) -> bool:
	if (
		weapon_instance_id <= 0
		or target_instance_id <= 0
		or melee_sequence <= 0
		or not VALID_PROFILES.has(feedback_profile_id)
		or damage_kind.is_empty()
		or not VALID_IMPACTS.has(impact_kind)
		or not contact_normal.is_finite()
		or contact_normal.is_zero_approx()
		or not _accept_monotonic(_melee_highest_sequence, weapon_instance_id, melee_sequence)
	):
		return false
	var event_key := StringName("melee/%d/%d/%d" % [weapon_instance_id, target_instance_id, melee_sequence])
	var settings := _profile_settings(feedback_profile_id)
	var impact := _impact_settings(impact_kind)
	_activate_slot(
		event_key,
		&"contact",
		feedback_profile_id,
		impact_kind,
		damage_kind,
		integer_contact_global_position,
		_quantize_direction_8(contact_normal),
		float(impact.duration),
		_even_px(
			float(settings.hit_size)
			* float(impact.scale)
			* MELEE_CONTACT_VISUAL_SCALE
		),
		impact.color as Color
	)
	if combat_camera != null:
		combat_camera.add_visual_impulse(contact_normal, float(settings.hit_impulse) * float(impact.impulse_scale) * 1.15)
	feedback_spawned.emit(&"melee_contact", integer_contact_global_position, event_key)
	return true


func present_projectile_contact(
	projectile_instance_id: int,
	target_instance_id: int,
	feedback_profile_id: StringName,
	integer_contact_global_position: Vector2i,
	contact_normal: Vector2,
	damage_kind: StringName,
	impact_kind: StringName,
	contact_sequence: int
) -> bool:
	if (
		projectile_instance_id <= 0
		or target_instance_id <= 0
		or contact_sequence <= 0
		or not VALID_PROFILES.has(feedback_profile_id)
		or damage_kind.is_empty()
		or not VALID_IMPACTS.has(impact_kind)
		or not contact_normal.is_finite()
		or contact_normal.is_zero_approx()
		or not _accept_contact(projectile_instance_id, target_instance_id, contact_sequence)
	):
		return false
	var event_key := StringName("contact/%d/%d/%d" % [
		projectile_instance_id,
		target_instance_id,
		contact_sequence,
	])
	var settings := _profile_settings(feedback_profile_id)
	var impact := _impact_settings(impact_kind)
	_activate_slot(
		event_key,
		&"contact",
		feedback_profile_id,
		impact_kind,
		damage_kind,
		integer_contact_global_position,
		_quantize_direction_8(contact_normal),
		float(impact.duration),
		_even_px(float(settings.hit_size) * float(impact.scale)),
		impact.color as Color
	)
	if combat_camera != null:
		combat_camera.add_visual_impulse(contact_normal, float(settings.hit_impulse) * float(impact.impulse_scale))
	feedback_spawned.emit(&"contact", integer_contact_global_position, event_key)
	return true


func present_enemy_defeated(
	enemy_instance_id: int,
	integer_death_global_position: Vector2i,
	xp: int,
	materials: int,
	death_sequence: int
) -> bool:
	if (
		enemy_instance_id <= 0
		or death_sequence <= 0
		or xp < 0
		or materials < 0
		or not _accept_monotonic(_death_highest_sequence, enemy_instance_id, death_sequence)
	):
		return false
	var event_key := StringName("death/%d/%d" % [enemy_instance_id, death_sequence])
	_activate_slot(
		event_key,
		&"death",
		&"",
		&"",
		&"",
		integer_death_global_position,
		Vector2i.RIGHT,
		0.20,
		_even_px(
			DEATH_BASE_SIZE_PX
			+ minf(
				float(xp + materials) * DEATH_REWARD_SIZE_PER_POINT_PX,
				DEATH_REWARD_SIZE_CAP_PX
			)
		),
		Color("ff7657")
	)
	if combat_camera != null:
		var deterministic_direction := DIRECTIONS_8[(enemy_instance_id * 5 + death_sequence * 3) % DIRECTIONS_8.size()]
		combat_camera.add_visual_impulse(Vector2(deterministic_direction), 1.8)
	feedback_spawned.emit(&"death", integer_death_global_position, event_key)
	return true


func present_player_damage_taken(
	integer_global_position: Vector2i,
	final_damage: float,
	remaining_health: float,
	lethal: bool,
	sequence: int
) -> bool:
	if (
		sequence <= _player_hit_highest_sequence
		or not is_finite(final_damage)
		or final_damage <= 0.0
		or not is_finite(remaining_health)
		or remaining_health < 0.0
	):
		return false
	_player_hit_highest_sequence = sequence
	var event_key := StringName("player_hit/%d" % sequence)
	var direction := DIRECTIONS_8[posmod(sequence * 3, DIRECTIONS_8.size())]
	_activate_slot(
		event_key,
		&"player_hit",
		&"",
		&"",
		&"player",
		integer_global_position,
		direction,
		0.10,
		36,
		Color("ef3340")
	)
	if combat_camera != null:
		combat_camera.add_visual_impulse(Vector2(direction), 3.5 if lethal else 2.75)
	feedback_spawned.emit(&"player_hit", integer_global_position, event_key)
	return true


func present_pickup_collected(
	pickup_instance_id: int,
	integer_collection_global_position: Vector2i,
	visual_amount: int,
	collection_sequence: int
) -> bool:
	if (
		pickup_instance_id <= 0
		or visual_amount <= 0
		or collection_sequence <= 0
		or not _accept_monotonic(
			_pickup_highest_sequence,
			pickup_instance_id,
			collection_sequence
		)
	):
		return false
	var event_key := StringName("pickup/%d/%d" % [pickup_instance_id, collection_sequence])
	_activate_slot(
		event_key,
		&"pickup",
		&"",
		&"",
		&"reward",
		integer_collection_global_position,
		Vector2i.UP,
		0.11,
		_even_px(18.0 + minf(float(visual_amount) * 2.0, 8.0)),
		Color("ffd34d")
	)
	feedback_spawned.emit(&"pickup", integer_collection_global_position, event_key)
	return true


func active_effect_count(kind: StringName = &"") -> int:
	if kind.is_empty():
		return _active_count
	var count := 0
	for slot: FeedbackSlot in _slots:
		if slot.active and slot.kind == kind:
			count += 1
	return count


func allocated_slot_count() -> int:
	return _slots.size()


func debug_effects() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index in _slots.size():
		var slot := _slots[index]
		if not slot.active:
			continue
		result.append({
			"slot_index": index,
			"activation_serial": slot.activation_serial,
			"event_key": slot.event_key,
			"kind": slot.kind,
			"profile": slot.profile,
			"impact": slot.impact,
			"damage_kind": slot.damage_kind,
			"visual_source": slot.visual_source,
			"visual_selector": slot.visual_selector,
			"texture_size": slot.texture_size,
			"texture_pivot": slot.texture_pivot,
			"texture_rotation_radians": slot.texture_rotation_radians,
			"texture_mirror_x": slot.texture_mirror_x,
			"position": slot.position,
			"direction": slot.direction,
			"age": slot.age,
			"duration": slot.duration,
			"size_px": slot.size_px,
		})
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return int(left.activation_serial) < int(right.activation_serial)
	)
	return result


func _physics_process(delta: float) -> void:
	if _active_count <= 0:
		return
	var safe_delta := maxf(delta, 0.0)
	for slot: FeedbackSlot in _slots:
		if not slot.active:
			continue
		slot.age += safe_delta
		if slot.age >= slot.duration:
			slot.active = false
			_active_count -= 1
		elif slot.render_phase != _phase(slot):
			_refresh_slot_primitives(slot)
	queue_redraw()


func _draw() -> void:
	for slot: FeedbackSlot in _slots:
		if not slot.active:
			continue
		if slot.texture != null:
			var center := Vector2i(to_local(Vector2(slot.position)).round())
			var phase_alpha := [1.0, 0.72, 0.38][_phase(slot)] as float
			if slot.kind == &"muzzle":
				draw_set_transform(
					Vector2(center),
					slot.texture_rotation_radians,
					Vector2(-1.0 if slot.texture_mirror_x else 1.0, 1.0)
				)
				draw_texture_rect(
					slot.texture,
					Rect2(Vector2(-slot.texture_pivot), Vector2(slot.texture_size)),
					false,
					Color(1.0, 1.0, 1.0, phase_alpha)
				)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			else:
				var texture_rect := Rect2(
					Vector2(center - slot.texture_pivot),
					Vector2(slot.texture_size)
				)
				draw_texture_rect(
					slot.texture,
					texture_rect,
					false,
					Color(1.0, 1.0, 1.0, phase_alpha)
				)
			continue
		for index in slot.primitive_count:
			var rect := slot.primitive_rects[index]
			draw_rect(Rect2(Vector2(rect.position), Vector2(rect.size)), slot.primitive_colors[index], true)


func debug_block_primitives() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for slot: FeedbackSlot in _slots:
		if not slot.active:
			continue
		for index in slot.primitive_count:
			result.append({
				"event_key": slot.event_key,
				"kind": slot.kind,
				"rect": slot.primitive_rects[index],
				"color": slot.primitive_colors[index],
			})
	return result


func _refresh_slot_primitives(slot: FeedbackSlot) -> void:
	slot.primitive_count = 0
	slot.render_phase = _phase(slot)
	if slot.texture != null:
		return
	match slot.kind:
		&"contact": _append_contact_primitives(slot)


func _append_contact_primitives(slot: FeedbackSlot) -> void:
	var phase := _phase(slot)
	var center := Vector2i(to_local(Vector2(slot.position)).round())
	var normal_index := DIRECTIONS_8.find(slot.direction)
	var core_size := maxi(slot.size_px - phase * 2, 4)
	var color := Color("fff8cf") if phase == 0 else (slot.color if phase == 1 else slot.color.darkened(0.30))
	_append_block(slot, center, _even_px(float(core_size) * 0.55), color)
	for offset_index in [-1, 0, 1]:
		var ray := DIRECTIONS_8[posmod(normal_index + offset_index, DIRECTIONS_8.size())]
		var distance := maxi(core_size * (2 + phase) / 3, 4)
		_append_block(slot, center + ray * distance, _even_px(float(core_size) * 0.30), slot.color)


func _activate_slot(
	event_key: StringName,
	kind: StringName,
	profile: StringName,
	impact: StringName,
	damage_kind: StringName,
	position: Vector2i,
	direction: Vector2i,
	duration: float,
	size_px: int,
	color: Color
) -> void:
	var slot := _slots[_next_slot]
	if not slot.active:
		_active_count += 1
	_activation_serial += 1
	slot.active = true
	slot.activation_serial = _activation_serial
	slot.event_key = event_key
	slot.kind = kind
	slot.profile = profile
	slot.impact = impact
	slot.damage_kind = damage_kind
	slot.visual_source = (
		&"static_asset_required" if STATIC_ONLY_KINDS.has(kind) else &"procedural_fallback"
	)
	slot.visual_selector = &""
	slot.texture = null
	slot.texture_size = Vector2i.ZERO
	slot.texture_pivot = Vector2i.ZERO
	slot.texture_rotation_radians = 0.0
	slot.texture_mirror_x = false
	slot.position = position
	slot.direction = direction
	slot.age = 0.0
	slot.duration = maxf(duration, 0.001)
	slot.size_px = maxi(size_px, 4)
	slot.color = color
	slot.render_phase = -1
	_resolve_static_muzzle(slot)
	_resolve_static_impact(slot)
	_resolve_static_feedback(slot)
	_refresh_slot_primitives(slot)
	_next_slot = (_next_slot + 1) % _slots.size()
	queue_redraw()


func _resolve_static_muzzle(slot: FeedbackSlot) -> void:
	if slot.kind != &"muzzle" or _static_asset_snapshot == null:
		return
	var selector := STATIC_MUZZLE_SELECTORS.get(slot.profile, &"") as StringName
	if selector.is_empty():
		return
	var handle := _static_asset_snapshot.resolve_asset(
		STATIC_MUZZLE_ASSET_ID,
		STATIC_MUZZLE_ROLE,
		selector
	)
	if (
		handle == null
		or handle.texture == null
		or handle.display_size_px.x <= 0
		or handle.display_size_px.y <= 0
	):
		return
	var content_min := handle.anchors_px.get(&"content_min", Vector2i.ZERO) as Vector2i
	var content_max := handle.anchors_px.get(&"content_max", Vector2i.ZERO) as Vector2i
	var content_size := content_max - content_min + Vector2i.ONE
	if content_size.x <= 0 or content_size.y <= 0:
		return
	var render_scale := float(slot.size_px) / float(maxi(content_size.x, content_size.y))
	slot.visual_source = &"static_asset"
	slot.visual_selector = selector
	slot.texture = handle.texture
	slot.texture_size = Vector2i(
		maxi(int(round(float(handle.display_size_px.x) * render_scale)), 1),
		maxi(int(round(float(handle.display_size_px.y) * render_scale)), 1)
	)
	slot.texture_pivot = Vector2i(
		int(round(float(handle.pivot_px.x) * render_scale)),
		int(round(float(handle.pivot_px.y) * render_scale))
	)
	var direction_angle := Vector2(slot.direction).angle()
	slot.texture_mirror_x = slot.direction.x < 0
	slot.texture_rotation_radians = (
		wrapf(direction_angle - PI, -PI, PI)
		if slot.texture_mirror_x
		else direction_angle
	)
	GogoStaticConsumerRegistry.observe_handle(
		handle,
		"res://game/gameplay/feedback/combat_feedback_presenter.gd",
		"CombatFeedback/%s" % String(selector)
	)


func _resolve_static_impact(slot: FeedbackSlot) -> void:
	if slot.kind != &"contact" or _static_asset_snapshot == null:
		return
	var selector := STATIC_IMPACT_SELECTORS.get(slot.impact, &"") as StringName
	if selector.is_empty():
		return
	var handle := _static_asset_snapshot.resolve_asset(
		STATIC_IMPACT_ASSET_ID,
		STATIC_IMPACT_ROLE,
		selector
	)
	if (
		handle == null
		or handle.texture == null
		or handle.display_size_px.x <= 0
		or handle.display_size_px.y <= 0
	):
		return
	slot.visual_source = &"static_asset"
	slot.visual_selector = selector
	slot.texture = handle.texture
	var source_size := handle.display_size_px
	var render_scale := float(slot.size_px) / float(maxi(source_size.x, source_size.y))
	slot.texture_size = Vector2i(
		maxi(int(round(float(source_size.x) * render_scale)), 1),
		maxi(int(round(float(source_size.y) * render_scale)), 1)
	)
	slot.texture_pivot = Vector2i(
		int(round(float(handle.pivot_px.x) * render_scale)),
		int(round(float(handle.pivot_px.y) * render_scale))
	)
	GogoStaticConsumerRegistry.observe_handle(
		handle,
		"res://game/gameplay/feedback/combat_feedback_presenter.gd",
		"CombatFeedback/%s" % String(selector)
	)


func _resolve_static_feedback(slot: FeedbackSlot) -> void:
	if not STATIC_FEEDBACK_SELECTORS.has(slot.kind) or _static_asset_snapshot == null:
		return
	var selector := STATIC_FEEDBACK_SELECTORS.get(slot.kind, &"") as StringName
	var handle := _static_asset_snapshot.resolve_asset(
		STATIC_FEEDBACK_ASSET_ID,
		STATIC_FEEDBACK_ROLE,
		selector
	)
	if (
		handle == null
		or handle.texture == null
		or handle.display_size_px.x <= 0
		or handle.display_size_px.y <= 0
	):
		return
	var content_min := handle.anchors_px.get(&"content_min", Vector2i.ZERO) as Vector2i
	var content_max := handle.anchors_px.get(&"content_max", Vector2i.ZERO) as Vector2i
	var content_size := content_max - content_min + Vector2i.ONE
	if content_size.x <= 0 or content_size.y <= 0:
		content_size = handle.display_size_px
	var render_scale := float(slot.size_px) / float(maxi(content_size.x, content_size.y))
	slot.visual_source = &"static_asset"
	slot.visual_selector = selector
	slot.texture = handle.texture
	slot.texture_size = Vector2i(
		maxi(int(round(float(handle.display_size_px.x) * render_scale)), 1),
		maxi(int(round(float(handle.display_size_px.y) * render_scale)), 1)
	)
	slot.texture_pivot = Vector2i(
		int(round(float(handle.pivot_px.x) * render_scale)),
		int(round(float(handle.pivot_px.y) * render_scale))
	)
	GogoStaticConsumerRegistry.observe_handle(
		handle,
		"res://game/gameplay/feedback/combat_feedback_presenter.gd",
		"CombatFeedback/%s" % String(selector)
	)


func _accept_contact(projectile_instance_id: int, target_instance_id: int, sequence: int) -> bool:
	var highest := int(_contact_highest_sequence.get(projectile_instance_id, 0))
	var sequence_key := StringName("%d/%d" % [projectile_instance_id, sequence])
	if sequence <= highest or _contact_target_by_sequence.has(sequence_key):
		return false
	_contact_highest_sequence[projectile_instance_id] = sequence
	_contact_target_by_sequence[sequence_key] = target_instance_id
	return true


static func _accept_monotonic(state: Dictionary, emitter_id: int, sequence: int) -> bool:
	if sequence <= int(state.get(emitter_id, 0)):
		return false
	state[emitter_id] = sequence
	return true


static func _quantize_direction_8(direction: Vector2) -> Vector2i:
	var index := posmod(int(round(direction.angle() / (PI * 0.25))), DIRECTIONS_8.size())
	return DIRECTIONS_8[index]


static func _even_px(value: float) -> int:
	var rounded := maxi(int(round(value)), 4)
	return rounded if rounded % 2 == 0 else rounded + 1


static func _phase(slot: FeedbackSlot) -> int:
	var progress := clampf(slot.age / maxf(slot.duration, 0.001), 0.0, 0.999)
	return mini(int(progress * 3.0), 2)


func _append_block(
	slot: FeedbackSlot,
	center: Vector2i,
	size_px: int,
	color: Color
) -> void:
	if slot.primitive_count >= MAX_PRIMITIVES_PER_EFFECT:
		return
	var even_size := _even_px(float(size_px))
	var half := even_size / 2
	slot.primitive_rects[slot.primitive_count] = Rect2i(
		center - Vector2i(half, half),
		Vector2i(even_size, even_size)
	)
	slot.primitive_colors[slot.primitive_count] = color
	slot.primitive_count += 1


static func _profile_settings(profile: StringName) -> Dictionary:
	return PROFILE_SETTINGS.get(profile, PROFILE_SETTINGS[&"rifle"])


static func _impact_settings(impact: StringName) -> Dictionary:
	return IMPACT_SETTINGS.get(impact, IMPACT_SETTINGS[&"normal"])
