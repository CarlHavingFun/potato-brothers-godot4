extends GdUnitTestSuite


const TEST_SETTINGS_ROOT := "user://tests/runtime_regression_settings"
const DEADZONE_ACTIONS: Array[StringName] = [
	&"move_left", &"move_right", &"move_up", &"move_down",
	&"aim_left", &"aim_right", &"aim_up", &"aim_down",
]

var _original_product_settings: ProductSettings
var _original_settings_store: SettingsStore
var _original_settings_initialized: bool
var _original_deadzones: Dictionary = {}


func before_test() -> void:
	_original_product_settings = Global.product_settings.copy()
	_original_settings_store = Global.settings_store
	_original_settings_initialized = Global._settings_initialized
	_original_deadzones.clear()
	for action: StringName in DEADZONE_ACTIONS:
		if InputMap.has_action(action):
			_original_deadzones[action] = InputMap.action_get_deadzone(action)
	_cleanup_settings_files()
	Global.settings_store = SettingsStore.new(TEST_SETTINGS_ROOT)
	Global._settings_initialized = true


func after_test() -> void:
	Global.end_run()
	Global.restore_product_settings(_original_product_settings)
	for raw_action: Variant in _original_deadzones:
		InputMap.action_set_deadzone(
			StringName(raw_action), float(_original_deadzones[raw_action])
		)
	Global.settings_store = _original_settings_store
	Global._settings_initialized = _original_settings_initialized
	_cleanup_settings_files()


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

	var initial := Global.product_settings.copy()
	initial.display_mode = DisplayMode.WINDOWED
	initial.resolution = Vector2i(1600, 900)
	assert_bool(Global.preview_product_settings(initial)).is_true()
	Global.call("toggle_fullscreen")
	assert_int(Global.product_settings.display_mode).is_equal(
		DisplayMode.BORDERLESS_FULLSCREEN
	)
	assert_int(Global.settings_store.load_settings().display_mode).is_equal(
		DisplayMode.BORDERLESS_FULLSCREEN
	)


func test_leaving_fullscreen_uses_a_shrinkable_window_size() -> void:
	var initial := Global.product_settings.copy()
	initial.display_mode = DisplayMode.BORDERLESS_FULLSCREEN
	initial.resolution = Vector2i(1920, 1080)
	assert_bool(Global.preview_product_settings(initial)).is_true()

	Global.toggle_fullscreen()

	assert_int(Global.product_settings.display_mode).is_equal(DisplayMode.WINDOWED)
	assert_object(Global.product_settings.resolution).is_equal(Vector2i(1280, 720))
	var saved := Global.settings_store.load_settings()
	assert_int(saved.display_mode).is_equal(DisplayMode.WINDOWED)
	assert_object(saved.resolution).is_equal(Vector2i(1280, 720))


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


func test_auto_target_uses_tree_only_when_no_enemy_is_in_range() -> void:
	var weapon_definition := Content.catalog.get_weapon(&"weapon/pistol")
	var holder: Node2D = auto_free(Node2D.new())
	var tree: EcologyTree = auto_free(load(
		"res://scenes/arena/ecology/ecology_tree.tscn"
	).instantiate() as EcologyTree)
	var enemy: Enemy = auto_free(load(
		"res://scenes/unit/enemy/enemy_chaser_slow.tscn"
	).instantiate() as Enemy)
	var weapon: Weapon = auto_free(weapon_definition.tiers[0].scene.instantiate() as Weapon)
	add_child(holder)
	holder.add_child(tree)
	holder.add_child(enemy)
	holder.add_child(weapon)
	tree.position = Vector2(20.0, 0.0)
	enemy.position = Vector2(200.0, 0.0)

	var tree_hurtbox := tree.get_node("Hurtbox") as Area2D
	var enemy_hurtbox := enemy.get_node("HurtboxComponent") as Area2D
	weapon._on_range_area_area_entered(tree_hurtbox)
	weapon.update_closest_target()
	assert_object(weapon.closest_target).is_same(tree)

	weapon._on_range_area_area_entered(enemy_hurtbox)
	weapon.update_closest_target()
	assert_object(weapon.closest_target).is_same(enemy)

	weapon._on_range_area_area_exited(enemy_hurtbox)
	weapon.update_closest_target()
	assert_object(weapon.closest_target).is_same(tree)


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
	var m4a4 := Content.catalog.get_weapon(&"weapon/shotgun")
	var weapon: Weapon = auto_free(m4a4.tiers[0].scene.instantiate() as Weapon)
	add_child(weapon)
	await await_idle_frame()
	weapon.setup_weapon(m4a4.tiers[0])

	assert_object(weapon.current_attack_pattern()).is_same(m4a4.attack_pattern)
	assert_int(weapon.current_attack_pattern().kind).is_equal(AttackPatternDef.Kind.BURST)
	assert_int(weapon.current_attack_pattern().burst_count).is_equal(3)


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


func _cleanup_settings_files() -> void:
	var path := "%s/settings_v1.json" % TEST_SETTINGS_ROOT
	for suffix: String in ["", ".tmp", ".bak"]:
		var target := path + suffix
		if FileAccess.file_exists(target):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(target))
