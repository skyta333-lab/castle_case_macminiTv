# CHANGELOG — Castle V2（Mac mini non-TV 全天任务）

分支：`work/macmini-nontv-castle-v2` ｜ 基线：V1 静态展示工程
本日志覆盖 **TASK 01 – TASK 06** 的全部变更，均为实测可复跑结果，未做人工修饰。

---

## TASK 01 — 玩家探索（第一/第三人称自由行走）

**目标**：把 V1 的「固定机位展示」升级为可自由探索的场景，并保证物理与碰撞可用。

新增：

- `scripts/player_controller.gd`：WASD 移动、Shift 冲刺、Space 跳跃、鼠标视角（俯仰受限），
  对外暴露 `get_interact_ray()`、`apply_look(relative)`、`set_active()`、`teleport_to()`、`get_active_camera()`
  等公开方法，便于 headless 验证与其它控制器复用。
- `scripts/camera_mode_manager.gd`：展示环绕 / 第一人称 / 第三人称三档镜头统一切换，
  切换时只激活目标相机并令旧相机 `current = false`，退出后环绕速度严格还原。
- `scripts/castle_collision.gd`：按城堡模型关键部位**程序化生成简化碰撞体**（23 个 static body，
  含门前斜坡与台基斜面 Cap），避免把 655 个网格全量转 ConcavePolygonShape3D 带来的开销。
- `scripts/hud.gd` + `scenes/hud.tscn`：状态栏、准星、交互提示与说明面板骨架。
- `scenes/player.tscn`：玩家场景（第一人称相机 + 第三人称相机 + 挂在 Player 下的 `InteractRay`，
  `collision_mask = 5`，交互距离 9 m）。
- `project.godot`：补齐输入映射（移动 / 冲刺 / 跳跃 / 交互 / 三档镜头 / 昼夜 / 烟花 / 演示模式 / 画质 / 鼠标）。

结果：玩家可在前庭与台基上正常行走、跳跃、切换视角，碰撞体数量受控（23 个）。

---

## TASK 02 — 昼夜环境系统

**目标**：DAY / SUNSET / NIGHT 三套预设 + 自动昼夜循环，夜晚靠窗户自发光而非新增实时灯。

新增：

- `scripts/environment_manager.gd`、`scripts/environment_preset.gd`（自定义 Resource）。
- `materials/env_day_preset.tres`、`materials/env_sunset.tres`、`materials/env_night.tres`。
  预设取值优先级：**检查器覆盖 > `materials/*.tres` > 脚本内置默认**。
- `F1` / `F2` / `F3` 切预设、`F4` 自动昼夜（`day_length_seconds = 180`）。
- 过渡方式：太阳角度 / 能量 / 颜色、天空、环境光、雾密度全部插值，**相邻 5 分钟最大太阳角度跳变 7.3°**，
  无 180° 跳变；`get_night_factor()` 供烟花、夜景灯等系统读取。
- 窗户自发光：273 个窗网格去重为 **2 份材质副本**，夜间 `emission_energy_multiplier = 2.60`，**零新增实时灯**。
- `tools/verify_environment.gd`：headless 自检，结尾打印 `TASK02_VERIFY_PASS`。

结果：昼夜切换与连续推进均可用，夜晚画面由窗光承担主要可读性。

---

## TASK 03 — 交互热点（POI）

**目标**：在城堡关键位置布置交互热点，准星命中提示 + 交互说明，正门可开合。

新增：

- `scripts/interactable.gd`（接口基类：`get_interaction_text()` / `interact()`）、
  `scripts/poi_interactable.gd`（POI 实现 + 悬浮标记）、`scripts/interaction_controller.gd`（射线检测与调度）。
- `scripts/gate_poi.gd`、`scripts/gate_controller.gd`：正门开合逻辑与门扇动画。
- `scenes/pois.tscn`、`scenes/poi_marker.tscn`：**6 个交互热点**
  Castle Main Gate（正门）、Central Tower（中央主塔）、West Tower（西塔）、East Tower（东塔）、
  Gate Banners（门前旗帜）、Rock Podium & Garden Terrace（岩台花园）。
- `E` 交互：命中热点时准星提示 `「E 交互 · <热点名>」`，按下弹出说明面板，再按 `E` / `Esc` 关闭；
  `F8` 开关 POI 悬浮标记。
- `tools/verify_interaction.gd`：headless 逐点验证 6 个热点命中、说明文案与正门开合，
  同时回归「交互系统不影响移动与落地」。

结果：6 个热点全部可命中并可交互，正门开合正常。

---

## TASK 04 — 烟花特效与演示模式

**目标**：夜间烟花齐射，并提供一键演示（切夜景 + 展示机位）。

新增：

