---
AIGC:
    Label: "1"
    ContentProducer: 001191440300708461136T1XGW3
    ProduceID: 44f0e24762f9ee24c3d7182ad71c0adb_15301d1bb02411f1ac01525400e6dd8f
    ReservedCode1: F9CgHi8QGg9dp7pqQm4JfGF/UXW1jMsYCufjTGHc4WVqW/DRAwRjYVnRLF6bEuQwBWdOxDWJUAZgDcSp874ak6jFEnHqT0lyCtT6cR57vcrvWXcgyksjrSyBvGrumcuL9X5Sy9Sb9RF0M4Vy+7v3ZgllOW807CZT9ZkbYmUinaS7bALtqkvCGDtmmcI=
    ContentPropagator: 001191440300708461136T1XGW3
    PropagateID: 44f0e24762f9ee24c3d7182ad71c0adb_15301d1bb02411f1ac01525400e6dd8f
    ReservedCode2: F9CgHi8QGg9dp7pqQm4JfGF/UXW1jMsYCufjTGHc4WVqW/DRAwRjYVnRLF6bEuQwBWdOxDWJUAZgDcSp874ak6jFEnHqT0lyCtT6cR57vcrvWXcgyksjrSyBvGrumcuL9X5Sy9Sb9RF0M4Vy+7v3ZgllOW807CZT9ZkbYmUinaS7bALtqkvCGDtmmcI=
---

# 城堡性能基准报告（TASK 05）

本报告由 `castle_godot/tools/benchmark.gd` 在本机真实窗口渲染下跑出的 12 组数据生成，
数据原始文件：`castle_godot/docs/benchmark_results.json`。所有数值均为实测，未经人工修饰。

## 1. 结论摘要

- 4 个场景 × 3 个画质档共 **12 组全部跑通**，无脚本错误、无崩溃。
- 平均帧率在 **118.7 ~ 120.0 FPS** 区间，帧间隔 8.33 ~ 8.42 ms。把 Draw Call 从 483 拉到 1629（3.4 倍）
  平均帧率几乎不动，说明本机在该分辨率下存在 **约 120 FPS 的帧节奏上限**（实测屏幕刷新率 240 Hz、
  vsync 已关闭、`Engine.max_fps = 0`）。因此 **平均 FPS 已饱和，不能用来区分档位优劣**，
  区分度应看 **最低 FPS / 1% Low / Draw Call / Objects**。
- 可见性优化效果明确（DAY + Showcase 同机位对比）：
  Draw Call 由 HIGH 的 1629 降到 MEDIUM 934（**-42.7%**）、LOW 483（**-70.4%**）；
  同帧物体数由 2301 降到 1610（**-30.0%**）/ 1153（**-49.9%**）。
- **推荐默认档：MEDIUM**（工程默认值已是 MEDIUM，符合“稳定优先”，且画面与 TASK02~04 验收一致）。
- **主要瓶颈：Draw Call 与同帧物体数量**（城堡 GLB 共 655 个网格），其次是阴影距离（HIGH 520m / MEDIUM 320m / LOW 150m）
  与夜景后处理（Glow / Fog / SSAO）。在本机这个规模下，GPU 并未被打满，帧率对画质档不敏感。

## 2. 测试环境

| 项目 | 值 |
| --- | --- |
| Machine | Mac mini non-TV |
| 处理器 | Apple M2 Pro（10 核） |
| 显卡 | Apple M2 Pro (Apple8)，Vulkan 4.0 |
| 内存 | 16384 MB |
| 操作系统 | macOS 26.6.2 |
| Godot | 4.7.2-stable (official) |
| 渲染后端 | forward_plus |
| Resolution | 1600 × 900（窗口模式） |
| Preset | 场景相关：DAY / NIGHT（见下表） |
| Date | 2026-09-14 |
| vsync / max_fps | 实测 vsync_mode=0（关闭）/ Engine.max_fps=0 |
| 屏幕刷新率 | 240 Hz（实测） |

