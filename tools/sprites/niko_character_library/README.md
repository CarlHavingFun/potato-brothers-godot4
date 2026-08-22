# Niko 人工动画入口

打开项目根目录的 `res://Niko动画工作台.tscn`。场景树的 `Actions` 下列出 Niko 的七个游戏动作：

- `Spawn` → `spawn_down`
- `Idle` → `idle_down`
- `Walk` → `walk_down`
- `Dash` → `dash_down`
- `Hit` → `hit_down`
- `Death` → `death_down`
- `Victory` → `victory_down`

每个动作节点都引用同一个总资源：

`runtime/niko_runtime_frames.tres`

选择动作节点，在检查器中点击 `Sprite Frames`，然后在底部 SpriteFrames 编辑器中选择同名动画。可以直接拖入帧、删除或排序，并修改 FPS 和循环。保存资源后，`player_niko.tscn` 会立即使用新动画，不需要修改角色节点，也不需要再次发布 runtime。

`dash_down` 初始只有一帧待机占位图，导入 Dash 素材后直接替换即可。其他方向缺少动画时，游戏会自动使用对应的 `*_down` 正面动画。

人工编辑该总资源后，不要再点击视频动画工具里的“发布运行时”，否则发布操作会重新生成并覆盖总资源。
