---
AIGC:
    Label: "1"
    ContentProducer: 001191440300708461136T1XGW3
    ProduceID: 44f0e24762f9ee24c3d7182ad71c0adb_13fd6277b02411f1af37525400826444
    ReservedCode1: qFBNMFdYN0cGUeSDRcDH3Kgxo8LO/B6rrD7slBcYDWyZ8ilhzhvxq5EqoTyOxkfLG/Mb+/QVc16AyytlHDIk7r487yPilxoaWZnQdUzCEKmxWscFiXh/0m/2bLkP+f9oIF3MBTseNmpdkRn8CBNmKnSJnBCC88UTwNa86uE03099q9ignE/t/3CDLwI=
    ContentPropagator: 001191440300708461136T1XGW3
    PropagateID: 44f0e24762f9ee24c3d7182ad71c0adb_13fd6277b02411f1af37525400826444
    ReservedCode2: qFBNMFdYN0cGUeSDRcDH3Kgxo8LO/B6rrD7slBcYDWyZ8ilhzhvxq5EqoTyOxkfLG/Mb+/QVc16AyytlHDIk7r487yPilxoaWZnQdUzCEKmxWscFiXh/0m/2bLkP+f9oIF3MBTseNmpdkRn8CBNmKnSJnBCC88UTwNa86uE03099q9ignE/t/3CDLwI=
---

# castle_godot — 童话城堡 Godot 4.7 演示工程（V2）

> Mac mini（non-TV）全天任务 TASK 01–06 交付版本。工程位于仓库
> `castle_case_macminiTv/castle_godot/`，模型由 Blender 4.2 脚本生成并导出为
> `assets/models/castle_ref_model.glb`（655 个网格节点，230 × 88.29 × 230）。
> 分支：`work/macmini-nontv-castle-v2`（等待 MacBook 验收，不自动合并 main）。

## 项目简介

本工程是一个可自由探索的迪士尼风格童话城堡场景，在 V1「静态展示」基础上补齐了
**玩家探索、昼夜环境、交互热点、烟花特效、性能基准与 QA 交付**六块能力：

- **自由探索**：WASD + 冲刺 + 跳跃的第一人称 / 第三人称行走，程序化碰撞体覆盖前庭、斜坡与主台基。
- **三档镜头**：展示环绕 / 第一人称 / 第三人称随时切换，互不残留状态。
- **连续昼夜**：DAY / SUNSET / NIGHT 三套预设 + 自动昼夜推进；夜晚窗户自发光，不新增实时灯。
- **交互热点**：6 个 POI（正门、中央主塔、西塔、东塔、门前旗帜、岩台花园），准星命中提示 + E 查看说明，正门可开合。
- **烟花特效**：4 个发射位、按昼夜自动调整可见度，配合演示模式一键切夜景。
- **性能可控**：LOW / MEDIUM / HIGH 三档画质、性能 HUD、可复跑的基准脚本与实测报告。

### 启动方式

```bash
GODOT="/Users/yujiang/Downloads/Godot.app/Contents/MacOS/Godot"   # 或 /Applications/Godot.app/...

# 首次 / 资源变更后：导入资源
"$GODOT" --headless --path castle_godot --import

# 图形界面运行（推荐，窗口 1600 × 900）
"$GODOT" --path castle_godot

# 无头跑主场景（快速冒烟，300 帧后退出）
"$GODOT" --headless --path castle_godot --quit-after 300
```

一键自检（全部 headless，退出码 0 = 通过）：

```bash
"$GODOT" --headless --path castle_godot --script res://tools/verify_project.gd    # 工程基线 17 项
"$GODOT" --headless --path castle_godot --script res://tools/verify_environment.gd # 昼夜环境
"$GODOT" --headless --path castle_godot --script res://tools/verify_interaction.gd # 交互热点
"$GODOT" --headless --path castle_godot --script res://tools/verify_quality.gd     # 画质 / 性能 HUD（89 项）
"$GODOT" --headless --path castle_godot --script res://tools/verify_v2.gd          # V2 交付总自检（A~I 组）
```

性能基准（**必须非 headless**，真实窗口渲染）与截图采集：

```bash
"$GODOT" --path castle_godot --script res://tools/benchmark.gd              # 生成 docs/benchmark_results.json
"$GODOT" --path castle_godot --script res://tools/capture_screenshots.gd    # 生成 docs/screenshots/ 四张图
```

### 操作键

| 按键 | 功能 |
| --- | --- |
| `W` / `A` / `S` / `D` | 前 / 左 / 后 / 右移动 |
| `Shift` | 冲刺 |
| `Space` | 跳跃 |
| `E` | 与准星指向的交互热点交互（查看说明 / 开合正门） |
| `1` / `2` / `3` | 镜头模式：展示环绕 / 第一人称 / 第三人称 |
| `F1` / `F2` / `F3` | 环境预设：DAY / SUNSET / NIGHT |
| `F4` | 自动昼夜推进开关（`day_length_seconds = 180`） |
| `F5` | 烟花开关（夜间自动齐射） |
| `F6` | 演示模式：一键切夜景 + 面向城堡展示机位（再按还原） |
| `F7` | 性能 HUD 开关（FPS / 帧时长 / Draw Call / 物体数 / 档位 / 分辨率 / 坐标） |
| `F8` | POI 悬浮标记开关 |
| `7` / `8` / `9` | 画质档 LOW / MEDIUM / HIGH（默认 MEDIUM） |
| `Esc` | 释放 / 重新捕获鼠标（自由查看用） |

