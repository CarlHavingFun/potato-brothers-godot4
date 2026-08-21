# Video Sprite Studio

通用的视频转像素帧、网页挑帧与 Godot 4 `SpriteFrames` 直出工具。它不依赖 MCP；代码随本仓库版本化，素材工作区默认位于 `%LOCALAPPDATA%\VideoSpriteStudio\workspace`。

## 启动与工作流

双击仓库根目录的 `启动视频精灵工作台.cmd`。默认地址为 <http://127.0.0.1:8766/studio/?lang=cn>。若服务已启动，脚本只打开网页；若端口被其他程序占用，脚本会明确失败，绝不结束未知进程。

1. 新建角色、对象或特效，上传造型基准图。角色默认逻辑高度 64、锚点 `(128,232)`；对象和特效默认逻辑尺寸 128、中心锚点 `(128,128)`。所有输出单元格均为 256×256。
2. 选择主体、填写动画名并上传 `.mp4`、`.mov`、`.mkv`、`.webm` 或 `.avi`。PixelMotion 使用边缘连通抠图，sprite-gen 负责调色板锁与像素规范化；每个真实源帧都进入候选池。
3. 任务为 `ready` 后打开挑帧。普通点击、Ctrl、Shift 和 Ctrl+Shift 多选、批量添加/移除、重复、拖动排序、FPS、Loop、单帧 PNG 和 GIF 均沿用 sprite-gen curation。
4. 回到工作台，填写任意 Godot 4 项目绝对路径、总 `SpriteFrames.tres` 和动画名。先“预览差异”，再确认生成。任何选择、FPS、Loop 或目标变化都会令旧确认失效。

网页还支持切换外部工作区、手工粘贴项目路径、服务端目录浏览、最近项目以及从项目中发现已有 `SpriteFrames.tres`。

## Godot 输出契约

每个主体默认只有一个总资源：

`res://assets/generated/video_sprites/<subject_id>/<subject_id>_animations.tres`

Niko 默认使用：

`res://tools/sprites/niko_character_library/authoring/niko_all_actions.tres`

每次确认仅把选定帧安装到：

`res://assets/generated/video_sprites/<subject_id>/<animation>/<revision>/`

该目录只含 `atlas.png`、`manifest.json` 和 `provenance.json`。Godot headless bridge 使用 manifest 的显式矩形加载/创建总 `SpriteFrames`，只替换指定动画，保留其他动画，并通过临时资源回读后原子替换正式 `.tres`。

工具明确不会修改 `.tscn`、`AnimatedSprite2D` 节点、首选 take 或 runtime，也不会把视频和全量候选 PNG 写入项目。Niko authoring 导出后，仍需在 Godot 角色动画 Dock 中显式点击“发布运行时”。

## 依赖与故障定位

工作台首页显示 Python、sprite-gen、PixelMotion、ffprobe 和 Godot 的解析路径。后台日志位于 `%LOCALAPPDATA%\VideoSpriteStudio\studio.stdout.log` 与 `studio.stderr.log`；每个任务还在外部工作区保存 worker stdout/stderr、receipt、视频哈希和持久状态。

旧 `/download/atlas` ZIP 接口仍由 curation 服务保留兼容，但正常网页隐藏该入口，默认交付方式为“导出到 Godot”。
