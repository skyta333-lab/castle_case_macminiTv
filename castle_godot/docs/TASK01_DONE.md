# TASK 01 完成标记 — 城堡可探索控制器

> 分支：`work/macmini-nontv-castle-v2`
> 引擎：Godot 4.7.2.stable（`/Users/yujiang/Downloads/Godot.app/Contents/MacOS/Godot`）

## 1. 目标回顾

把「固定相机自动环绕展示」升级为可进入场景探索的 Godot 原型，**同时保留原有展示模式**。

## 2. 新增文件

| 文件 | 说明 |
|---|---|
| `castle_godot/scenes/player.tscn` | 玩家场景：CharacterBody3D + CapsuleShape3D(碰撞层2) + Head + 第一人称 Camera3D + SpringArm3D/第三人称 Camera3D + InteractRay |
| `castle_godot/scripts/player_controller.gd` | 玩家控制器：WASD / Shift 冲刺 / Space 跳跃 / 重力 / 鼠标视角 / 坠落复位 / 交互射线维护 |
| `castle_godot/scripts/camera_mode_manager.gd` | 镜头模式管理：1 展示环绕、2 第一人称、3 第三人称；鼠标捕获/释放；暂停/恢复 `castle_showcase.gd` 的环绕 |
| `castle_godot/scenes/hud.tscn` | HUD 场景（CanvasLayer） |
| `castle_godot/scripts/hud.gd` | HUD：操作说明、当前模式、画质档、准星、性能信息、POI 提示位 |
| `castle_godot/scripts/castle_collision.gd` | 程序化碰撞：地面 + 城堡关键体块（23 个 StaticBody3D） |
| `castle_godot/docs/TASK01_DONE.md` | 本文件 |

## 3. 修改文件

| 文件 | 修改内容 |
|---|---|
| `castle_godot/project.godot` | 补全 InputMap（21 个动作）、主场景、窗口与渲染基础配置 |
| `castle_godot/scenes/main.tscn` | 新增 `WorldCollision` / `PlayerSpawn` / `Player` / `CameraModeManager` / `HUD` 节点；原有 `Castle` / `MainCamera` / `SunLight` / `Ground` 保持不变 |

**未改动**（全局约束要求保持兼容）：`castle_ref_model.glb`、`castle_ref_model.blend`、`castle_showcase.gd`。
`castle_showcase.gd` 的环绕相机逻辑完全复用：进入玩家模式时只把 `camera_orbit_speed` 置 0 暂停环绕，退出时还原。

## 4. 操作键位

| 按键 | 功能 |
|---|---|
| `W` `A` `S` `D` | 前后左右移动 |
| 鼠标移动 | 视角（第一/第三人称共用，俯仰限制 ±85°） |
| `Shift` | 冲刺（18 → 40 单位/秒） |
| `Space` | 跳跃 |
| `1` | 展示环绕模式（默认，玩家冻结） |
| `2` | 第一人称探索 |
| `3` | 第三人称探索（SpringArm3D 防穿墙） |
| `ESC` | 释放鼠标 |
| 鼠标左键 | 重新捕获鼠标 |
| `E` | 交互（TASK 03 使用） |

## 5. 碰撞策略

按任务书「可玩优先、性能可接受」原则，**没有**把 655 个网格全量转成 ConcavePolygonShape3D，而是：

- 草地：1 个 230×6×230 的 Box（顶面 y=0）+ 1 个 600×4×600 的外围兜底 Box（防掉出世界）；
- 城堡：从模型实测世界 AABB 生成 **19 个关键体块**（Rock_Podium / Rock_Podium_Cap / Forecourt / Mass_Mid / Mass_Upper / 3 段低矮园墙 / 11 座塔身圆柱），
  其中圆柱取 `min(x,z)/2` 作半径、Y 作高；
- 台阶：用 1 个绕 X 轴倾斜约 26.6° 的 Box 当斜坡（z 58.6→52.0，y 0→4.0）；
- 台基高差：用 1 个 2m 长的小斜坡（z 41→39，y 4.0→4.8）替代 0.8m 垂直台阶。

合计 **23 个静态碰撞体**，远低于全量凹多边形的开销。

> 踩坑记录：台阶斜坡顶端必须正好落在 `Forecourt` 前立面 `z=52`（y=4.0）上。最初把顶端设在 z=50.6，玩家会提前钻进前庭平台方块内部而被卡死（实测卡在 z=52.6 / y=3.07）。已修正为 `ramp_top=(0, 4.0, 52.0)`。

## 6. 出生点

`PlayerSpawn = (0, 0.4, 78)`：

- 正对城堡主入口（+Z 方向看向 -Z）；
- 位于草地上（地面 y=0），不在空中、不与模型重叠（前方 20m 内无实体）；
- 正前方即为台阶 → 前庭 → 大门 → 内庭的主动线。

## 7. 自检结果

自检方式：`godot --headless --path . --fixed-fps 60 --script res://tools/<临时脚本>`，用 `Input.action_press` 与直接驱动视角数学模拟真实操作。

| # | 检查项 | 结果 |
|---|---|---|
| 1 | 工程能启动 | ✅ 无脚本报错，`[castle_godot] scene ready` |
| 2 | 无 GDScript parse error | ✅ 无 SCRIPT ERROR |
| 3 | 玩家出生正常 | ✅ 出生 1.6s 后稳定落地 y=0.00，`on_floor=true` |
| 4 | WASD 有效 | ✅ 直行从 z=78 → z=14.6（穿过大门进入内庭） |
| 5 | 鼠标视角有效 | ✅ yaw 变化 -0.600 rad、pitch -0.300 rad（headless 无显示服务器，改用 `apply_look` 直接验证） |
| 6 | 玩家不会掉出世界 | ✅ 全程 `min_y=0.00`，另有 `fall_limit_y` 自动复位 |
| 7 | `1/2/3` 模式可切换 | ✅ 三种相机 `current` 状态正确，展示模式恢复后环绕相机重新生效 |
| 8 | 城堡仍正常加载 | ✅ 655 个网格，世界 AABB 230×88.29×230 |
| 9 | 冲刺有效 | ✅ 速度 13.9 → 40.0 |
| 10 | 跳跃有效 | ✅ 起跳 vy=10.71 |
| 11 | 台阶可通行 | ✅ 沿斜坡从 y=0 走到 y=4.00，再上 4.80 台基顶 |

## 8. 已知问题

1. **headless 下鼠标无法进入 `MOUSE_MODE_CAPTURED`**（无显示服务器），鼠标视角只能通过 `apply_look()` 数学层面验证；实际捕获行为需在带窗口的 Godot 中人工确认。
2. **台阶为斜坡近似**：5 级台阶（每级 0.8m）在碰撞上被一条斜坡替代，视觉完全一致，但脚下不是"逐级抬升"的手感。
3. **低矮园墙（LowWall_W/C/E，高 1.2~1.6m）有碰撞**，正对台阶的一段会挡住直行路线，需要从两侧缺口（|x|>6）绕行；这是模型本身的花园布局，非缺陷。
4. **街道家具/栏杆/窗户未生成碰撞**（如 `Rail_*`、`Win_Glass×91`、`Gate_Door_*`），可穿过；门与入口策略在 TASK 03 处理。
5. `Mass_Mid` / `Mass_Upper` 等高处体块有碰撞，但玩家无法到达该高度，仅作视觉遮蔽备位。
