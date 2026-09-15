# TASK 04 — 夜景视觉升级 + 烟花特效（完成记录）

## 交付物

| 文件 | 说明 |
| --- | --- |
| `castle_godot/scripts/night_lighting.gd` | 夜景灯光组（节点 `NightLights`），固定 6 盏 OmniLight3D，随昼夜系数平滑亮灭 |
| `castle_godot/scripts/fireworks_controller.gd` | 烟花系统控制器（GPUParticles3D，4 发射位错峰，可开关、可参数化） |
| `castle_godot/scripts/presentation_controller.gd` | 演示模式（F6）：切 NIGHT + 开烟花 + 展示相机 + 缓慢环绕，可完整还原 |
| `castle_godot/scenes/fireworks.tscn` | 烟花场景（`Fireworks` 节点 + 4 个 Marker3D 发射位 Pad1~Pad4） |
| `castle_godot/scenes/main.tscn` | 挂接 `NightLights` / `Fireworks` / `PresentationController`（GLB 未做任何改动） |
| `castle_godot/scripts/hud.gd` + `scenes/hud.tscn` | 新增 FX 状态行（`FX: Fireworks ON/OFF | Presentation ON/OFF`） |
| `castle_godot/tools/verify_fx.gd` | headless 自检脚本（63 项断言） |
| `castle_godot/tools/soak_fx.gd` | headless 稳定性长跑脚本（真实运行 10 分钟，每 30 秒采样） |

设计原则：**用少量固定灯 + 材质自发光**做夜景，**不创建任何随时间增长的实时资源**。
所有新增节点均为静态结构，粒子系统数量、灯光数量、材质数量在运行期恒定。

---

## 1. 夜景灯光（共 6 盏，固定）

`NightLights` 在世界坐标固定放置 6 盏 `OmniLight3D`，全部 **关闭阴影**（`shadow_enabled = false`），
亮度由 `night_factor` 经 `pow(factor, 1.35)` 曲线驱动，白天为 0（熄灭），夜晚满亮：

| 名称 | 位置 | 颜色 | 能量 | 范围 | 用途 |
| --- | --- | --- | --- | --- | --- |
| GateWarm | (0, 8.5, 30.5) | (1.00, 0.72, 0.42) 暖光 | 7.0 | 32 | 主入口暖光 |
| ForecourtWest | (-18, 9, 30) | (0.62, 0.78, 1.00) 冷光 | 3.2 | 36 | 西侧补光 |
| ForecourtEast | (18, 9, 30) | (0.62, 0.78, 1.00) 冷光 | 3.2 | 36 | 东侧补光 |
| TowerRimLow | (0, 30, 16) | (1.00, 0.86, 0.62) | 5.0 | 46 | 主塔轮廓（下段） |
| TowerRimHigh | (0, 62, -2) | (0.78, 0.86, 1.00) | 3.6 | 52 | 主塔轮廓（上段） |
| PodiumAccent | (-24, 8, 34) | (1.00, 0.66, 0.38) | 2.6 | 22 | 台基 / 露台点缀 |

窗户发光沿用 TASK02 的**材质自发光策略**：91 个 `Win_Glass` 网格按源材质去重后共享 2 份 `StandardMaterial3D` 副本
（夜晚 `emission_energy = 2.6`，暖色 (1, 0.72, 0.38)），**零新增实时灯**。

暖冷对比：入口/台基偏暖（2700~3000K 观感），前庭侧光与主塔上段偏冷（月色调），形成"暖门面 + 冷轮廓"的夜景层次。

---

## 2. 烟花系统

场景 `scenes/fireworks.tscn`，4 个发射位（≥3 要求），每个发射位挂 1 个 `GPUParticles3D`：

| 发射位 | 世界坐标 | 说明 |
| --- | --- | --- |
| Pad1 | (-70, 110, 60) | 西南高空 |
| Pad2 | (80, 120, 30) | 东南高空 |
| Pad3 | (0, 135, 90) | 正阴天顶 |
| Pad4 | (40, 125, -80) | 城堡后方 |

粒子参数：

