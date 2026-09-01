class_name GogoWeaponQualityRules
extends RefCounted


static func is_valid(quality: int) -> bool:
	return quality >= 1 and quality <= 4


static func factor(quality: int) -> float:
	match quality:
		1:
			return 1.0
		2:
			return 1.5
		3:
			return 2.0
		4:
			return 2.5
	return 0.0


static func sale_price(base_price: int, quality: int) -> int:
	if not is_valid(quality):
		return 0
	return maxi(1, roundi(float(base_price) * 0.35 * factor(quality)))


static func label(quality: int) -> String:
	match quality:
		1:
			return "I"
		2:
			return "II"
		3:
			return "III"
		4:
			return "IV"
	return ""


static func color(quality: int) -> Color:
	match quality:
		1:
			return Color("e8e6dc")
		2:
			return Color("4c88df")
		3:
			return Color("c65ce2")
		4:
			return Color("ef6a67")
	return Color.TRANSPARENT
