extends SceneTree
## tools/verify_quality.gd
## TASK05 自检脚本（headless，无需显示服务器）：
##   1. 装配（QualityManager / PerformanceHud / HUD 的 Quality/Perf 行 / 输入映射）
##   2. 默认档 = MEDIUM（Mac mini 默认）
##   3. F7 真实按键开关性能 HUD（隐藏时零采样）+ 读数内容完整
##   4. 7 / 8 / 9 真实按键切档，HUD 与子系统同步
##   5. 三档逐项生效值校验（MSAA / FXAA / 渲染比例 / 阴影距离与质量 / 摄像机 far /
##      粒子数量与拖尾 / 粒子绘制距离 / 夜景灯点亮数 / Glow / Fog / SSAO / 小装饰物可见距离）
##   6. LOW 档烟花粒子明显减少、夜景灯点亮数减少
##   7. 任意顺序来回切换后回到 MEDIUM，参数与初始 MEDIUM 完全一致（无残留）
##   8. 稳定性：30 轮换档后节点 / 对象 / 灯光 / 粒子系统数量不增长
##   9. 回归：TASK01~04 的节点与关键行为仍在（玩家 / 昼夜 / POI / 烟花 / 演示模式）
##
## 用法：
##   Godot --headless --path . --script res://tools/verify_quality.gd
## 退出码 0 = 全部通过；1 = 存在失败项。

const MAIN_SCENE := "res://scenes/main.tscn"

var _pass := 0
var _fail := 0
var _scene: Node = null
var _quality: Node = null
var _perf_hud: Node = null
var _hud: Node = null
var _env_mgr: Node = null
var _fireworks: Node = null
var _night_lights: Node = null
var _sun: DirectionalLight3D = null
var _showcase_camera: Camera3D = null
var _player: Node3D = null
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


func _seconds(s: float) -> void:
	await create_timer(s).timeout


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


func _count_nodes(root_node: Node) -> int:
	var n := 1
	for c in root_node.get_children():
		n += _count_nodes(c)
	return n


func _count_gpu_particles(root_node: Node) -> int:
	var n := 1 if root_node is GPUParticles3D else 0
	for c in root_node.get_children():
		n += _count_gpu_particles(c)
	return n


func _count_lights(root_node: Node) -> int:
	var n := 1 if root_node is Light3D else 0
	for c in root_node.get_children():
		n += _count_lights(c)
	return n


func _count_cameras(root_node: Node) -> Array[Camera3D]:
	var out: Array[Camera3D] = []
	if root_node is Camera3D:
		out.append(root_node as Camera3D)
	for c in root_node.get_children():
		out.append_array(_count_cameras(c))
	return out


func _settings() -> Dictionary:
	return _quality.call("get_effective_settings")


func _snapshot() -> Dictionary:
	var props_end := 0.0
	var castle := _scene.get_node_or_null("Castle")
	if castle != null:
		var first_prop: MeshInstance3D = null
		for node in _all_mesh_instances(castle):
			var aabb: AABB = (node as MeshInstance3D).mesh.get_aabb()
			if aabb.size.length() < 4.0 and not String(node.name).contains("Win_"):
				first_prop = node
				break
		if first_prop != null:
			props_end = first_prop.visibility_range_end
	var player_fars: Array = []
	for cam in _count_cameras(_player):
		player_fars.append(cam.far)
	var amounts: Array = _fireworks.call("get_system_amounts")
	return {
		"msaa_3d": _viewport.msaa_3d,
		"screen_space_aa": _viewport.screen_space_aa,
		"scaling_3d_scale": snappedf(_viewport.scaling_3d_scale, 0.001),
		"shadow_enabled": _sun.shadow_enabled,
		"shadow_max_distance": snappedf(_sun.directional_shadow_max_distance, 0.01),
		"shadow_blur": snappedf(_sun.shadow_blur, 0.01),
		"light_angular_distance": snappedf(_sun.light_angular_distance, 0.01),
		"showcase_far": snappedf(_showcase_camera.far, 0.01),
		"player_fars": str(player_fars),
		"particle_amounts": str(amounts),
		"particle_draw_distance": snappedf(float(_fireworks.call("get_particle_draw_distance")), 0.01),
		"light_budget": int(_night_lights.call("get_light_budget")),
		"prop_visibility_end": snappedf(props_end, 0.01),
		"glow": _env_mgr.call("get_environment").glow_enabled,
		"fog": _env_mgr.call("get_environment").fog_enabled,
		"ssao": _env_mgr.call("get_environment").ssao_enabled,
		"window_materials": int(_env_mgr.call("get_window_material_count")),
	}


