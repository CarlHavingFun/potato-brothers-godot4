extends Node2D
class_name Weapon

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision: CollisionShape2D = %CollisionShape2D
@onready var cooldown_timer: Timer = $CooldownTimer
@onready var weapon_behavior: WeaponBehavior = $WeaponBehavior

var data: ItemWeapon
var is_attacking := false
var atk_start_pos: Vector2
var targets: Array[Enemy]
var closest_target: Enemy
var weapon_spread: float
var aim_resolver := AimResolver.new()
var pending_pierce := 0
var pending_bounce := 0
var presentation_controller: PresentationController

func _ready() -> void:
	presentation_controller = PresentationController.new()
	presentation_controller.name = "PresentationController"
	add_child(presentation_controller)
	atk_start_pos = sprite.position


func _process(delta: float) -> void:
	if not Global.is_combat_active(): return
	
	if not is_attacking:
		prune_targets()
		if targets.size() > 0:
			update_closest_target()
		else:
			closest_target = null
	
	presentation_controller.set_semantic_state(&"attack" if is_attacking else &"idle")
	rotate_to_target()
	update_visuals()
	
	if can_use_weapon():
		use_weapon()


func setup_weapon(data: ItemWeapon) -> void:
	self.data = data
	var definition := Content.catalog.get_weapon(Content.catalog.get_item_stable_id(data))
	if definition != null:
		presentation_controller.configure(
			sprite,
			&"weapon",
			definition.get_presentation_id(Content.catalog.pack_id),
			sprite.texture
		)
	presentation_controller.set_semantic_state(&"idle")
	collision.shape = collision.shape.duplicate()
	collision.shape.radius = Global.combat_resolver.attack_range(
		data.stats.max_range, Global.current_run.player_stats
	) if Global.current_run != null and Global.combat_resolver != null else data.stats.max_range
	apply_tier_outline()


func use_weapon() -> void:
	calculate_spread()
	var definition := Content.catalog.get_weapon(Content.catalog.get_item_stable_id(data))
	Global.dispatch_gameplay_event(
		GameplayEvent.Type.ATTACKED,
		{"base_damage": data.stats.damage},
		definition.tags if definition != null else [],
		self
	)
	GameplayCues.emit_cue(&"weapon.fire", {
		"presentation_id": definition.get_presentation_id(Content.catalog.pack_id) if definition != null else &"",
		"world_position": global_position,
	})
	weapon_behavior.execute_attack()
	var base_cooldown := Global.combat_resolver.attack_cooldown(
		data.stats.cooldown, Global.current_run.player_stats
	) if Global.current_run != null and Global.combat_resolver != null else data.stats.cooldown
	var pattern := current_attack_pattern()
	cooldown_timer.wait_time = base_cooldown * (
		pattern.cooldown_multiplier if pattern != null else 1.0
	)
	cooldown_timer.start()


func current_attack_pattern() -> AttackPatternDef:
	if data == null:
		return null
	var definition := Content.catalog.get_weapon(Content.catalog.get_item_stable_id(data))
	return definition.attack_pattern if definition != null else null


func apply_attack_effects(result: EffectResult) -> void:
	pending_pierce += maxi(0, result.pierce)
	pending_bounce += maxi(0, result.bounce)


func consume_projectile_effects() -> Dictionary:
	var result := {"pierce": pending_pierce, "bounce": pending_bounce}
	pending_pierce = 0
	pending_bounce = 0
	return result


func spawn_effect_projectiles(commands: Array[Dictionary]) -> void:
	if weapon_behavior != null and weapon_behavior.has_method("spawn_effect_projectiles"):
		weapon_behavior.call("spawn_effect_projectiles", commands)


func rotate_to_target() -> void:
	if is_attacking:
		rotation = get_custom_rotation_to_target()
	else:
		rotation = get_rotation_to_target()


func get_custom_rotation_to_target() -> float:
	if Global.aim_mode == AimMode.MANUAL_MOUSE:
		return aim_resolver.rotation_to_aim(
			global_position, Global.aim_mode, Vector2.ZERO, _manual_aim_position(), false
		) + weapon_spread
	if not closest_target or not is_instance_valid(closest_target):
		return rotation
	
	var rot := global_position.direction_to(closest_target.global_position).angle()
	return rot + weapon_spread


func get_rotation_to_target() -> float:
	if Global.aim_mode == AimMode.MANUAL_MOUSE:
		return aim_resolver.rotation_to_aim(
			global_position, Global.aim_mode, Vector2.ZERO, _manual_aim_position(), false
		)
	if targets.size() == 0:
		return get_idle_rotation()
	
	var rot := global_position.direction_to(closest_target.global_position).angle()
	return rot


func get_idle_rotation() -> float:
	if is_instance_valid(Global.player) and Global.player.is_facing_right():
		return 0
	else:
		return PI


func _manual_aim_position() -> Vector2:
	var stick := Input.get_vector(&"aim_left", &"aim_right", &"aim_up", &"aim_down")
	if stick.length() >= 0.25:
		return global_position + stick.normalized() * 1000.0
	return get_global_mouse_position()


func update_visuals() -> void:
	if abs(rotation) > PI / 2:
		sprite.scale.y = -0.5
	else:
		sprite.scale.y = 0.5


func calculate_spread() -> void:
	weapon_spread = randf_range(-1 + data.stats.accuracy, 1 - data.stats.accuracy)
	rotation += weapon_spread


func update_closest_target() -> void:
	closest_target = get_closest_target()


func get_closest_target() -> Enemy:
	if targets.size() == 0:
		return null
	
	var closest_enemy := targets[0]
	var closest_distance := global_position.distance_to(closest_enemy.global_position)
	
	for i in range(1, targets.size()):
		var target: Enemy = targets[i]
		var distance := global_position.distance_to(target.global_position)
		
		if distance < closest_distance:
			closest_enemy = target
			closest_distance = distance
	
	return closest_enemy


func prune_targets() -> void:
	for index: int in range(targets.size() - 1, -1, -1):
		var target := targets[index]
		if not is_instance_valid(target) or not target.is_inside_tree():
			targets.remove_at(index)
	if not is_instance_valid(closest_target) or not closest_target in targets:
		closest_target = null


func resolve_enemy_target(area: Area2D) -> Enemy:
	var current: Node = area
	while current != null:
		if current is Enemy:
			return current as Enemy
		current = current.get_parent()
	return null


func can_use_weapon() -> bool:
	return cooldown_timer.is_stopped() and aim_resolver.can_fire(
		Global.aim_mode, closest_target != null and is_instance_valid(closest_target)
	)


func apply_tier_outline() -> void:
	if data.item_tier == Global.UpgradeTier.COMMON:
		sprite.material = null
		return
	
	var outline_color := Global.TIER_COLORS[data.item_tier]
	sprite.material.set_shader_parameter("outline_color", outline_color)


func _on_range_area_area_entered(area: Area2D) -> void:
	var target := resolve_enemy_target(area)
	if target != null and not target in targets:
		targets.push_back(target)


func _on_range_area_area_exited(area: Area2D) -> void:
	var target := resolve_enemy_target(area)
	if target != null:
		targets.erase(target)
	if targets.size() == 0:
		closest_target = null
