# TASK 03 — 城堡交互与 POI 热点系统（完成报告）

- 分支：`work/macmini-nontv-castle-v2`
- 提交信息：`feat(castle): add interaction and POI system`
- 自检结论：**TASK03_VERIFY_PASS**（`tools/verify_interaction.gd`，41/41 通过，0 失败）
- 平台：Godot 4.7.2.stable / macOS（headless 可复现）

---

## 1. 交互架构

数据流为单向链，交互中枢不感知任何具体热点名字，新增热点无需改控制器：

```text
PlayerController.InteractRay (RayCast3D, mask = 1|4)
        │ 每帧复制当前激活相机的 transform（第一/第三人称都跟随准星）
        ▼
InteractionController._update_target()  ──▶ GameHud.set_prompt("Press E to interact  ·  <标题>")
        │ Input: interact (E) / toggle_poi_markers (F8)
        ▼
Interactable.interact(actor)  ──▶ 具体行为：展开说明面板 / 开合正门
```

| 文件 | 职责 |
|---|---|
| `scripts/interactable.gd` | 通用可交互基类（`Area3D`，`collision_layer = 4`）：`get_interaction_text()` / `interact(actor)` / `can_interact(actor)` / `set_marker_visible()`。射线只认基类，不认具体实现 |
| `scripts/poi_interactable.gd` | POI 热点：`poi_id / poi_title / poi_description`（均 `@export`）+ 说明面板开关 + 头顶 marker（发光球 + `Label3D`） |
| `scripts/gate_poi.gd` | 正门热点：一次 E 同时开合面板与两扇门叶，面板正文附实时门态（OPEN / CLOSED） |
| `scripts/gate_controller.gd` | 门叶开合动画：运行时按门叶自身 AABB 推算铰链，Tween 驱动绕 Y 轴旋转，**不修改 / 不重导出 GLB** |
| `scripts/interaction_controller.gd` | 交互中枢：读射线、写 HUD 提示、派发 `interact()`、F8 批量显隐 marker |
| `scenes/poi_marker.tscn` | marker 预制体（自发光球 + Label3D，默认隐藏） |
| `scenes/pois.tscn` | 6 个 POI + `GateController` 的装配场景 |
| `scenes/main.tscn` | 仅新增两个节点实例：`PoiSet`、`InteractionController`（原有节点未改动） |
| `tools/verify_interaction.gd` | headless 自检脚本（见第 4 节） |

输入映射（TASK01 已定义，本任务直接复用）：`interact = E`、`toggle_poi_markers = F8`。

---

## 2. 六个 POI 位置（世界坐标）

爆炸盒/球体积均位于前庭与台基可达范围内（前庭地面 y = 4.0，玩家眼高 +2.6）。

| # | 节点 | 主题 | 形状 / 体积 | 世界位置 | marker 高度 |
|---|---|---|---|---|---|
| 1 | `POI_Gate` | Castle Main Gate | Box 17.6 × 11.2 × 2.0 | (0, 9.6, 26.2) | +5.0 |
| 2 | `POI_CentralTower` | Central Tower | Sphere r = 3.5 | (0, 13.0, 30.5) | +4.0 |
| 3 | `POI_WestTower` | West Tower | Sphere r = 3.5 | (−10, 13.0, 27.0) | +4.5 |
| 4 | `POI_EastTower` | East Tower | Sphere r = 3.5 | (10, 13.0, 27.0) | +4.5 |
| 5 | `POI_GateBanners` | Gate Banners | Sphere r = 3.0 | (−15, 11.0, 29.0) | +6.0 |
| 6 | `POI_PodiumTerrace` | Rock Podium & Garden Terrace | Sphere r = 2.8 | (−25, 5.5, 34.0) | +3.5 |

- 正门体积做成"贴门盒"：站在前庭任意位置平视门扇都能命中，且不遮挡上方主塔热点（主塔热点位于门前上方空域，F8 打开 marker 后可直接对准）。
- 6 条说明文案互不相同，每条 40 字以上，含建筑结构与出处说明。
- `collision_layer = 4`、`collision_mask = 0`：热点体积不参与物理，**不阻挡玩家移动**（自检已验证前进 16.65 m 无阻）。

---

## 3. 门模型是否可独立控制 —— 可以，且未破坏 GLB