### 模式切换

| 模式 | 按键 | 说明 |
| --- | --- | --- |
| 展示环绕（Showcase） | `1` | 主相机环绕全场景，距离 260 m、高度 95 m、注视高度 38 m、环绕 6°/s |
| 第一人称（First Person） | `2` | 玩家被激活并接管视角，眼高 2.6 m，鼠标锁定 |
| 第三人称（Third Person） | `3` | 相机跟随玩家身后（演示模式下降到 3°/s） |

三种模式共用同一 `CameraModeManager`，切换时激活新相机并令旧相机 `current = false`，
退出展示 / 演示模式后环绕速度严格还原到进入前的值，不残留状态。
`F6` 演示模式进入时固定为展示环绕 + NIGHT，退出时还原进入前的镜头模式与日照状态。

### 昼夜

- 三套预设资源：`materials/env_day_preset.tres`、`materials/env_sunset.tres`、`materials/env_night.tres`；
  取值优先级为「检查器覆盖 > `materials/*.tres` > 脚本内置默认」。
- `F1` / `F2` / `F3` 切换预设，过渡为插值（太阳角度 / 能量 / 颜色、天空、环境光、雾），无 180° 跳变
  （相邻 5 分钟最大太阳角度跳变 7.3°）。
- `F4` 打开自动昼夜：默认 180 s 一个完整循环，HUD 顶部实时显示当前预设与时刻。
- 夜晚光照**只用窗户自发光**：273 个窗网格去重为 2 份材质副本，夜间 `emission_energy_multiplier = 2.60`，
  零新增实时灯；夜景补光由 `NightLights` 提供且受画质档的灯光预算约束。

### 交互

- 6 个交互热点（`scenes/pois.tscn`，脚本 `scripts/poi_interactable.gd`）：

| 热点 | 说明 |
| --- | --- |
| Castle Main Gate（正门） | 正门可开合，交互后门扇开门动画 + 说明面板 |
| Central Tower（中央主塔） | 城堡最高塔与尖顶说明 |
| West Tower（西塔） | 西侧塔楼与旗杆说明 |
| East Tower（东塔） | 东侧塔楼与旗杆说明 |
| Gate Banners（门前旗帜） | 大门两侧旗帜说明 |
| Rock Podium & Garden Terrace（岩台花园） | 岩台基座与花园平台说明 |

- `InteractRay` 挂在 Player 下，`collision_mask = 5`，交互距离 9 m；准星指向热点时显示
  `「E 交互 · <热点名>」`，按 `E` 弹出说明面板，再按 `E` / `Esc` 关闭。
- `F8` 打开 POI 悬浮标记（标签 + 图标），便于定位。

### 烟花

- 4 个发射位（`scenes/fireworks.tscn`），`one_shot` 粒子，粒子寿命 2.4 s、单发射位 220 粒子，
  粒子总数恒定不累积。
- `F5` 开关；开启后按 `spawn_interval = 1.8 s`（±0.35 s 抖动）自动齐射，每次 2 发、发射时间错开 0.45 s。
- 与昼夜联动：`night_only = true`，可见度随夜晚系数变化（白天 0.22 倍，夜晚 1.0 倍）；
  画质档同时缩放粒子量（LOW 为 MEDIUM 的 25%）与拖尾开关。

### 性能档

| 参数 | LOW | MEDIUM（默认） | HIGH |
| --- | --- | --- | --- |
| `msaa` / `screen_space_aa` | 关 / FXAA | 4× / 关 | 4× / 关 |
| `render_scale` | 0.75 | 1.0 | 1.0 |
| `shadow_max_distance` | 150 m | 320 m | 520 m |
| `shadow_blur` / `light_angular_distance` | 0.3 / 0 | 1.0 / 0 | 1.6 / 1.2 |
| Glow / Fog / SSAO | 关 / 关 / 关 | 开 / 开 / 开 | 开 / 开 / 开 |
| `window_emission_scale` | 0.6 | 1.0 | 1.15 |
| `particle_scale` / 拖尾 | 0.25 / 关 | 1.0 / 开 | 1.0 / 开 |
| 夜景灯预算 | 3 | 不限 | 不限 |
| 相机远平面 | 700 m | 950 m | 1500 m |
| 小装饰物可见性终点 | 70 m | 140 m | 不剔除 |

- 切档即时生效，30 轮连续换档压力测试后节点数 / 粒子系统数（4）/ 灯光数（7）无漂移。
- 实测（Mac mini，M2 Pro，1600 × 900，真实窗口渲染，详见 `docs/PERFORMANCE_REPORT.md`）：
  12 组场景全部跑通，平均帧率 118.7–120.0 FPS（存在约 120 FPS 帧节奏上限，因此**平均帧率不适合区分档位**）；
  区分度看渲染负载——DAY + Showcase 下 Draw Call 由 HIGH 的 1629 降到 MEDIUM 934（−42.7%）、LOW 483（−70.4%）。
  **推荐默认档：MEDIUM。**

