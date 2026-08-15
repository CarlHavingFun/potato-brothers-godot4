class_name FrontendShell
extends Control


signal run_requested(request: RunLaunchRequest)
signal continue_requested
signal settings_requested
signal codex_requested
signal quit_requested
signal profile_changed(profile_id: int)

const TRANSITION_SECONDS := 0.16
const CARD_SIZE := Vector2(224, 138)

@onready var pages: Control = $Pages
@onready var background: TextureRect = $Background
@onready var product_name_label: Label = $Pages/TitlePage/SafeArea/Layout/Logo/Name
@onready var primary_button: Button = $Pages/TitlePage/SafeArea/Layout/Menu/PrimaryButton
@onready var new_game_button: Button = $Pages/TitlePage/SafeArea/Layout/Menu/NewGameButton
@onready var profile_button: Button = $Pages/TitlePage/SafeArea/Layout/Menu/ProfileButton
@onready var profile_choices: VBoxContainer = $Pages/ProfilePage/Content/ProfileChoices
@onready var repair_notice_label: Label = $Pages/ProfilePage/Content/RepairNotice
@onready var character_choices: GridContainer = $Pages/CharacterPage/Content/CharacterChoices
@onready var character_icon: TextureRect = $Pages/CharacterPage/Content/Body/CharacterCard/Info/Icon
@onready var character_name: Label = $Pages/CharacterPage/Content/Body/CharacterCard/Info/Name
@onready var character_traits: RichTextLabel = $Pages/CharacterPage/Content/Body/CharacterCard/Info/Traits
@onready var character_record: Label = $Pages/CharacterPage/Content/Body/OptionsCard/Options/Record
@onready var aim_mode_option: OptionButton = $Pages/CharacterPage/Content/Body/OptionsCard/Options/AimMode
@onready var run_mode_option: OptionButton = $Pages/CharacterPage/Content/Body/OptionsCard/Options/RunMode
@onready var device_hint: Label = %DeviceHint
@onready var weapon_choices: GridContainer = $Pages/WeaponPage/Content/WeaponChoices
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
var _rename_input: LineEdit
var _pending_profile_action := 0


func _ready() -> void:
	_apply_skin_branding()
	InputDevices.device_changed.connect(_on_input_device_changed)
	selection_flow.step_changed.connect(_on_step_changed)
	selection_flow.draft_changed.connect(_on_draft_changed)
	selection_flow.run_requested.connect(_on_flow_run_requested)
	_setup_aim_mode()
	_setup_run_mode()
	_on_input_device_changed(InputDevices.active_device)
	_setup_profile_dialogs()
	_build_character_choices()
	_refresh_profiles()
	_show_step(SelectionStep.Value.TITLE, false)
	_register_button_feedback(self)


func _apply_skin_branding() -> void:
	if Presentation.active_skin == null:
		return
	product_name_label.text = Presentation.active_skin.product_name
	if Presentation.active_skin.background != null:
		background.texture = Presentation.active_skin.background
	if Presentation.active_skin.font != null and theme != null:
		theme.default_font = Presentation.active_skin.font


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
	var target_seed := random_seed if random_seed != 0 else _make_prerun_seed()
	var target_aim := aim_mode if AimMode.is_valid(aim_mode) else Global.meta_progress.aim_mode
	if target_profile != Global.active_profile_id() and not Global.switch_profile(target_profile):
		return false
	var target_run_mode := run_mode if RunMode.is_valid(run_mode) else RunMode.STANDARD
	return selection_flow.begin_new_run(target_profile, target_seed, target_aim, target_run_mode)


func choose_character(character_id: StringName) -> bool:
	var definition := Content.catalog.get_character(character_id)
	if definition == null or definition.unlock_difficulty > Global.meta_progress.highest_unlocked_difficulty:
		return false
	var stable_id := definition.get_stable_id(Content.catalog.pack_id)
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
	if is_instance_valid(aim_mode_option):
		aim_mode_option.select(value.aim_mode)
	if is_instance_valid(run_mode_option):
		run_mode_option.select(value.run_mode)


