extends GdUnitTestSuite


const CORE_ZH := "res://content_packs/default/i18n/game.zh_CN.po"
const CORE_EN := "res://content_packs/default/i18n/game.en.po"
const DEV_SKIN_ZH := "res://content_packs/skins/dev_placeholder/i18n/skin.zh_CN.po"
const DEV_SKIN_EN := "res://content_packs/skins/dev_placeholder/i18n/skin.en.po"
const ALT_SKIN_ZH := "res://content_packs/skins/test_alt/i18n/skin.zh_CN.po"
const ALT_SKIN_EN := "res://content_packs/skins/test_alt/i18n/skin.en.po"
const RELEASE_SKIN_ZH := "res://content_packs/skins/lets_gooooo/i18n/skin.zh_CN.po"
const RELEASE_SKIN_EN := "res://content_packs/skins/lets_gooooo/i18n/skin.en.po"

var _original_locale := ""


func before_test() -> void:
	_original_locale = TranslationServer.get_locale()
	LocalizedTextService.configure_core_paths([CORE_ZH, CORE_EN])
	LocalizedTextService.configure_skin_paths([DEV_SKIN_ZH, DEV_SKIN_EN])


func after_test() -> void:
	TranslationServer.set_locale(_original_locale)
	LocalizedTextService.configure_core_paths([CORE_ZH, CORE_EN])
	LocalizedTextService.configure_skin_paths([DEV_SKIN_ZH, DEV_SKIN_EN])


func test_chinese_missing_key_never_uses_english_fallback() -> void:
	var english_only := Translation.new()
	english_only.locale = "en"
	english_only.add_message(&"missing.runtime.copy", "Leaked English")
	TranslationServer.add_translation(english_only)
	TranslationServer.set_locale("zh_CN")
	assert_str(LocalizedTextService.resolve(
		&"missing.runtime.copy", [], "Damage"
	)).is_equal(LocalizedTextService.DEFAULT_ZH_MISSING_TEXT)
	assert_str(LocalizedTextService.resolve(
		&"missing.content.name", [], "Coffee"
	)).is_equal(LocalizedTextService.DEFAULT_ZH_MISSING_NAME)
	TranslationServer.remove_translation(english_only)


func test_runtime_catalogs_recover_from_the_actual_autoloads_before_ready() -> void:
	TranslationServer.set_locale("zh_CN")
	LocalizedTextService.configure_core_paths([])
	LocalizedTextService.clear_skin_paths()
	assert_str(LocalizedTextService.resolve(&"ui.title.start")).is_equal("开始游戏")
	assert_str(LocalizedTextService.resolve(&"ui.title.name")).is_equal("LET'S GOOOOO")


func test_active_skin_copy_overrides_core_copy_deterministically() -> void:
	TranslationServer.set_locale("zh_CN")
	assert_str(LocalizedTextService.resolve(&"ui.title.name")).is_equal("GOBRO")
	LocalizedTextService.configure_skin_paths([ALT_SKIN_ZH, ALT_SKIN_EN])
	assert_str(LocalizedTextService.resolve(&"ui.title.name")).is_equal("替代表现测试")
	assert_str(LocalizedTextService.resolve(&"ui.title.start")).is_equal("开始游戏")
	assert_str(LocalizedTextService.resolve(&"character.brawler.name")).is_equal("替代斗士")
	assert_str(LocalizedTextService.resolve(&"weapon.smg.name")).is_equal("替代连发器")
	assert_str(LocalizedTextService.resolve(&"passive.cape.name")).is_equal("替代披风")
	assert_str(LocalizedTextService.resolve(&"enemy.charger.name")).is_equal("替代冲击兽")


func test_core_catalogs_have_matching_keys_and_do_not_mix_languages() -> void:
	var zh := load(CORE_ZH) as Translation
	var en := load(CORE_EN) as Translation
	assert_object(zh).is_not_null()
	assert_object(en).is_not_null()
	if zh == null or en == null:
		return
	var zh_keys := Array(zh.get_message_list())
	var en_keys := Array(en.get_message_list())
	zh_keys.sort()
	en_keys.sort()
	assert_array(zh_keys).contains_exactly(en_keys)
	for raw_key: Variant in zh_keys:
		var key := str(raw_key)
		var zh_message := str(zh.get_message(key))
		var en_message := str(en.get_message(key))
		assert_bool(_contains_disallowed_latin(zh_message)).override_failure_message(
			"Chinese translation contains untranslated Latin copy: %s = %s" % [key, zh_message]
		).is_false()
		assert_bool(_contains_han(en_message)).override_failure_message(
			"English translation contains Han characters: %s = %s" % [key, en_message]
		).is_false()