| 参数 | 值 | 说明 |
| --- | --- | --- |
| 单发粒子数 `particle_amount` | 220 | 每个发射位单次爆发上限 |
| 总粒子预算 | **880** = 220 × 4 | 恒定，运行期不增长（长跑实测恒定 880） |
| 生命周期 | 2.4 s | `one_shot = true`，爆炸后自然消散 |
| `fixed_fps` | 30 | 限制粒子更新频率，降低 GPU 峰值 |
| 拖尾 | 开启（画质可关） | `trail_enabled`，由质量档位接管 |
| 发射节奏 | `spawn_interval = 1.8 s` ±35% 抖动 | 避免机械感 |
| 每轮齐射 | `burst_count = 2` 个发射位 | 从 4 个发射位随机抽取 |
| 错峰 | `burst_stagger = 0.45 s` | 同一轮内 2 发之间随机错开 0~0.45 s |
| 材质 | 每发射位独立 `StandardMaterial3D`（加法混合 + 自发光 3.0，不投/不受阴影） | 数量固定，不累积 |

昼夜响应：夜晚可见度 1.0，白天压到 `day_visibility = 0.22`（自检实测 0.220），即"白天不强制显示高亮烟花"。

---

## 3. 演示模式（F6）

`PresentationController` 进入演示模式时按顺序执行，并**记录进入前状态**，再次 F6 完整还原：

| 步骤 | 进入 F6 | 退出 F6 |
| --- | --- | --- |
| 环境 | 切 NIGHT 预设 + 关闭自动昼夜 | 还原进入前预设（如 DAY）与自动昼夜开关 |
| 烟花 | 打开 | 关闭 |
| 相机 | 切展示相机（Showcase，mode=1） | 还原进入前相机模式（探索中触发则回到探索） |
| 环绕 | 速度改为 `orbit_speed = 3.0` 度/秒（缓慢环绕） | 还原原速度（默认 6.0 度/秒） |
| HUD | `Presentation ON` | `Presentation OFF` |

---

## 4. 视觉质量约束

夜景不追求写实，只追求"变化明显、稳定、可控"，相关参数都在环境预设里（`materials/env_night.tres`）：

| 项 | NIGHT 取值 | 防翻车措施 |
| --- | --- | --- |
| Glow 强度 / Bloom | 1.1 / 0.2 | 阈值 0.85，自发光能量 2.6 + 烟花 3.0，避免泛光炸白 |
| 曝光 | 0.90 | 配合月光 0.17 + 环境光 0.28，避免整体过暗 |
| 雾 | 密度 0.0022，雾色 (0.09, 0.12, 0.25) | 冷色薄雾拉开城堡与远景层次 |
| SSAO | 关闭 | 夜间省 GPU |
| 粒子总量 | 硬上限 220 × 4 = 880 | 无逐帧新增粒子系统 / 无逐帧重建缓冲（仅质量档位变化时写 `amount`） |
| 实时灯 | **仅 6 盏**，全部无阴影 | 拒绝"数百实时灯"方案 |

---

## 5. 参数化（任务 05 可接管）

烟花已暴露（`@export`，检查器可改、脚本可写）：

```text
enabled           烟花总开关（bool，默认 false）
spawn_interval    发射间隔秒（0.1~30，默认 1.8）
burst_count       每轮齐射的发射位数（1~8，默认 2）
particle_amount   单发粒子数（32~2048，默认 220）
```

其它可调项：`interval_jitter`、`burst_stagger`、`start_delay`、`particle_lifetime`、`particle_speed_min/max`、
`particle_gravity`、`trails_enabled`、`night_only`、`day_visibility`，以及给 TASK05 预留的
`set_quality_scale(scale, use_trails)`（同时缩放粒子数量与拖尾，实测不重建粒子系统、不改变对象数量）。

---

## 6. 自检结果

### 6.1 功能自检（`tools/verify_fx.gd`，headless）

```bash
Godot --headless --path . --script res://tools/verify_fx.gd
```

结果：**63 项通过 / 0 项失败**

