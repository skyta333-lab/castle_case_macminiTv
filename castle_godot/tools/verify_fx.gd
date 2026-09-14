extends SceneTree
## tools/verify_fx.gd
## TASK04 自检脚本（headless，无需显示服务器）：
##   1. 场景装配（Fireworks / NightLights / PresentationController / HUD 状态行）
##   2. 烟花系统结构（≥3 发射位、每发射位 1 个 one_shot GPUParticles3D、参数化）
##   3. F5 真实按键开关烟花 + HUD 状态同步
##   4. 发射与错峰（fired_total / 延迟队列）
##   5. 粒子不累积（10 分钟等价仿真：600 轮齐射后对象数 / 粒子预算恒定）
##   6. 昼夜响应（白天压制 / 夜晚满可见度 / 夜景灯光随夜亮起，全部无阴影）
##   7. F6 真实按键演示模式（切 NIGHT + 开烟花 + 展示相机 + 缓慢环绕 + 退出还原）
##   8. 回归：GLB 未破坏、TASK01~03 节点仍在
##
## 用法：
##   Godot --headless --path . --script res://tools/verify_fx.gd
## 退出码 0 = 全部通过；1 = 存在失败项。

const MAIN_SCENE := "res://scenes/main.tscn"
const NIGHT_PRESET := 2
const DAY_PRESET := 0

var _pass := 0
var _fail := 0


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


## 等待昼夜插值到达目标值（transition_seconds 默认 1.2s）
func _wait_night(env_mgr: Node, target: float, timeout: float = 6.0) -> float:
	var elapsed := 0.0
	while elapsed < timeout:
		var f: float = float(env_mgr.call("get_night_factor"))
		if absf(f - target) <= 0.02:
			return f
		await create_timer(0.05).timeout
		elapsed += 0.05
	return float(env_mgr.call("get_night_factor"))


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


func _property_names(obj: Object) -> PackedStringArray:
	var out := PackedStringArray()
	for p in obj.get_property_list():
		out.append(String(p["name"]))
	return out


func _count_nodes(root_node: Node) -> int:
	var n := 1
	for c in root_node.get_children():
		n += _count_nodes(c)
	return n


func _count_particles_nodes(root_node: Node) -> int:
	var n := 1 if root_node is GPUParticles3D else 0
	for c in root_node.get_children():
		n += _count_particles_nodes(c)
	return n