func test_release_skin_catalogs_have_matching_keys_and_do_not_mix_languages() -> void:
	var zh := load(RELEASE_SKIN_ZH) as Translation
	var en := load(RELEASE_SKIN_EN) as Translation
	assert_object(zh).is_not_null()
	assert_object(en).is_not_null()
	if zh == null or en == null:
		return
	var zh_keys := Array(zh.get_message_list())
	var en_keys := Array(en.get_message_list())
	zh_keys.sort()
	en_keys.sort()
	assert_array(zh_keys).contains_exactly(en_keys)
	for raw_key: Variant in zh_keys:
		var key := str(raw_key)
		var zh_message := str(zh.get_message(key))
		var en_message := str(en.get_message(key))
		assert_bool(_contains_disallowed_latin(zh_message)).override_failure_message(
			"Release skin Chinese copy contains untranslated Latin text: %s = %s" % [
				key, zh_message,
			]
		).is_false()
		assert_bool(_contains_han(en_message)).override_failure_message(
			"Release skin English copy contains Han characters: %s = %s" % [key, en_message]
		).is_false()


func test_release_skin_replaces_every_visible_legacy_product_reference() -> void:
	LocalizedTextService.configure_skin_paths([RELEASE_SKIN_ZH, RELEASE_SKIN_EN])
	for locale: String in ["zh_CN", "en"]:
		TranslationServer.set_locale(locale)
		for key: StringName in [
			&"ui.title.name", &"ui.frontend.build", &"ui.character.hint", &"ui.codex.title",
		]:
			var rendered := LocalizedTextService.resolve(key)
			assert_str(rendered).override_failure_message(
				"Legacy brand leaked through %s/%s" % [locale, key]
			).not_contains("GOBRO")
		assert_str(LocalizedTextService.resolve(&"ui.title.name")).is_equal("LET'S GOOOOO")


func test_every_visible_content_name_exists_in_both_locales() -> void:
	var definitions: Array[ContentDef] = []
	definitions.append_array(Content.catalog.get_characters())
	definitions.append_array(Content.catalog.get_weapons())
	definitions.append_array(Content.catalog.get_passives())
	definitions.append_array(Content.catalog.get_enemies())
	for definition: ContentDef in definitions:
		assert_bool(LocalizedTextService.has_message(
			definition.display_name_key, "zh_CN"
		)).override_failure_message(
			"Missing Chinese content name: %s" % definition.display_name_key
		).is_true()
		assert_bool(LocalizedTextService.has_message(
			definition.display_name_key, "en"
		)).override_failure_message(
			"Missing English content name: %s" % definition.display_name_key
		).is_true()


func test_item_formatter_uses_typed_modifiers_and_localized_actual_weapon_values() -> void:
	TranslationServer.set_locale("zh_CN")
	var coffee := Content.catalog.get_passive(&"passive/coffee")
	assert_object(coffee).is_not_null()
	if coffee != null:
		var passive_text := ItemDescriptionFormatter.format_passive(coffee.item)
		assert_str(passive_text).contains("攻击速度")
		assert_str(passive_text).contains("伤害")
		assert_str(passive_text).not_contains("Damage")
		assert_str(passive_text).not_contains("Coffee")
	var smg := Content.catalog.get_weapon(&"weapon/smg")
	assert_object(smg).is_not_null()
	if smg != null and not smg.tiers.is_empty():
		var stats := PlayerStats.new({"damage": 10.0, "ranged_damage": 3.0})
		var weapon_text := ItemDescriptionFormatter.format_weapon(smg.tiers[0], stats)
		assert_str(weapon_text).contains("伤害")
		assert_str(weapon_text).contains("暴击")
		assert_str(weapon_text).not_contains("Damage")