func _on_flow_run_requested(request: RunLaunchRequest) -> void:
	run_requested.emit(request)


func _show_step(step: int, animate := true) -> void:
	current_step = step
	var target := _page_for_step(step)
	for page: Control in pages.get_children():
		page.visible = page == target
	last_focus_restored = false
	if target == null:
		return
	target.modulate.a = 1.0
	target.position.x = 0.0
	if animate and is_inside_tree():
		target.modulate.a = 0.0
		target.position.x = 30.0
		var tween := create_tween().set_parallel(true)
		tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(target, "modulate:a", 1.0, TRANSITION_SECONDS)
		tween.tween_property(target, "position:x", 0.0, TRANSITION_SECONDS)
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
	aim_mode_option.add_item("自动瞄准", AimMode.AUTO_TARGET)
	aim_mode_option.add_item("手动瞄准", AimMode.MANUAL_MOUSE)
	aim_mode_option.select(Global.meta_progress.aim_mode)


func _on_aim_mode_selected(index: int) -> void:
	if index not in [AimMode.AUTO_TARGET, AimMode.MANUAL_MOUSE]:
		return
	draft.aim_mode = index
	selection_flow.draft_changed.emit(draft)


func _setup_run_mode() -> void:
	run_mode_option.clear()
	run_mode_option.add_item("标准模式", RunMode.STANDARD)
	run_mode_option.add_item("无尽模式", RunMode.ENDLESS)
	run_mode_option.select(draft.run_mode)


func _on_run_mode_selected(index: int) -> void:
	if index < 0 or index >= run_mode_option.item_count:
		return
	selection_flow.set_run_mode(run_mode_option.get_item_id(index))


func _build_character_choices() -> void:
	_clear_children(character_choices)
	var random_button := _make_choice_button("？\n随机", null)
	random_button.pressed.connect(choose_random_character)
	character_choices.add_child(random_button)
	for definition: CharacterDef in Content.catalog.get_characters():
		var unlocked := definition.unlock_difficulty <= Global.meta_progress.highest_unlocked_difficulty
		var label := Content.catalog.get_character_display_name(definition)
		if not unlocked:
			label = "🔒\n%s\n难度 %d 解锁" % [label, definition.unlock_difficulty]
		var button := _make_choice_button(
			label,
			Presentation.resolve_texture(
				&"character", definition.get_presentation_id(Content.catalog.pack_id), definition.stats.icon
			)
		)
		button.disabled = not unlocked
		button.set_meta("content_id", definition.get_stable_id(Content.catalog.pack_id))
		button.pressed.connect(choose_character.bind(definition.get_stable_id(Content.catalog.pack_id)))
		button.focus_entered.connect(_preview_character.bind(definition))
		button.mouse_entered.connect(_preview_character.bind(definition))
		character_choices.add_child(button)
	_register_button_feedback(character_choices)


func _preview_character(definition: CharacterDef) -> void:
	_update_character_details(definition)


func _update_character_details(definition: CharacterDef) -> void:
	if definition == null or definition.stats == null:
		return
	var stats := definition.stats
	character_icon.texture = Presentation.resolve_texture(
		&"character", definition.get_presentation_id(Content.catalog.pack_id), stats.icon
	)
	character_name.text = Content.catalog.get_character_display_name(definition)
	character_traits.text = _character_traits_text(definition)
	var stable_id := definition.get_stable_id(Content.catalog.pack_id)
	character_record.text = "最高通关：难度 %d\n无尽纪录：第 %d 波" % [
		Global.meta_progress.highest_clear_for(stable_id),
		Global.meta_progress.highest_endless_wave_any(stable_id),
	]
	weapon_character_icon.texture = character_icon.texture
	weapon_character_name.text = character_name.text
	weapon_character_traits.text = character_traits.text