> 说明：本机屏幕实测 240 Hz，但 12 组平均帧率稳定落在 119 ~ 120 FPS，说明窗口模式下存在约 120 FPS 的帧节奏限制。
> 这一点直接决定了读表方式：**平均 FPS 全部贴顶，档位差异只体现在最低帧与渲染负载上**。

## 3. 基准方法

脚本：`castle_godot/tools/benchmark.gd`（`--script` 方式启动，真实渲染，不 headless）。

- 每组场景：先按场景配置（画质档 / 昼夜预设 / 镜头模式 / 烟花开关 / 玩家行走），
  等待夜晚系数到达目标值并预热 **1.6 s**，再连续采样 **5.0 s** 的逐帧数据。
- 采样指标：`average_fps`、`minimum_fps`、`fps_1pct_low`、`avg_frame_ms`、`p99_frame_ms`、
  `avg_draw_calls`、`avg_objects`、`avg_primitives`、`static_memory_mb`、`night_factor`、烟花齐射次数、玩家末位置与朝向。
- 三个档位走同一套代码路径，只改参数；每档开始前都重新复位场景状态。
- 玩家探索场景在每档开始时显式把位置与朝向复位（`_reset_player_heading`），
  三档走出的轨迹与末朝向完全一致（末位置 (-60.5, 0.0, 51.3)、末朝向 114.0°），保证三档可比。

## 4. 三档画质参数（实测生效值）

| 参数 | LOW | MEDIUM（默认） | HIGH |
| --- | --- | --- | --- |
| `msaa` | 0 | 2 | 2 |
| `screen_space_aa` | 1 | 0 | 0 |
| `render_scale` | 0.75 | 1.0 | 1.0 |
| `shadow_enabled` | true | true | true |
| `shadow_max_distance` | 150.0 | 320.0 | 520.0 |
| `shadow_blur` | 0.3 | 1.0 | 1.6 |
| `light_angular_distance` | 0.0 | 0.0 | 1.2 |
| `glow_enabled` | false | true | true |
| `fog_enabled` | false | true | true |
| `ssao_enabled` | false | true | true |
| `window_emission_scale` | 0.6 | 1.0 | 1.15 |
| `particle_scale` | 0.25 | 1.0 | 1.0 |
| `particle_trails` | false | true | true |
| `night_light_budget` | 3 | -1 | -1 |
| `camera_far` | 700.0 | 950.0 | 1500.0 |
| `prop_visibility_end` | 70.0 | 140.0 | 0.0 |
| `particle_draw_distance` | 300.0 | 0.0 | 0.0 |

补充（自检脚本 `tools/verify_quality.gd` 实测，见 `docs/verify_quality_output.txt`）：

- 小装饰物可见性剔除清单：**201 个**网格（几何对角线 < 4.0 m，`Win_` 窗户除外）。
- 烟花粒子量：**LOW = 220 / MEDIUM = 880**（LOW 为 MEDIUM 的 25%），且 LOW 关闭粒子拖尾；
  MEDIUM 为 4 个发射位 × 220 粒子。
- 换档 30 轮压力测试：节点数、粒子系统数（4）、灯光数（7）均不发生漂移，无泄漏。

## 5. 基准结果

### 5.1 汇总表（12 组）