| 分组 | 覆盖内容 | 结果 |
| --- | --- | --- |
| A 场景装配 | Fireworks / NightLights / PresentationController / HUD FX 行 / TASK01-03 节点仍在 | 8/8 |
| B 烟花结构 | 4 发射位、每发射位 1 个 one_shot GPUParticles3D、坐标互不相同、4 个参数已暴露且可写 | 9/9 |
| C F5 真实按键 | 启动关闭 → F5 开 → F5 关；HUD 状态同步；关闭后无粒子在发射、队列清空 | 8/8 |
| D 发射与错峰 | 自动周期内确实发射（fired 0→8）、一轮齐射 3 发、≥2 发带错峰延迟、队列消费干净 | 6/6 |
| E 不累积 | 600 轮齐射（≈18 分钟等价）后节点数 / 粒子系统数 / 灯光数 / 粒子预算全部不变 | 6/6 |
| F 昼夜响应 | 白天 night=0.000、可见度 0.220、灯光熄灭 energy=0；夜晚 night=1.000、可见度 1.000、点亮 6/6 盏、全部无阴影 | 8/8 |
| G F6 演示模式 | 进入（NIGHT + 烟花 ON + mode=1 + 3.0 度/秒 + HUD ON）、退出（烟花关 + 环绕还原 6.00 + 环境还原 DAY + HUD OFF） | 14/14 |
| H 回归 | GLB 节点 656 个子节点未动、程序化碰撞体仍在、交互控制器仍在、F1-F6 键位无冲突 | 4/4 |

### 6.2 稳定性长跑（`tools/soak_fx.gd`，headless，真实运行 10 分钟）

```bash
Godot --headless --path . --script res://tools/soak_fx.gd
```

运行条件：NIGHT 预设 + 烟花开启（真实 `spawn_interval`，未加速），每 30 秒采样。

| t(s) | 引擎对象数 | 场景节点数 | 粒子系统数 | 灯光数 | 活跃粒子总量 | 待发队列 |
| --- | --- | --- | --- | --- | --- | --- |
| 0 | 3735 | 780 | 4 | 6 | 880 | 0 |
| 150 | 3736 | 780 | 4 | 6 | 880 | 0 |
| 300 | 3736 | 780 | 4 | 6 | 880 | 0 |
| 450 | 3736 | 780 | 4 | 6 | 880 | 0 |
| 600 | 3736 | 780 | 4 | 6 | 880 | 0 |

- 结论：**PASS**
- 引擎对象数漂移 3735 → 3736（+1，为首帧一次性初始化），前段均值 3735.9 / 后段均值 3736.0，**无单调增长**
- 场景节点数恒定 780，粒子系统恒定 4 个，灯光恒定 6 盏，粒子预算恒定 880
- 10 分钟内真实发射统计：齐射 **337 轮**、触发 **674 发**（= 337 × 2，与配置完全吻合，无泄漏无重复）
- 待发队列峰值仅 1，夜景灯点亮峰值 6 盏

---

## 7. 性能观察

- **对象数量**：10 分钟连续发射 + 夜景灯全亮的条件下，引擎对象数稳定在 3736（漂移 1），节点数恒定 780，**不存在持续增长**。
- **粒子**：一次齐射最多同时 2 个发射位生效，活跃粒子总量峰值 880（= 220 × 4 上限），`one_shot` + `lifetime 2.4s` 保证自然消散；关闭烟花立即停止发射并清空待发队列。
- **灯光**：夜景只增加 6 盏无阴影 OmniLight3D，白天能量总和为 0（实测 energy=0.0000），不参与阴影贴图渲染。
- **材质**：窗户自发光仅 2 份材质副本（按源材质去重），烟花每个发射位 1 份固定材质，均不随运行时间增长。
- **限制策略**：粒子更新 `fixed_fps = 30`，拖尾可由质量档位关闭，`set_quality_scale` 缩放粒子数但**不重建粒子系统**，为 TASK05 的低画质档预留了"降本不增量"的通路。
- 说明：headless 环境无法给出真实渲染帧率/GPU 占用，**帧率与画质档位实测数据由 TASK05 的性能基准脚本负责**；本任务的性能结论限定在"对象/资源不增长"这一可客观测定的范围内。

---

## 8. 快捷键汇总（TASK04 新增）

| 按键 | 功能 |
| --- | --- |
| **F5** | 烟花开关（ON/OFF，HUD 实时同步） |
| **F6** | 演示模式进入 / 退出（NIGHT + 烟花 + 展示相机 + 缓慢环绕） |
| F1 / F2 / F3 | 白天 / 黄昏 / 夜晚（TASK02） |
| F4 | 自动昼夜（TASK02） |
| 1 / 2 / 3 | 展示 / 第一人称 / 第三人称（TASK01） |
| E、F8 | 交互、POI marker（TASK03） |

---

## 9. 提交

```bash
git add -A
git commit -m "feat(castle): add night lighting and fireworks presentation mode"
git push
```

分支：`work/macmini-nontv-castle-v2`（不合并 main）
