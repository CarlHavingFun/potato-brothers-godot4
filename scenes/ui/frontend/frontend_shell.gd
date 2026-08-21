class_name FrontendShell
extends Control


signal run_requested(request: RunLaunchRequest)
signal continue_requested
signal settings_requested
signal codex_requested
signal quit_requested
signal profile_changed(profile_id: int)

const TRANSITION_SECONDS := 0.16
const WEAPON_CARD_SIZE_SMALL := Vector2(152, 82)
const WEAPON_CARD_SIZE_LARGE := Vector2(244, 100)
const CHARACTER_CARD_SIZE_SMALL := Vector2(72, 64)
const CHARACTER_CARD_SIZE_LARGE := Vector2(92, 84)

@onready var pages: Control = $Pages
@onready var background: TextureRect = $Background
@onready var brand_mark: TextureRect = $Pages/TitlePage/SafeArea/Layout/Logo/BrandMark
@onready var product_name_label: Label = $Pages/TitlePage/SafeArea/Layout/Logo/Name
@onready var tagline_label: Label = $Pages/TitlePage/SafeArea/Layout/Logo/Tagline
@onready var build_label: Label = $Pages/TitlePage/SafeArea/Layout/Version
@onready var primary_button: Button = $Pages/TitlePage/SafeArea/Layout/Menu/PrimaryButton
@onready var new_game_button: Button = $Pages/TitlePage/SafeArea/Layout/Menu/NewGameButton
@onready var profile_button: Button = $Pages/TitlePage/SafeArea/Layout/Menu/ProfileButton
@onready var profile_choices: VBoxContainer = $Pages/ProfilePage/Content/ProfileChoices
@onready var repair_notice_label: Label = $Pages/ProfilePage/Content/RepairNotice
@onready var profile_status_label: Label = $Pages/ProfilePage/Content/ProfileStatus
@onready var profile_back_button: Button = $Pages/ProfilePage/Content/Header/BackButton
@onready var character_choices: GridContainer = $Pages/CharacterPage/Content/CharacterChoices
@onready var character_body: HBoxContainer = $Pages/CharacterPage/Content/Body
@onready var character_header_gap: Control = $Pages/CharacterPage/Content/HeaderGap
@onready var character_grid_gap: Control = $Pages/CharacterPage/Content/GridGap
@onready var character_card: Panel = $Pages/CharacterPage/Content/Body/CharacterCard
@onready var character_record_card: Panel = $Pages/CharacterPage/Content/Body/RecordCard
@onready var character_options_card: Panel = $Pages/CharacterPage/Content/Body/OptionsCard
@onready var character_icon: TextureRect = $Pages/CharacterPage/Content/Body/CharacterCard/Info/Details/Icon
@onready var character_name: Label = $Pages/CharacterPage/Content/Body/CharacterCard/Info/Name
@onready var character_traits: RichTextLabel = $Pages/CharacterPage/Content/Body/CharacterCard/Info/Details/Traits
@onready var character_record: Label = $Pages/CharacterPage/Content/Body/RecordCard/Record/Value
@onready var character_back_button: Button = $Pages/CharacterPage/Content/Header/BackButton
@onready var aim_mode_option: OptionButton = $Pages/CharacterPage/Content/Body/OptionsCard/Options/AimMode
@onready var run_mode_option: OptionButton = $Pages/CharacterPage/Content/Body/OptionsCard/Options/RunMode
@onready var device_hint: Label = %DeviceHint
@onready var weapon_choices: GridContainer = $Pages/WeaponPage/Content/WeaponChoices
@onready var weapon_content: VBoxContainer = $Pages/WeaponPage/Content
@onready var weapon_body: HBoxContainer = $Pages/WeaponPage/Content/Body
@onready var weapon_back_button: Button = $Pages/WeaponPage/Content/Header/BackButton
@onready var weapon_character_card: Panel = $Pages/WeaponPage/Content/Body/CharacterCard
@onready var weapon_detail_card: Panel = $Pages/WeaponPage/Content/Body/WeaponCard
@onready var weapon_character_icon: TextureRect = $Pages/WeaponPage/Content/Body/CharacterCard/Info/Icon
@onready var weapon_character_name: Label = $Pages/WeaponPage/Content/Body/CharacterCard/Info/Name
@onready var weapon_character_traits: RichTextLabel = $Pages/WeaponPage/Content/Body/CharacterCard/Info/Traits
@onready var weapon_icon: TextureRect = $Pages/WeaponPage/Content/Body/WeaponCard/Info/Icon
@onready var weapon_name: Label = $Pages/WeaponPage/Content/Body/WeaponCard/Info/Name
@onready var weapon_stats: RichTextLabel = $Pages/WeaponPage/Content/Body/WeaponCard/Info/Stats
@onready var overview_character_name: Label = $Pages/DifficultyPage/Content/Overview/CharacterCard/Name
@onready var overview_character_icon: TextureRect = $Pages/DifficultyPage/Content/Overview/CharacterCard/Icon
@onready var overview_character_traits: RichTextLabel = $Pages/DifficultyPage/Content/Overview/CharacterCard/Traits
@onready var overview_weapon_name: Label = $Pages/DifficultyPage/Content/Overview/WeaponCard/Name
@onready var overview_weapon_icon: TextureRect = $Pages/DifficultyPage/Content/Overview/WeaponCard/Icon
@onready var overview_weapon_stats: RichTextLabel = $Pages/DifficultyPage/Content/Overview/WeaponCard/Stats
@onready var difficulty_rules: RichTextLabel = $Pages/DifficultyPage/Content/Overview/DifficultyCard/Rules
@onready var difficulty_choices: HBoxContainer = $Pages/DifficultyPage/Content/DifficultyChoices

var selection_flow := SelectionFlow.new()
var current_step: int = SelectionStep.Value.TITLE
var draft := SelectionDraft.new()
var last_focus_restored := false
var _visible_weapon_ids: Array[StringName] = []
var _focus_by_step: Dictionary = {}
var _new_game_dialog: ConfirmationDialog
var _delete_dialog: ConfirmationDialog
var _rename_dialog: ConfirmationDialog
var _rename_instructions: Label
var _rename_input: LineEdit
var _rename_error: Label
var _pending_profile_action := 0
var _profile_buttons_by_slot: Dictionary = {}
var _character_buttons_by_id: Dictionary = {}
var _random_character_button: Button
var _weapon_stats_return_focus: Button
var _fallback_theme: Theme
var _page_transition: Tween


func _ready() -> void:
	# Keep the scene-owned theme as the fallback for development/test skins that
	# intentionally do not provide a branded Theme resource.
	_fallback_theme = theme
	_apply_skin_branding()
	if not Presentation.skin_loaded.is_connected(_on_skin_loaded):
		Presentation.skin_loaded.connect(_on_skin_loaded)
	resized.connect(_apply_character_page_layout)
	resized.connect(_apply_weapon_page_layout)
	InputDevices.device_changed.connect(_on_input_device_changed)
	selection_flow.step_changed.connect(_on_step_changed)
	selection_flow.draft_changed.connect(_on_draft_changed)
	selection_flow.run_requested.connect(_on_flow_run_requested)
	_setup_aim_mode()
	_setup_run_mode()
	_on_input_device_changed(InputDevices.active_device)
	_setup_profile_dialogs()
	weapon_stats.gui_input.connect(_on_weapon_stats_gui_input)
	_apply_character_page_layout()
	_apply_weapon_page_layout()
	_build_character_choices()
	_refresh_profiles()
	_show_step(SelectionStep.Value.TITLE, false)
	_register_button_feedback(self)
	_apply_character_page_layout.call_deferred()
	_apply_weapon_page_layout.call_deferred()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_apply_skin_branding()
		_retranslate_dynamic_ui()


