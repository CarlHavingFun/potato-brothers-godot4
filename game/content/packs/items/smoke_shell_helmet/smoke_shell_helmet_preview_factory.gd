class_name SmokeShellHelmetPreviewFactory
extends RefCounted


const APPEARANCE_ID: StringName = &"gogobro.preview:appearance/smoke_shell_helmet"
const TARGET_CHARACTER_ID: StringName = &"character.niko:character/niko"
const APPEARANCE_TEXTURE := preload(
	"res://game/assets/gogobro_static_preview/items/smoke_shell_helmet_appearance.png"
)


static func configure_item(definition: GogoItemDefinition) -> void:
	if definition == null:
		return
	definition.icon_asset_id = &"smoke_shell_helmet"
	definition.appearances.assign([create_appearance()])


static func create_appearance() -> GogoAppearanceDefinition:
	var appearance := GogoAppearanceDefinition.new()
	appearance.appearance_id = APPEARANCE_ID
	appearance.target_character_id = TARGET_CHARACTER_ID
	appearance.texture = APPEARANCE_TEXTURE
	appearance.slot = &"head"
	appearance.socket_id = &"head_shell"
	appearance.mode = GogoAppearanceDefinition.Mode.RIGID
	appearance.display_priority = 100
	appearance.depth = 40
	appearance.render_scale = Vector2(0.625, 0.625)
	appearance.rendered_pivot_px = Vector2i(36, 48)
	appearance.local_offset_px = Vector2i.ZERO
	return appearance
