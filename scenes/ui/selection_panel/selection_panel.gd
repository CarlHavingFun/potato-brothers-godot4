extends Panel
class_name SelectionPanel

signal on_selection_completed

@onready var player_container: HBoxContainer = %PlayerContainer
@onready var weapon_container: HBoxContainer = %WeaponContainer

@onready var player_icon: TextureRect = %PlayerIcon
@onready var player_name: Label = %PlayerName
@onready var player_title: Label = %PlayerTitle
@onready var player_description: RichTextLabel = %PlayerDescription

var player_button_group := ButtonGroup.new()
var weapon_button_group := ButtonGroup.new()


func _ready() -> void:
	for child in player_container.get_children(): child.queue_free()
	for child in weapon_container.get_children(): child.queue_free()
	
	show_player_info(false)
	load_players()
	load_weapons()


func load_players() -> void:
	var characters: Array[CharacterDef] = Content.catalog.get_characters()
	if characters.is_empty():
		return
	
	for character: CharacterDef in characters:
		var card: SelectionCard = Global.SELECTION_CARD_SCENE.instantiate()
		card.button_group = player_button_group
		card.pressed.connect(_on_player_selected.bind(character, card))
		player_container.add_child(card)
		card.set_icon(Presentation.resolve_texture(
			&"character", character.get_presentation_id(Content.catalog.pack_id), character.stats.icon
		))


func load_weapons() -> void:
	var weapons: Array[WeaponDef] = Content.catalog.get_weapons()
	if weapons.is_empty():
		return
	
	for definition: WeaponDef in weapons:
		if definition.tiers.is_empty():
			continue
		var weapon := definition.tiers[0]
		var card: SelectionCard = Global.SELECTION_CARD_SCENE.instantiate()
		card.button_group = weapon_button_group
		card.pressed.connect(_on_weapon_selected.bind(definition, card))
		weapon_container.add_child(card)
		card.icon = Presentation.resolve_texture(
			&"weapon", definition.get_presentation_id(Content.catalog.pack_id), weapon.item_icon
		)


func show_player_info(value: bool) -> void:
	player_icon.visible = value
	player_name.visible = value
	player_title.visible = value
	player_description.visible = value


func reset_selection() -> void:
	for node: Node in player_container.get_children():
		var card := node as BaseButton
		if card != null:
			card.set_pressed_no_signal(false)
			var indicator := card.get_node_or_null("SelectedIndicator") as Control
			if indicator != null:
				indicator.hide()
	for node: Node in weapon_container.get_children():
		var card := node as BaseButton
		if card != null:
			card.set_pressed_no_signal(false)
			var indicator := card.get_node_or_null("SelectedIndicator") as Control
			if indicator != null:
				indicator.hide()
	show_player_info(false)


func _on_player_selected(character: CharacterDef, card: SelectionCard = null) -> void:
	if not Global.select_character(character):
		return
	if card != null:
		card.button_pressed = true
	var player := character.stats
	show_player_info(true)
	
	player_icon.texture = Presentation.resolve_texture(
		&"character", character.get_presentation_id(Content.catalog.pack_id), player.icon
	)
	player_name.text = ItemDescriptionFormatter.character_display_name(character)
	player_title.text = LocalizedTextService.resolve(&"ui.selection.character_type")
	player_description.text = FrontendViewModel.character_traits(character)


func _on_weapon_selected(weapon: WeaponDef, card: SelectionCard = null) -> void:
	if not Global.select_starting_weapon(weapon):
		return
	if card != null:
		card.button_pressed = true


func _on_continue_buttom_pressed() -> void:
	GameplayCues.emit_cue(&"ui.confirm")
	
	if not Global.main_player_selected or not Global.main_weapon_selected:
		return
	
	on_selection_completed.emit()
	hide()
