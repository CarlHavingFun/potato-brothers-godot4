extends Area2D
class_name HurtboxComponent

signal on_damaged(hitbox: HitboxComponent)

var repeating_hitboxes: Dictionary = {}


func _ready() -> void:
	set_physics_process(false)


func _on_area_entered(area: Area2D) -> void:
	if area is HitboxComponent:
		var hitbox := area as HitboxComponent
		on_damaged.emit(hitbox)
		if hitbox.repeat_interval > 0.0:
			repeating_hitboxes[hitbox.get_instance_id()] = {
				"hitbox": weakref(hitbox),
				"time_left": hitbox.repeat_interval,
			}
			set_physics_process(true)


func _on_area_exited(area: Area2D) -> void:
	if area is not HitboxComponent:
		return
	repeating_hitboxes.erase(area.get_instance_id())
	if repeating_hitboxes.is_empty():
		set_physics_process(false)


func _physics_process(delta: float) -> void:
	for instance_id: int in repeating_hitboxes.keys():
		var state := repeating_hitboxes.get(instance_id, {}) as Dictionary
		var hitbox_ref := state.get("hitbox") as WeakRef
		var hitbox := hitbox_ref.get_ref() as HitboxComponent if hitbox_ref != null else null
		if not is_instance_valid(hitbox) or hitbox.repeat_interval <= 0.0:
			repeating_hitboxes.erase(instance_id)
			continue

		var time_left := float(state.get("time_left", hitbox.repeat_interval)) - delta
		while time_left <= 0.0:
			on_damaged.emit(hitbox)
			time_left += hitbox.repeat_interval
		state["time_left"] = time_left
		repeating_hitboxes[instance_id] = state

	if repeating_hitboxes.is_empty():
		set_physics_process(false)
