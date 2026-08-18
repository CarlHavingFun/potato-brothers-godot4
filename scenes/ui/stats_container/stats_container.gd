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

@onready var stats_grid: GridContainer = %StatsGrid

var _title_labels: Dictionary = {}
var _value_labels: Dictionary = {}
var _last_locale := ""


func _ready() -> void:
	_build_stat_rows()
	refresh_stats()


func _process(_delta: float) -> void:
	refresh_stats()


func refresh_stats() -> void:
	if _last_locale != TranslationServer.get_locale():
		_refresh_titles()
	for stat_id in StatId.size():
		var value_label := _value_labels.get(stat_id) as Label
		if value_label == null:
			continue
		value_label.text = (
			_format_stat_value(stat_id, Global.get_stat_value_by_id(stat_id))
			if Global.current_run != null
			else "—"
		)


func stat_row_count() -> int:
	return _value_labels.size()


func title_text_for_stat(stat_id: int) -> String:
	var label := _title_labels.get(stat_id) as Label
	return label.text if label != null else ""


func value_text_for_stat(stat_id: int) -> String:
	var label := _value_labels.get(stat_id) as Label
	return label.text if label != null else ""


func _build_stat_rows() -> void:
	for child: Node in stats_grid.get_children():
		child.queue_free()
	_title_labels.clear()
	_value_labels.clear()
	for stat_id in StatId.size():
		var card := PanelContainer.new()
		card.name = "Stat_%s" % StatId.key(stat_id)
		card.custom_minimum_size = Vector2(210.0, 48.0)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_theme_stylebox_override("panel", _stat_card_style())
		stats_grid.add_child(card)

		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 10)
		margin.add_theme_constant_override("margin_top", 6)
		margin.add_theme_constant_override("margin_right", 10)
		margin.add_theme_constant_override("margin_bottom", 6)
		card.add_child(margin)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		margin.add_child(row)

		var title := Label.new()
		title.name = "Title"
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.add_theme_font_size_override("font_size", 17)
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(title)

		var value := Label.new()
		value.name = "Value"
		value.custom_minimum_size.x = 58.0
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.add_theme_font_size_override("font_size", 18)
		row.add_child(value)

		_title_labels[stat_id] = title
		_value_labels[stat_id] = value
	_refresh_titles()


func _refresh_titles() -> void:
	_last_locale = TranslationServer.get_locale()
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


func _stat_card_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.71, 0.88, 0.24)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	return style
