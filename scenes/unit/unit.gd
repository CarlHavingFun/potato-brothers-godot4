extends CharacterBody2D
class_name Unit

@export var stats: UnitStats

@onready var visuals: Node2D = %Visuals
@onready var sprite: Sprite2D = %Sprite
@onready var anim_player: AnimationPlayer = $AnimationPlayer
@onready var health_component: HealthComponent = $HealthComponent
@onready var flash_timer: Timer = $FlashTimer

var active_effect_statuses: Dictionary = {}
var status_immunities: Array[StringName] = []
var presentation_controller: PresentationController
var _last_damage_source: Object

func _ready() -> void:
	presentation_controller = PresentationController.new()
	presentation_controller.name = "PresentationController"
	presentation_controller.animation_player = anim_player
	add_child(presentation_controller)
	# Scene resources are definitions. Every spawned unit owns an independent
	# runtime copy so upgrades and per-wave scaling cannot mutate another unit or
	# the immutable .tres cached by ResourceLoader.
	if stats != null:
		stats = stats.duplicate(true)
	health_component.setup(stats)
	refresh_presentation_settings()


func configure_presentation(category: StringName, presentation_id: StringName) -> void:
	presentation_controller.configure(sprite, category, presentation_id, sprite.texture)
	var shadow := get_node_or_null("Visuals/Shadow") as Sprite2D
	if shadow != null:
		shadow.texture = Presentation.resolve_texture(
			&"pickup", &"pickup.shadow", shadow.texture
		)


func _physics_process(delta: float) -> void:
	for raw_status_id: Variant in active_effect_statuses.keys():
		var status_id := StringName(str(raw_status_id))
		var state := active_effect_statuses.get(status_id, {}) as Dictionary
		state["remaining"] = maxf(0.0, float(state.get("remaining", 0.0)) - delta)
		if status_id == &"burn":
			state["tick_remaining"] = float(state.get("tick_remaining", 0.5)) - delta
			while float(state["tick_remaining"]) <= 0.0 and float(state["remaining"]) > 0.0:
				apply_effect_damage(
					float(state.get("amount", 0.0)) * maxi(1, int(state.get("stacks", 1))),
					status_source(status_id)
				)
				state["tick_remaining"] = float(state["tick_remaining"]) + 0.5
		if float(state["remaining"]) <= 0.0:
			active_effect_statuses.erase(status_id)
		else:
			active_effect_statuses[status_id] = state


func apply_effect_status(command: Dictionary, source: Object = null) -> void:
	var status_id := StringName(str(command.get("status_id", "")))
	if status_id.is_empty() or status_id in status_immunities:
		return
	var existing := active_effect_statuses.get(status_id, {}) as Dictionary
	var incoming_stacks := maxi(1, int(command.get("stacks", 1)))
	var next_stacks := (
		maxi(int(existing.get("stacks", 0)), incoming_stacks)
		if bool(command.get("refresh_only", false))
		else int(existing.get("stacks", 0)) + incoming_stacks
	)
	active_effect_statuses[status_id] = {
		"remaining": maxf(float(existing.get("remaining", 0.0)), float(command.get("duration", 0.0))),
		"stacks": mini(99, next_stacks),
		"amount": maxf(float(existing.get("amount", 0.0)), float(command.get("amount", 0.0))),
		"speed_multiplier": minf(
			float(existing.get("speed_multiplier", 1.0)),
			clampf(float(command.get("speed_multiplier", 1.0)), 0.1, 1.0)
		),
		"interrupt_ranged": bool(existing.get("interrupt_ranged", false)) or bool(
			command.get("interrupt_ranged", false)
		),
		"tick_remaining": minf(float(existing.get("tick_remaining", 0.5)), 0.5),
		"source": source if is_instance_valid(source) else existing.get("source"),
	}


func effect_status_stacks(status_id: StringName) -> int:
	return int((active_effect_statuses.get(status_id, {}) as Dictionary).get("stacks", 0))


func status_source(status_id: StringName) -> Object:
	var source: Object = (active_effect_statuses.get(status_id, {}) as Dictionary).get("source")
	return source if is_instance_valid(source) else null


func effect_speed_multiplier() -> float:
	var multiplier := 1.0
	for status_id: StringName in [&"slow", &"smoke", &"blind"]:
		if not active_effect_statuses.has(status_id):
			continue
		var state := active_effect_statuses.get(status_id, {}) as Dictionary
		var fallback := 0.7 if status_id == &"slow" else 0.75
		multiplier = minf(
			multiplier,
			clampf(float(state.get("speed_multiplier", fallback)), 0.1, 1.0)
		)
	return multiplier


func is_ranged_attack_interrupted() -> bool:
	for raw_status_id: Variant in active_effect_statuses.keys():
		var state := active_effect_statuses.get(raw_status_id, {}) as Dictionary
		if bool(state.get("interrupt_ranged", false)):
			return true
	return active_effect_statuses.has(&"blind")