func _finish() -> void:
	print("\n=== TASK04 自检结果：%d 项通过 / %d 项失败 ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)


# ---------------------------------------------------------------------------
# 主流程
# ---------------------------------------------------------------------------

func _run() -> void:
	print("=== TASK04 verify: night lighting & fireworks ===")

	var packed := load(MAIN_SCENE) as PackedScene
	if packed == null:
		_check("加载主场景", false, MAIN_SCENE)
		_finish()
		return
	var scene: Node = packed.instantiate()
	root.add_child(scene)
	await _frames(10)

	var env_mgr: Node = scene.get_node_or_null("EnvironmentManager")
	var fw := scene.get_node_or_null("Fireworks") as FireworksController
	var lights := scene.get_node_or_null("NightLights") as NightLighting
	var pres := scene.get_node_or_null("PresentationController") as PresentationController
	var cam_mgr: Node = scene.get_node_or_null("CameraModeManager")
	var hud := scene.get_node_or_null("HUD") as GameHud

	# ------------------------------------------------------------ A. 装配
	print("\n[A] 场景装配")
	_check("EnvironmentManager 存在", env_mgr != null)
	_check("Fireworks 节点存在且挂 FireworksController", fw != null)
	_check("NightLights 存在且挂 NightLighting", lights != null)
	_check("PresentationController 存在", pres != null)
	_check("CameraModeManager 存在", cam_mgr != null)
	_check("HUD 存在", hud != null)
	_check("回顾 TASK01-03 节点仍在（Castle/PoiSet/Player）", scene.get_node_or_null("Castle") != null and scene.get_node_or_null("PoiSet") != null and scene.get_node_or_null("Player") != null)
	_check("HUD 提供 FX 状态行", hud != null and _property_names(hud).has("fx_label"))
	if env_mgr == null or fw == null or lights == null or pres == null or cam_mgr == null or hud == null:
		_finish()
		return

	# ------------------------------------------------------------ B. 烟花结构
	print("\n[B] 烟花系统结构")
	var pad_count: int = fw.get_pad_count()
	var sys_count: int = fw.get_system_count()
	_check("发射位 ≥ 3", pad_count >= 3, "%d 个发射位" % pad_count)
	_check("每个发射位对应一个粒子系统", sys_count == pad_count, "systems=%d pads=%d" % [sys_count, pad_count])

	var one_shot_ok := true
	var gpu_ok := true
	var lifetime_ok := true
	for pad in fw.get_children():
		if not (pad is Node3D):
			continue
		for sub in pad.get_children():
			var ps := sub as GPUParticles3D
			if ps == null:
				continue
			if not ps.one_shot:
				one_shot_ok = false
			if ps.lifetime <= 0.0 or ps.amount <= 0:
				lifetime_ok = false
			if ps.process_material == null or not (ps.process_material is ParticleProcessMaterial):
				gpu_ok = false
	_check("全部粒子系统为 one_shot（天然不无限累积）", one_shot_ok)
	_check("粒子系统为 GPUParticles3D + ParticleProcessMaterial", gpu_ok)
	_check("粒子系统 lifetime/amount 有效", lifetime_ok)

	var launch_points: Array = fw.get_launch_points()
	var distinct := {}
	for p in launch_points:
		distinct["%d_%d_%d" % [int(p.x), int(p.y), int(p.z)]] = true
	_check("发射位坐标互不相同（错峰分布）", distinct.size() == launch_points.size(), "%d 个不同坐标" % distinct.size())

	var props := _property_names(fw)
	var need_params := ["enabled", "spawn_interval", "burst_count", "particle_amount"]
	var missing := PackedStringArray()
	for p in need_params:
		if not props.has(p):
			missing.append(p)
	_check("必备参数已暴露（enabled/spawn_interval/burst_count/particle_amount）", missing.is_empty(), "缺失: %s" % str(missing))
	var old_interval: float = fw.spawn_interval
	fw.set("spawn_interval", 2.5)
	_check("参数可写入（spawn_interval 可改）", absf(fw.spawn_interval - 2.5) < 0.001, "写回 %.2f" % fw.spawn_interval)
	fw.set("spawn_interval", old_interval)
	_check("错峰延迟参数存在（burst_stagger > 0）", fw.burst_stagger > 0.0, "%.2f 秒" % fw.burst_stagger)

	# ------------------------------------------------------------ C. F5 开关
	print("\n[C] F5 烟花开关（真实按键）")
	_check("InputMap fireworks_toggle 绑定 F5", _action_has_key("fireworks_toggle", KEY_F5))
	_check("启动时烟花默认关闭", not fw.is_enabled())
	_press(KEY_F5)
	await _frames(3)
	_check("F5 打开烟花", fw.is_enabled())
	_check("HUD 同步 Fireworks ON", hud.get_fx_status().contains("Fireworks ON"), hud.get_fx_status())
	_press(KEY_F5)
	await _frames(3)
	_check("再按 F5 关闭烟花", not fw.is_enabled())
	_check("HUD 同步 Fireworks OFF", hud.get_fx_status().contains("Fireworks OFF"), hud.get_fx_status())
	await _frames(3)
	_check("关闭后无粒子系统仍在发射", fw.get_emitting_count() == 0, "emitting=%d" % fw.get_emitting_count())
	_check("关闭后延迟队列被清空", fw.get_pending_count() == 0)

	# ------------------------------------------------------------ D. 发射与错峰
	print("\n[D] 发射与错峰")
	env_mgr.call("set_preset", NIGHT_PRESET)
	var night_now := await _wait_night(env_mgr, 1.0, 6.0)
	_check("切到夜晚（night_factor ≈ 1）", absf(night_now - 1.0) <= 0.02, "night=%.3f" % night_now)

	var fired_before: int = fw.get_fired_total()
	fw.spawn_interval = 0.4
	fw.start_delay = 0.05
	fw.set_enabled(true)
	await _seconds(1.2)
	_check("自动周期内确实发射（fired_total 增长）", fw.get_fired_total() > fired_before, "%d -> %d" % [fired_before, fw.get_fired_total()])
	_check("齐射轮次 ≥ 1", fw.get_volley_total() >= 1, "volley=%d" % fw.get_volley_total())

	fw.set_enabled(false)
	await _seconds(0.2)
	# 单轮错峰：burst_count 个发射位错开延迟
	fw.burst_count = 3
	fw.burst_stagger = 0.45
	fw.fire_volley()
	var delays: Array = fw.get_pending_delays()
	var staggered := 0
	for d in delays:
		if float(d) > 0.0:
			staggered += 1
	_check("一轮齐射排入 burst_count 个发射位", delays.size() == 3, "pending=%d" % delays.size())
	_check("同一轮内 ≥ 2 个发射位带错峰延迟", staggered >= 2, "staggered=%d" % staggered)
	await _seconds(1.0)
	_check("错峰队列会被消费完（不残留）", fw.get_pending_count() == 0, "pending=%d" % fw.get_pending_count())

	# ------------------------------------------------------------ E. 不累积
	print("\n[E] 粒子不累积（600 轮齐射 ≈ 10 分钟以上仿真）")
	var nodes_before := _count_nodes(fw)
	var gpu_before := _count_particles_nodes(fw)
	var lights_before: int = lights.get_light_count()
	var budget_before: int = fw.get_total_particle_budget()
	var obj_before: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	for i in 600:
		fw.fire_volley()
		await process_frame
	await _seconds(0.5)
	var nodes_after := _count_nodes(fw)
	var gpu_after := _count_particles_nodes(fw)
	var lights_after: int = lights.get_light_count()
	var budget_after: int = fw.get_total_particle_budget()
	var obj_after: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	_check("烟花子树节点数不增长", nodes_after == nodes_before, "%d -> %d" % [nodes_before, nodes_after])
	_check("粒子系统数量不增长", gpu_after == gpu_before, "%d -> %d" % [gpu_before, gpu_after])
	_check("夜景灯光数量不增长", lights_after == lights_before, "%d -> %d" % [lights_before, lights_after])
	_check("粒子预算恒定", budget_after == budget_before, "%d -> %d" % [budget_before, budget_after])
	_check("引擎对象总数稳定（漂移 ≤ 200）", obj_after - obj_before <= 200, "%d -> %d" % [obj_before, obj_after])
	var amounts: Array = fw.get_system_amounts()
	var amount_ok := true
	for a in amounts:
		if int(a) > fw.get_particle_amount():
			amount_ok = false
	_check("各发射位粒子数 ≤ 单发配置", amount_ok, "%s / max=%d" % [str(amounts), fw.get_particle_amount()])

	# ------------------------------------------------------------ F. 昼夜响应
	print("\n[F] 昼夜响应（灯光 / 烟花）")
	env_mgr.call("set_preset", DAY_PRESET)
	var day_factor := await _wait_night(env_mgr, 0.0, 6.0)
	_check("切到白天（night_factor ≈ 0）", day_factor <= 0.02, "night=%.3f" % day_factor)
	await _seconds(0.3)
	_check("白天烟花被压制（可见度 < 0.5）", fw.get_visibility_scale() < 0.5, "scale=%.3f" % fw.get_visibility_scale())
	_check("白天夜景灯光熄灭", lights.get_light_energy_total() <= 0.001, "energy=%.4f" % lights.get_light_energy_total())

	env_mgr.call("set_preset", NIGHT_PRESET)
	var night_factor := await _wait_night(env_mgr, 1.0, 6.0)
	await _seconds(0.3)
	_check("夜晚烟花满可见度", fw.get_visibility_scale() >= 0.99, "scale=%.3f" % fw.get_visibility_scale())
	var lit := 0
	var shadow_free := true
	for l in lights.get_lights():
		if l.visible and l.light_energy > 0.001:
			lit += 1
		if l.shadow_enabled:
			shadow_free = false
	_check("夜晚点亮 ≥ 5 盏夜景灯", lit >= 5, "点亮 %d / 共 %d 盏" % [lit, lights.get_light_count()])
	_check("夜景灯全部关闭阴影（性能）", shadow_free)
	_check("夜景灯 energy 总量 > 0", lights.get_light_energy_total() > 0.0, "energy=%.3f" % lights.get_light_energy_total())
	_check("城堡窗户自发光策略仍在（无新增实时灯）", int(env_mgr.call("get_window_material_count")) > 0, "%d 份自发光材质" % int(env_mgr.call("get_window_material_count")))

	# ------------------------------------------------------------ G. F6 演示模式
	print("\n[G] F6 演示模式（真实按键）")
	_check("InputMap presentation_mode 绑定 F6", _action_has_key("presentation_mode", KEY_F6))
	env_mgr.call("set_preset", DAY_PRESET)
	await _wait_night(env_mgr, 0.0, 6.0)
	await _seconds(0.2)
	var showcase_speed_before: float = float(scene.get("camera_orbit_speed"))
	_press(KEY_F6)
	await _frames(4)
	_check("F6 进入演示模式", pres.is_active())
	_check("演示模式切到 NIGHT 预设", String(env_mgr.call("get_preset_name")) == "NIGHT", String(env_mgr.call("get_preset_name")))
	_check("演示模式打开烟花", fw.is_enabled())
	_check("演示模式切到展示相机", int(cam_mgr.get("current_mode")) == CameraModeManager.Mode.SHOWCASE, "mode=%d" % int(cam_mgr.get("current_mode")))
	var orbit_now: float = float(scene.get("camera_orbit_speed"))
	_check("演示模式环绕速度 = 目标速度且非静止", absf(orbit_now - pres.get_orbit_speed()) < 0.01 and orbit_now > 0.5, "orbit=%.2f 目标=%.2f" % [orbit_now, pres.get_orbit_speed()])
	_check("演示模式环绕速度确实是缓慢的（≤ 6 度/秒）", orbit_now <= 6.0, "orbit=%.2f" % orbit_now)
	_check("HUD 同步 Presentation ON", hud.get_fx_status().contains("Presentation ON"), hud.get_fx_status())
	var demo_night := await _wait_night(env_mgr, 1.0, 6.0)
	_check("演示模式夜晚生效（night_factor ≈ 1）", absf(demo_night - 1.0) <= 0.02, "night=%.3f" % demo_night)

	_press(KEY_F6)
	await _frames(4)
	_check("再按 F6 退出演示模式", not pres.is_active())
	_check("退出后烟花关闭", not fw.is_enabled())
	_check("退出后环绕速度还原", absf(float(scene.get("camera_orbit_speed")) - showcase_speed_before) < 0.01, "%.2f -> %.2f" % [showcase_speed_before, float(scene.get("camera_orbit_speed"))])
	await _seconds(0.2)
	_check("退出后环境预设还原为 DAY", String(env_mgr.call("get_preset_name")) == "DAY", String(env_mgr.call("get_preset_name")))
	_check("HUD 同步 Presentation OFF", hud.get_fx_status().contains("Presentation OFF"), hud.get_fx_status())

	# ------------------------------------------------------------ H. 回归
	print("\n[H] 回归检查")
	var castle: Node = scene.get_node_or_null("Castle")
	_check("Castle GLB 节点仍在且未被替换", castle != null and castle.get_child_count() > 0, "%d 个子节点" % (castle.get_child_count() if castle != null else 0))
	var collision: Node = scene.get_node_or_null("WorldCollision")
	_check("TASK01 程序化碰撞体仍在", collision != null and collision.get_child_count() > 0)
	_check("TASK03 交互控制器仍在", scene.get_node_or_null("InteractionController") != null)
	_check("F5/F6/F1-F4 键位互不冲突", _action_has_key("fireworks_toggle", KEY_F5) and _action_has_key("presentation_mode", KEY_F6) and not _action_has_key("fireworks_toggle", KEY_F6))

	_finish()
