extends WeaponBehavior
class_name MeleeBehavior

@export var hitbox: HitboxComponent

func execute_attack() -> void:
	weapon.is_attacking = true
	var pattern := weapon.current_attack_pattern()
	var strike_count := pattern.runtime_shot_count() if pattern != null else 1
	for strike_index: int in strike_count:
		await _execute_strike(pattern)
		if strike_index < strike_count - 1:
			var interval := pattern.runtime_shot_interval()
			if interval > 0.0:
				await get_tree().create_timer(interval, false).timeout
				if not is_instance_valid(weapon) or weapon.data == null:
					return
	weapon.is_attacking = false
	critical = false
	weapon.sprite.rotation = 0.0


func _execute_strike(pattern: AttackPatternDef) -> void:
	var tween := create_tween()
	var recoil_pos := Vector2(weapon.atk_start_pos.x - weapon.data.stats.recoil, weapon.atk_start_pos.y)
	tween.tween_property(weapon.sprite, "position", recoil_pos, weapon.data.stats.recoil_duration)

	hitbox.enable()
	hitbox.repeat_interval = (
		maxf(0.03, pattern.continuous_tick_interval)
		if pattern != null and pattern.kind == AttackPatternDef.Kind.CONTINUOUS
		else 0.0
	)
	var definition := Content.catalog.get_weapon(Content.catalog.get_item_stable_id(weapon.data))
	var effect_tags: Array[StringName] = []
	if definition != null:
		effect_tags.assign(definition.tags)
	hitbox.setup(
		get_damage() * (pattern.damage_multiplier if pattern != null else 1.0),
		critical,
		weapon.data.stats.knockback,
		weapon.get_parent(),
		weapon,
		effect_tags,
		pattern.projectile_modifiers() if pattern != null else {}
	)
	
	var reach_multiplier := pattern.melee_reach_multiplier if pattern != null else 1.0
	var active_multiplier := pattern.active_duration_multiplier if pattern != null else 1.0
	var attack_pos := Vector2(
		weapon.atk_start_pos.x + weapon.data.stats.max_range * reach_multiplier,
		weapon.atk_start_pos.y
	)
	if pattern != null and pattern.kind in [AttackPatternDef.Kind.ARC, AttackPatternDef.Kind.ORBIT, AttackPatternDef.Kind.AREA]:
		weapon.sprite.rotation = deg_to_rad(-pattern.swing_degrees * 0.5)
		tween.tween_property(
			weapon.sprite, "rotation", deg_to_rad(pattern.swing_degrees * 0.5),
			weapon.data.stats.attack_duration * active_multiplier
		)
	tween.tween_property(
		weapon.sprite, "position", attack_pos, weapon.data.stats.attack_duration * active_multiplier
	)
	tween.tween_property(weapon.sprite, "position", weapon.atk_start_pos, weapon.data.stats.back_duration)
	await tween.finished
	hitbox.disable()
	hitbox.repeat_interval = 0.0
	weapon.sprite.rotation = 0.0