勘察结论（直接读取 GLB 节点树与包围盒得到）：

```text
Castle/Gate_Door_W   x −8.8 … −2.8,  y 4 … 15,  z 24.2 … 25.0   （左门叶）
Castle/Gate_Door_E   x  2.8 …  8.8,  y 4 … 15,  z 24.2 … 25.0   （右门叶）
```

两扇门叶是**互相独立的 `MeshInstance3D`**，各自以外缘（x = ∓8.8）为铰链，可绕竖直轴向外旋开。因此：

- 门开 / 关由 `gate_controller.gd` 在**运行时改写节点 transform**实现（`rotate_about_hinge()`，95°，1.6 s，`TRANS_CUBIC/EASE_OUT`）；
- 铰链位置由门叶自身 AABB 在父空间自动推算，模型微调后无需改代码；
- GLB 文件字节未变（`git status` 中 `castle_ref_model.glb` 无改动），未重导出、未改节点结构；
- 门叶本身没有碰撞体，开关门不会把玩家卡住。

> 后续若不满足于"运行时旋转"，希望门叶带门框动画 / 门轴音效，则见下节 Blender 需求。

---

## 4. 自检（`tools/verify_interaction.gd`）

```bash
cd ~/Projects/castle_case_macminiTv/castle_godot
/Users/yujiang/Downloads/Godot.app/Contents/MacOS/Godot --headless --path . \
    --script res://tools/verify_interaction.gd
```

退出码 0 = 通过，输出末行打印 `TASK03_VERIFY_PASS`。本次实测 **41 项全通过**：

| 分组 | 覆盖内容 |
|---|---|
| A 装配 | 场景节点、第一人称激活、23 个程序化碰撞体、射线启用与掩码、E/F8 输入映射、POI ≥ 5（实际 6）、标题/说明唯一性、marker 默认隐藏 |
| B 移动 | 落地稳定站立于前庭（`is_on_floor = true`）、WASD 前进不受热点体积影响 |
| C 射线命中 | 6 个 POI **逐个用例**：站位 + 准星瞄向 → 期望命中（6/6 命中正确） |
| D 提示与面板 | HUD 提示文本含 E 与标题、E 展开面板、标题/正文正确、再按 E 关闭、指向天空时无目标且提示隐藏 |
| E 正门 | `Gate_Door_W/E` 可独立控制、开启动画到位（progress 1.000000）、实测旋转 95.0°、关闭动画到位（0.000000）、关门后 transform 回到初值（Δorigin ≈ 4.8e−7） |
| F F8 | marker 批量打开 / 关闭全部生效 |

运行日志无持续刷屏错误（仅 `[castle_collision] / [environment] / [castle_godot]` 各一条启动信息）。

---

## 5. 后续 Blender 需求（可选增强，非本任务阻塞项）

1. 门叶可加"门框 + 门轴 + 门闩"细节，并给门叶一个独立的旋转轴空物体（`Empty`），运行时可直接读该空物体的 transform，铰链推算代码即可删除。
2. 门洞（Gate_Opening）目前是实体墙的一部分，若后续要做"进入城堡内部"，需要在 Blender 里挖出门洞并补内墙。
3. 若要做门的开合**动画剪辑**（而非程序化旋转），建议在 GLB 内做 `Gate_Open` / `Gate_Close` 两条 Animation，运行时用 `AnimationPlayer` 播放；本任务保留程序化方案以避免重导出模型。

---

## 6. 验收对照

| 验收项 | 结果 |
|---|---|
| 玩家能靠近热点 | ✅ 热点位于前庭 / 台基可达范围 |
| 准星 / 射线可以检测 | ✅ `RayCast3D`，mask = 1\|4，长度 9 m |
| 显示 E 提示 | ✅ `Press E to interact  ·  <标题>` |
| 至少 5 个 POI | ✅ 6 个 |
| 至少 5 条不同说明 | ✅ 6 条 |
| UI 可关闭 | ✅ E 开 / E 关 |
| 没有持续刷屏错误日志 | ✅ |
| 不影响玩家移动 | ✅ 热点 `collision_layer = 4`，自检实测 |
| 正门交互 | ✅ 门叶可独立控制 → 实现开合动画，GLB 未改动 |
| F8 调试 marker | ✅ 默认隐藏，F8 切换 |
