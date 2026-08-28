# GOGOBRO 运行清晰度与战斗补全报告

日期：2026-08-28

审核状态：实现提交 `385083c65635334eb1e9e0a6723d64df07ac9e9c`

目标：Godot 4.7.1 / Windows / 1280×720

证据判定：**PASS**（Critical 0、Important 0）

## 交付结果

本轮把开发预览素材收束为可发行、可玩的 GOGOBRO 完整表面：

- Niko 是唯一可选玩家角色。
- 12 把 CS 原型武器均有真实图标、中央详情、环绕自动攻击和确定性实战序列。
- Drifter、Spark、Rammer 三种敌人全部使用 authored sprite，运行时无圆形 fallback。
- 30 个实体物品、6 个升级、武器、UI、世界和反馈素材组成 70-unit shipping set；source/native 和真实导出 PCK 均为 70 ready / 0 fallback。
- XP 与 supply 从敌人死亡处生成、弹出、磁吸、精确一次收集，并在波次切换前清理。
- rapid/rifle/heavy/suppressed 射击、normal/critical/pierce/explosion 接触、击杀、受伤和拾取均接入原创 WAV、voice pool 与局部 hitstop。
- HUD、商店、升级奖励和暂停采用《土豆兄弟》式信息结构与低边框扫描顺序，同时保持原创 CS 社区服务器视觉；没有复制其文件或 UI 美术。
- 最终 Windows 发行包以真实 EXE marker 证明到达 70/0 主菜单；视觉等价的前一修复包另有 Niko → 12 武器 → AK-47 第 1 波的前台截图，字标、按钮、武器和战斗资产均未退化为 fallback。

视觉门槛以 1280×720 实机清晰度、轮廓、层级和稳定性为准。细节允许存在，不因没有采用粗像素或大色块而失败。

## 关键实现面

### 敌人与运行尺寸

三种敌人以角色差异而非仅色相差异建立轮廓：紧凑追击体、发射型 Spark、装甲楔形 Rammer。64×64 source 在约 40–56 px 运行呈现中保持底部/中心 pivot 和 nearest filtering。最终 combat coverage 中 authored role count 3、enemy count 10、fallback circle 0。

### 结构化 UI

主菜单、Niko 选择、武器选择、难度、战斗 HUD、商店、升级、暂停形成完整玩家路径。商店/升级的主操作复用四状态按钮语言；卡片只保留单一表面、稀有度边和必要分隔，避免多层装饰边框。商店包含四报价、货币/刷新、锁定、六武器位、右侧属性和下一波动作；升级包含四选择、刷新和属性对照；暂停包含操作、物品、六武器、属性和波次条。

### 战斗反馈

攻击与伤害排序保持确定性。局部 hitstop 不使用 `Engine.time_scale`；HUD 和暂停输入不被冻结。player hit 追加镜头 impulse、白闪和音频。反馈 presenter 使用短生命周期；最终证据不再暂停 aging，也不会把死亡方块永久留在构图中。

### 动态拾取

敌人死亡生成 experience 与 supply 节点。奖励先按既有 ledger 预留，拾取节点负责物理 pop/magnet/collection 状态，canonical collection 只提交一次。12 武器 motion run 对每行记录收集前位置、10 physics frame 后位置和位移；12/12 行 motion proven，最小位移 `14.999935 px`，完成帧 active pickup 全为 0。

### Shipping 与发行回归

65 个已接受 preview unit 与 5 个 shipping-only unit 形成 70-unit union。shipping PNG 使用无损 RGBA8 import policy，使解码像素哈希和 alpha 合同能在导出 PCK 中保持一致。

旧包红证据为：`3 ready / 67 fallback / release_ready=false / 134 issues`，字标/按钮/武器图丢失。新检查器挂载最终 PCK 并从内部重建 shipping snapshot，硬断言 Niko decoded RGBA8 identity、70/0、0 issues、字标、按钮四态、12 武器图标与详情纹理；最终真实 EXE 在 runtime/stdout 同时写出 `main_menu ready=70 fallback=0 wordmark=1 buttons=1`。视觉等价前一修复包的三张前台截图确认玩家实际看到的结果。

