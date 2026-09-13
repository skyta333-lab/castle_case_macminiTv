# castle_godot — 童话城堡 Godot 4.7 演示工程

按参考截图程序化重建的迪士尼风格城堡，本工程为其 Godot 4.7 运行场景（模型由 Blender 4.2 脚本生成，导出为 `assets/models/castle_ref_model.glb`）。

完整说明见同级交付文档《童话城堡项目开发文档.md》。

## 快速开始

```bash
GODOT="/Applications/Godot.app/Contents/MacOS/Godot"

# 导入 / 刷新资源
"$GODOT" --headless --path . --import

# 运行主场景
"$GODOT" --headless --path . --quit-after 300

# 工程自检（退出码 0 = 全部通过）
"$GODOT" --headless --path . --script res://tools/verify_project.gd
```

图形界面：用 Godot 4.7 导入本目录的 `project.godot`，按 F5 运行。

## 结构

| 路径 | 说明 |
|---|---|
| `project.godot` | 工程配置，主场景 `res://scenes/main.tscn` |
| `scenes/main.tscn` | 主场景：WorldEnvironment + SunLight + Ground + Castle 实例 + MainCamera |
| `scripts/castle_showcase.gd` | 相机环绕、太阳环绕、场景 AABB 自检输出 |
| `materials/env_day.tres` | 程序化天空 + 环境光 + 雾 + 泛光 |
| `materials/ground_grass.tres` | 地面草地材质 |
| `assets/models/castle_ref_model.glb` | 城堡模型（655 个网格节点，230 × 88.29 × 230） |
| `tools/verify_project.gd` | 命令行自检脚本 |

## 模型参数速查

- 整体尺寸：230.0 × 230.0 × 88.29（Y-up，底部 Y = −1.0）
- 面数 / 顶点：17,191 / 19,923
- 分层集合：`01_Terrain_Podium`、`02_Environment`、`03_Walls_Massing`、`04_Towers`、`05_Roofs_Domes`、`06_Windows`、`07_Ornaments`、`08_Flags`
- 材质：16 种（`Castle_Limestone` 为主，另有 `Castle_Gold`、`Castle_WindowGlass`、`Castle_TerracottaBrick` 等）

## 验证状态

Godot 4.7.2-stable 下：资源导入成功、主场景无头运行 300 帧零报错、自检 17 项全部通过。
