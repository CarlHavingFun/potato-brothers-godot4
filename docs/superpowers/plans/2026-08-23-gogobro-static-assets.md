# GOGOBRO static assets implementation plan

## Global constraints

- Implement original GOGOBRO chunky true-pixel art and generic tactical-shooter community humor. Do not copy scripts, assets, names, UI geometry, official logos, team/event marks, real-player likenesses, map names, proprietary skin patterns, or quotes from another game.
- `E:/BrotatoResearchMod/game-project` is behavior-scale research only. No source, resource, copy, ID, coordinate, or art may be copied.
- Keep the existing Master Ni walk-down atlas byte-identical: 8 frames, 128x128 cells, 1024x128 atlas, 8 FPS. Appearances are separate layers.
- Approval states are exactly `planned -> generated -> review -> approved -> integrated -> qa_passed`. Only approved artifacts may enter `curated` or a runtime skin pack.
- The plan is intentionally human-gated. This execution stops after Task 3 presents the first single candidate for approval. Task 4 may start only after explicit user approval.
- All runtime names and descriptions have `zh_CN` and `en`. Characters, enemies, weapons, items, and upgrades also have one-line bilingual flavor copy. Numeric effect prose is generated from effect data and is never stored as a second handwritten value string.
- Master objects use 64 logical pixels rendered at 4x to 256x256; wearable runtime images use 128x128; small projectiles/HUD icons use 128x128; backgrounds use 1920x1080 from 480x270 logical pixels.
- AI output is raw only. Publishable stills must pass sprite-gen deterministic chroma removal, pixel-unfake/grid cleanup, binary-alpha and transparent-RGB checks. Raw/chroma/candidates are never loaded by runtime.
- Do not switch the startup chain or remove placeholders until all current runtime categories are approved. This branch may add the new registry and review artifacts without making incomplete content the default.

## Task 1: Canonical 76-unit registry and validator

Create a single canonical JSON registry at `game/content/assets/gogobro_static_assets_v1.json`, a focused loader/validator at `game/content/assets/static_asset_registry.gd`, and a focused GdUnit test at `tests/unit/test_static_asset_registry.gd`.

Use strict TDD: write and run the focused test first and record the expected RED result, implement the minimum loader/validator and registry, then record GREEN. The full baseline currently has unrelated stale directional-sprite test parse failures; do not change those files. Run only `res://tests/unit/test_static_asset_registry.gd` for this task.

The registry must contain exactly these category counts and exactly 76 approval units:

- `character_creature`: 5
- `weapon`: 13
- `projectile_hit_kit`: 1
- `item`: 30
- `upgrade`: 6
- `world`: 11
- `ui_brand`: 10

Each entry includes: `asset_id`, `category`, `content_id`, bilingual localization, structured effect data where applicable, rarity, max count, appearance slot/mode/depth where applicable, prompt version, output specification, intended file paths, hashes (nullable before generation), and approval status. IDs must be unique and stable lower-snake-case. All initial entries are `planned`. The validator must reject wrong counts, duplicate IDs/content IDs, unknown category/status, missing bilingual copy, handwritten numeric effect text, and missing mandatory item/upgrade fields.

The 76 units are:

1. Character/creature: Master Ni / 尼公子; Lost Rotator / 迷路补位员; Long-Angle Sentry / 远点架枪机; Force-Buy Rusher / 强起冲锋者; Site-Scout Chicken / 巡点鸡.
2. Weapon: Warmup Shiv / 热身短刃; Community Tapper / 社区连点器; Wood-Stock Assault Rifle / 木托突击步枪; Service Carbine / 制式卡宾枪; Heavy Bolt Sniper / 重型栓动狙; Suppressed Carbine / 消音卡宾枪; Suppressed Tactical Pistol / 消音战术手枪; Heavy Hand Cannon / 重型手炮; Service Pistol / 制式手枪; Box Submachine Gun / 盒式冲锋枪; Compact Submachine Gun / 紧凑冲锋枪; Bullpup PDW / 牛头式 PDW; Folding-Stock Submachine Gun / 折叠托冲锋枪.
3. Projectile/hit kit: pistol/SMG round, rifle round, sniper round, hostile pulse, and static hit/critical/pierce/explosion marks as sub-assets of one unit.
4. Items: the 30 rows in the table below.
5. Upgrade: One More Round / 多活一回合; Trade-Step Drills / 补枪步伐; Pre-Aim Drills / 预瞄训练; Economy Sense / 经济嗅觉; Kevlar Reinforcement / 甲板加固; Medical Timeout / 医疗暂停.
6. World: Community Server Floor / 社区服地砖; Arena Boundary Border / 场界边框; Community Server Decor Pack / 社区服装饰包 (six original variants); Spawn Marker / 出生点标记; Experience Pickup / 经验拾取物; Supply Pickup / 补给拾取物; Medical Pickup / 医疗拾取物; Site-Hold Turret / 守点炮台; Hazard Beacon / 危险信标; Supply Crate / 补给箱; Weapon Rack / 武器架.
7. UI/brand: GOGOBRO Wordmark / GOGOBRO 标志锁定字; Menu Background / 菜单背景; Nine-Slice Panel / 九宫格面板; Card and Rarity Frame Kit / 卡片与四级稀有度边框; Four-State Button / 四状态按钮; Combat HUD Shell / 战斗 HUD 外壳; HUD Icon Kit / HUD 图标; Control Icon Kit / 操作图标; Zone Thumbnail / 区域缩略图; Difficulty Badge Kit / 难度徽章.