## 完成矩阵

| 需求 | 最终证据 | 结果 |
| --- | --- | --- |
| Niko-only | 角色页 `1/1`；coverage `character_count=1` | PASS |
| 12 把 CS 武器 | 12/12 实图；12/12 sequence complete；23 fires、20 projectile contacts、5 melee contacts | PASS |
| 环绕自动开火 | 六武器原生战斗图；33 shots、22 contacts | PASS |
| 3 个 authored 敌人 | authored roles 3，fallback circles 0 | PASS |
| projectile / hit / crit / pierce / explosion / death | 四种 impact、击杀事件、短时反馈与无 stale block 终帧 | PASS |
| 动态 XP/材料拾取 | 12/12 motion proven，min 14.999935 px；34 sequence collections；canonical 2-kind collection | PASS |
| HUD / 商店 / 升级 / 暂停 | 1280×720 原生路由截图、native tests、归档结构比较 | PASS |
| 低边框与实体物品 | 四报价/四升级实体图标、单层卡面、统一按钮 | PASS |
| 70-unit 静态素材 | native coverage 70/70；source dry-run 70/0；导出 PCK 70/0 | PASS |
| 音频 / 打击 / 射击 | 75-entry ledger、6 event classes、4 shot + 4 contact variants、hitstop observed/cleared | PASS |
| 真实发行包 | 最终 PCK main_menu/Niko decoded RGBA8/shipping texture gate；最终 EXE 自报 marker；视觉等价前一包三路前台图 | PASS |

## 核心证据

完整视觉判定与全部截图哈希：

- [最终视觉审计](../../../.superpowers/sdd/2026-08-28-runtime-clarity-combat-completion/final-visual-audit.md)
- [最终运行试玩](../../../.superpowers/sdd/2026-08-28-runtime-clarity-combat-completion/final-runtime-playtest.md)

关键 evidence：

| 证据 | SHA-256 / 结果 |
| --- | --- |
| final clean combat 1280×720 | `96C538955960CCE39BF4E49D785599E2DCDEC00B71693C313779E210B0CC8169` |
| final pause 1280×720 | `C8C0E2725D4FF01B27F7981B40CA30C58F97545B1C8A914F583A8EFF25BA2A09` |
| coverage JSON | `08317CE104B9B801C7068DB237B6876F0E56C204565F06C3E0612FAF871503A4` |
| 12-weapon motion manifest | `06FFB188E0C020F1BB3165BDC7A47A0011F53E7DCFF8C2A48CD30BC2D8D04E8F` |
| native shipping capture | `36FF6F8B6F23D5F5115E0D38CF0CBB093181833AF02E2709CF8154B5070F8B84` |
| visually equivalent release main menu | `02A253556C8E5863E33F9799CFB413A036FFA2BBA7806A0AC5059F8690EC66F2` |
| visually equivalent release 12-weapon page | `0F620D7C9532ADDAEA066CEFB1707F58B32C450C12B9F4F5AE0A101AE41545A2` |
| visually equivalent release AK-47 combat | `FB42961B0FB137000B6B29683090314DF4DB926C974FA6105531F03A02BB344B` |
| final PCK inspector log | `95BA58C6231AE93EA24F311B91C14861C36BB2077D9A3E504B318CAAE89BD239` |
| final EXE runtime log | `CDA9F4490276C418B6052406722BCF99EF25979E69840C702D75EC55CABCDBD1` |

真实发行文件：

| 文件 | 大小 | SHA-256 |
| --- | ---: | --- |
| `reports/runtime-clarity-combat-completion/root-final-release-verified/GOGOBRO.exe` | 109,071,360 bytes | `04BAF75CC1D69DD93EB709533ECAB4FD7770BB8A530645717017A06A9D9809FC` |
| `reports/runtime-clarity-combat-completion/root-final-release-verified/GOGOBRO.pck` | 1,859,964 bytes | `BE017BF43D8EA570CC08CDEEA756626FCCCE9BAE79027F7E8D7DDC2F9E190F10` |

