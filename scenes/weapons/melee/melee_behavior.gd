extends WeaponBehavior
class_name MeleeBehavior

@export var hitbox: HitboxComponent

func execute_attack() -> void:
	weapon.is_attacking = true
	var pattern := weapon.current_attack_pattern()
	
	var tween := create_tween()
	
	var recoil_pos := Vector2(weapon.atk_start_pos.x - weapon.data.stats.recoil, weapon.atk_start_pos.y)
	tween.tween_property(weapon.sprite, "position", recoil_pos, weapon.data.stats.recoil_duration)
	
	hitbox.enable()
	var definition := Content.catalog.get_weapon(Content.catalog.get_item_stable_id(weapon.data))
	hitbox.setup(
		get_damage() * (pattern.damage_multiplier if pattern != null else 1.0),
		critical,
		weapon.data.stats.knockback,
		weapon.get_parent(),
		weapon,
		definition.tags if definition != null else []
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
	
	apply_life_steal()
	
	tween.tween_property(weapon.sprite, "position", weapon.atk_start_pos, weapon.data.stats.back_duration)
	
	tween.finished.connect(func():
		hitbox.disable()
		weapon.is_attacking = false
		critical = false
		weapon.sprite.rotation = 0.0
	)
