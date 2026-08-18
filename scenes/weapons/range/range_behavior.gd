extends WeaponBehavior
class_name RangeBehavior

@onready var muzzle: Marker2D = %Muzzle

func execute_attack() -> void:
	weapon.is_attacking = true
	var pattern := weapon.current_attack_pattern()
	var windup := pattern.attack_windup() if pattern != null else 0.0
	if windup > 0.0:
		await get_tree().create_timer(windup, false).timeout
		if not is_instance_valid(weapon) or weapon.data == null:
			return

	var tween := create_tween()
	var attack_pos := Vector2(weapon.atk_start_pos.x - weapon.data.stats.recoil, weapon.atk_start_pos.y)
	tween.tween_property(weapon.sprite, "position", attack_pos, weapon.data.stats.recoil_duration)
	tween.tween_property(weapon.sprite, "position", weapon.atk_start_pos, weapon.data.stats.recoil_duration)
	await _fire_sequence(pattern)
	await tween.finished
	weapon.is_attacking = false
	critical = false


func _fire_sequence(pattern: AttackPatternDef) -> void:
	var shot_count := pattern.runtime_shot_count() if pattern != null else 1
	var shot_interval := pattern.runtime_shot_interval() if pattern != null else 0.0
	var sequence_damage_scale := 1.0 / float(shot_count) if (
		pattern != null and pattern.kind == AttackPatternDef.Kind.BEAM
	) else 1.0
	var effect_modifiers := weapon.consume_projectile_effects()
	for sequence_index: int in shot_count:
		create_projectile(sequence_index, sequence_damage_scale, effect_modifiers)
		if sequence_index < shot_count - 1 and shot_interval > 0.0:
			await get_tree().create_timer(shot_interval, false).timeout
			if not is_instance_valid(weapon) or weapon.data == null:
				return


func create_projectile(
	sequence_index: int = 0,
	sequence_damage_scale: float = 1.0,
	effect_modifiers: Dictionary = {}
) -> void:
	var pattern := weapon.current_attack_pattern()
	var rotations := _tier_volley_rotations(pattern, sequence_index)
	var resolved_effect_modifiers := (
		effect_modifiers
		if not effect_modifiers.is_empty()
		else weapon.consume_projectile_effects()
	)
	for shot_rotation: float in rotations:
		_create_projectile_at_rotation(
			shot_rotation, resolved_effect_modifiers, sequence_damage_scale
		)


func _tier_volley_rotations(
	pattern: AttackPatternDef, sequence_index: int
) -> PackedFloat32Array:
	var tier_projectile_count := weapon.data.stats.projectile_count
	if tier_projectile_count <= 0:
		return (
			pattern.volley_rotations(weapon.rotation, sequence_index)
			if pattern != null
			else PackedFloat32Array([weapon.rotation])
		)
	var result := PackedFloat32Array()
	var spread := pattern.spread_degrees if pattern != null else 0.0
	for lane in tier_projectile_count:
		var centered := float(lane) - float(tier_projectile_count - 1) * 0.5
		result.append(
			weapon.rotation
			+ deg_to_rad(centered * spread)
			+ float(maxi(0, sequence_index)) * 0.0075
		)
	return result


func _create_projectile_at_rotation(
	shot_rotation: float,
	modifiers: Dictionary = {},
	damage_scale: float = 1.0
) -> void:
	var instance := weapon.data.stats.projectile_scene.instantiate() as Projectile
	get_tree().root.add_child(instance)
	instance.global_position = muzzle.global_position
	var definition := Content.catalog.get_weapon(Content.catalog.get_item_stable_id(weapon.data))
	var pattern := weapon.current_attack_pattern()
	var pattern_modifiers := pattern.projectile_modifiers() if pattern != null else {}
	var velocity := (
		Vector2.RIGHT.rotated(shot_rotation)
		* weapon.data.stats.projectile_speed
		* float(pattern_modifiers.get("speed_multiplier", 1.0))
	)
	var damage := (
		get_damage()
		* float(pattern_modifiers.get("damage_multiplier", 1.0))
		* maxf(0.0, damage_scale)
	)
	var effect_tags: Array[StringName] = []
	if definition != null:
		effect_tags.assign(definition.tags)
	instance.set_projectile(
		velocity,
		damage,
		critical,
		weapon.data.stats.knockback,
		weapon.get_parent(),
		weapon,
		effect_tags,
		int(modifiers.get("pierce", 0)) + int(pattern_modifiers.get("pierce", 0)),
		int(modifiers.get("bounce", 0)) + int(pattern_modifiers.get("bounce", 0)),
		definition.get_presentation_id(Content.catalog.pack_id) if definition != null else &"projectile.enemy",
		pattern_modifiers
	)


func spawn_effect_projectiles(commands: Array[Dictionary]) -> void:
	if weapon.data == null or weapon.data.stats == null or weapon.data.stats.projectile_scene == null:
		return
	var total_count := 0
	for command: Dictionary in commands:
		total_count += maxi(0, int(command.get("count", 0)))
	for index in total_count:
		var centered_index := float(index) - float(total_count - 1) * 0.5
		_create_projectile_at_rotation(weapon.rotation + centered_index * 0.12)