最终 `runtime.log` 与 `stdout.log` 同时包含 `GOGOBRO_EXPORTED_MAIN_MENU_READY route=main_menu ready=70 fallback=0 wordmark=1 buttons=1 release=1 preview=0`，stderr 为空；同一 EXE/PCK 在含空格的 `space path release v2` / `space path check v2` 中以相同 PCK、inspector、runtime 和 stdout 哈希再次通过。

## 测试汇总

| 测试 | 结果 |
| --- | --- |
| Godot complete suite | 40/40 suites，380/380 cases，0 error/failure/flaky/skip/orphan；`final-full-gdunit-v2/report_1/results.xml` SHA-256 `3AABB63A05790FE44ECF5405F768354D3F64376ABD5096C94E17FE34076CB082` |
| final native combat focus | 2/2 |
| shipping RGBA8 import policy | 1/1 |
| native menu | 1/1，7 route captures |
| native shipping | PASS，70 ready / 0 fallback |
| deterministic weapon sequence | 12/12 complete，12/12 motion proven，36 captures |
| combat SFX Python | 3/3 |
| shipping builder Python | 1/1 |
| shipping dry-run | 70 active / 0 inactive，pending 0 |
| exported release | 最终 PCK gate PASS；最终 EXE `release=1 preview=0` marker 与 runtime errors 0；视觉等价前一包前台截图 PASS；发行审核 0/0/0 PASS |
| final code safety review | `release-boot-fix-review.md` 独立 code review：Critical / Important / Minor = 0 / 0 / 0，PASS |

完整命令记录见[最终运行试玩](../../../.superpowers/sdd/2026-08-28-runtime-clarity-combat-completion/final-runtime-playtest.md#精确命令)。主要命令为 Godot import、GdUnit 全套、native menu/combat、native shipping、12 武器 runner、两项 Python 工具、Windows release export 和 `tools/check_exported_release.ps1`。

`pytest` 在系统与 bundled Python 中均未安装。`unittest discover` 的 25 项中 23 项通过，2 个模块因缺 `pytest` 与外部 `sprite_gen` 包导入失败；没有安装新依赖。与本任务直接相关的 Python 测试为 4/4。报告没有把该限制写成“全部 Python 通过”。

## 视觉与产品判定

在原尺寸中，Niko、武器关键部件、三种敌人、拾取物、HUD 文字和按钮均清楚；没有 magenta、明显 interpolation blur 或发行态文字 fallback。M4A1-S/AWP 的极细部分、瞬时近战反馈和偏厚倒计时底板仍有三项非阻塞 Minor，详见视觉审计。

归档《土豆兄弟》比较支持现有 setup/combat/upgrade/shop/pause 的结构与扫描顺序。本轮没有重新启动《土豆兄弟》，因为上次 Steam 进程逃离隔离存档；这是明确的安全替代，不是遗漏说明。

## 覆盖边界与历史观察

- 早期 Task 4 review 曾记录 session 为 null/过期与同步跨拾取重入的理论 collection 边缘情形；最终独立代码安全复核未留下开放 finding，结论为 0/0/0。
- `fallback_circle_count` 在逐敌人断言后写为 0，而非截图时独立动态枚举；逐实例 visual assertions 和运行图仍支持结论。
- native UI 有已知 opposite-anchor warning；没有 runtime error 或测试失败。
- 键盘持续移动手感与主观扬声器听感适合后续真人试玩，本次不夸大自动化覆盖。

## 最终判定

三个曾阻塞验收的问题都已闭环：

1. 发行包从 3/70 修复为 70/70；最终 EXE marker 与 PCK hash 锁定包身份，视觉等价前一包的真实前台图确认实际画面。
2. 战斗 evidence 不再冻结 feedback aging，最终帧没有 stale blocks。
3. 12 武器序列在收集前记录真实 pickup motion，再保存收集完成帧。

当前无开放 Critical 或 Important。最终发行审核和代码安全审核均为 0/0/0 PASS；独立视觉审核保留 3 项非阻塞润色 Minor。按“1280×720 实机清晰即可、允许细节”的用户标准，项目达到本轮运行清晰度与战斗补全定义，最终判定为 **PASS**。
