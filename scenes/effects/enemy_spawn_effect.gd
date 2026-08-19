extends Sprite2D
class_name EnemySpawnEffect

@onready var anim_player: AnimationPlayer = $AnimationPlayer


func _ready() -> void:
	texture = Presentation.resolve_texture(&"scene", &"scene.enemy.spawn", null, &"background")