func apply_effect_damage(amount: float, source: Object = null) -> void:
	if amount <= 0.0 or health_component.current_health <= 0.0:
		return
	if self is Player:
		receive_typed_damage(
			amount,
			source,
			[&"effect"] as Array[StringName]
		)
		return
	record_damage_source(source)
	set_flash_material()
	health_component.take_damage(amount)


func receive_typed_damage(
	amount: float,
	source: Object = null,
	gameplay_tags: Array[StringName] = [],
	critical := false
) -> void:
	if amount <= 0.0 or health_component.current_health <= 0.0:
		return
	var source_node := source as Node2D if is_instance_valid(source) else null
	var scripted_hit := HitboxComponent.new()
	scripted_hit.setup(
		amount,
		critical,
		0.0,
		source_node,
		source,
		gameplay_tags
	)
	_on_hurtbox_component_on_damaged(scripted_hit)
	scripted_hit.free()


func record_damage_source(source: Object) -> void:
	if is_instance_valid(source):
		_last_damage_source = source


func kill_credit_source(fallback: Object) -> Object:
	return _last_damage_source if is_instance_valid(_last_damage_source) else fallback


func set_flash_material(reduce_flashes_override: Variant = null) -> void:
	var reduce_flashes := (
		bool(reduce_flashes_override)
		if reduce_flashes_override is bool
		else GameplayCuePresenter.runtime_bool(&"reduce_flashes", false)
	)
	if reduce_flashes:
		sprite.material = null
		flash_timer.stop()
		return
	sprite.material = Global.FLASH_MATERIAL
	flash_timer.start()


func refresh_presentation_settings() -> void:
	var health_bar := get_node_or_null("HealthBar") as Control
	if health_bar == null:
		return
	var is_player_unit := self is Player
	var is_boss_unit := (
		self is Enemy
		and (self as Enemy).definition != null
		and &"boss" in (self as Enemy).definition.tags
	)
	health_bar.visible = health_bar_visible_for(
		is_player_unit,
		is_boss_unit,
		GameplayCuePresenter.runtime_bool(&"show_player_health_bar", true),
		GameplayCuePresenter.runtime_bool(&"show_boss_health_bar", true)
	)


static func health_bar_visible_for(
	is_player_unit: bool,
	is_boss_unit: bool,
	show_player_health_bar: bool,
	show_boss_health_bar: bool
) -> bool:
	if is_player_unit:
		return show_player_health_bar
	if is_boss_unit:
		return show_boss_health_bar
	return true


func _on_hurtbox_component_on_damaged(hitbox: HitboxComponent) -> void:
	if hitbox == null or health_component.current_health <= 0 or is_damage_invulnerable():
		return

	var request := HitRequest.from_hitbox(hitbox, self)
	request.dodge_chance = stats.block_chance / 100.0
	request.damage_multiplier = incoming_damage_multiplier()
	if self is Player and Global.current_run != null:
		request.dodge_chance = Global.combat_resolver.dodge_chance(
			Global.current_run.player_stats,
			Global.current_run.dodge_cap_override
		)
		request.armor = Global.current_run.player_stats.get_stat(StatId.ARMOR)
	var hit_result := HitResolver.new(Global.combat_resolver).resolve(request)
	if hit_result.dodged:
		if self is Player:
			Global.dispatch_gameplay_event(
				GameplayEvent.Type.DODGED, {"incoming_damage": hitbox.damage}, [], self, hitbox.source
			)
		Global.on_create_block_text.emit(self)
		return
	if not hit_result.landed:
		return

	var effect_result: EffectResult
	if self is Player:
		effect_result = Global.dispatch_gameplay_event(
			GameplayEvent.Type.DAMAGED, {"damage": hit_result.damage}, [], hitbox.source, self
		)
	else:
		effect_result = Global.dispatch_gameplay_event(
			GameplayEvent.Type.CRITICAL_HIT if hitbox.critical else GameplayEvent.Type.HIT,
			{"damage": hit_result.damage}, hitbox.gameplay_tags, hit_result.gameplay_source, self
		)
	hit_result.apply_extra_damage(effect_result.extra_damage)
	record_damage_source(hit_result.gameplay_source)
	if hitbox.critical:
		GameplayCues.emit_cue(&"hit.critical", {
			"damage": hit_result.damage,
			"world_position": global_position,
		})
	else:
		GameplayCues.emit_cue(&"hit.normal", {
			"damage": hit_result.damage,
			"world_position": global_position,
		})
	presentation_controller.set_semantic_state(&"hit")

	set_flash_material()
	var health_before := health_component.current_health
	health_component.take_damage(hit_result.damage)
	hit_result.record_health_change(health_before, health_component.current_health)
	hitbox.display_damage = hit_result.damage
	Global.on_create_damage_text.emit(self, hitbox)
	hitbox.confirm_hit(hit_result)


func incoming_damage_multiplier() -> float:
	return 1.0


func is_damage_invulnerable() -> bool:
	return false


func _on_flash_timer_timeout() -> void:
	sprite.material = null