### 目录结构

```text
castle_godot/
├── project.godot                # 工程配置（主场景 res://scenes/main.tscn，1600×900，输入映射）
├── scenes/
│   ├── main.tscn                # 主场景：环境 + 太阳 + 地面 + 碰撞 + 城堡 + 玩家 + HUD + 各控制器
│   ├── player.tscn              # 玩家（第一/第三人称相机、InteractRay）
│   ├── hud.tscn                 # HUD（状态、准星、交互提示、说明面板）
│   ├── pois.tscn / poi_marker.tscn   # 6 个交互热点与悬浮标记
│   └── fireworks.tscn           # 4 个烟花发射位
├── scripts/
│   ├── castle_showcase.gd       # 展示机位环绕、太阳环绕、场景 AABB 自检
│   ├── player_controller.gd     # 移动 / 跳跃 / 视角 / teleport_to / apply_look
│   ├── camera_mode_manager.gd   # 三档镜头切换与状态还原
│   ├── castle_collision.gd      # 程序化碰撞体（23 个 static body）
│   ├── environment_manager.gd / environment_preset.gd   # 昼夜系统与预设资源
│   ├── night_lighting.gd        # 夜景补光与灯光预算
│   ├── hud.gd                   # 状态栏、准星、热点提示、说明面板
│   ├── interaction_controller.gd / interactable.gd / poi_interactable.gd / gate_poi.gd / gate_controller.gd
│   ├── fireworks_controller.gd  # 烟花发射、齐射、昼夜与画质联动
│   ├── presentation_controller.gd  # F6 演示模式编排与还原
│   ├── quality_manager.gd       # LOW / MEDIUM / HIGH 三档画质与可见性剔除
│   └── performance_hud.gd       # F7 性能 HUD
├── materials/
│   ├── env_day.tres, ground_grass.tres
│   └── env_day_preset.tres, env_sunset.tres, env_night.tres   # 三套昼夜预设
├── assets/models/castle_ref_model.glb   # 城堡模型（655 网格，230 × 88.29 × 230）
├── docs/
│   ├── PERFORMANCE_REPORT.md     # TASK 05 性能基准报告（12 组实测）
│   ├── benchmark_results.json    # 基准原始数据
│   ├── TASK01_DONE.md … TASK05_DONE.md   # 各阶段交付报告
│   ├── CHANGELOG_V2.md           # V2 变更日志（TASK 01–06）
│   ├── verify_quality_output.txt / verify_v2_output.txt   # 自检原始输出
│   └── screenshots/              # 四张交付截图（01 白天探索 / 02 夜景 / 03 烟花 / 04 性能 HUD）
└── tools/
    ├── verify_project.gd / verify_environment.gd / verify_interaction.gd / verify_quality.gd / verify_v2.gd
    ├── benchmark.gd              # 基准脚本
    └── capture_screenshots.gd    # 截图采集脚本
```

交付截图（`docs/screenshots/`）：

| 文件 | 内容 |
| --- | --- |
| `01_day_exploration.png` | 白天第一人称探索，前庭望向城堡 |
| `02_night_castle.png` | 夜景城堡（展示机位，仅窗户自发光 + 夜景补光） |
| `03_fireworks.png` | 夜间烟花齐射 |
| `04_performance_hud.png` | MEDIUM 档 + 性能 HUD（FPS / Draw Call / 坐标等） |

### 已知限制

- 平均帧率被约 120 FPS 的帧节奏上限压住（实测屏幕 240 Hz、vsync 已关、`Engine.max_fps = 0`），
  本机无法用平均 FPS 区分画质档，请参考 `docs/PERFORMANCE_REPORT.md` 中的最低帧 / 1% Low / Draw Call。
- 主要瓶颈是 Draw Call 与同帧物体数（城堡 GLB 共 655 个网格），城堡本体未做网格合并与 LOD。
- 碰撞体是**简化程序化碰撞**（23 个 Box / Cylinder，含门前斜坡与台基斜面），
  不是模型级 ConcavePolygonShape3D，塔楼尖顶等装饰区域不可攀爬。
- 烟花与夜景光效依赖 forward_plus 渲染后端；若改用移动 / 兼容后端，视觉与性能表现会变化。
- 阴影在 LOW 档仅 150 m，远处景物阴影会缺失；`prop_visibility_end` 会剔除 201 个几何对角线 < 4 m 的小装饰物
  （窗户除外），因此 LOW 档远景细节明显减少。
- 截图与基准脚本必须在**非 headless** 模式运行（需要真实渲染后端），headless 下只能跑自检脚本。
- 演示模式（F6）会临时接管镜头与昼夜，期间手动切换镜头模式会以最后一次操作为准，退出时还原到进入前状态。
*（内容由AI生成，仅供参考）*
