class_name GogoStatIconPresenter
extends RefCounted


const ICON_ATLAS := preload("res://game/assets/ui/stat_icon_kit.png")
const ICON_CELL_SIZE := Vector2i(64, 64)
const ICON_COLUMNS := 4
const STAT_ICON_INDEX := {
	&"max_health": 0,
	&"health_regen": 1,
	&"damage_multiplier": 2,
	&"melee_damage": 3,
	&"ranged_damage": 4,
	&"attack_speed": 5,
	&"attack_speed_multiplier": 6,
	&"critical_chance": 7,
	&"attack_range_bonus": 8,
	&"armor": 9,
	&"dodge": 10,
	&"movement_speed": 11,
	&"movement_speed_multiplier": 12,
	&"pickup_range": 13,
	&"economy": 14,
	&"explosion_damage_multiplier": 15,
	# These combat-specific stats intentionally reuse the closest physical
	# glyphs in the fixed 4x4 atlas instead of rendering text-only rows.
	&"counter_strafe_brake": 11,
	&"moving_recoil_control": 4,
}


static func texture_for(stat_key: StringName) -> Texture2D:
	if not STAT_ICON_INDEX.has(stat_key):
		return null
	var index := int(STAT_ICON_INDEX[stat_key])
	var texture := AtlasTexture.new()
	texture.atlas = ICON_ATLAS
	texture.region = Rect2(
		Vector2(
			float(index % ICON_COLUMNS) * ICON_CELL_SIZE.x,
			float(floori(float(index) / float(ICON_COLUMNS))) * ICON_CELL_SIZE.y
		),
		Vector2(ICON_CELL_SIZE)
	)
	return texture


static func build_icon(
	stat_key: StringName,
	display_size: Vector2 = Vector2(18, 18)
) -> TextureRect:
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.texture = texture_for(stat_key)
	icon.custom_minimum_size = display_size if icon.texture != null else Vector2.ZERO
	icon.size = icon.custom_minimum_size
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.visible = icon.texture != null
	icon.set_meta(&"stat_key", stat_key)
	return icon
