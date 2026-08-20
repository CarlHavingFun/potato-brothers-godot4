# Niko 视频全帧精灵库

这套工具把视频的每一帧转为 Godot 可用的 256×256 像素精灵，并把“完整来源”和“人工选择”分开保存。它不会伪造缺失方向，也不会接入正式玩家角色资源。

## MCP 命令

- `video_sprites.scan_directory`：递归扫描视频，返回路径、哈希、尺寸、精确 FPS、时间戳及总帧数。
- `video_sprites.import_directory`：异步导入目录内所有视频。
- `video_sprites.import_video`：异步重试或新增单个视频。
- `video_sprites.job_status`：查看进度；Python 完成后生成 Godot 资源和预览场景。
- `video_sprites.validate_library`：只读验证 PNG、图集、manifest、SpriteFrames 和预览场景。

当前机器的完整目录导入参数示例：

```json
{
  "source_directory": "E:\\01_gobro\\MINIMAX_OK\\niko",
  "output_directory": "res://tools/sprites/niko_video_library",
  "pipeline_root": "E:\\01_gobro\\pixelmotion-2d-niko",
  "python_executable": "C:\\Users\\18421\\.codex\\skills\\sprite-gen\\.venv\\Scripts\\python.exe",
  "force_generated": false,
  "replace_selection": false
}
```

导入立即返回 `job_id`，随后用 `video_sprites.job_status` 轮询。默认输出位置严格限制在 `res://tools/sprites` 下。

## 在 Godot 中选帧

每个 clip 包含：

- `frames/frame_###.png`：所有独立帧；
- `atlas.png`：Godot 使用的 16 列透明图集；
- `manifest.json`：显式矩形、源帧号、时间戳和逐帧时长；
- `source_all_frames.tres`：每次导入都会刷新，保留源视频的全部帧和 24 FPS 时间；
- `selection.tres`：用于人工删帧、排序和设置 selected FPS；
- `preview.tscn`：最近邻、棋盘透明背景和 `(128, 232)` 根点参考线预览。

在 Godot 文件系统里双击 `selection.tres`，进入内置 SpriteFrames 编辑器：删除不需要的帧、拖动调整顺序，然后设置循环和速度。比如从 124 个 24 FPS 来源帧中选出 8 帧后，可把 selected FPS 改为 10。

普通重导入 never overwrites `selection.tres`。只有显式传入 `replace_selection: true` 才会用全部来源帧重置人工选择；该操作会丢弃当前选择，因此不要作为日常重导入选项。

`source_all_frames.tres` 始终是不可编辑来源基线；游戏或样片应引用 `selection.tres`。所有贴图使用最近邻过滤，不应启用平滑、mipmap 或有损压缩。
