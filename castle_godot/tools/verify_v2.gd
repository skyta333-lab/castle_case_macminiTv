extends SceneTree
## tools/verify_v2.gd
## TASK06 V2 交付总自检（headless，无需显示服务器）。
##
## 覆盖 TASK06 验收清单里所有可在无显示器环境验证的项：
##   [A] 主场景与必需节点（任务书列出的 8 项 + 其余子系统）
##   [B] 模型与场景规模（城堡 GLB 网格数 / 世界 AABB / 可见性剔除清单）
##   [C] 玩家移动与碰撞（落地、WASD 前进、跳跃、传送、程序化碰撞体）
##   [D] 镜头切换（1 / 2 / 3 三种模式，玩家激活跟随）
##   [E] 昼夜环境（F1 / F2 / F3 预设、夜间因子排序、F4 自动昼夜推进）
##   [F] 交互热点（POI 数量与文案、准星命中、E 说明面板、F8 标记、正门开合）
##   [G] 烟花与演示模式（F5 开关与真实发射、F6 一键夜景并完整还原）
##   [H] 性能 HUD 与三档画质（F7、7 / 8 / 9、切回无残留）
##   [I] V2 交付物（README / CHANGELOG / 截图 / 性能报告 / 基准 JSON / 各任务 DONE）
##
## 用法：
##   Godot --headless --path . --script res://tools/verify_v2.gd
## 退出码 0 = 全部通过；1 = 存在失败项。

const MAIN_SCENE := "res://scenes/main.tscn"
const EYE_HEIGHT := 2.6
const REQUIRED_NODES: Array[String] = [
	"Castle",
	"Player",
	"MainCamera",
	"EnvironmentManager",
	"InteractionController",
	"Fireworks",
	"PerformanceHud",
	"HUD",
	"PoiSet",
	"QualityManager",
	"NightLights",
	"PresentationController",
	"WorldCollision",
	"CameraModeManager",
]

## 交互命中用例（与 verify_interaction.gd 同源，站位取自前庭平台）
var _cases: Array = [
	{"label": "正门", "stand": Vector3(0.0, 4.4, 34.0), "aim": Vector3(0.0, 7.0, 26.2), "expect": "POI_Gate"},
	{"label": "中央主塔", "stand": Vector3(0.0, 4.4, 34.0), "aim": Vector3(0.0, 13.0, 30.5), "expect": "POI_CentralTower"},
	{"label": "西塔", "stand": Vector3(-10.0, 4.4, 36.0), "aim": Vector3(-10.0, 13.0, 27.0), "expect": "POI_WestTower"},
	{"label": "东塔", "stand": Vector3(10.0, 4.4, 36.0), "aim": Vector3(10.0, 13.0, 27.0), "expect": "POI_EastTower"},
]

var _pass := 0
var _fail := 0

var _scene: Node = null
var _castle: Node = null
var _player: PlayerController = null
var _camera_mgr: Node = null
var _env_mgr: Node = null
var _ic: Node = null
var _fireworks: Node = null
var _night_lights: Node = null
var _presentation: Node = null
var _quality: Node = null
var _perf_hud: Node = null
var _hud: Node = null
var _poi_set: Node = null
var _gate: Node = null
var _showcase_camera: Camera3D = null
var _viewport: Viewport = null


func _initialize() -> void:
	_run.call_deferred()


# ---------------------------------------------------------------------------
# 断言 / 工具
# ---------------------------------------------------------------------------

func _check(label: String, ok: bool, detail: String = "") -> void:
	var suffix := ("  -> " + detail) if detail != "" else ""
	if ok:
		_pass += 1
		print("  [PASS] %s%s" % [label, suffix])
	else:
		_fail += 1
		print("  [FAIL] %s%s" % [label, suffix])


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _physics(n: int) -> void:
	for i in n:
		await physics_frame


func _wait_for(predicate: Callable, timeout_ms: int) -> bool:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < timeout_ms:
		if predicate.call():
			return true
		await process_frame
	return predicate.call()


func _press(key: Key) -> void:
	var down := InputEventKey.new()
	down.physical_keycode = key
	down.keycode = key
	down.pressed = true
	Input.parse_input_event(down)
	var up := InputEventKey.new()
	up.physical_keycode = key
	up.keycode = key
	up.pressed = false
	Input.parse_input_event(up)