| 场景 | 档位 | 平均 FPS | 最低 FPS | 1% Low | 平均帧时长 (ms) | P99 帧时长 (ms) | Draw Calls | Objects | Primitives |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| DAY + Showcase | LOW | 120.0 | 81.6 | 103.7 | 8.34 | 9.64 | 483 | 1153 | 20677 |
| DAY + Showcase | MEDIUM | 119.7 | 43.2 | 81.3 | 8.36 | 12.30 | 934 | 1610 | 41463 |
| DAY + Showcase | HIGH | 120.0 | 72.8 | 90.5 | 8.33 | 11.05 | 1629 | 2301 | 60416 |
| NIGHT + Showcase | LOW | 119.9 | 61.4 | 103.0 | 8.34 | 9.71 | 483 | 1157 | 19891 |
| NIGHT + Showcase | MEDIUM | 119.7 | 56.6 | 79.0 | 8.36 | 12.66 | 929 | 1609 | 40195 |
| NIGHT + Showcase | HIGH | 118.8 | 48.6 | 78.7 | 8.41 | 12.70 | 1618 | 2294 | 59332 |
| NIGHT + Fireworks | LOW | 118.7 | 47.0 | 61.7 | 8.42 | 16.21 | 485 | 1157 | 19891 |
| NIGHT + Fireworks | MEDIUM | 119.6 | 49.1 | 78.0 | 8.36 | 12.82 | 928 | 1606 | 39760 |
| NIGHT + Fireworks | HIGH | 119.1 | 53.4 | 79.0 | 8.40 | 12.66 | 1579 | 2253 | 55334 |
| Player Exploration | LOW | 119.6 | 52.0 | 92.2 | 8.36 | 10.85 | 610 | 1288 | 36941 |
| Player Exploration | MEDIUM | 119.9 | 60.3 | 82.6 | 8.34 | 12.11 | 638 | 1322 | 38390 |
| Player Exploration | HIGH | 119.5 | 42.2 | 78.7 | 8.37 | 12.71 | 803 | 1483 | 45342 |

### 5.2 逐场景明细

**DAY + Showcase** — 白天 + 展示环绕（自动环绕，相位按场景错开）

| 档位 | 平均 FPS | 最低 FPS | 1% Low | 平均帧时长 | Draw Calls | Objects | 静态内存 (MB) | 其他 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| LOW | 120.0 | 81.6 | 103.7 | 8.34 ms | 483 | 1153 | 66.3 | 机位固定 |
| MEDIUM | 119.7 | 43.2 | 81.3 | 8.36 ms | 934 | 1610 | 66.4 | 机位固定 |
| HIGH | 120.0 | 72.8 | 90.5 | 8.33 ms | 1629 | 2301 | 67.3 | 机位固定 |

**NIGHT + Showcase** — 夜晚 + 展示环绕（窗光自发光 + 夜景灯）

| 档位 | 平均 FPS | 最低 FPS | 1% Low | 平均帧时长 | Draw Calls | Objects | 静态内存 (MB) | 其他 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| LOW | 119.9 | 61.4 | 103.0 | 8.34 ms | 483 | 1157 | 68.0 | 机位固定 |
| MEDIUM | 119.7 | 56.6 | 79.0 | 8.36 ms | 929 | 1609 | 68.2 | 机位固定 |
| HIGH | 118.8 | 48.6 | 78.7 | 8.41 ms | 1618 | 2294 | 68.2 | 机位固定 |

**NIGHT + Fireworks** — 夜晚 + 烟花（5 秒采样内实际发射齐射）

| 档位 | 平均 FPS | 最低 FPS | 1% Low | 平均帧时长 | Draw Calls | Objects | 静态内存 (MB) | 其他 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| LOW | 118.7 | 47.0 | 61.7 | 8.42 ms | 485 | 1157 | 68.2 | 采样期齐射 6 次；机位固定 |
| MEDIUM | 119.6 | 49.1 | 78.0 | 8.36 ms | 928 | 1606 | 68.3 | 采样期齐射 6 次；机位固定 |
| HIGH | 119.1 | 53.4 | 79.0 | 8.40 ms | 1579 | 2253 | 68.3 | 采样期齐射 4 次；机位固定 |

**Player Exploration** — 玩家第一人称探索（固定圆弧行走轨迹，三档完全一致）

| 档位 | 平均 FPS | 最低 FPS | 1% Low | 平均帧时长 | Draw Calls | Objects | 静态内存 (MB) | 其他 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| LOW | 119.6 | 52.0 | 92.2 | 8.36 ms | 610 | 1288 | 68.4 | 末位置 (-60.5, 0.0, 51.5) / 朝向 114.0° |
| MEDIUM | 119.9 | 60.3 | 82.6 | 8.34 ms | 638 | 1322 | 68.5 | 末位置 (-60.5, 0.0, 51.3) / 朝向 114.0° |
| HIGH | 119.5 | 42.2 | 78.7 | 8.37 ms | 803 | 1483 | 68.5 | 末位置 (-60.5, 0.0, 51.3) / 朝向 114.0° |

