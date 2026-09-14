# TASK 05 — 性能优化、质量档与基准测试（完成记录）

## 交付物

| 文件 | 说明 |
| --- | --- |
| `castle_godot/scripts/quality_manager.gd` | 画质档管理器（节点 `QualityManager`），LOW / MEDIUM / HIGH 三档，快捷键 7 / 8 / 9 |
| `castle_godot/scripts/performance_hud.gd` | 性能 HUD（节点 `PerformanceHud`），快捷键 F7 显示 / 隐藏，默认关闭 |
| `castle_godot/scripts/hud.gd` + `scenes/hud.tscn` | 新增 `QualityLabel`（画质档状态行）与 `PerfLabel`（性能面板） |
| `castle_godot/scenes/main.tscn` | 挂接 `QualityManager` / `PerformanceHud`（GLB 未做任何改动） |
| `castle_godot/tools/benchmark.gd` | 基准脚本：4 场景 × 3 档 = 12 组，真实窗口渲染采样 |
| `castle_godot/tools/verify_quality.gd` | headless 自检脚本（89 项断言） |
| `castle_godot/docs/benchmark_results.json` | 12 组原始数据（机器可读） |
| `castle_godot/docs/PERFORMANCE_REPORT.md` | 性能基准报告（由上述 JSON 生成，含环境、参数、结果、瓶颈、复跑方式） |
| `castle_godot/docs/verify_quality_output.txt` | 自检脚本原始输出 |
| `castle_godot/scripts/fireworks_controller.gd` | 新增 `set_particle_draw_distance` / `get_particle_draw_distance`，供画质档控制粒子绘制距离 |
| `castle_godot/scripts/night_lighting.gd` | 新增 `set_light_budget`，供画质档限制夜间同时点亮的灯数 |
| `castle_godot/scripts/castle_showcase.gd` | 新增 `set_orbit_angle` / `get_orbit_angle`，供基准脚本把展示环绕相位错开 |

设计原则：**只通过已有子系统的公开接口下发参数，不重建任何节点 / 资源**。
三档走同一套代码路径，切换只改参数，因此任意档位可任意顺序互切；运行期粒子系统数、灯光数、材质数均恒定。

---

## 1. 性能 HUD（F7）

- 开关：`F7`（输入动作 `toggle_perf_hud`），启动默认**关闭**，隐藏时完全不采样（零开销）。
- 采样频率 4 次/秒（`update_interval = 0.25 s`），读数全部来自引擎自带 `Performance` 监视器，不依赖外部 profiler。
- 显示内容（推给 HUD 左下角 `PerfLabel`，与其它 HUD 元素互不干扰）：

```text
FPS 110  |  Frame 9.09 ms
Draw Calls 0  |  Objects 3730  |  Nodes 783
Quality: MEDIUM  |  1600x900 (scale 1.00)
Player: (0.0, 0.4, 78.0)
```

> 注：上面这行是 **headless 自检**里的实际抓取文本，因此 `Draw Calls` 为 0 属正常（无渲染后端）。
> 带窗口渲染下的真实 Draw Call 见第 5 节基准结果。
> 另外，`perf_hud.gd` 内部的 `get_metrics()` 还额外提供 `process_ms` / `physics_ms` / `static_memory_mb`，
> 供脚本化采样使用（基准脚本即复用同一套读数口径）。

---

## 2. 三档差异（LOW / MEDIUM / HIGH）

快捷键：`7` = LOW，`8` = MEDIUM，`9` = HIGH。下表为**实测生效值**（取自基准运行日志的 `[quality] level = ...`）。

| 参数 | LOW（稳定优先） | MEDIUM（默认） | HIGH（画质加料） |
| --- | --- | --- | --- |
| `msaa` | 关闭（0） | 4x（2） | 4x（2） |
| `screen_space_aa` | FXAA（1） | 关闭 | 关闭 |
| `render_scale` | 0.75 | 1.0 | 1.0 |
| `shadow_enabled` | true | true | true |
| `shadow_max_distance` | 150 m | 320 m | 520 m |
| `shadow_blur` | 0.3 | 1.0 | 1.6 |
| `light_angular_distance` | 0.0 | 0.0 | 1.2 |
| `glow_enabled` | **false（强制关）** | true | true |
| `fog_enabled` | **false（强制关）** | true | true |
| `ssao_enabled` | **false（强制关）** | true | true |
| `window_emission_scale` | 0.6 | 1.0 | 1.15 |
| `particle_scale` | **0.25** | 1.0 | 1.0 |
| `particle_trails` | **false** | true | true |
| `night_light_budget` | **3 盏** | 不限（-1） | 不限（-1） |
| `camera_far` | 700 m | 950 m | 1500 m |
| `prop_visibility_end` | 70 m | 140 m | **0（不剔除）** |
| `particle_draw_distance` | 300 m | 0（不限） | 0（不限） |

