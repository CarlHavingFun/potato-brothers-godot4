# GOGOBRO

GOGOBRO 是一个使用 Godot 4.7.1 独立重写的俯视角生存动作游戏。项目以职责、生命周期、数据流和机制行为等价为目标，不复制其他游戏的源码、文案、ID、数据表或美术。

## 当前可运行闭环

主入口是 `res://game/app/app_root.tscn`，目前包含：

```text
主菜单 → 角色选择 → 武器选择 → 难度选择
       → 战斗 → 升级 → 商店 → 下一波
       → authored zone 最终波胜利/失败结算 → 主菜单
```

验证内容全部由 `ValidationContentFactory` 及独立内容包创建，当前闭环使用 NiKo、多类武器/敌人/物品/升级、1 个区域、1 个难度和 20 个 authored 波次。运行时不依赖旧工程的资产或存档。

## 架构

新运行时代码全部位于 `res://game/`：

- `app/`：`AppKernel`、场景流程、挑战入口；
- `session/`：不可跨局复用的 `GameSession`、`GogoRunState`、玩家状态；
- `content/`：内容 API v1、独立角色/武器包、原子快照；
- `gameplay/`：规则顺序、效果、商店、战斗世界和实体；
- `ui/`：只发送会话命令并读取状态的流程场景；
- `platform/`：存档、设置、音频、成就和平台边界；
- `modding/`：Godot Mod Loader 隔离适配边界。

角色包和武器包彼此独立，可分开启用、禁用、更新和替换。变化先进入 `ContentPackCatalog`，只允许在主菜单且无活动会话时原子生成新 `ContentSnapshot`；进行中的一局永远使用启动时冻结的快照。

外层 profile schema 为 1，局内 checkpoint 当前写 schema 3，并兼容读取 checkpoint schema 1/2（旧版不承诺精确还原随机流）。项目已把 `user://` 映射到操作系统中独立的 GOGOBRO 用户数据目录，当前存档直接写入其中的 `profile.json`；启动时只会验证并迁移历史嵌套路径 `user://GOGOBRO/profile.json`，不会读取其他游戏目录。检查点采用完整文件 SHA 基线、跨进程锁、临时文件重读验证、备份和原子替换流程；活动或无法确认所有者状态的锁保持失败关闭，仅回收已确认进程退出的遗留锁。

## 开发工具

`addons/`、`tools/` 和 `mcp_commands/` 保留 FrameKit、视频精灵工作台、sprite-gen/Godot 导入、MCP 与 GdUnit4。源视频及全量候选帧必须留在项目外，只有挑选后的资源可以进入游戏目录。

运行当前 authored zone 全波次确定性闭环：

```powershell
Godot_v4.7.1-stable_win64_console.exe --headless --path . `
  --script res://tools/gogobro_v2_headless_smoke.gd
```

编辑器解析检查：

```powershell
Godot_v4.7.1-stable_win64_console.exe --headless --editor --path . --quit
```

Godot MCP 编辑器插件代码仍保留，但默认关闭以减少编辑器启动开销；需要时可在“项目 → 项目设置 → 插件”启用。启用后它只使用回环地址，若本机 9100–9115 全部被占用会报告端口错误，但不影响游戏主入口。

## Mod 边界

`GogoModLoaderAdapter` 只允许在主菜单切换 Mod 档案，并始终要求重启后生效。公开的 Godot Mod Loader 7.0.1 稳定版声明面向 Godot 4.1–4.3；本项目使用 Godot 4.7.1，因此在确认兼容版本前不把该依赖强行加入启动链。