### Item effect data

Use operation values, not handwritten effect prose. Percent values are integer percentage-point semantics. `null` max count means unlimited.

| ID | zh_CN / en | rarity x max | effects | slot |
|---|---|---|---|---|
| ballistic_liner | 防弹内衬 / Ballistic Liner | common x3 | max_health +3 | torso |
| silent_step_insoles | 静步鞋垫 / Silent-Step Insoles | common xnull | move_speed_pct +3 | feet |
| crosshair_shim | 准星校片 / Crosshair Shim | common xnull | damage_pct +5 | wrist |
| supply_radar | 补给雷达 / Supply Radar | common x3 | economy +5 | side_left |
| trade_guard | 补枪护腕 / Trade Guard | common x3 | armor +1 | wrist |
| tactical_med_patch | 战术急救贴 / Tactical Med Patch | common x3 | regeneration +2 | torso |
| smoke_shell_helmet | 封烟头盔 / Smoke-Shell Helmet | common x3 | armor +1; move_speed_pct -3 | head |
| force_buy_runners | 强起跑鞋 / Force-Buy Runners | common xnull | move_speed_pct +6; armor -1 | feet |
| eco_round_coin_pouch | 经济局零钱袋 / Eco-Round Coin Pouch | common xnull | economy +5; damage_pct -3 | side_right |
| rebound_fire_bottle | 反弹火线瓶 / Rebound Fire Bottle | uncommon x3 | damage_pct +5; explosion_damage_pct +15; armor -1 | side_left |
| entry_fragger_dumbbell | 突破手哑铃 / Entry-Fragger Dumbbell | uncommon x3 | max_health +3; melee_damage +2; move_speed_pct -3 | back |
| corner_lucky_claw | 夹点幸运爪 / Corner Lucky Claw | uncommon x2 | critical_chance +5; dodge +3; range -15 | trinket_left |
| scorched_defuse_pliers | 灼热拆包钳 / Scorched Defuse Pliers | rare x1 | armor +2; regeneration +3; dodge -5; conditional health_lte_pct 50 => attack_speed_pct +15 | side_right |
| save_time_watch | 保枪倒计表 / Save-Time Watch | rare x1 | economy +8; move_speed_pct -3; conditional wave_progress_gte_pct 75 => move_speed_pct +20, dodge +20, damage_pct -20 | wrist |
| skyline_grenade | 天外高抛雷 / Skyline Grenade | rare x1 | per_weapon every_nth_ranged_attack 7 => explosion 100% attack damage; range -15 | side_left |
| post_match_analysis_desk | 赛后复盘台 / Post-Match Analysis Desk | legendary x4 | progressive four-stage; stage 4 first_damage_taken_per_wave => negate and knockback_nearby | back |
| one_missed_shot | 只空那一发 / The One Missed Shot | legendary x1 | ranged_damage +4; attack_speed_pct -10; per_weapon every_nth_ranged_attack 5 => forced_critical and critical_damage_pct +50 | trinket_right |
| falling_sniper_charm | 坠线狙击挂件 / Falling Sniper Charm | legendary x1 | range +100; ranged_damage +3; attack_speed_pct -10; while_moving ranged_attack => damage_pct +25 and pierce +1 | trinket_left |
| boost_step_stool | 垫点折凳 / Boost Step Stool | common x2 | move_speed_pct +3; dodge +3 | back |
| post_match_mic | 赛后嘴硬麦 / Post-Match Mic | common xnull | attack_speed_pct +5; economy +5; damage_pct -3 | torso |
| halftime_tactics_board | 半场战术板 / Halftime Tactics Board | common x1 | armor +1; damage_pct +2; conditional wave_progress_gte_pct 50 => damage_pct +8 and dodge +5 | back |
| hand_cannon_ace_coin | 手炮五杀币 / Hand-Cannon Ace Coin | uncommon x2 | ranged_damage +3; critical_chance +5; attack_speed_pct -5 | trinket_right |
| sneaky_site_mask | 静步面罩 / Sneaky-Site Mask | uncommon x2 | dodge +7; move_speed_pct +3; melee_damage -2 | face |
| arena_chant_cassette | 主场合唱磁带 / Arena Chant Cassette | uncommon x1 | move_speed_pct +3; economy +5; conditional wave_progress_lte_pct 20 => attack_speed_pct +10 | side_right |
| mouse_lift_pad | 抬鼠垫 / Mouse-Lift Pad | rare x1 | range +30; attack_speed_pct +10; critical_chance +5; dodge -3 | back |
| lineup_chalk | 道具点位粉笔 / Lineup Chalk | rare x1 | range +15; first_projectile_per_wave => damage_pct +20 and pierce +1 | side_left |
| site_hold_bandana | 守点头巾 / Site-Hold Bandana | rare x1 | armor +3; damage_pct +5; move_speed_pct -5; conditional health_lte_pct 40 => attack_speed_pct +15 | head |
| airshot_wing_charm | 腾空狙击翼章 / Airshot Wing Charm | legendary x1 | ranged_damage +4; critical_chance +9; attack_speed_pct -12; per_weapon every_nth_ranged_attack 4 => forced_critical and critical_damage_pct +35 | trinket_left |
| clutch_stopwatch | 残局秒表 / Clutch Stopwatch | legendary x1 | damage_pct +12; dodge +10; range +30; conditional enemy_count_lte 3 => damage_pct +20 and attack_speed_pct +15 | wrist |
| three_beat_magazine | 三发节奏弹匣 / Three-Beat Magazine | legendary x1 | ranged_damage +4; attack_speed_pct +5; range -15; per_weapon every_nth_ranged_attack 3 => damage_pct +30 and pierce +1 | side_right |