func _apply_skin_branding() -> void:
	if Presentation.active_skin == null:
		return
	var skin := Presentation.active_skin
	var source_theme: Theme = skin.theme if skin.theme != null else _fallback_theme
	if source_theme != null:
		# Font assignment must not mutate either the skin resource or the scene
		# subresource; both may be reused by comparison tests and other screens.
		theme = source_theme.duplicate(true) as Theme
	product_name_label.text = LocalizedTextService.resolve(
		&"ui.title.name", [], skin.product_name
	)
	product_name_label.visible = skin.show_product_branding
	# These two labels are skin-owned copy. Godot's global TranslationServer does
	# not define deterministic precedence when the core and skin catalogs expose
	# the same key, so resolve them explicitly through the skin-first service.
	tagline_label.text = LocalizedTextService.resolve(&"ui.frontend.subtitle")
	build_label.text = LocalizedTextService.resolve(&"ui.frontend.build")
	brand_mark.texture = skin.logo
	brand_mark.visible = skin.show_product_branding and brand_mark.texture != null
	brand_mark.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	if skin.background != null:
		background.texture = skin.background
		background.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	if skin.font != null and theme != null:
		theme.default_font = skin.font


func _on_skin_loaded(_skin_id: StringName) -> void:
	if is_node_ready():
		_apply_skin_branding()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or current_step == SelectionStep.Value.TITLE:
		return
	if event.is_action_pressed("ui_cancel"):
		go_back()
		get_viewport().set_input_as_handled()


func begin_new_run(
	profile_id: int = 0,
	random_seed: int = 0,
	aim_mode: int = -1,
	run_mode: int = RunMode.STANDARD
) -> bool:
	var target_profile := profile_id if profile_id > 0 else Global.active_profile_id()
	if target_profile == 0:
		target_profile = _first_empty_profile_slot()
	if target_profile == 0:
		return false
	var target_seed := random_seed if random_seed != 0 else _make_prerun_seed()
	var target_aim := (
		aim_mode if AimMode.is_valid(aim_mode) else Global.product_settings.aim_mode
	)
	if target_profile != Global.active_profile_id():
		var summaries := Global.profile_summaries()
		var summary: Dictionary = summaries[target_profile - 1] if target_profile <= summaries.size() else {}
		if bool(summary.get("exists", false)):
			if not Global.switch_profile(target_profile):
				return false
		elif not Global.stage_profile_for_new_run(target_profile):
			return false
	var target_run_mode := run_mode if RunMode.is_valid(run_mode) else RunMode.STANDARD
	return selection_flow.begin_new_run(target_profile, target_seed, target_aim, target_run_mode)


func choose_character(character_id: StringName) -> bool:
	var definition := Content.catalog.get_character(character_id)
	if definition == null or definition.unlock_difficulty > Global.meta_progress.highest_unlocked_difficulty:
		return false
	var stable_id := definition.get_stable_id(Content.catalog.pack_id)
	var focus_target := _character_buttons_by_id.get(stable_id) as Button
	if is_instance_valid(focus_target):
		_focus_by_step[SelectionStep.Value.CHARACTER] = focus_target
	if not selection_flow.choose_character(stable_id):
		return false
	_update_character_details(definition)
	_build_weapon_choices(definition)
	return true


func choose_random_character() -> bool:
	var available: Array[CharacterDef] = []
	for definition: CharacterDef in Content.catalog.get_characters():
		if definition.unlock_difficulty <= Global.meta_progress.highest_unlocked_difficulty:
			available.append(definition)
	if available.is_empty():
		return false
	var rng := RandomNumberGenerator.new()
	rng.seed = draft.random_seed ^ 0x474F4252
	return choose_character(available[rng.randi_range(0, available.size() - 1)].get_stable_id(Content.catalog.pack_id))


func choose_weapon(weapon_id: StringName) -> bool:
	var definition := Content.catalog.get_weapon(weapon_id)
	if definition == null:
		return false
	var stable_id := definition.get_stable_id(Content.catalog.pack_id)
	if stable_id not in _visible_weapon_ids or not selection_flow.choose_weapon(stable_id):
		return false
	_update_weapon_details(definition)
	_update_final_overview()
	_build_difficulty_choices()
	return true


func choose_random_weapon() -> bool:
	if _visible_weapon_ids.is_empty():
		return false
	var rng := RandomNumberGenerator.new()
	rng.seed = draft.random_seed ^ 0x57454150
	return choose_weapon(_visible_weapon_ids[rng.randi_range(0, _visible_weapon_ids.size() - 1)])


func choose_difficulty(level: int, highest_unlocked: int = -1) -> RunLaunchRequest:
	var cap := highest_unlocked if highest_unlocked > 0 else Global.meta_progress.highest_unlocked_difficulty
	return selection_flow.choose_difficulty(level, cap)


func go_back() -> bool:
	_remember_focus()
	return selection_flow.go_back()


func reset_to_title() -> void:
	selection_flow.reset_to_title()
	_refresh_profiles()


func visible_weapon_ids() -> Array[StringName]:
	return _visible_weapon_ids.duplicate()


func _on_step_changed(step: int) -> void:
	_show_step(step)


func _on_draft_changed(value: SelectionDraft) -> void:
	draft = value
	_sync_character_selection_state()
	if is_instance_valid(aim_mode_option):
		aim_mode_option.select(value.aim_mode)
	if is_instance_valid(run_mode_option):
		run_mode_option.select(value.run_mode)


func _on_flow_run_requested(request: RunLaunchRequest) -> void:
	run_requested.emit(request)


func _show_step(step: int, animate := true) -> void:
	if is_instance_valid(_page_transition):
		_page_transition.kill()
		_page_transition = null
	current_step = step
	var target := _page_for_step(step)
	for page: Control in pages.get_children():
		page.modulate.a = 1.0
		page.position.x = 0.0
		page.visible = page == target
	last_focus_restored = false
	if target == null:
		return
	target.modulate.a = 1.0
	target.position.x = 0.0
	if animate and is_inside_tree():
		target.modulate.a = 0.0
		target.position.x = 30.0
		_page_transition = create_tween().set_parallel(true)
		_page_transition.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_page_transition.tween_property(target, "modulate:a", 1.0, TRANSITION_SECONDS)
		_page_transition.tween_property(target, "position:x", 0.0, TRANSITION_SECONDS)
	_restore_focus(step, target)


func _page_for_step(step: int) -> Control:
	match step:
		SelectionStep.Value.TITLE:
			return $Pages/TitlePage
		SelectionStep.Value.PROFILE:
			return $Pages/ProfilePage
		SelectionStep.Value.CHARACTER:
			return $Pages/CharacterPage
		SelectionStep.Value.WEAPON:
			return $Pages/WeaponPage
		SelectionStep.Value.DIFFICULTY:
			return $Pages/DifficultyPage
	return null


func _remember_focus() -> void:
	var owner := get_viewport().gui_get_focus_owner()
	if owner != null and is_ancestor_of(owner):
		_focus_by_step[current_step] = owner


func _restore_focus(step: int, page: Control) -> void:
	var target := _focus_by_step.get(step) as Control
	if step == SelectionStep.Value.CHARACTER and (
		not is_instance_valid(target) or not target.visible or target.focus_mode == Control.FOCUS_NONE
	):
		target = _preferred_character_focus()
	if not is_instance_valid(target) or not target.visible or target.focus_mode == Control.FOCUS_NONE:
		target = _first_focusable(page)
	if is_instance_valid(target):
		target.call_deferred("grab_focus")
		last_focus_restored = true