三档的定性差异：

| | LOW | MEDIUM | HIGH |
| --- | --- | --- | --- |
| 定位 | 稳定优先、画面明显降级但场景结构完整 | **与 TASK02~04 验收外观完全一致** | 在 MEDIUM 之上继续加料 |
| 后处理 | Glow / Fog / SSAO 全关 | 全开 | 全开 + 更远更柔的阴影 |
| 渲染分辨率 | 75% + FXAA 补抗锯齿 | 原生 + MSAA 4x | 原生 + MSAA 4x |
| 烟花 | 粒子 220（MEDIUM 的 25%）、无拖尾、绘制距离 300 m | 粒子 880（4 × 220）、带拖尾 | 同 MEDIUM |
| 夜景灯 | 最多同时点亮 3 盏 | 全部 6 盏 | 全部 6 盏 |
| 小装饰物 | 70 m 外剔除 | 140 m 外剔除 | 不剔除 |
| 实测 Draw Call（DAY + Showcase 同机位） | 483 | 934 | 1629 |

关键取舍：**glow / fog / ssao 三个键是"总开关与"语义**——画质档为 true 时由昼夜预设决定，为 false 时强制关闭。
因此 LOW 在白天也能关掉月亮 / 白昼预设里的 Glow、Fog、SSAO，保证"稳定优先"名副其实。

---

## 3. 默认质量：MEDIUM

- 工程默认值：`QualityManager.start_level = Level.MEDIUM`，启动即应用（`apply_on_ready = true`）。
- 理由：与 TASK02~04 已验证的夜景外观完全一致（**不产生任何视觉回退**）；Draw Call 相比 HIGH 低 42.7%；
  在本机 1600×900 下平均帧率已到帧节奏上限（见第 5 节）。符合任务书"Mac mini 默认 MEDIUM、稳定优先"的要求。

---

## 4. 可见性优化（实测生效）

| 手段 | 设置 | 效果（实测） |
| --- | --- | --- |
| 摄像机 far | 700 / 950 / 1500 m（LOW / MEDIUM / HIGH） | 限制最远绘制距离 |
| 太阳阴影距离 | 150 / 320 / 520 m | 阴影贴图覆盖范围随档位变化 |
| 小装饰物可见距离剔除 | `prop_visibility_end` = 70 / 140 / 不剔除 | 命中 **201 个**网格（几何对角线 < 4.0 m），`Win_` 窗户关键字排除、不参与剔除 |
| 粒子绘制距离 | LOW 300 m，MEDIUM/HIGH 不限 | 远景烟花粒子不再提交 |
| 夜景灯预算 | LOW 3 盏，MEDIUM/HIGH 全部 | 减少实时灯数量 |
| 粒子数量 | LOW 220 / MEDIUM 880 | LOW 为 MEDIUM 的 25%，且无拖尾 |

**未做**（任务书明确不要求）：没有强制重构城堡 655 个网格、没有改 GLB、没有做网格合并或 LOD。

DAY + Showcase 同机位实测（基准数据）：

| 档位 | Draw Calls | 相对 HIGH | Objects | 相对 HIGH | Primitives | 相对 HIGH |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| HIGH | 1629 | — | 2301 | — | 60416 | — |
| MEDIUM | 934 | **-42.7%** | 1610 | **-30.0%** | 41463 | -31.4% |
| LOW | 483 | **-70.4%** | 1153 | **-49.9%** | 20677 | -65.8% |

---

## 5. 基准结果

脚本：`castle_godot/tools/benchmark.gd`；环境：**Mac mini non-TV / Apple M2 Pro / macOS 26.6.2 / Godot 4.7.2-stable / forward_plus / 1600×900 窗口 / vsync 关闭（实测）/ 屏幕 240 Hz / Date 2026-09-14**。
每组场景预热 1.6 s 后连续采样 5.0 s，4 场景 × 3 档 = 12 组，全部跑通。
完整报告见 [`docs/PERFORMANCE_REPORT.md`](./PERFORMANCE_REPORT.md)，原始数据见 [`docs/benchmark_results.json`](./benchmark_results.json)。

