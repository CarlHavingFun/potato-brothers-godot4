class_name EndlessScalingDef
extends Resource


@export_range(1.0, 2.0, 0.001) var health_growth_per_wave := 1.12
@export_range(1.0, 2.0, 0.001) var damage_growth_per_wave := 1.055
@export_range(0.0, 1.0, 0.001) var density_growth_per_wave := 0.04
@export_range(1.0, 10.0, 0.01) var density_cap := 2.4
@export_range(0.0, 1.0, 0.001) var speed_growth_per_wave := 0.01
@export_range(1.0, 3.0, 0.01) var speed_cap := 1.25
@export_range(0.0, 1.0, 0.001) var material_drop_loss_per_wave := 0.02
@export_range(0.0, 1.0, 0.01) var material_drop_floor := 0.25
@export_range(1.0, 2.0, 0.001) var shop_price_growth_per_wave := 1.06


func endless_wave_index(wave_number: int) -> int:
	return maxi(0, wave_number - 20)


func health_multiplier(wave_number: int) -> float:
	return pow(health_growth_per_wave, endless_wave_index(wave_number))


func damage_multiplier(wave_number: int) -> float:
	return pow(damage_growth_per_wave, endless_wave_index(wave_number))


func density_multiplier(wave_number: int) -> float:
	return minf(density_cap, 1.0 + density_growth_per_wave * endless_wave_index(wave_number))


func speed_multiplier(wave_number: int) -> float:
	return minf(speed_cap, 1.0 + speed_growth_per_wave * endless_wave_index(wave_number))


func material_drop_multiplier(wave_number: int) -> float:
	return maxf(material_drop_floor, 1.0 - material_drop_loss_per_wave * endless_wave_index(wave_number))


func shop_price_multiplier(wave_number: int) -> float:
	return pow(shop_price_growth_per_wave, endless_wave_index(wave_number))