func _character_traits_text(definition: CharacterDef) -> String:
	var stats := definition.stats
	return (
		"[color=#9ed66f]+ 最大生命 %d[/color]\n"
		+ "[color=#9ed66f]+ 基础伤害 %.1f[/color]\n"
		+ "[color=#86cde8]+ 移动速度 %d[/color]\n"
		+ "[color=#f4d35e]+ 幸运 %.1f[/color]\n"
		+ "[color=#d4a5ff]+ 格挡 %.1f%%[/color]"
	) % [stats.health, stats.damage, stats.speed, stats.luck, stats.block_chance]


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
	var random_button := _make_choice_button("？\n随机", null)
	random_button.pressed.connect(choose_random_weapon)
	weapon_choices.add_child(random_button)
	for definition: WeaponDef in _allowed_weapons(character):
		if definition.tiers.is_empty() or definition.tiers[0] == null:
			continue
		var stable_id := definition.get_stable_id(Content.catalog.pack_id)
		_visible_weapon_ids.append(stable_id)
		var item := definition.tiers[0]
		var button := _make_choice_button(
			Content.catalog.get_item_display_name(item),
			Presentation.resolve_texture(
				&"weapon", definition.get_presentation_id(Content.catalog.pack_id), item.item_icon
			)
		)
		button.set_meta("content_id", stable_id)
		button.pressed.connect(choose_weapon.bind(stable_id))
		button.focus_entered.connect(_preview_weapon.bind(definition))
		button.mouse_entered.connect(_preview_weapon.bind(definition))
		weapon_choices.add_child(button)
	_register_button_feedback(weapon_choices)


func _preview_weapon(definition: WeaponDef) -> void:
	_update_weapon_details(definition)


func _update_weapon_details(definition: WeaponDef) -> void:
	if definition == null or definition.tiers.is_empty():
		return
	var item := definition.tiers[0]
	weapon_icon.texture = Presentation.resolve_texture(
		&"weapon", definition.get_presentation_id(Content.catalog.pack_id), item.item_icon
	)
	weapon_name.text = Content.catalog.get_item_display_name(item)
	weapon_stats.text = _weapon_stats_text(item)


func _weapon_stats_text(item: ItemWeapon) -> String:
	if item == null or item.stats == null:
		return ""
	var type_name := "近战" if item.type == ItemWeapon.WeaponType.MELEE else "远程"
	var tags := Content.catalog.get_tags_for_item(item)
	var tag_text := " / ".join(tags.map(func(tag: StringName): return String(tag).get_slice("/", 1)))
	return (
		"[color=#f4d35e]%s · I 阶[/color]\n\n"
		+ "伤害  [color=#9ed66f]%.1f[/color]\n"
		+ "攻速  [color=#9ed66f]%.2f 秒[/color]\n"
		+ "暴击  [color=#9ed66f]%.0f%% × %.1f[/color]\n"
		+ "射程  [color=#9ed66f]%.0f[/color]\n"
		+ "击退  [color=#86cde8]%.1f[/color]\n"
		+ "标签  [color=#d4a5ff]%s[/color]"
	) % [
		type_name, item.stats.damage, item.stats.cooldown,
		item.stats.crit_chance * 100.0, item.stats.crit_damage,
		item.stats.max_range, item.stats.knockback, tag_text,
	]


func _update_final_overview() -> void:
	var character := Content.catalog.get_character(draft.character_id)
	var weapon := Content.catalog.get_weapon(draft.weapon_id)
	if character != null:
		overview_character_name.text = Content.catalog.get_character_display_name(character)
		overview_character_icon.texture = Presentation.resolve_texture(
			&"character", character.get_presentation_id(Content.catalog.pack_id), character.stats.icon
		)
		overview_character_traits.text = _character_traits_text(character)
	if weapon != null and not weapon.tiers.is_empty():
		overview_weapon_name.text = Content.catalog.get_item_display_name(weapon.tiers[0])
		overview_weapon_icon.texture = Presentation.resolve_texture(
			&"weapon", weapon.get_presentation_id(Content.catalog.pack_id), weapon.tiers[0].item_icon
		)
		overview_weapon_stats.text = _weapon_stats_text(weapon.tiers[0])


