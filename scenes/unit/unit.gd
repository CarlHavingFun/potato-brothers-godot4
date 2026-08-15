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
	active_effect_statuses[status_id] = {
		"remaining": maxf(float(existing.get("remaining", 0.0)), float(command.get("duration", 0.0))),
		"stacks": mini(99, int(existing.get("stacks", 0)) + maxi(1, int(command.get("stacks", 1)))),
		"amount": maxf(float(existing.get("amount", 0.0)), float(command.get("amount", 0.0))),
		"tick_remaining": minf(float(existing.get("tick_remaining", 0.5)), 0.5),
		"source": source if is_instance_valid(source) else existing.get("source"),
	}


func effect_status_stacks(status_id: StringName) -> int:
	return int((active_effect_statuses.get(status_id, {}) as Dictionary).get("stacks", 0))


func status_source(status_id: StringName) -> Object:
	var source: Object = (active_effect_statuses.get(status_id, {}) as Dictionary).get("source")
	return source if is_instance_valid(source) else null


func effect_speed_multiplier() -> float:
	return 0.7 if active_effect_statuses.has(&"slow") else 1.0


func apply_effect_damage(amount: float, source: Object = null) -> void:
	if amount <= 0.0 or health_component.current_health <= 0.0:
		return
	record_damage_source(source)
	set_flash_material()
	health_component.take_damage(amount)


func record_damage_source(source: Object) -> void:
	if is_instance_valid(source):
		_last_damage_source = source


func kill_credit_source(fallback: Object) -> Object:
	return _last_damage_source if is_instance_valid(_last_damage_source) else fallback


func set_flash_material() -> void:
	sprite.material = Global.FLASH_MATERIAL
	flash_timer.start()


func _on_hurtbox_component_on_damaged(hitbox: HitboxComponent) -> void:
	if health_component.current_health <= 0:
		return
	
	var block_chance := stats.block_chance / 100.0
	var received_damage := hitbox.damage
	if self is Player and Global.current_run != null:
		block_chance = Global.combat_resolver.dodge_chance(Global.current_run.player_stats)
		received_damage = Global.combat_resolver.damage_after_armor(
			hitbox.damage,
			Global.current_run.player_stats.get_stat(StatId.ARMOR)
		)
	var blocked := Global.get_chance_sucess(block_chance)
	if blocked:
		if self is Player:
			Global.dispatch_gameplay_event(
				GameplayEvent.Type.DODGED, {"incoming_damage": hitbox.damage}, [], self, hitbox.source
			)
		Global.on_create_block_text.emit(self)
		return
	received_damage *= incoming_damage_multiplier()
	var effect_result: EffectResult
	if self is Player:
		effect_result = Global.dispatch_gameplay_event(
			GameplayEvent.Type.DAMAGED, {"damage": received_damage}, [], hitbox.source, self
		)
	else:
		var gameplay_source := hitbox.gameplay_source if is_instance_valid(hitbox.gameplay_source) else hitbox.source
		effect_result = Global.dispatch_gameplay_event(
			GameplayEvent.Type.CRITICAL_HIT if hitbox.critical else GameplayEvent.Type.HIT,
			{"damage": received_damage}, hitbox.gameplay_tags, gameplay_source, self
		)
	received_damage += effect_result.extra_damage
	record_damage_source(
		hitbox.gameplay_source if is_instance_valid(hitbox.gameplay_source) else hitbox.source
	)
	if hitbox.critical:
		GameplayCues.emit_cue(&"hit.critical", {
			"damage": received_damage,
			"world_position": global_position,
		})
	else:
		GameplayCues.emit_cue(&"hit.normal", {
			"damage": received_damage,
			"world_position": global_position,
		})
	presentation_controller.set_semantic_state(&"hit")
	
	set_flash_material()
	health_component.take_damage(received_damage)
	hitbox.display_damage = received_damage
	Global.on_create_damage_text.emit(self, hitbox)


func incoming_damage_multiplier() -> float:
	return 1.0


func _on_flash_timer_timeout() -> void:
	sprite.material = null
