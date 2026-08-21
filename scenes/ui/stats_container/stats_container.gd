extends Panel
class_name StatsContainer


const PERCENT_STATS := {
	StatId.LIFE_STEAL: true,
	StatId.DAMAGE: true,
	StatId.ATTACK_SPEED: true,
	StatId.CRITICAL_CHANCE: true,
	StatId.DODGE: true,
	StatId.MOVE_SPEED: true,
}
const POSITIVE_COLOR := Color("72e04d")
const NEGATIVE_COLOR := Color("e54a45")
const NEUTRAL_COLOR := Color("f2f2f2")

@onready var stats_grid: GridContainer = %StatsGrid
@onready var title_label: Label = $MarginContainer/VBoxContainer/Title
@onready var level_icon: TextureRect = $MarginContainer/VBoxContainer/LevelRow/Icon
@onready var level_name: Label = $MarginContainer/VBoxContainer/LevelRow/Name
@onready var level_value: Label = $MarginContainer/VBoxContainer/LevelRow/Value

var _title_labels: Dictionary = {}
var _value_labels: Dictionary = {}
var _icon_rects: Dictionary = {}
var _last_locale := ""


func _ready() -> void:
	_build_stat_rows()
	level_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	refresh_stats()


func _process(_delta: float) -> void:
	refresh_stats()


func refresh_stats() -> void:
	if _last_locale != TranslationServer.get_locale():
		_refresh_titles()
	level_value.text = str(Global.current_run.level) if Global.current_run != null else "—"
	level_icon.texture = _resolve_level_icon()
	for stat_id in StatId.size():
		var value_label := _value_labels.get(stat_id) as Label
		var title := _title_labels.get(stat_id) as Label
		if value_label == null:
			continue
		if Global.current_run == null:
			value_label.text = "—"
			value_label.add_theme_color_override("font_color", NEUTRAL_COLOR)
			if title != null:
				title.add_theme_color_override("font_color", NEUTRAL_COLOR)
			continue
		var stat_value := Global.get_stat_value_by_id(stat_id)
		var value_color := _value_color(stat_value)
		value_label.text = _format_stat_value(stat_id, stat_value)
		value_label.add_theme_color_override("font_color", value_color)
		if title != null:
			title.add_theme_color_override("font_color", value_color)


func stat_row_count() -> int:
	return _value_labels.size()


func title_text_for_stat(stat_id: int) -> String:
	var label := _title_labels.get(stat_id) as Label
	return label.text if label != null else ""


func value_text_for_stat(stat_id: int) -> String:
	var label := _value_labels.get(stat_id) as Label
	return label.text if label != null else ""


func level_value_text() -> String:
	return level_value.text


func icon_texture_for_stat(stat_id: int) -> Texture2D:
	var icon := _icon_rects.get(stat_id) as TextureRect
	return icon.texture if icon != null else null


func value_color_for_stat(stat_id: int) -> Color:
	var label := _value_labels.get(stat_id) as Label
	return label.get_theme_color("font_color") if label != null else NEUTRAL_COLOR


func _build_stat_rows() -> void:
	for child: Node in stats_grid.get_children():
		child.queue_free()
	_title_labels.clear()
	_value_labels.clear()
	_icon_rects.clear()
	for stat_id in StatId.size():
		var row := HBoxContainer.new()
		row.name = "Stat_%s" % StatId.key(stat_id)
		row.custom_minimum_size = Vector2(0.0, 32.0)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 8)
		stats_grid.add_child(row)

		var icon := TextureRect.new()
		icon.name = "Icon"
		icon.custom_minimum_size = Vector2(26.0, 26.0)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.texture = _resolve_stat_icon(stat_id)
		row.add_child(icon)

		var title := Label.new()
		title.name = "Title"
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.add_theme_font_size_override("font_size", 18)
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(title)

		var value := Label.new()
		value.name = "Value"
		value.custom_minimum_size.x = 58.0
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.add_theme_font_size_override("font_size", 18)
		value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(value)

		_title_labels[stat_id] = title
		_value_labels[stat_id] = value
		_icon_rects[stat_id] = icon
	_refresh_titles()


func _refresh_titles() -> void:
	_last_locale = TranslationServer.get_locale()
	title_label.text = Global.translate_text(&"ui.stats.title", "Stats")
	level_name.text = Global.translate_text(&"ui.stats.current_level", "Current Level")
	for stat_id in StatId.size():
		var title := _title_labels.get(stat_id) as Label
		if title == null:
			continue
		var stat_key := StatId.key(stat_id)
		title.text = Global.translate_text(
			StringName("stat.%s" % stat_key),
			stat_key.replace("_", " ").capitalize()
		)
		title.tooltip_text = title.text


func _format_stat_value(stat_id: int, value: float) -> String:
	var absolute_value := absf(value)
	var number := (
		str(roundi(value))
		if is_equal_approx(absolute_value, roundf(absolute_value))
		else "%.1f" % value
	)
	if PERCENT_STATS.has(stat_id):
		return "%s%%" % number
	return number


func _value_color(value: float) -> Color:
	if value > 0.0:
		return POSITIVE_COLOR
	if value < 0.0:
		return NEGATIVE_COLOR
	return NEUTRAL_COLOR


func _resolve_stat_icon(stat_id: int) -> Texture2D:
	for item: ItemUpgrade in Content.catalog.get_upgrade_items():
		var definition := Content.catalog.get_upgrade_definition_for_item(item)
		if (
			definition != null
			and definition.quality == Global.UpgradeTier.COMMON
			and definition.stat_id == stat_id
		):
			return Presentation.resolve_content_texture(
				definition, item.item_icon, &"icon", Content.catalog.pack_id
			)
	return Presentation.resolve_texture(&"ui", &"ui.fallback")


func _resolve_level_icon() -> Texture2D:
	if Global.current_run == null or Global.current_run.character_id.is_empty():
		return Presentation.resolve_texture(&"ui", &"ui.fallback")
	var definition := Content.catalog.get_character(Global.current_run.character_id)
	return Presentation.resolve_content_texture(
		definition,
		definition.icon if definition != null else null,
		&"icon",
		Content.catalog.pack_id
	)
