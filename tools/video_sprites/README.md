# Niko 视频全帧精灵库

这套工具把视频的每一帧转为 Godot 可用的 256×256 像素精灵，并把“完整来源”、
“人工选择”和“游戏发布”分开保存。它不会伪造缺失方向；游戏只连接人工确认后发布的
轻量运行资源，不直接加载全帧母资源。

每一帧先由 PixelMotion 的边缘连通算法安全移除背景（保留白衣），再由 sprite-gen
官方 component-row extractor 完成 pixel-unfake、32 色共享调色板、alpha-centroid
水平对齐和底部落地。最终帧不是普通缩放结果。sprite-gen 以 y=232 作为地面边界，
所以最后一个不透明像素位于 y=231。

sprite-gen 的整行动作配准偶尔会让宽物体保留空白偏移（例如 `born` 第一帧的舱门）。
导入器会在 sprite-gen 完成后按 4 px 逻辑网格整体平移可见像素，使可容纳的内容重新
落回 24 px 安全区；该步骤不缩放、不重采样、不改色，也不会删除任何源帧。若舱门等
源道具本身宽于 208 px 安全区，则只裁掉安全区外的边缘像素，并在 manifest 的
`source_frames[].cropped_margin_pixels` 中记录实际裁掉的非透明像素数。每帧平移量记录
在 `source_frames[].alignment_shift_x`，最终所有帧都重新执行严格安全区校验。

## MCP 命令

- `video_sprites.scan_directory`：递归扫描视频，返回路径、哈希、尺寸、精确 FPS、时间戳及总帧数。
- `video_sprites.import_directory`：异步导入目录内所有视频。
- `video_sprites.import_video`：异步重试或新增单个视频。
- `video_sprites.job_status`：查看进度；Python 完成后生成 Godot 资源和预览场景。
- `video_sprites.validate_library`：只读验证 PNG、图集、manifest、SpriteFrames 和预览场景。
- `character_sprite.import_all`：按角色配置导入全部视频，并刷新一个集中展示所有动作/take 的母资源。
- `character_sprite.publish`：把人工编辑后的运行轨重新打包为轻量 Godot 图集和 SpriteFrames。
- `character_sprite.status`：列出统一动作模板、已导入 take、缺失动作及最近发布状态。

当前机器的完整目录导入参数示例：

```json
{
  "source_directory": "E:\\01_gobro\\MINIMAX_OK\\niko",
  "output_directory": "res://tools/sprites/niko_video_library",
  "pipeline_root": "E:\\01_gobro\\pixelmotion-2d-niko",
  "sprite_gen_root": "C:\\Users\\18421\\.codex\\skills\\sprite-gen",
  "python_executable": "C:\\Users\\18421\\.codex\\skills\\sprite-gen\\.venv\\Scripts\\python.exe",
  "force_generated": false,
  "replace_selection": false
}
```

导入立即返回 `job_id`，随后用 `video_sprites.job_status` 轮询。默认输出位置严格限制在 `res://tools/sprites` 下。

## 在 Godot 中选帧

Niko 的集中编辑入口是：

`res://tools/sprites/niko_character_library/authoring/niko_all_actions.tres`

其中 `source__动作_down__take` 动画永久保留每段视频的 124 帧；没有 `source__` 前缀的
`idle_down`、`walk_down` 等动画是人工运行轨。首次导入会从配置的首选 take 完整复制
124 帧、24 FPS。你可以直接在 Godot 原生 SpriteFrames 面板删除、排序、从图集补回帧，
并修改 selected FPS、逐帧时长和循环设置。

编辑完成后执行 `character_sprite.publish` 或编辑器菜单“角色精灵/发布当前角色动画”。
游戏只加载发布后的轻量资源，不加载全部 source 轨。

默认内容包中的 `character/well_rounded` 已改用
`res://scenes/unit/players/player_niko.tscn`；其他 11 个角色仍使用原场景。Niko 场景固定
引用 `runtime/niko_runtime_frames.tres`，所以你在母资源中手动选帧并再次“发布当前角色
动画”后，不需要再修改场景或内容包。

## 每个可玩角色需要的动作

当前项目的 12 个可玩角色使用同一个人工友好动作模板：`well_rounded`、`brawler`、
`bunny`、`crazy`、`knight`、`almighty`、`ember_sage`、`scrapwright`、`dash_raider`、
`bloodbound`、`scrap_broker`、`glass_cannon`。每个人物的集中 SpriteFrames 都应一览
以下 7 个运行动作；每个动作还可以有任意数量的 `source__动作_down__take` 全帧来源轨：

| 必需动作 | 用途 | 默认循环 | 当前方向规则 |
| --- | --- | --- | --- |
| `spawn_down` | 出生 / 入场 | 否 | 仅正面 |
| `idle_down` | 待机 | 是 | 缺方向时回退正面 |
| `walk_down` | 普通移动 | 是 | 8 方向请求全部回退正面 |
| `dash_down` | 冲刺 | 否 | 缺失时回退待机，不伪造资源 |
| `hit_down` | 受击 | 否 | 缺方向时回退正面 |
| `death_down` | 死亡 | 否 | 缺方向时回退正面 |
| `victory_down` | 胜利 | 否 | 缺方向时回退正面 |

Niko 当前视频与模板的映射如下；`dash_down` 明确缺失，不会用静态图冒充：

| Godot 动作 | 视频来源 / take | 默认循环 |
| --- | --- | --- |
| `spawn_down` | `born` / `born` | 否 |
| `idle_down` | `idle` / `calm` | 是 |
| `walk_down` | `walk` / `happy`（另含 `power`、`strong`） | 是 |
| `dash_down` | 暂无 | 否 |
| `hit_down` | `hit` / `hit` | 否 |
| `death_down` | `die` / `niko_die`（另含 `die`） | 否 |
| `victory_down` | `happy_jump` / `happy_jump` | 否 |

在补齐其他方向素材之前，运行时的 `walk_up`、`walk_left`、`walk_right` 及所有斜向
走路请求都统一解析到 `walk_down`；资源内不会复制出八份假方向动画。

每个 clip 包含：

- `frames/frame_###.png`：所有独立帧；
- `atlas.png`：Godot 使用的 16 列透明图集；
- `manifest.json`：显式矩形、源帧号、时间戳和逐帧时长；
- `source_all_frames.tres`：每次导入都会刷新，保留源视频的全部帧和 24 FPS 时间；
- `selection.tres`：用于人工删帧、排序和设置 selected FPS；
- `preview.tscn`：最近邻、棋盘透明背景和 `(128, 232)` 根点参考线预览。

在 Godot 文件系统里双击 `selection.tres`，进入内置 SpriteFrames 编辑器：删除不需要的帧、拖动调整顺序，然后设置循环和速度。比如从 124 个 24 FPS 来源帧中选出 8 帧后，可把 selected FPS 改为 10。

普通重导入 never overwrites `selection.tres`。只有显式传入 `replace_selection: true` 才会用全部来源帧重置人工选择；该操作会丢弃当前选择，因此不要作为日常重导入选项。

`source_all_frames.tres` 始终是不可编辑来源基线；单 clip 样片可以引用
`selection.tres`。正式人物游戏场景只引用由集中母资源发布出的
`runtime/<character>_runtime_frames.tres`。所有贴图使用最近邻过滤，不应启用平滑、
mipmap 或有损压缩。