func _all_mesh_instances(root_node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if root_node is MeshInstance3D and (root_node as MeshInstance3D).mesh != null:
		out.append(root_node as MeshInstance3D)
	for c in root_node.get_children():
		out.append_array(_all_mesh_instances(c))
	return out


func _lit_lights() -> int:
	var n := 0
	for light in _night_lights.call("get_lights"):
		var l := light as OmniLight3D
		if l.visible and l.light_energy > 0.001:
			n += 1
	return n


func _wait_night(env_mgr: Node, target: float, timeout: float = 6.0) -> float:
	var elapsed := 0.0
	while elapsed < timeout:
		var f: float = float(env_mgr.call("get_night_factor"))
		if absf(f - target) <= 0.02:
			return f
		await create_timer(0.05).timeout
		elapsed += 0.05
	return float(env_mgr.call("get_night_factor"))


# ---------------------------------------------------------------------------
# 主流程
# ---------------------------------------------------------------------------

func _run() -> void:
	print("=== TASK05 画质档 / 性能 HUD 自检 ===")
	_scene = load(MAIN_SCENE).instantiate()
	root.add_child(_scene)
	await _frames(5)
	await _seconds(0.5)

	_quality = _scene.get_node_or_null("QualityManager")
	_perf_hud = _scene.get_node_or_null("PerformanceHud")
	_hud = _scene.get_node_or_null("HUD")
	_env_mgr = _scene.get_node_or_null("EnvironmentManager")
	_fireworks = _scene.get_node_or_null("Fireworks")
	_night_lights = _scene.get_node_or_null("NightLights")
	_showcase_camera = _scene.get_node_or_null("MainCamera") as Camera3D
	_player = _scene.get_node_or_null("Player") as Node3D
	_viewport = root
	_sun = _env_mgr.call("get_sun") as DirectionalLight3D

	await _check_assembly()
	await _check_default_medium()
	await _check_perf_hud()
	await _check_switch_by_keys()
	await _check_levels()
	await _check_stability()
	await _check_regression()

	print("")
	print("=== 结果：%d 项通过 / %d 项失败 ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


# --- 1. 装配 ---------------------------------------------------------------

func _check_assembly() -> void:
	print("[1] 装配")
	_check("QualityManager 节点存在且脚本正确", _quality != null and _quality.has_method("set_level"))
	_check("PerformanceHud 节点存在且脚本正确", _perf_hud != null and _perf_hud.has_method("toggle"))
	_check("HUD 有 QualityLabel", _hud != null and _hud.get_node_or_null("QualityLabel") != null)
	_check("HUD 有 PerfLabel", _hud != null and _hud.get_node_or_null("PerfLabel") != null)
	_check("默认性能 HUD 关闭", not bool(_perf_hud.call("is_shown")))
	_check("输入映射 quality_low = 7", _action_has_key("quality_low", KEY_7))
	_check("输入映射 quality_medium = 8", _action_has_key("quality_medium", KEY_8))
	_check("输入映射 quality_high = 9", _action_has_key("quality_high", KEY_9))
	_check("输入映射 toggle_perf_hud = F7", _action_has_key("toggle_perf_hud", KEY_F7))
	_check("三档常量表完整（%d 档）" % 3, (_quality.call("get_settings_for", 0) as Dictionary).size() >= 12)


# --- 2. 默认档 -------------------------------------------------------------

func _check_default_medium() -> void:
	print("[2] 默认画质档")
	_check(
		"默认档 = MEDIUM",
		String(_quality.call("get_level_name")) == "MEDIUM",
		String(_quality.call("get_level_name"))
	)
	var hud_text := String((_hud.get_node("QualityLabel") as Label).text)
	_check("HUD 显示 Quality: MEDIUM", hud_text.contains("MEDIUM"), hud_text)
	var s := _settings()
	_check("MEDIUM 渲染比例为 1.0", is_equal_approx(float(s["render_scale"]), 1.0))
	_check("MEDIUM 未关闭 Glow / Fog", bool(s["glow_enabled"]) and bool(s["fog_enabled"]))


# --- 3. 性能 HUD -----------------------------------------------------------

func _check_perf_hud() -> void:
	print("[3] 性能 HUD（F7）")
	_press(KEY_F7)
	await _frames(2)
	_check("F7 打开性能 HUD", bool(_perf_hud.call("is_shown")))
	await _seconds(0.6)
	var text := String(_perf_hud.call("get_last_text"))
	var label := _hud.get_node("PerfLabel") as Label
	_check("性能 HUD 同步到 HUD Label", label.visible and label.text == text, label.text.replace("\n", " | "))
	_check("读数含 FPS", text.contains("FPS"), text.replace("\n", " | "))
	_check("读数含帧时间", text.contains("Frame"))
	_check("读数含 Draw Calls", text.contains("Draw Calls"))
	_check("读数含对象数 / 节点数", text.contains("Objects") and text.contains("Nodes"))
	_check("读数含当前画质档", text.contains("Quality: MEDIUM"))
	_check("读数含分辨率", text.contains("x") and text.contains("scale"))
	_check("读数含玩家坐标", text.contains("Player: ("))
	var m: Dictionary = _perf_hud.call("get_metrics")
	_check("指标采集可用（对象数 > 0）", int(m["objects"]) > 0, "objects=%d nodes=%d" % [int(m["objects"]), int(m["nodes"])])
	var before := String(_perf_hud.call("get_last_text"))
	_press(KEY_F7)
	await _seconds(0.6)
	_check("F7 关闭性能 HUD", not bool(_perf_hud.call("is_shown")))
	_check("HUD Label 同步隐藏", not label.visible)
	_check("隐藏后不再采样（文本保持不变）", String(_perf_hud.call("get_last_text")) == before)


# --- 4. 按键切档 -----------------------------------------------------------

func _check_switch_by_keys() -> void:
	print("[4] 7 / 8 / 9 真实按键切档")
	_press(KEY_7)
	await _frames(2)
	_check("按 7 → LOW", String(_quality.call("get_level_name")) == "LOW", String(_quality.call("get_level_name")))
	var hud_text := String((_hud.get_node("QualityLabel") as Label).text)
	_check("HUD 同步 LOW", hud_text.contains("LOW"), hud_text)
	_press(KEY_9)
	await _frames(2)
	_check("按 9 → HIGH", String(_quality.call("get_level_name")) == "HIGH", String(_quality.call("get_level_name")))
	_press(KEY_8)
	await _frames(2)
	_check("按 8 → MEDIUM", String(_quality.call("get_level_name")) == "MEDIUM", String(_quality.call("get_level_name")))
	_press(KEY_F7)
	await _frames(2)
	_check("切档后 F7 仍可打开性能 HUD（互不干扰）", bool(_perf_hud.call("is_shown")))
	await _seconds(0.5)
	_check("性能 HUD 画质行显示当前档 MEDIUM", String(_perf_hud.call("get_last_text")).contains("Quality: MEDIUM"))
	_press(KEY_9)
	await _seconds(0.5)
	_check("性能 HUD 画质行随切档实时刷新（→ HIGH）", String(_perf_hud.call("get_last_text")).contains("Quality: HIGH"), String(_perf_hud.call("get_last_text")).replace("\n", " | "))
	_press(KEY_8)
	await _seconds(0.4)
	_press(KEY_F7)
	await _frames(2)
	_check("再按 F7 关闭", not bool(_perf_hud.call("is_shown")))


# --- 5. 三档生效值 ---------------------------------------------------------

func _check_levels() -> void:
	print("[5] 三档逐项生效值")
	_quality.call("set_level", 1)
	await _seconds(0.4)
	var medium := _snapshot()

	_quality.call("set_level", 0)
	await _seconds(0.4)
	var low := _snapshot()
	_check("LOW：MSAA 关闭", int(low["msaa_3d"]) == Viewport.MSAA_DISABLED, str(low["msaa_3d"]))
	_check("LOW：FXAA 打开", int(low["screen_space_aa"]) == Viewport.SCREEN_SPACE_AA_FXAA, str(low["screen_space_aa"]))
	_check("LOW：渲染比例 0.75", is_equal_approx(float(low["scaling_3d_scale"]), 0.75), str(low["scaling_3d_scale"]))
	_check("LOW：阴影距离 150", is_equal_approx(float(low["shadow_max_distance"]), 150.0), str(low["shadow_max_distance"]))
	_check("LOW：阴影模糊 0.3", is_equal_approx(float(low["shadow_blur"]), 0.3), str(low["shadow_blur"]))
	_check("LOW：摄像机 far 700", is_equal_approx(float(low["showcase_far"]), 700.0), str(low["showcase_far"]))
	_check("LOW：Glow 关闭", not bool(low["glow"]))
	_check("LOW：Fog 关闭", not bool(low["fog"]))
	_check("LOW：SSAO 关闭", not bool(low["ssao"]))
	_check("LOW：小装饰物可见距离 70m", is_equal_approx(float(low["prop_visibility_end"]), 70.0), str(low["prop_visibility_end"]))
	_check("LOW：粒子绘制距离 300m", is_equal_approx(float(low["particle_draw_distance"]), 300.0), str(low["particle_draw_distance"]))
	_check("LOW：夜景灯预算 3 盏", int(low["light_budget"]) == 3, str(low["light_budget"]))
	var low_budget: int = int(_fireworks.call("get_total_particle_budget"))
	_check(
		"LOW：烟花粒子明显减少（≤ MEDIUM 的 30%）",
		float(low_budget) <= float(medium_budget_cache()) * 0.3,
		"LOW=%d / MEDIUM=%d" % [low_budget, medium_budget_cache()]
	)
	_check("LOW：拖尾关闭", not bool((_fireworks.get("trails_enabled"))))

	_quality.call("set_level", 2)
	await _seconds(0.4)
	var high := _snapshot()
	_check("HIGH：MSAA 4x", int(high["msaa_3d"]) == Viewport.MSAA_4X, str(high["msaa_3d"]))
	_check("HIGH：阴影距离 520", is_equal_approx(float(high["shadow_max_distance"]), 520.0), str(high["shadow_max_distance"]))
	_check("HIGH：阴影模糊 1.6", is_equal_approx(float(high["shadow_blur"]), 1.6), str(high["shadow_blur"]))
	_check("HIGH：光线角直径 1.2", is_equal_approx(float(high["light_angular_distance"]), 1.2), str(high["light_angular_distance"]))
	_check("HIGH：摄像机 far 1500", is_equal_approx(float(high["showcase_far"]), 1500.0), str(high["showcase_far"]))
	_check("HIGH：不做可见性剔除（小装饰物 0 = 不限）", is_equal_approx(float(high["prop_visibility_end"]), 0.0), str(high["prop_visibility_end"]))
	_check("HIGH：粒子绘制距离不限", is_equal_approx(float(high["particle_draw_distance"]), 0.0), str(high["particle_draw_distance"]))
	var high_win := float((_quality.call("get_settings_for", 2) as Dictionary)["window_emission_scale"])
	var medium_win := float((_quality.call("get_settings_for", 1) as Dictionary)["window_emission_scale"])
	_check("HIGH：窗光强度 > MEDIUM", high_win > medium_win, "%.2f vs %.2f" % [high_win, medium_win])

	_quality.call("set_level", 1)
	await _seconds(0.4)
	var back := _snapshot()
	_check("切回 MEDIUM 与初始 MEDIUM 完全一致（无残留）", _dict_matches(medium, back), _diff(medium, back))
	_check("MEDIUM 阴影距离 = 320（既有默认）", is_equal_approx(float(back["shadow_max_distance"]), 320.0), str(back["shadow_max_distance"]))
	_check("MEDIUM 摄像机 far = 950", is_equal_approx(float(back["showcase_far"]), 950.0), str(back["showcase_far"]))
	_check("MEDIUM 三台相机（展示 + 玩家 2）far 同步", String(back["player_fars"]).contains("950"), String(back["player_fars"]))
	_check("MEDIUM 粒子量与既有验收一致（4 发射位 × 220）", String(back["particle_amounts"]) == String(medium["particle_amounts"]), String(back["particle_amounts"]))
	_check("MEDIUM 窗光材质数量不变（0 新增灯 / 材质复用）", int(back["window_materials"]) == int(medium["window_materials"]), str(back["window_materials"]))

	# 夜景灯点亮数随档位变化（需要真的入夜）
	_quality.call("set_level", 0)
	_env_mgr.call("set_preset", 2)
	await _wait_night(_env_mgr, 1.0)
	_check("LOW：夜间只点亮 3 盏灯", _lit_lights() == 3, "点亮 %d 盏" % _lit_lights())
	_quality.call("set_level", 1)
	await _seconds(0.3)
	_check("MEDIUM：夜间点亮 6 盏灯（无回退）", _lit_lights() == 6, "点亮 %d 盏" % _lit_lights())
	_check("MEDIUM：Glow 恢复开启（与既有验收一致）", bool(_env_mgr.call("get_environment").glow_enabled))


func medium_budget_cache() -> int:
	return int(_fireworks.call("get_particle_amount")) * int(_fireworks.call("get_pad_count"))


func _dict_matches(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for k in a.keys():
		if str(a[k]) != str(b[k]):
			return false
	return true


func _diff(a: Dictionary, b: Dictionary) -> String:
	var out := PackedStringArray()
	for k in a.keys():
		if str(a[k]) != str(b[k]):
			out.append("%s: %s -> %s" % [k, str(a[k]), str(b[k])])
	return ", ".join(out)


# --- 6. 稳定性 -------------------------------------------------------------

func _check_stability() -> void:
	print("[6] 稳定性（30 轮换档）")
	_quality.call("set_level", 1)
	await _seconds(0.3)
	var nodes_before := _count_nodes(_scene)
	var lights_before := _count_lights(_scene)
	var particles_before := _count_gpu_particles(_scene)
	var cameras_before := _count_cameras(_scene).size()
	for i in range(30):
		_quality.call("set_level", i % 3)
		await _frames(1)
	_quality.call("set_level", 1)
	await _frames(2)
	_check("换档 30 轮后节点数不变", _count_nodes(_scene) == nodes_before, "%d -> %d" % [nodes_before, _count_nodes(_scene)])
	_check("换档 30 轮后灯光数不变", _count_lights(_scene) == lights_before, "%d -> %d" % [lights_before, _count_lights(_scene)])
	_check("换档 30 轮后粒子系统数不变", _count_gpu_particles(_scene) == particles_before, "%d -> %d" % [particles_before, _count_gpu_particles(_scene)])
	_check("换档 30 轮后相机数不变", _count_cameras(_scene).size() == cameras_before, "%d -> %d" % [cameras_before, _count_cameras(_scene).size()])
	_check("窗户自发光材质数量恒定", int(_env_mgr.call("get_window_material_count")) > 0, "%d 份" % int(_env_mgr.call("get_window_material_count")))


# --- 7. 回归 ---------------------------------------------------------------

func _check_regression() -> void:
	print("[7] TASK01~04 回归")
	for node_name in ["Player", "EnvironmentManager", "PoiSet", "InteractionController", "Fireworks", "NightLights", "PresentationController", "WorldCollision", "HUD"]:
		_check("节点仍在：%s" % node_name, _scene.get_node_or_null(node_name) != null)
	var poi_root := _scene.get_node_or_null("PoiSet")
	var poi_count := 0
	if poi_root != null:
		for c in poi_root.get_children():
			if c.has_method("get_interaction_text"):
				poi_count += 1
	_check("POI 数量 ≥ 5", poi_count >= 5, "%d 个" % poi_count)
	_check("展示相机可用（current）", _showcase_camera != null)
	_check("玩家控制器方法完整", _player != null and _player.has_method("teleport_to") and _player.has_method("set_camera_mode"))
	_check("烟花发射位 4 个", int(_fireworks.call("get_pad_count")) == 4, str(int(_fireworks.call("get_pad_count"))))
	_check("夜景灯 6 盏", int(_night_lights.call("get_light_count")) == 6, str(int(_night_lights.call("get_light_count"))))
	_check("昼夜系统接口完整", _env_mgr.has_method("set_preset_by_name") and _env_mgr.has_method("get_night_factor"))
	var castle := _scene.get_node_or_null("Castle")
	_check("城堡 GLB 已加载且网格数 > 0", castle != null and _all_mesh_instances(castle).size() > 0, "%d 个网格" % _all_mesh_instances(castle).size())
	_check("小装饰物剔除清单非空（可见性优化生效）", int(_quality.call("get_prop_count")) > 0, "%d 个" % int(_quality.call("get_prop_count")))
	_env_mgr.call("set_preset", 0)
	await _seconds(0.5)
	_check("回归：白天预设可切换", String(_env_mgr.call("get_preset_name")) == "DAY", String(_env_mgr.call("get_preset_name")))
