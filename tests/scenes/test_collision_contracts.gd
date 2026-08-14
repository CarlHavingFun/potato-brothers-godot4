extends GdUnitTestSuite


const PLAYER := 1
const ENEMY := 2
const HOSTILE_ATTACK := 4
const ENEMY_HURTBOX := 8
const FRIENDLY_ATTACK := 16
const PLAYER_HURTBOX := 32
const PICKUP := 64
const WORLD := 128


func test_collision_layers_are_named_and_do_not_overlap_roles() -> void:
	var expected := {
		1: "player",
		2: "enemy",
		3: "hostile_attack",
		4: "enemy_hurtbox",
		5: "friendly_attack",
		6: "player_hurtbox",
		7: "pickup",
		8: "world",
	}
	for layer: int in expected:
		assert_str(ProjectSettings.get_setting("layer_names/2d_physics/layer_%d" % layer, "")).is_equal(expected[layer])


func test_player_enemy_attack_and_pickup_scenes_match_the_collision_matrix() -> void:
	var player: CollisionObject2D = auto_free(load("res://scenes/unit/players/player_well_rounded.tscn").instantiate())
	var enemy: CollisionObject2D = auto_free(load("res://scenes/unit/enemy/enemy_chaser_slow.tscn").instantiate())
	var friendly_projectile: Node2D = auto_free(load("res://scenes/projectiles/projectile_pistol.tscn").instantiate())
	var hostile_projectile: Node2D = auto_free(load("res://scenes/projectiles/projectile_enemy.tscn").instantiate())
	var pickup: Area2D = auto_free(load("res://scenes/coins/coins.tscn").instantiate())
	var friendly: Area2D = friendly_projectile.get_node("HitboxComponent")
	var hostile: Area2D = hostile_projectile.get_node("HitboxComponent")

	assert_bool(player is CharacterBody2D).is_true()
	assert_int(player.collision_layer).is_equal(PLAYER)
	assert_int(player.collision_mask).is_equal(ENEMY | WORLD)
	assert_int((player.get_node("HurtboxComponent") as Area2D).collision_layer).is_equal(PLAYER_HURTBOX)
	assert_bool(enemy is CharacterBody2D).is_true()
	assert_int(enemy.collision_layer).is_equal(ENEMY)
	assert_int(enemy.collision_mask).is_equal(PLAYER | WORLD)
	assert_int((enemy.get_node("HurtboxComponent") as Area2D).collision_layer).is_equal(ENEMY_HURTBOX)
	assert_int(friendly.collision_layer).is_equal(FRIENDLY_ATTACK)
	assert_int(friendly.collision_mask).is_equal(ENEMY_HURTBOX)
	assert_int(hostile.collision_layer).is_equal(HOSTILE_ATTACK)
	assert_int(hostile.collision_mask).is_equal(PLAYER_HURTBOX)
	assert_int(pickup.collision_layer).is_equal(PICKUP)
	assert_int(pickup.collision_mask).is_equal(PLAYER)


func test_arena_has_world_collision_boundaries() -> void:
	var arena: Node = auto_free(load("res://scenes/arena/arena.tscn").instantiate())
	var world: StaticBody2D = arena.get_node("WorldBoundaries")
	assert_object(world).is_not_null()
	assert_int(world.collision_layer).is_equal(WORLD)
	assert_int(world.collision_mask).is_equal(PLAYER | ENEMY)
	assert_int(world.get_child_count()).is_equal(4)
