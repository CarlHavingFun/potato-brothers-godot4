class_name GameplayNoticeBus
extends RefCounted


signal notice_emitted(text_id: StringName, args: Array, priority: int)

enum Priority { INFO, IMPORTANT }


func material_pickup(amount: int, bag_bonus: int = 0) -> void:
	if amount <= 0:
		return
	if bag_bonus > 0:
		notice_emitted.emit(
			&"ui.notice.material_bag_bonus",
			[maxi(0, amount - bag_bonus), bag_bonus, amount],
			Priority.IMPORTANT
		)
	else:
		notice_emitted.emit(&"ui.notice.material_pickup", [amount], Priority.INFO)


func materials_banked(amount: int, first_time := false) -> void:
	if amount > 0:
		notice_emitted.emit(
			&"ui.notice.materials_banked_first" if first_time else &"ui.notice.materials_banked",
			[amount],
			Priority.IMPORTANT
		)
