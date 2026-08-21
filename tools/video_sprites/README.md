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
- `video_sprites.import_video`：异步处理单个视频到 `user://video_sprite_workspace` 下的外部暂存目录；不会在 `res://` 生成帧、图集、manifest 或预览资源。
- `video_sprites.job_status`：查看目录导入或外部单视频暂存任务的进度。
- `video_sprites.dependency_status`：列出 Python、PixelMotion、sprite-gen、worker 脚本和 ffprobe 的已解析/缺失路径，供编辑器 UI 显示。
- `video_sprites.cancel_job`：在该任务专属目录原子写入带 `job_id` 与随机 `job_token` 的协作式取消请求；绝不会按 PID 终止进程。worker 在安全检查点发现匹配请求后写入终态 `cancelled`。
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

目录导入立即返回 `job_id`，随后用 `video_sprites.job_status` 轮询；目录输出仍严格限制在 `res://tools/sprites` 下。单视频导入的 `staging_directory` 可省略，省略时自动创建 `user://video_sprite_workspace` 下唯一的任务目录；若提供，它必须是该根目录下的绝对路径。完整处理结果和 provenance 仅保留在该外部暂存位置，等待人工挑选后再发布。

编辑器菜单会保留导入命令对象并每 0.5 秒轮询，直到 Python 处理、Godot 导入、预览和
集中母资源全部完成。源目录与 PixelMotion 根目录可在“项目设置”中填写
`video_sprites/niko/source_directory`、`video_sprites/pixelmotion_root`，也可分别设置
`NIKO_VIDEO_SOURCE_DIRECTORY`、`PIXELMOTION2D_ROOT`；留空时会从项目的上级工作区
自动发现 `MINIMAX_OK/niko` 和 `pixelmotion-2d-niko`，因此编辑器插件不依赖某台机器的
盘符。

## 编辑器视频挑帧 Dock

启用“角色精灵编辑”插件后，右侧 Dock 会显示 Niko 配置中的 7 个必需动作、所有已注册
take 和当前首选 take。也可以用菜单“角色精灵/打开视频挑帧 Dock”聚焦它；原有的
“导入 Niko 全部视频”“发布当前角色动画”和“显示当前角色状态”菜单保持可用。

先选择动作，再把一个或多个 `.mp4`、`.mov`、`.mkv`、`.webm` 或 `.avi` 从 Windows
拖到动作树；文件名绝不会决定动作。若鼠标位置无法定位动作行，则使用当前选择；没有
选择时会明确拒绝。按钮“添加视频…”提供访问绝对文件系统的多文件选择器。每个文件都
直接调用共享 `VideoSpriteJobService`，不经过 MCP，也不会退回旧的项目内全帧导入。
Dock 的任务列表会逐项显示 action/take、队列/运行/取消/终态、进度和完整错误；取消只
作用于当前选中的活动任务，并使用协作式取消。

任务完成后，Dock 只从该任务的外部暂存目录接受恰好一个经
`VideoSpriteCurationService` 验证的 manifest。全部真实来源帧仍留在
`user://video_sprite_workspace`；缩略图与预览由 `Image.load_from_file` 创建
`ImageTexture`，不会让 Godot 导入所有候选 PNG。来源池不会因“添加所选”而减少。
每个完成任务都有独立挑帧快照；后台完成不会切换动作树或覆盖正在编辑的序列，点击任务
行才会打开该任务，切换回来仍保留未保存的选择、FPS 和 Loop。

来源与最终列表都支持普通单选、Ctrl 切换、Shift 范围和 Ctrl+Shift 追加范围。
“添加所选”按来源顺序批量追加；最终序列允许重复帧，并支持批量移除、稳定多项上移/
下移及拖动排序。FPS 可设为 `0.1–120`，Loop 独立可改，外部 PNG 预览始终使用最近邻。

“保存挑帧”只写外部 `godot-curation.json`，下次打开相同暂存结果会恢复；manifest 或
视频哈希过期会显示错误，不会静默使用旧选择。“预览并提升”先显示不会覆盖现有 take
的唯一名称与目标路径，确认后才把所选帧提升到
`res://tools/sprites/niko/<action>/<take>/`，刷新动作树并在 Godot 原生编辑器中打开新
`SpriteFrames`。“设为首选”和“发布运行时”是两个独立显式操作；开始任务、保存、
提升、打开资源和设为首选都不会隐式发布运行时资源。

“清理外部暂存”需要确认，活动任务会被拒绝，并显示精确删除路径和条目数。它只调用
共享服务的严格单目录清理，不会递归删除暂存根、兄弟目录或链接逃逸路径。

## 在 Godot 中选帧

Niko 的集中编辑入口是：

`res://tools/sprites/niko_character_library/authoring/niko_all_actions.tres`

其中 `source__动作_down__take` 动画永久保留每段视频的 124 帧；没有 `source__` 前缀的
`idle_down`、`walk_down` 等动画是人工运行轨。首次导入会从配置的首选 take 完整复制
124 帧、24 FPS。你可以直接在 Godot 原生 SpriteFrames 面板删除、排序、从图集补回帧，
并修改 selected FPS、逐帧时长和循环设置。

编辑完成后执行 `character_sprite.publish` 或编辑器菜单“角色精灵/发布当前角色动画”。
游戏只加载发布后的轻量资源，不加载全部 source 轨。
发布前会检查配置中所有具有视频 take 的动作仍至少有一帧；误删 `walk_down`、
`spawn_down` 等动作会直接拒绝发布。没有任何 take 的 `dash_down` 仍作为明确缺项保留，
不会被伪造，也不会在触发冲刺时锁死到循环待机动画。

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

`video_sprites.validate_library` 与 CLI `--validate-only` 使用严格资源验证：除 manifest
结构外，还会核对连续源帧号、逐帧 SHA-256、硬 alpha、整段动画共享最多 32 色、
24 px 安全区、每帧非空且脚底精确落在根点，以及每张单帧 PNG 与图集矩形的逐像素一致性。

在 Godot 文件系统里双击 `selection.tres`，进入内置 SpriteFrames 编辑器：删除不需要的帧、拖动调整顺序，然后设置循环和速度。比如从 124 个 24 FPS 来源帧中选出 8 帧后，可把 selected FPS 改为 10。

普通重导入 never overwrites `selection.tres`。只有显式传入 `replace_selection: true` 才会用全部来源帧重置人工选择；该操作会丢弃当前选择，因此不要作为日常重导入选项。

`source_all_frames.tres` 始终是不可编辑来源基线；单 clip 样片可以引用
`selection.tres`。正式人物游戏场景只引用由集中母资源发布出的
`runtime/<character>_runtime_frames.tres`。所有贴图使用最近邻过滤，不应启用平滑、
mipmap 或有损压缩。