func _action_has_key(action: String, key: Key) -> bool:
	if not InputMap.has_action(action):
		return false
	for ev in InputMap.action_get_events(action):
		var k := ev as InputEventKey
		if k != null and (k.physical_keycode == key or k.keycode == key):
			return true
	return false


func _all_mesh_instances(root_node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if root_node is MeshInstance3D and (root_node as MeshInstance3D).mesh != null:
		out.append(root_node as MeshInstance3D)
	for c in root_node.get_children():
		out.append_array(_all_mesh_instances(c))
	return out


func _count_lights(root_node: Node) -> int:
	var n := 1 if root_node is Light3D else 0
	for c in root_node.get_children():
		n += _count_lights(c)
	return n


func _file_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_as_text() if f != null else ""


func _file_size(path: String) -> int:
	if not FileAccess.file_exists(path):
		return -1
	var f := FileAccess.open(path, FileAccess.READ)
	return int(f.get_length()) if f != null else -1


func _aim_and_wait(aim: Vector3, frames: int) -> void:
	var head := _player.get_node_or_null("Head") as Node3D
	for i in 3:
		var cam := _player.get_active_camera()
		var eye: Vector3 = cam.global_position if cam != null else _player.global_position + Vector3(0.0, EYE_HEIGHT, 0.0)
		var d := aim - eye
		_player.rotation.y = atan2(-d.x, -d.z)
		if head != null:
			head.rotation.x = atan2(d.y, sqrt(d.x * d.x + d.z * d.z))
		await process_frame
	for i in frames:
		await process_frame


# ---------------------------------------------------------------------------
# 主流程
# ---------------------------------------------------------------------------

func _run() -> void:
	print("=== TASK06 V2 交付总自检（headless） ===")

	# -------------------------------------------------- A. 主场景与必需节点
	print("\n[A] 主场景与必需节点")
	var packed := load(MAIN_SCENE) as PackedScene
	_check("主场景文件存在且可加载", packed != null, MAIN_SCENE)
	if packed == null:
		_finish()
		return
	_scene = packed.instantiate()
	root.add_child(_scene)
	await _frames(5)
	await create_timer(0.6).timeout
	_check("主场景可实例化并进入场景树", _scene.is_inside_tree())

	_castle = _scene.get_node_or_null("Castle")
	_player = _scene.get_node_or_null("Player") as PlayerController
	_camera_mgr = _scene.get_node_or_null("CameraModeManager")
	_env_mgr = _scene.get_node_or_null("EnvironmentManager")
	_ic = _scene.get_node_or_null("InteractionController")
	_fireworks = _scene.get_node_or_null("Fireworks")
	_night_lights = _scene.get_node_or_null("NightLights")
	_presentation = _scene.get_node_or_null("PresentationController")
	_quality = _scene.get_node_or_null("QualityManager")
	_perf_hud = _scene.get_node_or_null("PerformanceHud")
	_hud = _scene.get_node_or_null("HUD")
	_poi_set = _scene.get_node_or_null("PoiSet")
	_gate = _poi_set.get_node_or_null("GateController") if _poi_set != null else null
	_showcase_camera = _scene.get_node_or_null("MainCamera") as Camera3D
	_viewport = root

	for node_name in REQUIRED_NODES:
		_check("必需节点存在：%s" % node_name, _scene.get_node_or_null(node_name) != null)
	_check("Engine 版本 = 4.x", Engine.get_version_info()["major"] == 4, String(Engine.get_version_info()["string"]))
	_check("项目主场景设置指向 main.tscn", String(ProjectSettings.get_setting("application/run/main_scene")) == MAIN_SCENE, String(ProjectSettings.get_setting("application/run/main_scene")))

	# -------------------------------------------------- B. 模型与场景规模
	print("\n[B] 模型与场景规模")
	var meshes := _all_mesh_instances(_castle)
	_check("城堡 GLB 已加载且网格数 > 0", meshes.size() > 0, "%d 个网格" % meshes.size())
	var merged := AABB()
	var seeded := false
	for mi in meshes:
		var box: AABB = mi.global_transform * mi.get_aabb()
		if not seeded:
			merged = box
			seeded = true
		else:
			merged = merged.merge(box)
	_check(
		"城堡整体包围盒尺寸合理（X / Z 均 > 200m）",
		seeded and merged.size.x > 200.0 and merged.size.z > 200.0 and merged.size.y > 80.0,
		"size=(%.1f, %.2f, %.1f)" % [merged.size.x, merged.size.y, merged.size.z]
	)
	_check("地面 Ground 存在（兜底承载面）", _scene.get_node_or_null("Ground") != null)
	_check("程序化碰撞体已生成（> 0 个静态体）", _scene.get_node_or_null("WorldCollision").get_child_count() > 0, "%d 个碰撞节点" % _scene.get_node_or_null("WorldCollision").get_child_count())
	_check("小装饰物可见性剔除清单非空", int(_quality.call("get_prop_count")) > 0, "%d 个" % int(_quality.call("get_prop_count")))

	# -------------------------------------------------- C. 玩家移动与碰撞
	print("\n[C] 玩家移动与碰撞")
	_check("玩家控制器方法完整", _player != null and _player.has_method("teleport_to") and _player.has_method("set_camera_mode") and _player.has_method("get_interact_ray") and _player.has_method("apply_look"))
	_check("输入映射 WASD 齐全", _action_has_key("move_forward", KEY_W) and _action_has_key("move_backward", KEY_S) and _action_has_key("move_left", KEY_A) and _action_has_key("move_right", KEY_D))
	_check("输入映射 sprint = Shift / jump = Space", _action_has_key("sprint", KEY_SHIFT) and _action_has_key("jump", KEY_SPACE))

	_player.rotation.y = 0.0
	var head_node := _player.get_node_or_null("Head") as Node3D
	_check("出生点 PlayerSpawn 已配置", _scene.get_node_or_null("PlayerSpawn") != null)
	_camera_mgr.call("set_mode", 2)
	await _frames(3)
	_check("切到第一人称后玩家恢复物理处理", _player.is_physics_processing())
	_player.rotation.y = 0.0
	if head_node != null:
		head_node.rotation.x = 0.0
	_player.teleport_to(Vector3(0.0, 5.0, 40.0))
	await _physics(90)
	var ground_y := _player.global_position.y
	_check(
		"玩家落到前庭平台且静止",
		_player.is_on_floor() and absf(_player.velocity.y) < 0.1 and ground_y > 3.5 and ground_y < 5.0,
		"y=%.2f on_floor=%s" % [ground_y, str(_player.is_on_floor())]
	)
	await _frames(3)

	var start_pos := _player.global_position
	Input.action_press("move_forward")
	await _physics(60)
	Input.action_release("move_forward")
	await _physics(5)
	var walk_dist := start_pos.distance_to(_player.global_position)
	_check("W 前进有效（热点体积不阻挡移动）", walk_dist > 1.0, "前进 %.2f m" % walk_dist)

	_player.teleport_to(Vector3(0.0, 4.5, 40.0))
	await _physics(40)
	var jump_base := _player.global_position.y
	Input.action_press("jump")
	await _physics(3)
	Input.action_release("jump")
	var peak := jump_base
	for i in 25:
		await physics_frame
		peak = maxf(peak, _player.global_position.y)
	_check("跳跃生效（离地高度 > 0.15m）", peak - jump_base > 0.15, "峰值 +%.3f m" % (peak - jump_base))
	await _physics(45)

	_player.teleport_to(Vector3(-25.0, 6.0, 41.5))
	await _frames(2)
	_check("teleport_to 定位准确", _player.global_position.distance_to(Vector3(-25.0, 6.0, 41.5)) < 0.05, "%.3f m 偏差" % _player.global_position.distance_to(Vector3(-25.0, 6.0, 41.5)))

	# -------------------------------------------------- D. 镜头切换
	print("\n[D] 镜头切换")
	_check("输入映射 mode_showcase = 1", _action_has_key("mode_showcase", KEY_1))
	_check("输入映射 mode_first_person = 2", _action_has_key("mode_first_person", KEY_2))
	_check("输入映射 mode_third_person = 3", _action_has_key("mode_third_person", KEY_3))
	_check("输入映射 toggle_mouse = Escape（释放/捕获鼠标）", _action_has_key("toggle_mouse", KEY_ESCAPE))

	_press(KEY_2)
	await _frames(3)
	_check("按 2 → 第一人称模式", int(_camera_mgr.get("current_mode")) == 2, "mode=%d" % int(_camera_mgr.get("current_mode")))
	_check("第一人称下玩家被激活", _player.active)
	var fp_cam := _player.get_active_camera()
	_check("第一人称使用玩家相机（非展示相机）", fp_cam != null and fp_cam != _showcase_camera, String(fp_cam.name) if fp_cam != null else "<空>")

	_press(KEY_3)
	await _frames(3)
	_check("按 3 → 第三人称模式", int(_camera_mgr.get("current_mode")) == 3, "mode=%d" % int(_camera_mgr.get("current_mode")))
	var tp_cam := _player.get_active_camera()
	_check("第三人称相机与第一人称不同（弹簧臂相机）", tp_cam != null and tp_cam != fp_cam, String(tp_cam.name) if tp_cam != null else "<空>")

	_press(KEY_1)
	await _frames(3)
	_check("按 1 → 展示环绕模式", int(_camera_mgr.get("current_mode")) == 1, "mode=%d" % int(_camera_mgr.get("current_mode")))
	_check("展示模式相机成为 current", _showcase_camera != null and _showcase_camera.current)
	_check("展示模式玩家不再跟随（释放控制）", not _player.active)
	_check("展示模式恢复自动环绕（orbit speed = 6°/s）", is_equal_approx(float(_scene.get("camera_orbit_speed")), 6.0), "%.1f°/s" % float(_scene.get("camera_orbit_speed")))

	# -------------------------------------------------- E. 昼夜环境
	print("\n[E] 昼夜环境")
	_check("输入映射 env_day = F1", _action_has_key("env_day", KEY_F1))
	_check("输入映射 env_sunset = F2", _action_has_key("env_sunset", KEY_F2))
	_check("输入映射 env_night = F3", _action_has_key("env_night", KEY_F3))
	_check("输入映射 env_auto_cycle = F4", _action_has_key("env_auto_cycle", KEY_F4))
	var preset_files_ok := true
	for preset_file in ["res://materials/env_day.tres", "res://materials/env_sunset.tres", "res://materials/env_night.tres"]:
		if _file_size(preset_file) <= 0:
			preset_files_ok = false
	_check("三套环境预设资源文件均已导出", preset_files_ok)

	_press(KEY_F1)
	await create_timer(0.8).timeout
	var day_factor := float(_env_mgr.call("get_night_factor"))
	var day_sun: DirectionalLight3D = _env_mgr.call("get_sun")
	var day_env: Environment = _env_mgr.call("get_environment")
	var day_energy := day_sun.light_energy if day_sun != null else 0.0
	_check("F1 → DAY 预设", String(_env_mgr.call("get_preset_name")) == "DAY", String(_env_mgr.call("get_preset_name")))
	_check("DAY 夜间因子 ≈ 0", day_factor < 0.05, "night_factor=%.3f" % day_factor)
	_check("DAY 天空为 ProceduralSky 且带雾", day_env != null and day_env.sky != null and day_env.fog_enabled)
	var day_fog_density := day_env.fog_density if day_env != null else -1.0
	_check("DAY 太阳明亮（energy > 0.8）", day_energy > 0.8, "energy=%.2f" % day_energy)

	_press(KEY_F3)
	await create_timer(1.2).timeout
	var night_factor := float(_env_mgr.call("get_night_factor"))
	var night_sun: DirectionalLight3D = _env_mgr.call("get_sun")
	var night_energy := night_sun.light_energy if night_sun != null else 0.0
	_check("F3 → NIGHT 预设", String(_env_mgr.call("get_preset_name")) == "NIGHT", String(_env_mgr.call("get_preset_name")))
	_check("NIGHT 夜间因子 ≈ 1", night_factor > 0.9, "night_factor=%.3f" % night_factor)
	_check("夜间太阳（月光）显著变暗", night_energy < day_energy * 0.4, "day=%.2f -> night=%.2f" % [day_energy, night_energy])
	_check("夜间天空整体压暗", night_sun != null and night_sun.light_color.b > night_sun.light_color.g, "color=%s" % str(night_sun.light_color) if night_sun != null else "无太阳节点")

	_press(KEY_F2)
	await create_timer(1.2).timeout
	var sunset_sun: DirectionalLight3D = _env_mgr.call("get_sun")
	var sunset_env: Environment = _env_mgr.call("get_environment")
	_check("F2 → SUNSET 预设", String(_env_mgr.call("get_preset_name")) == "SUNSET", String(_env_mgr.call("get_preset_name")))
	_check("SUNSET 太阳偏暖（R > B，金色黄昏）", sunset_sun != null and sunset_sun.light_color.r > sunset_sun.light_color.b, "color=%s" % str(sunset_sun.light_color) if sunset_sun != null else "无太阳节点")
	_check("SUNSET 雾更浓（密度 > 白天）", sunset_env != null and sunset_env.fog_density > day_fog_density, "%.4f vs %.4f" % [sunset_env.fog_density if sunset_env != null else -1.0, day_fog_density])
	_check("黄昏档窗光未点亮（night_factor = 0）", float(_env_mgr.call("get_night_factor")) < 0.05)

	_press(KEY_F4)
	await _frames(3)
	_check("F4 → 自动昼夜开启", bool(_env_mgr.call("is_auto_cycle")))
	var t0 := float(_env_mgr.call("get_time_of_day"))
	await create_timer(1.5).timeout
	var t1 := float(_env_mgr.call("get_time_of_day"))
	_check("自动昼夜时间推进", t1 > t0, "%.2fh -> %.2fh" % [t0, t1])
	_press(KEY_F4)
	await _frames(3)
	_check("再按 F4 → 自动昼夜关闭", not bool(_env_mgr.call("is_auto_cycle")))
	_check("夜景靠窗户自发光实现，城堡内无新增实时灯（≤ 2 盏）", _count_lights(_castle) <= 2, "%d 盏" % _count_lights(_castle))
	_check("夜景灯光组已装配", _night_lights != null and _night_lights.get_child_count() > 0, "%d 个子节点" % (_night_lights.get_child_count() if _night_lights != null else 0))
	_env_mgr.call("set_preset", 0)
	await create_timer(0.5).timeout

	# -------------------------------------------------- F. 交互热点
	print("\n[F] 交互热点")
	_check("输入映射 interact = E", _action_has_key("interact", KEY_E))
	_check("输入映射 toggle_poi_markers = F8", _action_has_key("toggle_poi_markers", KEY_F8))
	_camera_mgr.call("set_mode", 2)
	await _frames(3)
	var ray := _player.get_interact_ray()
	_check("InteractRay 已启用且掩码含交互层", ray != null and ray.enabled and (ray.collision_mask & 4) != 0, "mask=%d" % (ray.collision_mask if ray != null else 0))

	var pois: Array = _ic.call("get_poi_nodes")
	_check("交互热点数量 ≥ 5", pois.size() >= 5, "%d 个" % pois.size())
	var titles := {}
	var all_text := true
	for n in pois:
		var poi := n as PoiInteractable
		if poi == null or poi.poi_title.strip_edges() == "" or poi.get_poi_description().strip_edges() == "":
			all_text = false
			continue
		titles[poi.poi_title] = true
	_check("每个热点都有标题与说明", all_text)
	_check("热点标题互不相同", titles.size() == pois.size(), "%d 个不同标题" % titles.size())

	_player.set_physics_process(false)
	var hits := 0
	for c in _cases:
		_player.teleport_to(c["stand"])
		await _aim_and_wait(c["aim"], 3)
		var target: Node = _ic.call("get_target")
		var got: String = String(target.name) if target != null else "<空>"
		var ok: bool = got == c["expect"]
		if ok:
			hits += 1
		_check("准星命中「%s」" % c["label"], ok, "实际命中 %s" % got)
	_check("四个主要热点全部可被准星命中", hits == _cases.size(), "%d/%d" % [hits, _cases.size()])

	_player.teleport_to(_cases[1]["stand"])
	await _aim_and_wait(_cases[1]["aim"], 3)
	var locked := _ic.call("get_target") as PoiInteractable
	_check("射线锁定 PoiInteractable", locked != null)
	if locked != null:
		_check("HUD 提示含 E 与热点标题", _hud.prompt_label.visible and _hud.prompt_label.text.contains("E") and _hud.prompt_label.text.contains(locked.poi_title), "\"%s\"" % _hud.prompt_label.text)
		_ic.call("handle_interact")
		await _frames(2)
		_check("E 展开说明面板", locked.is_panel_open() and _hud.is_poi_visible())
		_check("面板正文含说明与关闭提示", _hud.poi_desc_label.text.contains("[E] Close") and _hud.poi_desc_label.text.length() > 30)
		_ic.call("handle_interact")
		await _frames(2)
		_check("再按 E 关闭面板", not locked.is_panel_open() and not _hud.is_poi_visible())

	_ic.call("set_markers_visible", true)
	await _frames(2)
	var markers_on := bool(_ic.call("are_markers_visible"))
	for n in pois:
		var p := n as PoiInteractable
		if p != null and not p.is_marker_visible():
			markers_on = false
	_check("F8 打开：全部热点标记可见", markers_on)
	_ic.call("set_markers_visible", false)
	await _frames(2)
	_check("F8 关闭：全部热点标记隐藏", not bool(_ic.call("are_markers_visible")))

	_check("GateController 存在（正门可交互）", _gate != null)
	if _gate != null:
		_check("GLB 中门叶可独立控制", bool(_gate.call("is_available")), "Gate_Door_W / Gate_Door_E")
		var door := _castle.get_node_or_null("Gate_Door_W") as Node3D
		var rest := door.transform if door != null else Transform3D()
		_gate.call("set_open", true)
		var opened := await _wait_for(func(): return float(_gate.call("get_progress")) >= 0.9999999, 8000)
		_check("门叶开启动画完成", opened, "progress=%.6f" % float(_gate.call("get_progress")))
		if door != null:
			var angle := rad_to_deg(rest.basis.get_rotation_quaternion().angle_to(door.transform.basis.get_rotation_quaternion()))
			_check("门叶绕铰链旋转约 95°", absf(angle - float(_gate.get("open_angle_degrees"))) < 5.0, "实测 %.1f°" % angle)
		_gate.call("set_open", false)
		var closed := await _wait_for(func(): return float(_gate.call("get_progress")) <= 0.0000001, 8000)
		_check("门叶关闭并回到初始 transform", closed, "progress=%.6f" % float(_gate.call("get_progress")))
	_player.set_physics_process(true)

	# -------------------------------------------------- G. 烟花与演示模式
	print("\n[G] 烟花与演示模式")
	_check("输入映射 fireworks_toggle = F5", _action_has_key("fireworks_toggle", KEY_F5))
	_check("输入映射 presentation_mode = F6", _action_has_key("presentation_mode", KEY_F6))
	_check("烟花发射位 = 4", int(_fireworks.call("get_pad_count")) == 4, str(int(_fireworks.call("get_pad_count"))))
	_check("烟花粒子系统已构建", int(_fireworks.call("get_system_count")) > 0, "%d 个系统" % int(_fireworks.call("get_system_count")))

	_press(KEY_F5)
	await _frames(3)
	_check("F5 → 烟花开启", bool(_fireworks.call("is_enabled")))
	var fired_before := int(_fireworks.call("get_fired_total"))
	_fireworks.call("fire_volley")
	await _frames(3)
	_check("fire_volley 生成待发射队列", int(_fireworks.call("get_pending_count")) > 0, "pending=%d" % int(_fireworks.call("get_pending_count")))
	var fired_now := await _wait_for(func(): return int(_fireworks.call("get_fired_total")) > fired_before, 6000)
	_check("烟花真实发射（fired_total 增长）", fired_now, "%d -> %d" % [fired_before, int(_fireworks.call("get_fired_total"))])
	_check("烟花对应粒子上限与画质档一致（4 × 220 = 880）", int(_fireworks.call("get_total_particle_budget")) == 880, str(int(_fireworks.call("get_total_particle_budget"))))
	_press(KEY_F5)
	await _frames(3)
	_check("再按 F5 → 烟花关闭", not bool(_fireworks.call("is_enabled")))

	_env_mgr.call("set_preset_by_name", "DAY")
	await create_timer(0.6).timeout
	_press(KEY_F6)
	await _frames(3)
	_check("F6 → 进入演示模式", bool(_presentation.call("is_active")))
	await create_timer(1.2).timeout
	_check("演示模式自动切到 NIGHT", String(_env_mgr.call("get_preset_name")) == "NIGHT", String(_env_mgr.call("get_preset_name")))
	_check("演示模式自动打开烟花", bool(_fireworks.call("is_enabled")))
	_check("演示模式切到展示相机", int(_camera_mgr.get("current_mode")) == 1, "mode=%d" % int(_camera_mgr.get("current_mode")))
	_check("演示模式环绕速度 = 3°/s（缓慢）", is_equal_approx(float(_presentation.call("get_orbit_speed")), 3.0), "%.1f°/s" % float(_presentation.call("get_orbit_speed")))
	_check("环绕速度已真正下发到展示场景（3°/s）", is_equal_approx(float(_scene.get("camera_orbit_speed")), 3.0), "%.1f°/s" % float(_scene.get("camera_orbit_speed")))

	_press(KEY_F6)
	await create_timer(1.2).timeout
	_check("再按 F6 → 退出演示模式", not bool(_presentation.call("is_active")))
	_check("退出后还原进入前的环境预设（DAY）", String(_env_mgr.call("get_preset_name")) == "DAY", String(_env_mgr.call("get_preset_name")))
	_check("退出后烟花关闭", not bool(_fireworks.call("is_enabled")))
	_check("退出后自动昼夜状态还原（关闭）", not bool(_env_mgr.call("is_auto_cycle")))
	var restored_mode := int(_camera_mgr.get("current_mode"))
	_check(
		"退出后环绕速度与恢复的镜头模式一致（展示=6°/s，玩家=0°/s）",
		is_equal_approx(float(_scene.get("camera_orbit_speed")), 6.0 if restored_mode == 1 else 0.0),
		"mode=%d speed=%.1f°/s" % [restored_mode, float(_scene.get("camera_orbit_speed"))]
	)

	# -------------------------------------------------- H. 性能 HUD 与三档
	print("\n[H] 性能 HUD 与三档画质")
	_check("输入映射 toggle_perf_hud = F7", _action_has_key("toggle_perf_hud", KEY_F7))
	_check("输入映射 quality_low / medium / high = 7 / 8 / 9", _action_has_key("quality_low", KEY_7) and _action_has_key("quality_medium", KEY_8) and _action_has_key("quality_high", KEY_9))
	_check("默认画质档 = MEDIUM（Mac mini 默认）", String(_quality.call("get_level_name")) == "MEDIUM", String(_quality.call("get_level_name")))
	_check("性能 HUD 默认关闭", not bool(_perf_hud.call("is_shown")))

	_press(KEY_F7)
	await create_timer(0.6).timeout
	var perf_text := String(_perf_hud.call("get_last_text"))
	_check("F7 → 性能 HUD 打开", bool(_perf_hud.call("is_shown")))
	_check("读数含 FPS / 帧时间", perf_text.contains("FPS") and perf_text.contains("Frame"), perf_text.replace("\n", " | "))
	_check("读数含 Draw Calls / Objects / Nodes", perf_text.contains("Draw Calls") and perf_text.contains("Objects") and perf_text.contains("Nodes"))
	_check("读数含画质档 / 分辨率 / 玩家坐标", perf_text.contains("Quality: MEDIUM") and perf_text.contains("scale") and perf_text.contains("Player: ("))
	_check("HUD Label 与性能 HUD 同步", (_hud.get_node("PerfLabel") as Label).visible and (_hud.get_node("PerfLabel") as Label).text == perf_text)
	var metrics: Dictionary = _perf_hud.call("get_metrics")
	_check("指标采集有效（对象数 / 节点数 > 0）", int(metrics["objects"]) > 0 and int(metrics["nodes"]) > 0, "objects=%d nodes=%d" % [int(metrics["objects"]), int(metrics["nodes"])])

	var medium_settings: Dictionary = _quality.call("get_effective_settings")
	_press(KEY_7)
	await create_timer(0.4).timeout
	var low_settings: Dictionary = _quality.call("get_effective_settings")
	_check("按 7 → LOW", String(_quality.call("get_level_name")) == "LOW", String(_quality.call("get_level_name")))
	_check("LOW：渲染比例 0.75 且关闭 Glow / SSAO", is_equal_approx(float(low_settings["render_scale"]), 0.75) and not bool(low_settings["glow_enabled"]) and not bool(low_settings["ssao_enabled"]))
	_check("LOW：摄像机 far 700（省算力）", is_equal_approx(float(low_settings["camera_far"]), 700.0), str(low_settings["camera_far"]))
	_check("LOW：小装饰物可见距离 70m（可见性剔除生效）", is_equal_approx(float(low_settings["prop_visibility_end"]), 70.0), str(low_settings["prop_visibility_end"]))
	_check("LOW：烟花粒子量下降（≤ MEDIUM 的 30%）", float(_fireworks.call("get_total_particle_budget")) <= 880.0 * 0.3, "LOW=%d" % int(_fireworks.call("get_total_particle_budget")))

	_press(KEY_9)
	await create_timer(0.4).timeout
	var high_settings: Dictionary = _quality.call("get_effective_settings")
	_check("按 9 → HIGH", String(_quality.call("get_level_name")) == "HIGH", String(_quality.call("get_level_name")))
	_check("HIGH：摄像机 far 1500 且不做可见性剔除", is_equal_approx(float(high_settings["camera_far"]), 1500.0) and is_equal_approx(float(high_settings["prop_visibility_end"]), 0.0))
	_check("HIGH：阴影距离 520 > MEDIUM 的 320", float(high_settings["shadow_max_distance"]) > float(medium_settings["shadow_max_distance"]), "%.0f vs %.0f" % [float(high_settings["shadow_max_distance"]), float(medium_settings["shadow_max_distance"])])

	_press(KEY_8)
	await create_timer(0.4).timeout
	_check("按 8 → MEDIUM", String(_quality.call("get_level_name")) == "MEDIUM", String(_quality.call("get_level_name")))
	var back_settings: Dictionary = _quality.call("get_effective_settings")
	_check("切回 MEDIUM 与初始 MEDIUM 完全一致（无残留）", str(back_settings) == str(medium_settings))
	_check("切档后性能 HUD 画质行实时刷新", String(_perf_hud.call("get_last_text")).contains("Quality: MEDIUM"), String(_perf_hud.call("get_last_text")).replace("\n", " | "))
	_press(KEY_F7)
	await _frames(3)
	_check("再按 F7 → 性能 HUD 关闭", not bool(_perf_hud.call("is_shown")))

	# -------------------------------------------------- I. V2 交付物
	print("\n[I] V2 交付物")
	var readme := _file_text("res://README.md")
	_check("README.md 存在且非空", readme.length() > 800, "%d 字符" % readme.length())
	for section in ["## 项目简介", "### 启动方式", "### 操作键", "### 模式切换", "### 昼夜", "### 交互", "### 烟花", "### 性能档", "### 目录结构", "### 已知限制"]:
		_check("README 含小节「%s」" % section, readme.contains(section))
	var changelog := _file_text("res://docs/CHANGELOG_V2.md")
	_check("docs/CHANGELOG_V2.md 存在且非空", changelog.length() > 600, "%d 字符" % changelog.length())
	for task_no in ["TASK 01", "TASK 02", "TASK 03", "TASK 04", "TASK 05"]:
		_check("CHANGELOG 覆盖 %s" % task_no, changelog.contains(task_no))
	_check("docs/PERFORMANCE_REPORT.md 存在且非空", _file_size("res://docs/PERFORMANCE_REPORT.md") > 2000)
	var bench_raw := _file_text("res://docs/benchmark_results.json")
	var bench: Dictionary = {}
	if bench_raw != "":
		var parsed = JSON.parse_string(bench_raw)
		if parsed is Dictionary:
			bench = parsed
	_check("docs/benchmark_results.json 可解析", not bench.is_empty())
	_check("benchmark 含 12 组场景结果", (bench.get("runs", []) as Array).size() == 12, "%d 组" % (bench.get("runs", []) as Array).size())
	_check("benchmark 记录了 Godot 版本与机器信息", bench.has("godot") and bench.has("machine"))
	var shot_dir := DirAccess.open("res://docs/screenshots")
	_check("docs/screenshots/ 目录存在", shot_dir != null)
	for shot in ["01_day_exploration.png", "02_night_castle.png", "03_fireworks.png", "04_performance_hud.png"]:
		var shot_path: String = "res://docs/screenshots/" + String(shot)
		_check("截图存在且非空：%s" % shot, _file_size(shot_path) > 20000, "%d 字节" % _file_size(shot_path))
	for task_no in range(1, 6):
		var done_path := "res://docs/TASK0%d_DONE.md" % task_no
		_check("阶段报告存在：TASK0%d_DONE.md" % task_no, _file_size(done_path) > 500)

	_finish()


# ---------------------------------------------------------------------------
# 收尾
# ---------------------------------------------------------------------------

func _finish() -> void:
	print("")
	print("=== 结果：%d 项通过 / %d 项失败 ===" % [_pass, _fail])
	print("=== RESULT === %s" % ("TASK06_VERIFY_PASS" if _fail == 0 else "TASK06_VERIFY_FAIL"))
	quit(1 if _fail > 0 else 0)