## 6. 可见性优化效果验证

以 `DAY + Showcase`（固定机位）为例，三档渲染负载：

| 档位 | Draw Calls | 相对 HIGH | Objects | 相对 HIGH | Primitives | 相对 HIGH |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| LOW | 483 | -70.3% | 1153 | -49.9% | 20677 | -65.8% |
| MEDIUM | 934 | -42.7% | 1610 | -30.0% | 41463 | -31.4% |
| HIGH | 1629 | +0.0% | 2301 | +0.0% | 60416 | +0.0% |

结论：`prop_visibility_end` 剔除（LOW 70 m / MEDIUM 140 m / HIGH 不剔除）叠加 `camera_far`
（700 / 950 / 1500 m）与阴影距离（150 / 320 / 520 m），把 Draw Call 压到 HIGH 的 57.3%（MEDIUM）
与 29.6%（LOW），同帧物体数压到 70.0% / 50.1%。**这是本任务里唯一被实测证明有效的性能手段。**

## 7. 瓶颈分析与建议（仅记录，未在本任务实施）

1. **Draw Call / 物体数量是主瓶颈**：城堡 GLB 含 655 个网格，HIGH 档同屏 1629 Draw Call、
   2301 个对象。画质档只能整片剔除小装饰物，粒度有限。
   建议后续：静态网格合并（MultiMesh / 合批）、为大型重复构件做实例化、必要时做人工 LOD。
2. **帧率对画质档不敏感**：12 组平均帧率差异 < 1.1%，最低 FPS 则波动明显
   （如 NIGHT + Showcase 从 LOW 61.4 到 MEDIUM 56.6、HIGH 48.6）。
   说明当前负载下 GPU 未打满，瓶颈更偏向帧节奏同步与瞬时提交，而非纯粹 GPU 像素/几何压力；
   LOW 的价值在于抬高更弱机器上的性能下限，而不是在本机换取更高平均帧率。
3. **烟花是瞬时负载**：NIGHT + Fireworks 三档平均帧率 118.7 ~ 119.6，但最低 FPS 掉到 47.0 ~ 53.4，
   1% Low 61.7 ~ 79.0，是 4 个场景里抖动最大的。建议后续给烟花增加“同时存活上限”或错峰发射。
4. **阴影距离与夜景后处理**是 HIGH 档的主要增量成本，需要真机更强的 GPU 才能体现差异。

## 8. 复跑方式与已知局限

复跑命令（真实窗口渲染，约 3 分钟）：

```bash
cd castle_godot
"/Users/yujiang/Downloads/Godot.app/Contents/MacOS/Godot" --path . --resolution 1600x900 \
  --script res://tools/benchmark.gd
```

画质档 / HUD 自检（headless，秒级）：

```bash
"/Users/yujiang/Downloads/Godot.app/Contents/MacOS/Godot" --headless --path . \
  --script res://tools/verify_quality.gd
```

已知局限，读表时请注意：

- **平均 FPS 已触顶**（约 120 FPS 帧节奏上限），本报告不把平均 FPS 作为档位优劣依据。
- **最低 FPS / 1% Low 受系统侧干扰较大**（窗口合成、后台进程、内存回收），单次 5 s 采样不足以
  做统计显著性判断，只能作为量级参考。
- headless 模式下的自检脚本里 Draw Call 读数为 0，属正常现象（无渲染后端）；
  本报告中的 Draw Call 均来自带窗口的真实渲染。
- 基准未做多次重复取平均，不构成严格对照实验；如需发布级数据，建议同一档位重复 5 次取中位数。

*（内容由AI生成，仅供参考）*
