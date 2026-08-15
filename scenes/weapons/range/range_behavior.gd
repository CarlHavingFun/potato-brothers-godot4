extends WeaponBehavior
class_name RangeBehavior

@onready var muzzle: Marker2D = %Muzzle

func execute_attack() -> void:
	weapon.is_attacking = true
	
	create_projectile()
	
	var tween := create_tween()
	var attack_pos := Vector2(weapon.atk_start_pos.x - weapon.data.stats.recoil, weapon.atk_start_pos.y)
	tween.tween_property(weapon.sprite, "position", attack_pos, weapon.data.stats.recoil_duration)
	tween.tween_property(weapon.sprite, "position", weapon.atk_start_pos, weapon.data.stats.recoil_duration)
	apply_life_steal()
	
	await tween.finished
	weapon.is_attacking = false
	critical = false


func create_projectile() -> void:
	var pattern := weapon.current_attack_pattern()
	var rotations := pattern.shot_rotations(weapon.rotation) if pattern != null else PackedFloat32Array([weapon.rotation])
	var effect_modifiers := weapon.consume_projectile_effects()
	for shot_rotation: float in rotations:
		_create_projectile_at_rotation(shot_rotation, effect_modifiers)


func _create_projectile_at_rotation(shot_rotation: float, modifiers: Dictionary = {}) -> void:
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
	var damage := get_damage() * float(pattern_modifiers.get("damage_multiplier", 1.0))
	instance.set_projectile(
		velocity,
		damage,
		critical,
		weapon.data.stats.knockback,
		weapon.get_parent(),
		weapon,
		definition.tags if definition != null else [],
		int(modifiers.get("pierce", 0)) + int(pattern_modifiers.get("pierce", 0)),
		int(modifiers.get("bounce", 0)) + int(pattern_modifiers.get("bounce", 0)),
		definition.get_presentation_id(Content.catalog.pack_id) if definition != null else &"projectile.enemy"
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