| 场景 | 档位 | 平均 FPS | 最低 FPS | 1% Low | 平均帧时长 (ms) | Draw Calls | Objects |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| DAY + Showcase | LOW | 120.0 | 81.6 | 103.7 | 8.34 | 483 | 1153 |
| DAY + Showcase | MEDIUM | 119.7 | 43.2 | 81.3 | 8.36 | 934 | 1610 |
| DAY + Showcase | HIGH | 120.0 | 72.8 | 90.5 | 8.33 | 1629 | 2301 |
| NIGHT + Showcase | LOW | 119.9 | 61.4 | 103.0 | 8.34 | 483 | 1157 |
| NIGHT + Showcase | MEDIUM | 119.7 | 56.6 | 79.0 | 8.36 | 929 | 1609 |
| NIGHT + Showcase | HIGH | 118.8 | 48.6 | 78.7 | 8.41 | 1618 | 2294 |
| NIGHT + Fireworks | LOW | 118.7 | 47.0 | 61.7 | 8.42 | 485 | 1157 |
| NIGHT + Fireworks | MEDIUM | 119.6 | 49.1 | 78.0 | 8.36 | 928 | 1606 |
| NIGHT + Fireworks | HIGH | 119.1 | 53.4 | 79.0 | 8.40 | 1579 | 2253 |
| Player Exploration | LOW | 119.6 | 52.0 | 92.2 | 8.36 | 610 | 1288 |
| Player Exploration | MEDIUM | 119.9 | 60.3 | 82.6 | 8.34 | 638 | 1322 |
| Player Exploration | HIGH | 119.5 | 42.2 | 78.7 | 8.37 | 803 | 1483 |

读表要点（必须看，否则会误读数据）：

1. **平均 FPS 已饱和**：12 组全部落在 118.7 ~ 120.0 FPS，帧间隔 8.33 ~ 8.42 ms。
   在 Draw Call 相差 3.4 倍（483 → 1629）的情况下平均帧率几乎不变，说明本机窗口模式存在约 120 FPS 的帧节奏限制
   （实测屏幕 240 Hz、vsync 已关闭、`max_fps = 0`）。**不能用平均 FPS 判断档位优劣**。
2. **烟花是瞬时负载**：NIGHT + Fireworks 平均帧率 118.7 ~ 119.6，但最低 FPS 掉到 47.0 ~ 53.4、1% Low 61.7 ~ 79.0，
   是 4 个场景里抖动最大的一组（采样期内实际发射 4 ~ 6 轮齐射）。
3. **LOW 不等于"帧率更高"**：LOW 的收益体现在渲染负载（Draw Call / Objects 大幅下降），而非本机平均帧率。
   它的价值是在更弱的机器或更高分辨率下抬高性能下限。
4. **玩家探索三档可比**：每档开始前显式复位位置与朝向（`_reset_player_heading`），三档走出完全相同的圆弧轨迹，
   末位置 (-60.5, 0.0, 51.3)、末朝向 114.0° 一致，Draw Call 610 / 638 / 803 的差异来自画质档本身而非取景差异。

---

## 6. 自检结果

### 6.1 画质档 / HUD 自检（`tools/verify_quality.gd`，headless）

```bash
"/Users/yujiang/Downloads/Godot.app/Contents/MacOS/Godot" --headless --path . --script res://tools/verify_quality.gd
```

结果：**89 项通过 / 0 项失败**（原始输出：`docs/verify_quality_output.txt`）

| 分组（脚本内编号） | 覆盖内容 | 断言数 | 关键证据 |
| --- | --- | ---: | --- |
| [1] 装配 | QualityManager / PerformanceHud / HUD 的 `QualityLabel` + `PerfLabel` / 四个输入动作 / 三档常量表 | 10/10 | `[quality] ready \| default=MEDIUM props=201` |
| [2] 默认画质档 | 启动档 = MEDIUM、HUD 状态行同步、渲染比例 1.0、未关闭 Glow / Fog | 4/4 | `HUD 显示 Quality: MEDIUM` |
| [3] 性能 HUD（F7） | 默认关闭 → F7 打开 → 文本推到 HUD → F7 关闭 → 隐藏后不再采样 | 13/13 | 读数含 FPS / 帧时间 / Draw Calls / 对象 / 节点 / 画质档 / 分辨率 / 玩家坐标 |
| [4] 7 / 8 / 9 真实按键切档 | 合成按键事件走完整输入链路，切档与 F7 交叉互不干扰 | 8/8 | `按 7 → LOW` / `按 9 → HIGH` / `按 8 → MEDIUM` |
| [5] 三档逐项生效值 | LOW 14 项、HIGH 8 项、MEDIUM 6 项、灯光预算 2 项 | 31/31 | LOW 粒子 220 = MEDIUM 880 的 25%；HIGH 剔除距离 0（不限）；三台相机 far 同步 |
| [6] 稳定性（30 轮换档） | 连续 30 轮换档后节点 / 灯光 / 粒子 / 相机 / 材质数量不漂移 | 5/5 | 节点 782 → 782、灯光 7 → 7、粒子系统 4 → 4、相机 3 → 3、窗光材质恒定 2 份 |
| [7] TASK01~04 回归 | 玩家 / 环境 / POI / 交互 / 烟花 / 夜景灯 / 演示模式 / 碰撞体 / HUD 全部仍在且接口完整 | 18/18 | 城堡 GLB 655 个网格、POI 6 个、烟花发射位 4 个、夜景灯 6 盏、剔除清单 201 个、白天预设可切 |

