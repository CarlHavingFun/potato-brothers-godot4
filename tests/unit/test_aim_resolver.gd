extends GdUnitTestSuite


const AIM_RESOLVER_PATH := "res://core/services/aim_resolver.gd"


func test_auto_mode_aims_at_nearest_target_and_requires_a_target_to_fire() -> void:
	assert_bool(ResourceLoader.exists(AIM_RESOLVER_PATH)).is_true()
	if not ResourceLoader.exists(AIM_RESOLVER_PATH):
		return
	var resolver: RefCounted = load(AIM_RESOLVER_PATH).new()

	assert_float(resolver.call(
		"rotation_to_aim", Vector2.ZERO, AimMode.AUTO_TARGET, Vector2(0, 10), Vector2(10, 0), true
	)).is_equal_approx(PI / 2.0, 0.001)
	assert_bool(resolver.call("can_fire", AimMode.AUTO_TARGET, false)).is_false()
	assert_bool(resolver.call("can_fire", AimMode.AUTO_TARGET, true)).is_true()


func test_manual_mode_aims_at_mouse_but_keeps_enemy_presence_fire_guard() -> void:
	assert_bool(ResourceLoader.exists(AIM_RESOLVER_PATH)).is_true()
	if not ResourceLoader.exists(AIM_RESOLVER_PATH):
		return
	var resolver: RefCounted = load(AIM_RESOLVER_PATH).new()

	assert_float(resolver.call(
		"rotation_to_aim", Vector2.ZERO, AimMode.MANUAL_MOUSE, Vector2(0, 10), Vector2(10, 0), true
	)).is_equal_approx(0.0, 0.001)
	assert_bool(resolver.call("can_fire", AimMode.MANUAL_MOUSE, false)).is_false()
	assert_bool(resolver.call("can_fire", AimMode.MANUAL_MOUSE, true)).is_true()


func test_global_aim_mode_rejects_invalid_settings() -> void:
	var original_mode := Global.aim_mode

	assert_bool(Global.set_aim_mode(AimMode.MANUAL_MOUSE)).is_true()
	assert_int(Global.aim_mode).is_equal(AimMode.MANUAL_MOUSE)
	assert_bool(Global.set_aim_mode(99)).is_false()
	assert_int(Global.aim_mode).is_equal(AimMode.MANUAL_MOUSE)

	Global.set_aim_mode(original_mode)


func test_default_pistol_is_registered_as_a_ranged_weapon() -> void:
	var pistol := Content.catalog.get_weapon(&"weapon/pistol")

	assert_object(pistol).is_not_null()
	assert_int(pistol.tiers[0].type).is_equal(ItemWeapon.WeaponType.RANGE)