func test_release_skin_flavor_is_visible_but_core_mechanics_remain_authoritative() -> void:
	LocalizedTextService.configure_skin_paths([RELEASE_SKIN_ZH, RELEASE_SKIN_EN])
	TranslationServer.set_locale("zh_CN")
	var ak := Content.catalog.get_weapon(&"weapon/carbine")
	var coffee := Content.catalog.get_passive(&"passive/coffee")
	assert_object(ak).is_not_null()
	assert_object(coffee).is_not_null()
	if ak != null:
		var text := ItemDescriptionFormatter.format_weapon(ak.tiers[0])
		assert_str(text).contains("第一发永远值得尊重")
		assert_str(text).contains("伤害")
	if coffee != null:
		var text := ItemDescriptionFormatter.format_passive(coffee.item)
		assert_str(text).contains("热身五分钟")
		assert_str(text).contains("攻击速度")


func test_character_traits_render_active_rule_contract_instead_of_legacy_five_stat_snapshot() -> void:
	TranslationServer.set_locale("zh_CN")
	var well_rounded := Content.catalog.get_character(&"character/well_rounded")
	var balanced_text := FrontendViewModel.character_traits(well_rounded)
	assert_str(balanced_text).contains("最大生命")
	assert_str(balanced_text).contains("移动速度")
	assert_str(balanced_text).contains("收获")
	assert_str(balanced_text).not_contains("450")
	var brawler := Content.catalog.get_character(&"character/brawler")
	var brawler_text := FrontendViewModel.character_traits(brawler)
	assert_str(brawler_text).contains("攻击速度")
	assert_str(brawler_text).contains("闪避")
	assert_str(brawler_text).contains("远程伤害")
	assert_str(brawler_text).contains("仅可使用")
	var glass_cannon := Content.catalog.get_character(&"character/glass_cannon")
	assert_str(FrontendViewModel.character_traits(glass_cannon)).contains("武器槽上限：1")


func test_character_traits_render_every_active_scalar_rule_with_explicit_units_and_color() -> void:
	TranslationServer.set_locale("zh_CN")
	var zh_expectations := {
		&"character/almighty": ["[color=#e46d58]经验获取 × 0.50[/color]"],
		&"character/knight": ["[color=#9ed66f]消耗品额外治疗 +3.0 点生命[/color]"],
		&"character/dash_raider": [
			"[color=#9ed66f]闪避上限 90%[/color]",
			"[color=#9ed66f]冲刺冷却 × 0.72[/color]",
			"[color=#9ed66f]冲刺持续时间 × 1.15[/color]",
		],
		&"character/bloodbound": ["[color=#9ed66f]消耗品治疗 × 1.30[/color]"],
		&"character/scrap_broker": [
			"[color=#9ed66f]商店价格 × 0.75[/color]",
			"[color=#9ed66f]回收收益 × 1.25[/color]",
			"[color=#e46d58]每波开始时材料清零[/color]",
			"[color=#9ed66f]初始材料 +25[/color]",
			"商店偏好：",
		],
		&"character/glass_cannon": ["[color=#e46d58]冲刺冷却 × 1.15[/color]"],
		&"character/crazy": ["[color=#f4d35e]初始武器：刺刀[/color]"],
	}
	_assert_character_trait_expectations(zh_expectations)

	TranslationServer.set_locale("en")
	var en_expectations := {
		&"character/almighty": ["[color=#e46d58]Experience gain × 0.50[/color]"],
		&"character/knight": ["[color=#9ed66f]Consumable healing +3.0 HP[/color]"],
		&"character/dash_raider": [
			"[color=#9ed66f]Dodge cap 90%[/color]",
			"[color=#9ed66f]Dash cooldown × 0.72[/color]",
			"[color=#9ed66f]Dash duration × 1.15[/color]",
		],
		&"character/bloodbound": ["[color=#9ed66f]Consumable healing × 1.30[/color]"],
		&"character/scrap_broker": [
			"[color=#9ed66f]Shop prices × 0.75[/color]",
			"[color=#9ed66f]Recycle value × 1.25[/color]",
			"[color=#e46d58]Materials reset to 0 at the start of each wave[/color]",
			"[color=#9ed66f]Starting materials +25[/color]",
			"Shop favors: ",
		],
		&"character/glass_cannon": ["[color=#e46d58]Dash cooldown × 1.15[/color]"],
		&"character/crazy": ["[color=#f4d35e]Starting weapon: Bayonet[/color]"],
	}
	_assert_character_trait_expectations(en_expectations)