func _first_focusable(root: Node) -> Control:
	if root is Control and (root as Control).focus_mode != Control.FOCUS_NONE and (root as Control).visible:
		return root as Control
	for child: Node in root.get_children():
		var candidate := _first_focusable(child)
		if candidate != null:
			return candidate
	return null


func _setup_aim_mode() -> void:
	aim_mode_option.clear()
	aim_mode_option.add_item(LocalizedTextService.resolve(&"ui.settings.auto_aim"), AimMode.AUTO_TARGET)
	aim_mode_option.add_item(LocalizedTextService.resolve(&"ui.settings.manual_aim"), AimMode.MANUAL_MOUSE)
	aim_mode_option.select(
		draft.aim_mode
		if AimMode.is_valid(draft.aim_mode)
		else Global.product_settings.aim_mode
	)


func _on_aim_mode_selected(index: int) -> void:
	if index not in [AimMode.AUTO_TARGET, AimMode.MANUAL_MOUSE]:
		return
	draft.aim_mode = index
	selection_flow.draft_changed.emit(draft)


func _setup_run_mode() -> void:
	run_mode_option.clear()
	run_mode_option.add_item(LocalizedTextService.resolve(&"ui.run_mode.standard"), RunMode.STANDARD)
	run_mode_option.add_item(LocalizedTextService.resolve(&"ui.run_mode.endless"), RunMode.ENDLESS)
	run_mode_option.select(draft.run_mode)


func _on_run_mode_selected(index: int) -> void:
	if index < 0 or index >= run_mode_option.item_count:
		return
	selection_flow.set_run_mode(run_mode_option.get_item_id(index))


func _build_character_choices() -> void:
	_clear_children(character_choices)
	_character_buttons_by_id.clear()
	_random_character_button = _make_character_choice_button(null, true)
	_random_character_button.pressed.connect(choose_random_character)
	_random_character_button.focus_entered.connect(
		_on_character_grid_focus_entered.bind(_random_character_button)
	)
	character_choices.add_child(_random_character_button)
	var first_available: CharacterDef
	for definition: CharacterDef in Content.catalog.get_characters():
		var unlocked := definition.unlock_difficulty <= Global.meta_progress.highest_unlocked_difficulty
		var stable_id := definition.get_stable_id(Content.catalog.pack_id)
		var button := _make_character_choice_button(definition, unlocked)
		button.set_meta("content_id", stable_id)
		button.pressed.connect(_on_character_choice_pressed.bind(definition, stable_id, button))
		button.focus_entered.connect(_preview_character.bind(definition))
		button.focus_entered.connect(_on_character_grid_focus_entered.bind(button))
		button.mouse_entered.connect(_preview_character.bind(definition))
		character_choices.add_child(button)
		_character_buttons_by_id[stable_id] = button
		if first_available == null and unlocked:
			first_available = definition
	_register_button_feedback(character_choices)
	var selected := Content.catalog.get_character(draft.character_id)
	var initial_preview := selected if selected != null else first_available
	if initial_preview != null:
		_update_character_details(initial_preview)
	_sync_character_selection_state()
	var preferred_focus := _preferred_character_focus()
	if preferred_focus != null:
		_focus_by_step[SelectionStep.Value.CHARACTER] = preferred_focus
	_wire_character_focus_graph(preferred_focus)
	_apply_character_page_layout()


func _preview_character(definition: CharacterDef) -> void:
	_update_character_details(definition)


func _on_character_choice_pressed(
	definition: CharacterDef,
	stable_id: StringName,
	button: Button
) -> void:
	if not bool(button.get_meta(&"unlocked", false)):
		button.set_pressed_no_signal(false)
		_update_character_details(definition)
		return
	choose_character(stable_id)


func _update_character_details(definition: CharacterDef) -> void:
	if definition == null or definition.stats == null:
		return
	var stats := definition.stats
	character_icon.texture = Presentation.resolve_content_texture(
		definition, stats.icon, &"icon", Content.catalog.pack_id
	)
	character_name.text = FrontendViewModel.character_name(definition)
	character_traits.text = _character_traits_text(definition)
	var stable_id := definition.get_stable_id(Content.catalog.pack_id)
	if definition.unlock_difficulty > Global.meta_progress.highest_unlocked_difficulty:
		character_record.text = LocalizedTextService.resolve(
			&"ui.character.unlock_requirement", [definition.unlock_difficulty]
		)
	else:
		character_record.text = LocalizedTextService.resolve(&"ui.character.record", [
			Global.meta_progress.highest_clear_for(stable_id),
			Global.meta_progress.highest_endless_wave_any(stable_id),
		])
	weapon_character_icon.texture = character_icon.texture
	weapon_character_name.text = character_name.text
	weapon_character_traits.text = character_traits.text


func _character_traits_text(definition: CharacterDef) -> String:
	return FrontendViewModel.character_traits(definition)


func _allowed_weapons(character: CharacterDef) -> Array[WeaponDef]:
	var result: Array[WeaponDef] = []
	if character == null:
		return result
	if character.starter_weapon_ids.is_empty():
		for definition: WeaponDef in Content.catalog.get_weapons():
			if character.rules == null or character.rules.allows_weapon(definition.tags):
				result.append(definition)
		return result
	for weapon_id: StringName in character.starter_weapon_ids:
		var definition := Content.catalog.get_weapon(weapon_id)
		if definition != null and (character.rules == null or character.rules.allows_weapon(definition.tags)):
			result.append(definition)
	return result


func _build_weapon_choices(character: CharacterDef) -> void:
	_clear_children(weapon_choices)
	_visible_weapon_ids.clear()
	_weapon_stats_return_focus = null
	var random_button := _make_choice_button(LocalizedTextService.resolve(&"ui.selection.random"), null)
	random_button.pressed.connect(choose_random_weapon)
	random_button.focus_entered.connect(_on_weapon_grid_focus_entered.bind(random_button))
	weapon_choices.add_child(random_button)
	var first_available: WeaponDef
	for definition: WeaponDef in _allowed_weapons(character):
		if definition.tiers.is_empty() or definition.tiers[0] == null:
			continue
		var stable_id := definition.get_stable_id(Content.catalog.pack_id)
		_visible_weapon_ids.append(stable_id)
		var item := definition.tiers[0]
		var button := _make_choice_button(
			FrontendViewModel.weapon_name(item),
			Presentation.resolve_content_texture(
				definition, item.item_icon, &"icon", Content.catalog.pack_id
			)
		)
		button.set_meta("content_id", stable_id)
		button.pressed.connect(choose_weapon.bind(stable_id))
		button.focus_entered.connect(_preview_weapon.bind(definition))
		button.focus_entered.connect(_on_weapon_grid_focus_entered.bind(button))
		button.mouse_entered.connect(_preview_weapon.bind(definition))
		weapon_choices.add_child(button)
		if first_available == null:
			first_available = definition
	_register_button_feedback(weapon_choices)
	_wire_weapon_focus_graph(random_button)
	if first_available != null:
		_update_weapon_details(first_available)


func _preview_weapon(definition: WeaponDef) -> void:
	_update_weapon_details(definition)


func _update_weapon_details(definition: WeaponDef) -> void:
	if definition == null or definition.tiers.is_empty():
		return
	var item := definition.tiers[0]
	weapon_icon.texture = Presentation.resolve_content_texture(
		definition, item.item_icon, &"icon", Content.catalog.pack_id
	)
	weapon_name.text = FrontendViewModel.weapon_name(item)
	weapon_stats.text = _weapon_stats_text(item)


