extends GdUnitTestSuite


func after_test() -> void:
	Global.end_run()


func test_fullscreen_shortcuts_are_recognized_and_toggle_saved_state() -> void:
	assert_bool(Global.has_method("is_fullscreen_toggle_event")).is_true()
	assert_bool(Global.has_method("toggle_fullscreen")).is_true()
	if not Global.has_method("is_fullscreen_toggle_event") or not Global.has_method("toggle_fullscreen"):
		return

	var f11 := InputEventKey.new()
	f11.pressed = true
	f11.keycode = KEY_F11
	var alt_enter := InputEventKey.new()
	alt_enter.pressed = true
	alt_enter.keycode = KEY_ENTER
	alt_enter.alt_pressed = true

	assert_bool(Global.call("is_fullscreen_toggle_event", f11)).is_true()
	assert_bool(Global.call("is_fullscreen_toggle_event", alt_enter)).is_true()

	var original := Global.meta_progress.fullscreen
	Global.call("toggle_fullscreen")
	assert_bool(Global.meta_progress.fullscreen).is_equal(not original)
	Global.meta_progress.fullscreen = original
	Global.apply_meta_settings()
	Global.save_progress(Global.current_run != null)


func test_leaving_fullscreen_uses_a_shrinkable_window_size() -> void:
	var original_fullscreen := Global.meta_progress.fullscreen
	var original_resolution := Global.meta_progress.resolution
	Global.meta_progress.fullscreen = true
	Global.meta_progress.resolution = "1920x1080"

	Global.toggle_fullscreen()

	assert_bool(Global.meta_progress.fullscreen).is_false()
	assert_str(Global.meta_progress.resolution).is_equal("1280x720")
	Global.meta_progress.fullscreen = original_fullscreen
	Global.meta_progress.resolution = original_resolution
	Global.apply_meta_settings()
	Global.save_progress(Global.current_run != null)


func test_weapon_detection_resolves_hurtbox_owner_and_starts_auto_attack() -> void:
	var weapon_definition := Content.catalog.get_weapon(&"weapon/pistol")
	assert_object(weapon_definition).is_not_null()
	if weapon_definition == null:
		return

	var holder: Node2D = auto_free(Node2D.new())
	var enemy: Enemy = auto_free(load("res://scenes/unit/enemy/enemy_chaser_slow.tscn").instantiate() as Enemy)
	var weapon: Weapon = auto_free(weapon_definition.tiers[0].scene.instantiate() as Weapon)
	add_child(holder)
	holder.add_child(enemy)
	holder.add_child(weapon)

	assert_bool(weapon.has_method("resolve_enemy_target")).is_true()
	if not weapon.has_method("resolve_enemy_target"):
		return
	var enemy_hurtbox := enemy.get_node("HurtboxComponent") as Area2D
	var range_area := weapon.get_node("RangeArea") as Area2D
	assert_int(range_area.collision_mask).is_equal(8)
	assert_object(weapon.call("resolve_enemy_target", enemy_hurtbox)).is_same(enemy)

	Global.begin_run(42, null, 0)
	Global.current_run.phase = RunPhase.COMBAT
	Global.player = null
	weapon.setup_weapon(weapon_definition.tiers[0])
	weapon._on_range_area_area_entered(enemy_hurtbox)
	weapon._process(0.016)

	assert_object(weapon.closest_target).is_same(enemy)
	assert_bool(weapon.cooldown_timer.is_stopped()).is_false()
	for child: Node in get_tree().root.get_children():
		if child is Projectile:
			child.queue_free()


func test_repeat_enabled_contact_hitbox_ticks_until_exit() -> void:
	var hurtbox: HurtboxComponent = auto_free(HurtboxComponent.new())
	var hitbox: HitboxComponent = auto_free(HitboxComponent.new())
	var hit_count: Array[int] = [0]
	hurtbox.on_damaged.connect(func(_hitbox: HitboxComponent) -> void: hit_count[0] += 1)

	assert_bool(_has_property(hitbox, &"repeat_interval")).is_true()
	if not _has_property(hitbox, &"repeat_interval"):
		return
	hitbox.set("repeat_interval", 0.75)
	hurtbox._on_area_entered(hitbox)
	assert_int(hit_count[0]).is_equal(1)

	hurtbox.call("_physics_process", 0.74)
	assert_int(hit_count[0]).is_equal(1)
	hurtbox.call("_physics_process", 0.02)
	assert_int(hit_count[0]).is_equal(2)
	hurtbox.call("_on_area_exited", hitbox)
	hurtbox.call("_physics_process", 1.0)
	assert_int(hit_count[0]).is_equal(2)


func test_runtime_weapon_resolves_its_typed_attack_pattern() -> void:
	var shotgun := Content.catalog.get_weapon(&"weapon/shotgun")
	var weapon: Weapon = auto_free(shotgun.tiers[0].scene.instantiate() as Weapon)
	add_child(weapon)
	await await_idle_frame()
	weapon.setup_weapon(shotgun.tiers[0])

	assert_object(weapon.current_attack_pattern()).is_same(shotgun.attack_pattern)
	assert_int(weapon.current_attack_pattern().shot_rotations(0.0).size()).is_equal(5)


func test_single_hitbox_does_not_repeat_and_enemy_contact_uses_confirmed_interval() -> void:
	var hurtbox: HurtboxComponent = auto_free(HurtboxComponent.new())
	var hitbox: HitboxComponent = auto_free(HitboxComponent.new())
	var hit_count: Array[int] = [0]
	hurtbox.on_damaged.connect(func(_hitbox: HitboxComponent) -> void: hit_count[0] += 1)

	assert_bool(_has_property(hitbox, &"repeat_interval")).is_true()
	if not _has_property(hitbox, &"repeat_interval"):
		return
	hurtbox._on_area_entered(hitbox)
	hurtbox.call("_physics_process", 1.0)
	assert_int(hit_count[0]).is_equal(1)

	var enemy: Node = auto_free(load("res://scenes/unit/enemy/enemy_chaser_slow.tscn").instantiate())
	var enemy_hitbox := enemy.get_node("HitboxComponent") as HitboxComponent
	assert_float(float(enemy_hitbox.get("repeat_interval"))).is_equal(0.75)


func _has_property(object: Object, property_name: StringName) -> bool:
	for property: Dictionary in object.get_property_list():
		if StringName(property.get("name", "")) == property_name:
			return true
	return false