func test_every_runtime_supported_character_rule_has_a_localized_visible_projection() -> void:
	for locale: String in ["zh_CN", "en"]:
		TranslationServer.set_locale(locale)
		for character: CharacterDef in Content.catalog.get_characters():
			var rules := character.rules
			if rules == null:
				continue
			var text := FrontendViewModel.character_traits(character)
			for raw_rule_id: Variant in rules.runtime_support:
				if not bool(rules.runtime_support[raw_rule_id]):
					continue
				_assert_runtime_rule_projection(
					str(raw_rule_id), rules, text, locale, character.content_id
				)
			assert_str(text).not_contains("core:")
			assert_str(text).not_contains("character_rule/")
			assert_str(text).not_contains("runtime_support")


func test_effect_only_passives_render_typed_mechanics_in_chinese() -> void:
	TranslationServer.set_locale("zh_CN")
	var echo_round := Content.catalog.get_passive(&"passive/echo_round")
	var volatile_core := Content.catalog.get_passive(&"passive/volatile_core")
	assert_object(echo_round).is_not_null()
	assert_object(volatile_core).is_not_null()
	if echo_round != null:
		var echo_text := ItemDescriptionFormatter.format_passive(echo_round.item)
		assert_str(echo_text).contains("命中时")
		assert_str(echo_text).contains("恢复 1 点生命")
		assert_str(echo_text).not_contains("effect/passive")
		assert_str(echo_text).not_contains("Heal")
	if volatile_core != null:
		var volatile_text := ItemDescriptionFormatter.format_passive(volatile_core.item)
		assert_str(volatile_text).contains("暴击时")
		assert_str(volatile_text).contains("额外造成 1.25 点伤害")
		assert_str(volatile_text).not_contains("critical_hit")
		assert_str(volatile_text).not_contains("Damage")


func test_effect_only_passives_render_typed_mechanics_in_english() -> void:
	TranslationServer.set_locale("en")
	var echo_round := Content.catalog.get_passive(&"passive/echo_round")
	var volatile_core := Content.catalog.get_passive(&"passive/volatile_core")
	assert_object(echo_round).is_not_null()
	assert_object(volatile_core).is_not_null()
	if echo_round != null:
		var echo_text := ItemDescriptionFormatter.format_passive(echo_round.item)
		assert_str(echo_text).contains("On hit")
		assert_str(echo_text).contains("Heal 1 health")
		assert_str(echo_text).not_contains("effect/passive")
		assert_str(echo_text).not_contains("命中")
	if volatile_core != null:
		var volatile_text := ItemDescriptionFormatter.format_passive(volatile_core.item)
		assert_str(volatile_text).contains("On critical hit")
		assert_str(volatile_text).contains("Deal 1.25 extra damage")
		assert_str(volatile_text).not_contains("critical_hit")
		assert_str(volatile_text).not_contains("伤害")


func test_material_notice_bus_distinguishes_bag_bonus_and_banking() -> void:
	var bus := GameplayNoticeBus.new()
	var emitted: Array[Dictionary] = []
	bus.notice_emitted.connect(func(key: StringName, args: Array, priority: int):
		emitted.append({"key": key, "args": args, "priority": priority})
	)
	bus.material_pickup(7, 3)
	bus.materials_banked(11, true)
	assert_int(emitted.size()).is_equal(2)
	assert_str(String(emitted[0].key)).is_equal("ui.notice.material_bag_bonus")
	assert_array(emitted[0].args).contains_exactly([4, 3, 7])
	assert_str(String(emitted[1].key)).is_equal("ui.notice.materials_banked_first")


func test_settlement_resolves_character_name_instead_of_exposing_stable_id() -> void:
	TranslationServer.set_locale("zh_CN")
	var character := Content.catalog.get_characters()[0]
	var run := RunState.new(42)
	run.character_id = character.get_stable_id(Content.catalog.pack_id)
	run.wave = 20
	var panel: SettlementPanel = auto_free(load(
		"res://scenes/ui/settlement_panel/settlement_panel.tscn"
	).instantiate())
	add_child(panel)
	await await_idle_frame()
	panel.show_result(run, true)
	assert_str(panel.details_label.text).contains(
		ItemDescriptionFormatter.character_display_name(character)
	)
	assert_str(panel.details_label.text).not_contains("core:")


