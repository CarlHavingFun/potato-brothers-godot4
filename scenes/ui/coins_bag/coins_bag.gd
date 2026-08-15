extends HBoxContainer
class_name CoinsBag

@onready var coins: Label = $Coins
@onready var material_icon: TextureRect = $TextureRect


func _ready() -> void:
	material_icon.texture = Presentation.resolve_texture(&"pickup", &"pickup.material")

func _process(delta: float) -> void:
	coins.text = str(Global.current_run.materials if Global.current_run != null else 0)