func _weapon_stats_text(item: ItemWeapon) -> String:
	if item == null or item.stats == null:
		return ""
	return FrontendViewModel.weapon_details(
		item, Global.current_run.player_stats if Global.current_run != null else null
	)


func _update_final_overview() -> void:
	var character := Content.catalog.get_character(draft.character_id)
	var weapon := Content.catalog.get_weapon(draft.weapon_id)
	if character != null:
		overview_character_name.text = FrontendViewModel.character_name(character)
		overview_character_icon.texture = Presentation.resolve_content_texture(
			character, character.stats.icon, &"icon", Content.catalog.pack_id
		)
		overview_character_traits.text = _character_traits_text(character)
	if weapon != null and not weapon.tiers.is_empty():
		overview_weapon_name.text = FrontendViewModel.weapon_name(weapon.tiers[0])
		overview_weapon_icon.texture = Presentation.resolve_content_texture(
			weapon, weapon.tiers[0].item_icon, &"icon", Content.catalog.pack_id
		)
		overview_weapon_stats.text = _weapon_stats_text(weapon.tiers[0])


func _build_difficulty_choices() -> void:
	_clear_children(difficulty_choices)
	var unlocked := Global.meta_progress.highest_unlocked_difficulty
	for definition: DifficultyDef in Content.catalog.get_difficulties():
		var level := definition.level
		var cleared := Global.meta_progress.highest_clear_for(draft.character_id) >= level
		var label := LocalizedTextService.resolve(
			&"ui.difficulty.choice", [level, "  ✓" if cleared else ""]
		)
		if level > unlocked:
			label = LocalizedTextService.resolve(&"ui.difficulty.locked", [level])
		var button := Button.new()
		button.custom_minimum_size = Vector2(
			190.0 if get_viewport_rect().size.x < 1500.0 else 250.0,
			72.0 if get_viewport_rect().size.y <= 720.0 else 82.0
		)
		button.text = label
		button.disabled = level > unlocked
		button.pressed.connect(choose_difficulty.bind(level, unlocked))
		button.focus_entered.connect(_preview_difficulty.bind(definition, level > unlocked))
		button.mouse_entered.connect(_preview_difficulty.bind(definition, level > unlocked))
		difficulty_choices.add_child(button)
	if difficulty_choices.get_child_count() > 0:
		_preview_difficulty(Content.catalog.get_difficulty(1), false)
	_register_button_feedback(difficulty_choices)


func _preview_difficulty(definition: DifficultyDef, locked: bool) -> void:
	if definition == null:
		return
	var lock_line := (
		LocalizedTextService.resolve(&"ui.difficulty.preview.locked")
		if locked
		else LocalizedTextService.resolve(&"ui.difficulty.preview.ready")
	)
	difficulty_rules.text = lock_line + LocalizedTextService.resolve(&"ui.difficulty.rules", [
		definition.health_multiplier, definition.damage_multiplier,
		definition.speed_multiplier, definition.spawn_density_multiplier,
		definition.elite_health_multiplier, definition.shop_price_multiplier,
		definition.material_drop_multiplier,
	])
	if draft.run_mode == RunMode.ENDLESS:
		difficulty_rules.text += LocalizedTextService.resolve(&"ui.difficulty.endless_summary")
	else:
		difficulty_rules.text += LocalizedTextService.resolve(&"ui.difficulty.standard_summary")


func _make_choice_button(label: String, icon_texture: Texture2D) -> Button:
	var button := Button.new()
	button.text = label
	button.icon = icon_texture
	button.expand_icon = true
	button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	button.clip_text = true
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_ALL
	_apply_weapon_choice_size(button)
	return button


func _apply_weapon_choice_size(button: Button) -> void:
	if not is_instance_valid(button):
		return
	var viewport_size := get_viewport_rect().size
	var compact := viewport_size.x < 1500.0 or viewport_size.y <= 800.0
	button.custom_minimum_size = (
		WEAPON_CARD_SIZE_SMALL if compact else WEAPON_CARD_SIZE_LARGE
	)
	button.add_theme_font_size_override(&"font_size", 16 if compact else 18)
	button.add_theme_constant_override(&"icon_max_width", 56 if compact else 68)


func _apply_weapon_page_layout() -> void:
	if not is_node_ready():
		return
	var viewport_size := get_viewport_rect().size
	var compact := viewport_size.x < 1500.0 or viewport_size.y <= 800.0
	weapon_content.add_theme_constant_override(&"separation", 8 if compact else 12)
	weapon_body.custom_minimum_size = Vector2(0.0, 210.0 if compact else 420.0)
	weapon_body.add_theme_constant_override(&"separation", 12 if compact else 20)
	weapon_character_card.custom_minimum_size = Vector2(400.0 if compact else 520.0, 0.0)
	weapon_detail_card.custom_minimum_size = Vector2.ZERO
	weapon_character_icon.custom_minimum_size = (
		Vector2(90.0, 90.0) if compact else Vector2(168.0, 168.0)
	)
	weapon_icon.custom_minimum_size = weapon_character_icon.custom_minimum_size
	weapon_character_name.add_theme_font_size_override(&"font_size", 24 if compact else 30)
	weapon_name.add_theme_font_size_override(&"font_size", 24 if compact else 30)
	weapon_character_traits.add_theme_font_size_override(&"normal_font_size", 16 if compact else 20)
	weapon_stats.add_theme_font_size_override(&"normal_font_size", 16 if compact else 20)
	_apply_weapon_stats_focus_style()
	weapon_choices.add_theme_constant_override(&"h_separation", 6 if compact else 10)
	weapon_choices.add_theme_constant_override(&"v_separation", 6 if compact else 10)
	for child: Node in weapon_choices.get_children():
		var button := child as Button
		if button != null:
			_apply_weapon_choice_size(button)
	weapon_body.queue_sort()
	weapon_choices.queue_sort()


func _apply_weapon_stats_focus_style() -> void:
	var accent := _character_accent_color()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.018, 0.023, 0.029, 0.96).lerp(accent, 0.12)
	style.border_color = accent
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.anti_aliasing = true
	style.anti_aliasing_size = 1.25
	style.corner_detail = 12
	style.content_margin_left = 6.0
	style.content_margin_top = 4.0
	style.content_margin_right = 6.0
	style.content_margin_bottom = 4.0
	weapon_stats.add_theme_stylebox_override(&"focus", style)


