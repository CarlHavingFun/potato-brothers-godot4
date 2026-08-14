extends CharacterBody2D
class_name Unit

@export var stats: UnitStats

@onready var visuals: Node2D = %Visuals
@onready var sprite: Sprite2D = %Sprite
@onready var anim_player: AnimationPlayer = $AnimationPlayer
@onready var health_component: HealthComponent = $HealthComponent
@onready var flash_timer: Timer = $FlashTimer

func _ready() -> void:
	# Scene resources are definitions. Every spawned unit owns an independent
	# runtime copy so upgrades and per-wave scaling cannot mutate another unit or
	# the immutable .tres cached by ResourceLoader.
	if stats != null:
		stats = stats.duplicate(true)
	health_component.setup(stats)


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
		Global.on_create_block_text.emit(self)
		return
	
	set_flash_material()
	health_component.take_damage(received_damage)
	hitbox.display_damage = received_damage
	Global.on_create_damage_text.emit(self, hitbox)


func _on_flash_timer_timeout() -> void:
	sprite.material = null