### 6.2 基准脚本

```bash
"/Users/yujiang/Downloads/Godot.app/Contents/MacOS/Godot" --path . --resolution 1600x900 --script res://tools/benchmark.gd
```

结果：**12 组全部跑通**，输出 `=== 基准测试完成：12 组 ===`，并写出 `docs/benchmark_results.json`。

---

## 7. 推荐默认档与主要瓶颈

### 推荐默认档：MEDIUM

- 与 TASK02~04 已验收外观完全一致，不引入视觉回退；
- Draw Call 相比 HIGH 低 42.7%、Objects 低 30.0%，已把可见性收益拿到手；
- 本机平均帧率已到帧节奏上限，MEDIUM 与 HIGH 的平均 FPS 差异在噪声内，而 MEDIUM 的负载明显更低；
- LOW 保留为"弱机 / 高分屏"降级档，也可在演示需要更高帧稳定性时手动按 `7` 切换。

### 主要瓶颈（按影响排序）

1. **Draw Call 与同帧物体数量**：城堡 GLB 共 655 个网格，HIGH 档同屏 1629 Draw Call / 2301 Objects。
   画质档只能在"整片剔除小装饰物"这一粒度上起作用，粒度有限。
   后续方向：静态网格合并 / MultiMesh 实例化 / 人工 LOD。
2. **阴影距离与后处理**：`shadow_max_distance`（150 / 320 / 520 m）与 Glow / Fog / SSAO 是 HIGH 档的主要增量成本，
   本机 GPU 未被打满，需要更强或更弱的硬件才能体现差异。
3. **烟花瞬时尖峰**：一次齐射同时激活 2 个发射位，最低帧掉到 47 左右。
   后续方向：给烟花加"同时存活上限"或加大齐射错峰，LOW 档已通过粒子 25% + 关闭拖尾 + 300 m 绘制距离来削峰。
4. **帧节奏本身**：12 组平均帧率贴顶约 120 FPS，最低帧波动更多来自帧节奏抖动而非渲染负载，
   说明继续在"画质参数"上做优化收益有限，重心应放在减少 Draw Call 与瞬时提交。

---

## 8. 本次修复的脚本缺陷（诚实记录）

基准脚本首次运行暴露了两个真实问题，均已在提交前修复，并复跑验证：

1. `benchmark.gd` 中 `var p99_ms := ...` / `var sorted := ...` 触发 GDScript 类型推断失败（Parse Error），
   脚本无法加载 → 改为显式类型标注 `Array[float]` / `float`，并移除未使用变量。
2. 玩家探索场景原先只调 `teleport_to()`（只复位位置与俯仰、不复位 yaw），导致 LOW 轮的转向残留到 MEDIUM / HIGH 轮，
   三档取景完全不同（实测末朝向 114.0° / -132.0° / -18.0°），数据不可比 →
   新增 `_reset_player_heading()`，每档开始显式复位位置与朝向，修复后三档末朝向一致（114.0°）。

---

## 9. 快捷键汇总（TASK05 新增）

| 按键 | 功能 |
| --- | --- |
| **F7** | 性能 HUD 显示 / 隐藏（默认关闭） |
| **7 / 8 / 9** | 画质档 LOW / MEDIUM / HIGH |
| F1 / F2 / F3 | 白天 / 黄昏 / 夜晚（TASK02） |
| F4 | 自动昼夜（TASK02） |
| F5 | 烟花开关（TASK04） |
| F6 | 演示模式（TASK04） |
| 1 / 2 / 3 | 展示 / 第一人称 / 第三人称（TASK01） |
| E、F8 | 交互、POI marker（TASK03） |

---

## 10. 提交

```bash
git add -A
git commit -m "perf(castle): add quality presets performance hud and benchmark"
git push
```

分支：`work/macmini-nontv-castle-v2`（不合并 main）