func _wire_weapon_focus_graph(anchor: Button = null) -> void:
	if not is_node_ready():
		return
	var buttons: Array[Button] = []
	for child: Node in weapon_choices.get_children():
		var button := child as Button
		if button != null and not button.disabled and button.focus_mode != Control.FOCUS_NONE:
			buttons.append(button)
	if buttons.is_empty():
		return
	var grid_anchor := anchor
	if not is_instance_valid(grid_anchor) or grid_anchor.disabled:
		grid_anchor = buttons[0]
	var columns := maxi(1, weapon_choices.columns)
	var final_row_start := ((buttons.size() - 1) / columns) * columns
	for index: int in buttons.size():
		var button := buttons[index]
		var column := index % columns
		var row_start := index - column
		var row_end := mini(row_start + columns - 1, buttons.size() - 1)
		var left := buttons[index - 1] if index > row_start else button
		var right := buttons[index + 1] if index < row_end else button
		var top: Control = weapon_stats if index < columns else buttons[index - columns]
		var bottom: Control = weapon_back_button
		if index + columns < buttons.size():
			bottom = buttons[index + columns]
		elif row_start < final_row_start:
			bottom = buttons[mini(final_row_start + column, buttons.size() - 1)]
		_set_focus_neighbor(button, &"focus_neighbor_left", left)
		_set_focus_neighbor(button, &"focus_neighbor_right", right)
		_set_focus_neighbor(button, &"focus_neighbor_top", top)
		_set_focus_neighbor(button, &"focus_neighbor_bottom", bottom)
	_set_focus_neighbor(weapon_back_button, &"focus_neighbor_top", grid_anchor)
	_set_focus_neighbor(weapon_back_button, &"focus_neighbor_bottom", grid_anchor)
	_set_focus_neighbor(weapon_back_button, &"focus_neighbor_left", grid_anchor)
	_set_focus_neighbor(weapon_back_button, &"focus_neighbor_right", grid_anchor)
	_set_focus_neighbor(weapon_stats, &"focus_neighbor_top", weapon_back_button)
	_set_focus_neighbor(weapon_stats, &"focus_neighbor_bottom", grid_anchor)


func _on_weapon_grid_focus_entered(button: Button) -> void:
	if not is_instance_valid(button) or button.disabled:
		return
	_weapon_stats_return_focus = button
	_focus_by_step[SelectionStep.Value.WEAPON] = button
	_set_focus_neighbor(weapon_stats, &"focus_neighbor_bottom", button)


func _on_weapon_stats_gui_input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	if event.is_action_pressed(&"ui_down"):
		_scroll_weapon_stats(1.0)
		weapon_stats.accept_event()
	elif event.is_action_pressed(&"ui_up"):
		_scroll_weapon_stats(-1.0)
		weapon_stats.accept_event()
	elif event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"ui_accept"):
		_return_focus_from_weapon_stats()
		weapon_stats.accept_event()


func _scroll_weapon_stats(direction: float) -> void:
	var scroll_bar := weapon_stats.get_v_scroll_bar()
	if scroll_bar == null:
		return
	var limit := maxf(scroll_bar.min_value, scroll_bar.max_value - scroll_bar.page)
	var step := maxf(28.0, scroll_bar.page * 0.3)
	scroll_bar.value = clampf(scroll_bar.value + direction * step, scroll_bar.min_value, limit)


func _return_focus_from_weapon_stats() -> void:
	var target := _weapon_stats_return_focus
	if not is_instance_valid(target) or not target.visible or target.disabled:
		for child: Node in weapon_choices.get_children():
			var button := child as Button
			if button != null and not button.disabled and button.focus_mode != Control.FOCUS_NONE:
				target = button
				break
	if is_instance_valid(target):
		target.grab_focus()


func _make_character_choice_button(definition: CharacterDef, unlocked: bool) -> Button:
	var button := Button.new()
	button.expand_icon = true
	button.clip_text = true
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.focus_mode = Control.FOCUS_ALL
	button.toggle_mode = definition != null
	button.set_meta(&"unlocked", unlocked)
	button.set_meta(
		&"press_cue",
		&"ui.confirm" if definition == null or unlocked else &"ui.locked"
	)
	if definition == null:
		button.text = LocalizedTextService.resolve(&"ui.character.random_symbol")
		button.tooltip_text = LocalizedTextService.resolve(&"ui.character.random_tooltip")
	else:
		var display_name := FrontendViewModel.character_name(definition)
		button.tooltip_text = (
			display_name
			if unlocked
			else LocalizedTextService.resolve(
				&"ui.character.locked_tooltip", [display_name, definition.unlock_difficulty]
			)
		)
		if unlocked:
			button.icon = Presentation.resolve_content_texture(
				definition,
				definition.stats.icon,
				&"icon",
				Content.catalog.pack_id,
			)
		else:
			button.text = LocalizedTextService.resolve(&"ui.character.lock_symbol")
	_apply_character_choice_style(button)
	_apply_character_choice_size(button)
	return button


func _apply_character_choice_style(button: Button) -> void:
	var accent := _character_accent_color()
	var surface := Color(0.018, 0.023, 0.029, 1.0)
	var normal_border := Color(0.16, 0.18, 0.2, 1.0).lerp(accent, 0.18)
	var glow := accent.darkened(0.15)
	glow.a = 0.72
	button.add_theme_stylebox_override(
		&"normal", _character_choice_style(
			_accent_surface(surface, accent, 0.02, 0.96), normal_border
		)
	)
	var hover_style := _character_choice_style(
		_accent_surface(surface, accent, 0.16, 0.98), accent, glow
	)
	button.add_theme_stylebox_override(&"hover", hover_style)
	button.add_theme_stylebox_override(&"focus", hover_style)
	var selected_style := _character_choice_style(
		_accent_surface(surface, accent, 0.28, 0.99), accent.lightened(0.15), glow
	)
	button.add_theme_stylebox_override(&"pressed", selected_style)
	button.add_theme_stylebox_override(&"hover_pressed", selected_style)
	button.add_theme_stylebox_override(
		&"disabled", _character_choice_style(
			_accent_surface(surface, accent, 0.01, 0.9), normal_border.darkened(0.4)
		)
	)
	button.add_theme_color_override(&"font_color", Color(0.9, 0.94, 0.97, 1.0))
	button.add_theme_color_override(&"font_hover_color", Color.WHITE)
	button.add_theme_color_override(&"font_focus_color", Color.WHITE)
	button.add_theme_color_override(&"font_pressed_color", Color.WHITE)
	button.add_theme_color_override(&"font_disabled_color", Color(0.44, 0.5, 0.54, 1.0))