func _build_difficulty_choices() -> void:
	_clear_children(difficulty_choices)
	var unlocked := Global.meta_progress.highest_unlocked_difficulty
	for definition: DifficultyDef in Content.catalog.get_difficulties():
		var level := definition.level
		var cleared := Global.meta_progress.highest_clear_for(draft.character_id) >= level
		var label := "难度 %d%s" % [level, "  ✓" if cleared else ""]
		if level > unlocked:
			label = "🔒 难度 %d" % level
		var button := Button.new()
		button.custom_minimum_size = Vector2(250, 82)
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
	var lock_line := "[color=#e46d58]尚未解锁[/color]\n\n" if locked else "[color=#9ed66f]点击即进入第一波[/color]\n\n"
	difficulty_rules.text = lock_line + (
		"敌人生命  [color=#f4d35e]× %.2f[/color]\n"
		+ "敌人伤害  [color=#f4d35e]× %.2f[/color]\n"
		+ "敌人速度  [color=#f4d35e]× %.2f[/color]\n"
		+ "生成密度  [color=#f4d35e]× %.2f[/color]\n\n"
		+ "精英生命  [color=#e46d58]× %.2f[/color]\n"
		+ "商店价格  [color=#e46d58]× %.2f[/color]\n"
		+ "材料掉落  [color=#86cde8]× %.2f[/color]\n\n"
		+ "第 10 / 15 波：精英\n第 20 波：终局 Boss"
	) % [
		definition.health_multiplier, definition.damage_multiplier,
		definition.speed_multiplier, definition.spawn_density_multiplier,
		definition.elite_health_multiplier, definition.shop_price_multiplier,
		definition.material_drop_multiplier,
	]
	if draft.run_mode == RunMode.ENDLESS:
		difficulty_rules.text += "\n\n[color=#d4a5ff]无尽模式：20 波后继续，每 5 波一轮。[/color]"
	else:
		difficulty_rules.text += "\n\n[color=#9ed66f]标准模式：击败第 20 波 Boss 后结算。[/color]"


func _make_choice_button(label: String, icon_texture: Texture2D) -> Button:
	var button := Button.new()
	button.custom_minimum_size = CARD_SIZE
	button.text = label
	button.icon = icon_texture
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 76)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_ALL
	return button


func _refresh_profiles() -> void:
	_clear_children(profile_choices)
	repair_notice_label.text = "\n".join(Global.meta_progress.repair_notices)
	repair_notice_label.visible = not Global.meta_progress.repair_notices.is_empty()
	var active_id := Global.active_profile_id()
	var summaries := Global.profile_summaries()
	for slot in range(1, ProfileStore.MAX_PROFILES + 1):
		var summary: Dictionary = summaries[slot - 1] if slot <= summaries.size() else {
			"id": slot, "name": "档案 %d" % slot, "exists": false, "has_checkpoint": false,
		}
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var select_button := Button.new()
		select_button.custom_minimum_size = Vector2(720, 92)
		select_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var state := "可继续" if bool(summary.get("has_checkpoint", false)) else ("已有进度" if bool(summary.get("exists", false)) else "空档案")
		var endless_high := int(summary.get("highest_endless_wave", 0))
		if endless_high > 0:
			state += " · 无尽 %d 波" % endless_high
		select_button.text = "%s%s\n%s" % ["● " if slot == active_id else "", str(summary.get("name", "档案 %d" % slot)), state]
		select_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		select_button.pressed.connect(_select_profile.bind(slot))
		row.add_child(select_button)
		var rename_button := Button.new()
		rename_button.custom_minimum_size = Vector2(130, 92)
		rename_button.text = "重命名"
		rename_button.pressed.connect(_request_rename_profile.bind(slot, str(summary.get("name", ""))))
		row.add_child(rename_button)
		var delete_button := Button.new()
		delete_button.custom_minimum_size = Vector2(130, 92)
		delete_button.text = "删除"
		delete_button.disabled = not bool(summary.get("exists", false))
		delete_button.pressed.connect(_request_delete_profile.bind(slot))
		row.add_child(delete_button)
		profile_choices.add_child(row)
	_register_button_feedback(profile_choices)

	var active_summary: Dictionary = summaries[active_id - 1] if active_id <= summaries.size() else {}
	var profile_name := str(active_summary.get("name", "档案 %d" % active_id))
	profile_button.text = "%s  ›" % profile_name
	var has_checkpoint := bool(active_summary.get("has_checkpoint", false))
	primary_button.text = "继续" if has_checkpoint else "开始"
	new_game_button.visible = has_checkpoint