func _assert_character_trait_expectations(expectations: Dictionary) -> void:
	for raw_character_id: Variant in expectations:
		var character := Content.catalog.get_character(StringName(str(raw_character_id)))
		assert_object(character).override_failure_message(
			"Missing character fixture: %s" % raw_character_id
		).is_not_null()
		if character == null:
			continue
		var text := FrontendViewModel.character_traits(character)
		for raw_expected: Variant in expectations[raw_character_id]:
			assert_str(text).override_failure_message(
				"Missing character rule copy for %s: %s\nActual:\n%s" % [
					raw_character_id, raw_expected, text,
				]
			).contains(str(raw_expected))
		assert_str(text).not_contains("core:")
		assert_str(text).not_contains("character_rule/")


func _assert_runtime_rule_projection(
	rule_id: String,
	rules: CharacterRuleDef,
	text: String,
	locale: String,
	character_id: StringName
) -> void:
	var expected := ""
	match rule_id:
		"starting_stats":
			for raw_stat: Variant in rules.starting_stat_modifiers:
				var stat_id := StatId.from_key(str(raw_stat))
				if StatId.is_valid(stat_id):
					expected = LocalizedTextService.resolve(
						StringName("stat.%s" % StatId.key(stat_id))
					)
					break
		"stat_modification_multipliers":
			expected = "获取量" if locale.begins_with("zh") else " gains"
		"unarmed_only", "ethereal_only":
			expected = "仅可使用" if locale.begins_with("zh") else "Weapons limited to"
		"no_melee_weapons":
			expected = "不可使用" if locale.begins_with("zh") else "Cannot use"
		"forced_starting_weapon":
			expected = "初始武器" if locale.begins_with("zh") else "Starting weapon"
		"consumable_healing_bonus":
			expected = "消耗品额外治疗" if locale.begins_with("zh") else "Consumable healing +"
		"life_steal_floor":
			expected = LocalizedTextService.resolve(&"stat.life_steal")
		"experience_gain_multiplier":
			expected = "经验获取" if locale.begins_with("zh") else "Experience gain"
		"dodge_cap_override":
			expected = "闪避上限" if locale.begins_with("zh") else "Dodge cap"
		"shop_price_multiplier":
			expected = "商店价格" if locale.begins_with("zh") else "Shop prices"
		"recycle_value_multiplier":
			expected = "回收收益" if locale.begins_with("zh") else "Recycle value"
		"materials_reset_on_wave_start":
			expected = "材料清零" if locale.begins_with("zh") else "Materials reset"
		"weapon_slot_limit":
			expected = "武器槽上限" if locale.begins_with("zh") else "Weapon slot limit"
		_:
			assert_bool(false).override_failure_message(
				"runtime_supported=true rule has no projection contract: %s (%s)" % [
					rule_id, character_id,
				]
			).is_true()
			return
	assert_str(expected).override_failure_message(
		"Projection fixture is empty for %s (%s)" % [rule_id, character_id]
	).is_not_empty()
	assert_str(text).override_failure_message(
		"runtime_supported=true rule is hidden: %s (%s, %s)\nActual:\n%s" % [
			rule_id, character_id, locale, text,
		]
	).contains(expected)


func _contains_disallowed_latin(value: String) -> bool:
	var cleaned := value
	var bbcode := RegEx.new()
	bbcode.compile("\\[[^\\]]+\\]")
	cleaned = bbcode.sub(cleaned, "", true)
	var placeholders := RegEx.new()
	placeholders.compile("(%[-+0-9.]*[a-zA-Z]|\\{[^}]+\\})")
	cleaned = placeholders.sub(cleaned, "", true)
	# Weapon model names are intentionally identical in both locales; all prose
	# remains translated. Keep this allowlist narrow so English stat/UI copy still fails.
	for allowed: String in [
		"GOBRO", "LET'S GOOOOO", "M9", "Zeus x27", "AWP", "Glock-18", "M4A4", "P90", "AK-47",
		"M4A1-S", "UMP-45", "MP9", "MAC-10", "C4", "USP-S",
	]:
		cleaned = cleaned.replace(allowed, "")
	var latin := RegEx.new()
	latin.compile("[A-Za-z]")
	return latin.search(cleaned) != null


func _contains_han(value: String) -> bool:
	for index in value.length():
		var codepoint := value.unicode_at(index)
		if codepoint >= 0x3400 and codepoint <= 0x9FFF:
			return true
	return false