func _character_choice_style(
	background_color: Color,
	border_color: Color,
	glow_color := Color.TRANSPARENT
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background_color
	style.border_color = border_color
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.anti_aliasing = true
	style.anti_aliasing_size = 1.25
	style.corner_detail = 12
	style.content_margin_left = 4.0
	style.content_margin_top = 4.0
	style.content_margin_right = 4.0
	style.content_margin_bottom = 4.0
	if glow_color.a > 0.0:
		style.shadow_color = glow_color
		style.shadow_size = 5
		style.shadow_offset = Vector2(0.0, 4.0)
	return style


func _character_accent_color() -> Color:
	var accent := Color.WHITE
	if Presentation.active_skin != null:
		accent = Presentation.active_skin.accent_color
	accent.a = 1.0
	return accent


func _accent_surface(base: Color, accent: Color, weight: float, alpha: float) -> Color:
	var result := base.lerp(accent, clampf(weight, 0.0, 1.0))
	result.a = alpha
	return result


func _apply_character_choice_size(button: Button) -> void:
	if not is_instance_valid(button):
		return
	var compact := get_viewport_rect().size.x < 1500.0 or get_viewport_rect().size.y <= 800.0
	button.custom_minimum_size = CHARACTER_CARD_SIZE_SMALL if compact else CHARACTER_CARD_SIZE_LARGE
	button.add_theme_font_size_override(&"font_size", 26 if compact else 34)
	button.add_theme_constant_override(&"icon_max_width", 52 if compact else 72)


func _apply_character_page_layout() -> void:
	if not is_node_ready():
		return
	var viewport_size := get_viewport_rect().size
	var compact := viewport_size.x < 1500.0 or viewport_size.y <= 800.0
	var body_height := 333.0 if compact else 500.0
	character_body.custom_minimum_size = Vector2(0.0, body_height)
	character_body.add_theme_constant_override(&"separation", 16 if compact else 24)
	character_card.custom_minimum_size = Vector2(510.0 if compact else 760.0, body_height)
	character_record_card.custom_minimum_size = Vector2(240.0 if compact else 360.0, body_height)
	character_options_card.custom_minimum_size = Vector2(214.0 if compact else 320.0, body_height)
	# The project renders through a 1920x1080 logical canvas. A 146px logical
	# gap maps to roughly 97px at 1280x720 and keeps the three-card row aligned
	# with the compact layout's 153px top edge after canvas scaling.
	character_header_gap.custom_minimum_size.y = 69.0 if compact else 146.0
	character_grid_gap.custom_minimum_size.y = 22.0 if compact else 28.0
	character_choices.custom_minimum_size.y = 64.0 if compact else 84.0
	character_choices.add_theme_constant_override(&"h_separation", 7 if compact else 10)
	character_choices.add_theme_constant_override(&"v_separation", 7 if compact else 10)
	character_icon.custom_minimum_size = Vector2(220.0, 220.0) if compact else Vector2(330.0, 330.0)
	character_name.add_theme_font_size_override(&"font_size", 30 if compact else 40)
	character_traits.add_theme_font_size_override(&"normal_font_size", 18 if compact else 24)
	character_record.add_theme_font_size_override(&"font_size", 20 if compact else 26)
	aim_mode_option.custom_minimum_size = Vector2(180.0, 44.0) if compact else Vector2(286.0, 58.0)
	run_mode_option.custom_minimum_size = aim_mode_option.custom_minimum_size
	for child: Node in character_choices.get_children():
		var button := child as Button
		if button != null:
			_apply_character_choice_size(button)
	character_body.queue_sort()
	character_choices.queue_sort()


func _sync_character_selection_state() -> void:
	for raw_id: Variant in _character_buttons_by_id:
		var button := _character_buttons_by_id[raw_id] as Button
		if is_instance_valid(button):
			button.set_pressed_no_signal(StringName(str(raw_id)) == draft.character_id)


func _preferred_character_focus() -> Button:
	if not draft.character_id.is_empty():
		var selected := _character_buttons_by_id.get(draft.character_id) as Button
		if is_instance_valid(selected) and bool(selected.get_meta(&"unlocked", false)):
			return selected
	for child: Node in character_choices.get_children():
		var button := child as Button
		if (
			button != null
			and button.has_meta(&"content_id")
			and bool(button.get_meta(&"unlocked", false))
		):
			return button
	return _random_character_button if is_instance_valid(_random_character_button) else null


func _wire_character_focus_graph(anchor: Button = null) -> void:
	if not is_node_ready():
		return
	var all_buttons: Array[Button] = []
	var focusable_buttons: Array[Button] = []
	for child: Node in character_choices.get_children():
		var button := child as Button
		if button == null:
			continue
		all_buttons.append(button)
		if not button.disabled and button.focus_mode != Control.FOCUS_NONE:
			focusable_buttons.append(button)
	if focusable_buttons.is_empty():
		return
	var grid_anchor := anchor
	if not is_instance_valid(grid_anchor) or grid_anchor.disabled:
		grid_anchor = focusable_buttons[0]

	for button: Button in all_buttons:
		var reference_index := focusable_buttons.find(button)
		if reference_index < 0:
			reference_index = _nearest_character_focus_index(button, focusable_buttons)
		var left := focusable_buttons[posmod(reference_index - 1, focusable_buttons.size())]
		var right := focusable_buttons[posmod(reference_index + 1, focusable_buttons.size())]
		_set_focus_neighbor(button, &"focus_neighbor_left", left)
		_set_focus_neighbor(button, &"focus_neighbor_right", right)
		_set_focus_neighbor(button, &"focus_neighbor_top", run_mode_option)
		_set_focus_neighbor(button, &"focus_neighbor_bottom", character_back_button)

	_set_focus_neighbor(character_back_button, &"focus_neighbor_top", grid_anchor)
	_set_focus_neighbor(character_back_button, &"focus_neighbor_bottom", aim_mode_option)
	_set_focus_neighbor(character_back_button, &"focus_neighbor_left", grid_anchor)
	_set_focus_neighbor(character_back_button, &"focus_neighbor_right", aim_mode_option)
	_set_focus_neighbor(aim_mode_option, &"focus_neighbor_top", character_back_button)
	_set_focus_neighbor(aim_mode_option, &"focus_neighbor_bottom", run_mode_option)
	_set_focus_neighbor(aim_mode_option, &"focus_neighbor_left", character_back_button)
	_set_focus_neighbor(aim_mode_option, &"focus_neighbor_right", run_mode_option)
	_set_focus_neighbor(run_mode_option, &"focus_neighbor_top", aim_mode_option)
	_set_focus_neighbor(run_mode_option, &"focus_neighbor_bottom", grid_anchor)
	_set_focus_neighbor(run_mode_option, &"focus_neighbor_left", aim_mode_option)
	_set_focus_neighbor(run_mode_option, &"focus_neighbor_right", grid_anchor)


func _nearest_character_focus_index(button: Button, focusable_buttons: Array[Button]) -> int:
	var button_index: int = button.get_index()
	var closest_index := 0
	var closest_distance := 1 << 30
	for index: int in focusable_buttons.size():
		var distance: int = absi(focusable_buttons[index].get_index() - button_index)
		if distance < closest_distance:
			closest_distance = distance
			closest_index = index
	return closest_index


func _on_character_grid_focus_entered(button: Button) -> void:
	if not is_instance_valid(button) or button.disabled:
		return
	_set_focus_neighbor(character_back_button, &"focus_neighbor_top", button)
	_set_focus_neighbor(character_back_button, &"focus_neighbor_left", button)
	_set_focus_neighbor(run_mode_option, &"focus_neighbor_bottom", button)
	_set_focus_neighbor(run_mode_option, &"focus_neighbor_right", button)


func _set_focus_neighbor(source: Control, property_name: StringName, target: Control) -> void:
	if not is_instance_valid(source) or not is_instance_valid(target):
		return
	source.set(property_name, source.get_path_to(target))


func _refresh_profiles(focus_slot: int = 0) -> void:
	_clear_children(profile_choices)
	_profile_buttons_by_slot.clear()
	repair_notice_label.text = "\n".join(Global.meta_progress.repair_notices.map(
		func(notice: String): return _localized_repair_notice(notice)
	))
	repair_notice_label.visible = not Global.meta_progress.repair_notices.is_empty()
	var active_id := Global.active_profile_id()
	var summaries := Global.profile_summaries()
	var profile_rows: Array[Dictionary] = []
	for slot in range(1, ProfileStore.MAX_PROFILES + 1):
		var summary: Dictionary = summaries[slot - 1] if slot <= summaries.size() else {
			"id": slot,
			"name": "",
			"exists": false,
			"has_progress": false,
			"has_checkpoint": false,
		}
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var select_button := Button.new()
		select_button.custom_minimum_size = Vector2(720, 92)
		select_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var state := LocalizedTextService.resolve(&"ui.profile.state.empty")
		if bool(summary.get("has_checkpoint", false)):
			state = LocalizedTextService.resolve(&"ui.profile.state.continue")
		elif bool(summary.get("has_progress", false)):
			state = LocalizedTextService.resolve(&"ui.profile.state.progress")
		elif bool(summary.get("exists", false)):
			state = LocalizedTextService.resolve(&"ui.profile.state.created")
		var endless_high := int(summary.get("highest_endless_wave", 0))
		if endless_high > 0:
			state += LocalizedTextService.resolve(&"ui.profile.state.endless", [endless_high])
		var exists := bool(summary.get("exists", false))
		var summary_name := (
			str(summary.get("name", ""))
			if exists
			else LocalizedTextService.resolve(&"ui.profile.empty_slot", [slot])
		)
		var display_name := (
			LocalizedTextService.resolve(&"ui.profile.active_name", [summary_name])
			if slot == active_id and exists
			else LocalizedTextService.resolve(&"ui.profile.pending_name", [summary_name])
			if slot == active_id and not exists
			else summary_name
		)
		select_button.text = "%s\n%s" % [display_name, state]
		select_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		select_button.pressed.connect(_select_profile.bind(slot))
		row.add_child(select_button)
		_profile_buttons_by_slot[slot] = select_button
		var rename_button := Button.new()
		rename_button.custom_minimum_size = Vector2(130, 92)
		rename_button.text = LocalizedTextService.resolve(
			&"ui.profile.rename" if exists else &"ui.profile.create"
		)
		if exists:
			rename_button.pressed.connect(_request_rename_profile.bind(slot, str(summary.get("name", ""))))
		else:
			rename_button.pressed.connect(_begin_profile_slot.bind(slot))
		row.add_child(rename_button)
		var delete_button := Button.new()
		delete_button.custom_minimum_size = Vector2(130, 92)
		delete_button.text = LocalizedTextService.resolve(&"ui.profile.delete")
		delete_button.disabled = not bool(summary.get("exists", false))
		delete_button.pressed.connect(_request_delete_profile.bind(slot))
		row.add_child(delete_button)
		profile_choices.add_child(row)
		profile_rows.append({
			"select": select_button,
			"rename": rename_button,
			"delete": delete_button,
		})
	_register_button_feedback(profile_choices)
	_wire_profile_focus_graph(profile_rows, active_id)
	var preferred_slot := focus_slot if focus_slot in range(1, ProfileStore.MAX_PROFILES + 1) else active_id
	var preferred_profile_button := _profile_buttons_by_slot.get(preferred_slot) as Button
	if is_instance_valid(preferred_profile_button):
		_focus_by_step[SelectionStep.Value.PROFILE] = preferred_profile_button
		if current_step == SelectionStep.Value.PROFILE:
			preferred_profile_button.call_deferred("grab_focus")

	var active_summary: Dictionary = (
		summaries[active_id - 1]
		if active_id > 0 and active_id <= summaries.size()
		else {}
	)
	var has_active_profile := bool(active_summary.get("exists", false))
	profile_button.text = (
		LocalizedTextService.resolve(&"ui.profile.current", [str(active_summary.get("name", ""))])
		if has_active_profile
		else LocalizedTextService.resolve(&"ui.profile.none")
	)
	var has_checkpoint := bool(active_summary.get("has_checkpoint", false))
	primary_button.text = (
		LocalizedTextService.resolve(&"ui.title.continue")
		if has_checkpoint
		else LocalizedTextService.resolve(&"ui.title.start")
	)
	new_game_button.visible = has_checkpoint


func _select_profile(profile_id: int) -> void:
	var summaries := Global.profile_summaries()
	var summary: Dictionary = summaries[profile_id - 1] if profile_id <= summaries.size() else {}
	if not bool(summary.get("exists", false)):
		_begin_profile_slot(profile_id)
		return
	if not Global.switch_profile(profile_id):
		_show_profile_error(&"ui.profile.error.switch", ERR_CANT_CREATE)
		return
	profile_status_label.visible = false
	_build_character_choices()
	_setup_aim_mode()
	_setup_run_mode()
	_refresh_profiles()
	profile_changed.emit(profile_id)
	selection_flow.reset_to_title()


func _begin_profile_slot(profile_id: int) -> void:
	profile_status_label.visible = false
	if not begin_new_run(profile_id):
		_show_profile_error(&"ui.profile.error.switch", ERR_CANT_CREATE)


func _setup_profile_dialogs() -> void:
	_new_game_dialog = ConfirmationDialog.new()
	_new_game_dialog.confirmed.connect(_begin_confirmed_new_game)
	add_child(_new_game_dialog)

	_delete_dialog = ConfirmationDialog.new()
	_delete_dialog.confirmed.connect(_confirm_delete_profile)
	add_child(_delete_dialog)

	_rename_dialog = ConfirmationDialog.new()
	add_child(_rename_dialog)
	var rename_content := VBoxContainer.new()
	rename_content.name = "RenameContent"
	rename_content.set_anchors_preset(Control.PRESET_TOP_WIDE)
	rename_content.offset_left = 24.0
	rename_content.offset_top = 54.0
	rename_content.offset_right = -24.0
	rename_content.offset_bottom = 180.0
	rename_content.add_theme_constant_override(&"separation", 10)
	_rename_dialog.add_child(rename_content)
	_rename_instructions = Label.new()
	_rename_instructions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rename_content.add_child(_rename_instructions)
	_rename_input = LineEdit.new()
	_rename_input.max_length = 24
	_rename_input.custom_minimum_size = Vector2(440, 52)
	rename_content.add_child(_rename_input)
	_rename_error = Label.new()
	_rename_error.visible = false
	_rename_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rename_error.add_theme_color_override(&"font_color", Color(1.0, 0.4, 0.34, 1.0))
	rename_content.add_child(_rename_error)
	_rename_dialog.confirmed.connect(_confirm_rename_profile)
	_update_profile_dialog_text()


func _request_delete_profile(profile_id: int) -> void:
	_pending_profile_action = profile_id
	_delete_dialog.popup_centered(Vector2i(560, 240))


func _confirm_delete_profile() -> void:
	var action_slot := _pending_profile_action
	var result := Global.delete_profile(action_slot)
	if result == OK:
		profile_status_label.visible = false
		_refresh_profiles(action_slot)
	else:
		_show_profile_error(&"ui.profile.error.delete", result)
	_pending_profile_action = 0


func _request_rename_profile(profile_id: int, current_name: String) -> void:
	_pending_profile_action = profile_id
	_rename_input.text = current_name
	_rename_error.visible = false
	_rename_dialog.popup_centered(Vector2i(560, 260))
	_rename_input.call_deferred("grab_focus")


func _confirm_rename_profile() -> void:
	var action_slot := _pending_profile_action
	var result := Global.rename_profile(action_slot, _rename_input.text)
	if result == OK:
		_rename_error.visible = false
		profile_status_label.visible = false
		_refresh_profiles(action_slot)
		_pending_profile_action = 0
		return
	_rename_error.text = LocalizedTextService.resolve(&"ui.profile.rename.invalid")
	_rename_error.visible = true
	GameLog.warning(&"profile", "profile_rename_failed", {
		"profile_id": _pending_profile_action,
		"error": error_string(result),
	})
	_rename_dialog.call_deferred("popup_centered", Vector2i(560, 300))
	_rename_input.call_deferred("grab_focus")


func _on_primary_pressed() -> void:
	var summaries := Global.profile_summaries()
	var index := Global.active_profile_id() - 1
	var has_checkpoint := index >= 0 and index < summaries.size() and bool(summaries[index].get("has_checkpoint", false))
	if has_checkpoint:
		continue_requested.emit()
	else:
		begin_new_run()


func _first_empty_profile_slot() -> int:
	for summary: Dictionary in Global.profile_summaries():
		if not bool(summary.get("exists", false)):
			return int(summary.get("id", 0))
	return 0


func _on_new_game_pressed() -> void:
	_new_game_dialog.popup_centered(Vector2i(620, 260))


func _begin_confirmed_new_game() -> void:
	Global.end_run()
	Global.save_progress(false)
	begin_new_run()


func _on_profiles_pressed() -> void:
	profile_status_label.visible = false
	_refresh_profiles()
	selection_flow.open_profiles()


func _on_codex_pressed() -> void:
	codex_requested.emit()


func _on_settings_pressed() -> void:
	settings_requested.emit()


func _on_quit_pressed() -> void:
	quit_requested.emit()


func _on_input_device_changed(_device: int) -> void:
	if is_instance_valid(device_hint):
		device_hint.text = LocalizedTextService.resolve(&"ui.frontend.device_hint", [
			InputDevices.confirm_prompt(), InputDevices.back_prompt()
		])


func _update_profile_dialog_text() -> void:
	if not is_instance_valid(_new_game_dialog):
		return
	_new_game_dialog.title = LocalizedTextService.resolve(&"ui.profile.new_game.title")
	_new_game_dialog.dialog_text = LocalizedTextService.resolve(&"ui.profile.new_game.body")
	_new_game_dialog.ok_button_text = LocalizedTextService.resolve(&"ui.profile.new_game.confirm")
	_delete_dialog.title = LocalizedTextService.resolve(&"ui.profile.delete.title")
	_delete_dialog.dialog_text = LocalizedTextService.resolve(&"ui.profile.delete.body")
	_delete_dialog.ok_button_text = LocalizedTextService.resolve(&"ui.profile.delete.confirm")
	_rename_dialog.title = LocalizedTextService.resolve(&"ui.profile.rename.title")
	_rename_dialog.dialog_text = ""
	_rename_instructions.text = LocalizedTextService.resolve(&"ui.profile.rename.body")
	_rename_dialog.ok_button_text = LocalizedTextService.resolve(&"ui.profile.rename.confirm")
	_rename_input.placeholder_text = LocalizedTextService.resolve(&"ui.profile.rename.placeholder")
	if _rename_error.visible:
		_rename_error.text = LocalizedTextService.resolve(&"ui.profile.rename.invalid")


func _wire_profile_focus_graph(rows: Array[Dictionary], active_id: int) -> void:
	if rows.is_empty():
		return
	var active_index := clampi(active_id - 1, 0, rows.size() - 1)
	var active_select := rows[active_index].get("select") as Button
	for index: int in rows.size():
		var current: Dictionary = rows[index]
		var previous: Dictionary = rows[posmod(index - 1, rows.size())]
		var following: Dictionary = rows[posmod(index + 1, rows.size())]
		var select := current.get("select") as Button
		var rename := current.get("rename") as Button
		var delete := current.get("delete") as Button
		var previous_delete := previous.get("delete") as Button
		var following_delete := following.get("delete") as Button
		_set_focus_neighbor(select, &"focus_neighbor_left", profile_back_button)
		_set_focus_neighbor(select, &"focus_neighbor_right", rename)
		_set_focus_neighbor(select, &"focus_neighbor_top", previous.get("select") as Button)
		_set_focus_neighbor(select, &"focus_neighbor_bottom", following.get("select") as Button)
		_set_focus_neighbor(rename, &"focus_neighbor_left", select)
		_set_focus_neighbor(rename, &"focus_neighbor_right", delete if not delete.disabled else select)
		_set_focus_neighbor(rename, &"focus_neighbor_top", previous.get("rename") as Button)
		_set_focus_neighbor(rename, &"focus_neighbor_bottom", following.get("rename") as Button)
		_set_focus_neighbor(delete, &"focus_neighbor_left", rename)
		_set_focus_neighbor(delete, &"focus_neighbor_right", select)
		_set_focus_neighbor(
			delete,
			&"focus_neighbor_top",
			previous_delete if not previous_delete.disabled else previous.get("rename") as Button
		)
		_set_focus_neighbor(
			delete,
			&"focus_neighbor_bottom",
			following_delete if not following_delete.disabled else following.get("rename") as Button
		)
	_set_focus_neighbor(profile_back_button, &"focus_neighbor_top", active_select)
	_set_focus_neighbor(profile_back_button, &"focus_neighbor_bottom", active_select)
	_set_focus_neighbor(profile_back_button, &"focus_neighbor_left", active_select)
	_set_focus_neighbor(profile_back_button, &"focus_neighbor_right", active_select)


func _show_profile_error(text_id: StringName, result: Error) -> void:
	profile_status_label.text = LocalizedTextService.resolve(text_id)
	profile_status_label.visible = true
	GameLog.warning(&"profile", "profile_action_failed", {
		"profile_id": _pending_profile_action,
		"error": error_string(result),
		"message_id": String(text_id),
	})


func _localized_repair_notice(notice: String) -> String:
	match notice:
		"Recovered legacy profile from backup during v3 migration.":
			return LocalizedTextService.resolve(&"ui.profile.repair.migration_backup")
		"Recovered v3 profile from backup during v4 migration.":
			return LocalizedTextService.resolve(&"ui.profile.repair.v4_migration_backup")
		"Recovered profile from backup after corrupted primary save.":
			return LocalizedTextService.resolve(&"ui.profile.repair.backup")
		_:
			return (
				LocalizedTextService.resolve(StringName(notice))
				if notice.begins_with("ui.")
				else LocalizedTextService.resolve(&"ui.profile.repair.unknown")
			)


func _retranslate_dynamic_ui() -> void:
	_setup_aim_mode()
	_setup_run_mode()
	_update_profile_dialog_text()
	_on_input_device_changed(InputDevices.active_device)
	_build_character_choices()
	var character := Content.catalog.get_character(draft.character_id)
	if character != null:
		_update_character_details(character)
		_build_weapon_choices(character)
	var weapon := Content.catalog.get_weapon(draft.weapon_id)
	if weapon != null:
		_update_weapon_details(weapon)
		_update_final_overview()
		_build_difficulty_choices()
	_refresh_profiles()


func _make_prerun_seed() -> int:
	return int(Time.get_ticks_usec() & 0x7FFFFFFF)


func _clear_children(parent: Node) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


func _register_button_feedback(root: Node) -> void:
	if root is BaseButton:
		var button := root as BaseButton
		if not button.has_meta(&"semantic_feedback_registered"):
			button.set_meta(&"semantic_feedback_registered", true)
			var press_cue := StringName(str(button.get_meta(&"press_cue", &"ui.confirm")))
			button.pressed.connect(GameplayCues.emit_cue.bind(press_cue, {}))
			button.mouse_entered.connect(_emit_hover_cue)
			button.mouse_entered.connect(_animate_button.bind(button, true))
			button.mouse_exited.connect(_animate_button.bind(button, false))
			button.focus_entered.connect(_emit_hover_cue)
			button.focus_entered.connect(_animate_button.bind(button, true))
			button.focus_exited.connect(_animate_button.bind(button, false))
	for child: Node in root.get_children():
		_register_button_feedback(child)


func _emit_hover_cue() -> void:
	GameplayCues.emit_cue(&"ui.hover")


func _animate_button(button: BaseButton, active: bool) -> void:
	if not is_instance_valid(button):
		return
	var previous_tween: Tween = (
		button.get_meta(&"semantic_feedback_tween") as Tween
		if button.has_meta(&"semantic_feedback_tween")
		else null
	)
	if is_instance_valid(previous_tween):
		previous_tween.kill()
	if button.disabled:
		button.self_modulate = Color.WHITE
		return
	var tween := button.create_tween()
	button.set_meta(&"semantic_feedback_tween", tween)
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(
		button,
		"self_modulate",
		Color(1.0, 0.96, 0.82, 1.0) if active else Color.WHITE,
		0.08
	)
