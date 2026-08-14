extends GdUnitTestSuite


const COMBAT_RESOLVER_PATH := "res://core/services/combat_resolver.gd"


func test_armor_reduces_damage_without_mutating_inputs() -> void:
	assert_bool(ResourceLoader.exists(COMBAT_RESOLVER_PATH)).is_true()
	if not ResourceLoader.exists(COMBAT_RESOLVER_PATH):
		return
	var resolver: RefCounted = load(COMBAT_RESOLVER_PATH).new()

	assert_float(resolver.call("damage_after_armor", 30.0, 15.0)).is_equal_approx(15.0, 0.001)
	assert_float(resolver.call("damage_after_armor", 30.0, 0.0)).is_equal(30.0)
	assert_float(resolver.call("damage_after_armor", 30.0, -15.0)).is_equal_approx(60.0, 0.001)