func _select_profile(profile_id: int) -> void:
	if not Global.switch_profile(profile_id):
		return
	_build_character_choices()
	_setup_aim_mode()
	_setup_run_mode()
	_refresh_profiles()
	profile_changed.emit(profile_id)
	selection_flow.reset_to_title()


func _setup_profile_dialogs() -> void:
	_new_game_dialog = ConfirmationDialog.new()
	_new_game_dialog.title = "覆盖当前检查点？"
	_new_game_dialog.dialog_text = "新游戏会覆盖当前未结束单局的波次检查点。局外解锁不会丢失。"
	_new_game_dialog.ok_button_text = "开始新游戏"
	_new_game_dialog.confirmed.connect(_begin_confirmed_new_game)
	add_child(_new_game_dialog)

	_delete_dialog = ConfirmationDialog.new()
	_delete_dialog.title = "删除档案？"
	_delete_dialog.dialog_text = "该档案的解锁、图鉴和检查点都会删除，此操作不可撤销。"
	_delete_dialog.ok_button_text = "确认删除"
	_delete_dialog.confirmed.connect(_confirm_delete_profile)
	add_child(_delete_dialog)

	_rename_dialog = ConfirmationDialog.new()
	_rename_dialog.title = "重命名档案"
	_rename_dialog.ok_button_text = "保存"
	_rename_input = LineEdit.new()
	_rename_input.max_length = 24
	_rename_input.placeholder_text = "输入档案名称"
	_rename_dialog.add_child(_rename_input)
	_rename_dialog.confirmed.connect(_confirm_rename_profile)
	add_child(_rename_dialog)


func _request_delete_profile(profile_id: int) -> void:
	_pending_profile_action = profile_id
	_delete_dialog.popup_centered(Vector2i(560, 240))


func _confirm_delete_profile() -> void:
	if Global.delete_profile(_pending_profile_action) == OK:
		_refresh_profiles()
	_pending_profile_action = 0


func _request_rename_profile(profile_id: int, current_name: String) -> void:
	_pending_profile_action = profile_id
	_rename_input.text = current_name
	_rename_dialog.popup_centered(Vector2i(560, 260))
	_rename_input.call_deferred("grab_focus")


func _confirm_rename_profile() -> void:
	if Global.rename_profile(_pending_profile_action, _rename_input.text) == OK:
		_refresh_profiles()
	_pending_profile_action = 0


func _on_primary_pressed() -> void:
	var summaries := Global.profile_summaries()
	var index := Global.active_profile_id() - 1
	var has_checkpoint := index >= 0 and index < summaries.size() and bool(summaries[index].get("has_checkpoint", false))
	if has_checkpoint:
		continue_requested.emit()
	else:
		begin_new_run()


func _on_new_game_pressed() -> void:
	_new_game_dialog.popup_centered(Vector2i(620, 260))


func _begin_confirmed_new_game() -> void:
	Global.end_run()
	Global.save_progress(false)
	begin_new_run()


func _on_profiles_pressed() -> void:
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
		device_hint.text = "%s 确认  ·  %s 返回" % [
			InputDevices.confirm_prompt(), InputDevices.back_prompt()
		]


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
			button.pressed.connect(GameplayCues.emit_cue.bind(&"ui.confirm", {}))
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
	if not is_instance_valid(button) or button.disabled:
		return
	button.pivot_offset = button.size * 0.5
	var tween := button.create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "scale", Vector2.ONE * (1.025 if active else 1.0), 0.08)