Appearance mode defaults: head/back/side/trinket/face use `RIGID`; torso/wrist/feet use `FRAME_OVERLAY`. Duplicate copies display once. Rarity wins slot conflicts; newest acquisition breaks equal-rarity ties. Left/right trinkets are separate slots.

Upgrade structured tier values:

- max health: +3/+6/+9/+12
- move speed: +3/+6/+9/+12 percent
- damage: +5/+8/+12/+16 percent
- economy: +5/+8/+10/+12
- armor: +1/+2/+3/+4
- regeneration: +2/+3/+4/+5

The test must prove the real loader/validator behavior using a valid canonical registry and malformed temporary fixtures. It must catch at least: one missing unit, duplicate asset ID, missing English copy, invalid status, missing item effects, and a numeric effect value embedded in localized description copy.

Commit the task after the focused test passes. Do not generate images or alter the startup chain in this task.

## Task 2: First anchor raw generation and deterministic sprite cleanup

Generate exactly one candidate set for `smoke_shell_helmet`. Use the built-in ImageGen path and the approved Master prompt. Image 1 is `E:/01_gobro/GOGOBRO_ASSET_INBOX/01_characters/niko/animations/walk_down/seed-front-300.png` for proportions/warm shape language only. Image 2 is `E:/01_gobro/GOGOBRO_ASSET_INBOX/01_characters/niko/animations/walk_down/niko-walk-happy-20260822-131247/frames/frame-001.png` for actual pixel density/hard edges only. Do not redesign or edit the character.

The icon is a single original protective smoke-shell helmet in slight top-down 3/4 view, readable at 64 logical pixels, with a warm dark-brown 1-2 logical-pixel outline, 12-18 colors, three value bands, large connected regions, charcoal/gun-gray/bone-white/deep-teal/orange-latch palette, no real logo or copied equipment profile. Use a flat chroma color that does not conflict with the subject palette.

The wearable is a separate 128x128 `RIGID` head-layer sprite aligned to Master Ni's walk-down frame. It must not modify the base frame. Produce a one-frame appearance plus explicit per-frame anchor metadata for the existing eight walk frames; do not create an animation state.

Save raw, request/prompt, deterministic cleanup outputs, reports, and candidate metadata under `E:/01_gobro/GOGOBRO_ASSET_INBOX/02_static_assets/items/smoke_shell_helmet/candidate-001/`. Keep raw/chroma outside runtime. Do not put anything under runtime `curated` before approval.

Run deterministic pixel/alpha QA: dimensions, nearest-compatible pixel grid, binary alpha, RGB=0 under alpha=0, no chroma remnants, continuous silhouette, palette count target, safe margins, and unchanged Master Ni atlas hash. After these checks pass, update only the `smoke_shell_helmet` registry entry with candidate paths, SHA-256 hashes, and status `review`; this is provenance tracking, not runtime integration.

## Task 3: Approval card and review handoff

Create one approval card for candidate 001 containing: transparent 256x256 icon, transparent 128x128 appearance, Master Ni composite, actual gameplay-size preview, bilingual name, bilingual short description, bilingual flavor line, and effect text generated from the structured effect data (`+1 armor`, `-3% move speed`). The card may render labels; runtime images may not.

Present the candidate to the user and stop for explicit approve/revise feedback. A rejection preserves candidate 001 and makes only the one requested targeted revision as candidate 002.

## Task 4: Post-approval integration (blocked until explicit approval)

After approval only: export approved stills from sprite-gen `curated`, update registry paths/hashes/status, add the item/appearance through the typed content interfaces, render an actual in-game screenshot, and move status through `approved -> integrated -> qa_passed` only as each gate passes. Then proceed to the next anchor, Wood-Stock Assault Rifle, one candidate at a time.