- `scripts/fireworks_controller.gd`、`scenes/fireworks.tscn`：**4 个发射位**，`one_shot` 粒子，
  粒子寿命 2.4 s、单发射位 220 粒子，**粒子总数恒定不累积**。
- 齐射策略：`spawn_interval = 1.8 s`（±0.35 s 抖动），每次 2 发、错开 0.45 s；
  对外提供 `set_enabled()` / `fire_volley()` / `fire_burst_now()` / `get_emitting_count()` / `get_fired_total()`。
- 昼夜联动：`night_only = true`，可见度随夜晚系数缩放（白天 0.22 倍 → 夜晚 1.0 倍）。
- `scripts/presentation_controller.gd`：`F6` 演示模式——一键切 NIGHT + 展示环绕机位（环绕降到 3°/s），
  再按 `F6` 完整还原进入前的镜头模式、环绕速度与日照状态。
- `scripts/night_lighting.gd`：夜景补光组，并提供 `set_light_budget()` 供画质档限制灯光数量。

结果：夜间烟花可自动齐射，演示模式进入 / 退出无状态残留。

---

## TASK 05 — 性能基准与画质档

**目标**：三档画质、性能 HUD、可复跑基准与实测报告。

新增：

- `scripts/quality_manager.gd`：LOW / MEDIUM / HIGH 三档参数化画质（MSAA、渲染缩放、阴影距离与模糊、
  角度光半径、Glow / Fog / SSAO、窗光强度、粒子缩放与拖尾、夜景灯预算、相机远平面、小装饰物可见性剔除），
  默认 **MEDIUM**；`set_level()` / `get_level_name()` / `get_effective_settings()` 对外可用。
- `scripts/performance_hud.gd`：`F7` 性能 HUD（FPS、帧时长、Draw Call、物体数、节点数、画质档、
  分辨率与渲染缩放、玩家坐标），刷新间隔 0.25 s。
- `tools/benchmark.gd`：真实窗口渲染下 4 场景 × 3 档位共 **12 组**采样（预热 1.6 s + 采样 5.0 s / 组），
  输出 `docs/benchmark_results.json`。
- `tools/verify_quality.gd`：**89 项断言全部通过**（三档参数、性能 HUD、30 轮换档稳定性、TASK01–04 回归），
  原始输出 `docs/verify_quality_output.txt`。
- `docs/PERFORMANCE_REPORT.md`：12 组实测数据与结论。
- 关联改动：`scenes/main.tscn`、`scripts/fireworks_controller.gd`（画质缩放注入）、
  `scripts/night_lighting.gd`（灯光预算）。

结果（Mac mini，Apple M2 Pro，1600 × 900）：

- 12 组全部跑通，平均帧率 **118.7 – 120.0 FPS**；本机存在约 120 FPS 的帧节奏上限，
  因此平均帧率不具区分度，改看最低帧 / 1% Low / Draw Call / Objects。
- DAY + Showcase 同机位对比：Draw Call 1629（HIGH）→ 934（MEDIUM，−42.7%）→ 483（LOW，−70.4%）；
  同帧物体数 2301 → 1610（−30.0%）→ 1153（−49.9%）。
- 30 轮连续换档后节点数、粒子系统数（4）、灯光数（7）无漂移。
- **推荐默认档：MEDIUM**（工程默认值一致，画面与 TASK02–04 验收结果一致）。

---

## TASK 06 — QA、自动验证与 V2 交付

新增 / 变更：

- `tools/verify_v2.gd`：V2 交付总自检，覆盖 A~I 九组——主场景与必需节点、模型与场景规模、
  玩家落地与移动、三档镜头切换与状态还原、昼夜预设与自动循环、交互热点与正门开合、
  烟花与演示模式还原、性能 HUD 与三档画质、V2 交付物完整性。
- `tools/capture_screenshots.gd`：非 headless 截图采集脚本，生成
  `docs/screenshots/01_day_exploration.png`、`02_night_castle.png`、`03_fireworks.png`、`04_performance_hud.png`。
- `README.md` 升级为 V2：项目简介、启动方式、操作键、模式切换、昼夜、交互、烟花、性能档、目录结构、已知限制。
- 新增本文件 `docs/CHANGELOG_V2.md`，按 TASK 01–06 汇总。
- 仓库清洁度：新增 `.gitignore`（忽略 `.godot/` 缓存、`.DS_Store`、系统垃圾与中间产物），
  并将已误入库的 `.godot/` 缓存移出版本控制（磁盘文件保留）。
- 最终提交并推送到 `work/macmini-nontv-castle-v2`，PR 指向 `main`，**不自动合并**。

验收要点：`tools/verify_v2.gd` 全组通过、四张截图存在且非空、README / CHANGELOG 齐全、
`git status` 无无关缓存与临时文件。
