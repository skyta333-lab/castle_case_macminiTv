extends SceneTree
## 临时：TASK 02 昼夜与环境系统自检，运行后删除。
## 用法：godot --headless --path . --fixed-fps 60 --script res://tools/verify_environment.gd

const MAIN := "res://scenes/main.tscn"

var _scene: Node
var _env_mgr: Node
var _sun: DirectionalLight3D
var _player: Node
var _mgr: Node
var _frames := 0
var _fails: Array = []
var _key_ok := true
var _night_em := 0.0
var _day_em := 0.0
var _windows: Array = []


func _windows_of(root: Node, out: Array) -> void:
	if root is MeshInstance3D and String(root.name).contains("Win_"):
		out.append(root)
	for c in root.get_children():
		_windows_of(c, out)


func _emission_of_first_window() -> float:
	for w in _windows:
		var mi := w as MeshInstance3D
		if mi == null or mi.mesh == null or mi.mesh.get_surface_count() <= 0:
			continue
		var m := mi.get_surface_override_material(0)
		if m is StandardMaterial3D:
			return (m as StandardMaterial3D).emission_energy_multiplier if (m as StandardMaterial3D).emission_enabled else 0.0
	return -999.0


func _press(key: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	ev.keycode = key
	ev.pressed = true
	Input.parse_input_event(ev)
	var ev2 := InputEventKey.new()
	ev2.physical_keycode = key
	ev2.keycode = key
	ev2.pressed = false
	Input.parse_input_event(ev2)


func _initialize() -> void:
	print("=== TASK02 VERIFY ===")
	var packed := load(MAIN) as PackedScene
	if packed == null:
		_fail("主场景加载失败")
		return
	_scene = packed.instantiate()
	root.add_child(_scene)
	_env_mgr = _scene.get_node_or_null("EnvironmentManager")
	_player = _scene.get_node_or_null("Player")
	_mgr = _scene.get_node_or_null("CameraModeManager")
	_sun = _scene.get_node_or_null("SunLight") as DirectionalLight3D
	if _env_mgr == null:
		_fail("主场景缺少 EnvironmentManager 节点")
	if _sun == null:
		_fail("主场景缺少 SunLight 节点")
	var castle := _scene.get_node_or_null("Castle")
	if castle != null:
		_windows_of(castle, _windows)
	print("windows found by test = %d" % _windows.size())


func _day_checks(tag: String) -> void:
	var e: Environment = _env_mgr.get_environment()
	print(
		"[%s] preset=%s sun_energy=%.3f sun_color=%s ambient=%.3f exposure=%.2f fog_density=%.5f sky_top=%s win_em=%.2f"
		% [
			tag, _env_mgr.get_preset_name(), _sun.light_energy, str(_sun.light_color),
			e.ambient_light_energy, e.tonemap_exposure, e.fog_density,
			str(e.sky.sky_material.sky_top_color), _emission_of_first_window()
		]
	)


func _process(_delta: float) -> bool:
	_frames += 1

	if _frames == 2:
		if _env_mgr == null or _sun == null:
			return true
		var e: Environment = _env_mgr.get_environment()
		if e == null:
			_fail("未拿到运行期 Environment")
		if _env_mgr.get_window_material_count() <= 0:
			_fail("没有收集到窗户自发光材质（关键字 Win_）")
		else:
			print("OK   窗户材质已接管: %d 份共享材质 / %d 个 Win_ 网格" % [_env_mgr.get_window_material_count(), _windows.size()])
		if _emission_of_first_window() != 0.0:
			_fail("白天窗户不应发光")
		else:
			print("OK   白天窗户自发光关闭")
		if absf(_sun.light_energy - 1.35) > 0.2:
			_fail("启动（DAY）太阳能量异常 %.3f" % _sun.light_energy)
		_day_checks("DAY")
	elif _frames == 4:
		_press(KEY_F3)
	elif _frames == 10:
		if _env_mgr.get_preset_name() != "NIGHT":
			_key_ok = false
			print("note: headless 按键事件未送达，改用直接 API 驱动")
			_env_mgr.set_preset(2)
	elif _frames == 110:
		var e: Environment = _env_mgr.get_environment()
		_day_checks("NIGHT")
		if _env_mgr.get_preset_name() != "NIGHT":
			_fail("F3 未切到夜晚（当前 %s）" % _env_mgr.get_preset_name())
		else:
			print("OK   F3 切到 NIGHT（按键事件链路 %s）" % ("正常" if _key_ok else "降级为直接 API"))
		if _sun.light_energy > 0.4:
			_fail("夜晚阳光能量过高 %.3f" % _sun.light_energy)
		if _sun.light_color.b > _sun.light_color.r:
			print("OK   夜间方向光为冷色月光 %s" % str(_sun.light_color))
		else:
			_fail("夜间方向光颜色不冷 %s" % str(_sun.light_color))
		if e.ambient_light_energy < 0.05:
			_fail("夜晚环境光过低，画面会全黑 %.3f" % e.ambient_light_energy)
		if e.sky.sky_material.sky_top_color.get_luminance() < 0.002:
			_fail("夜晚天空纯黑 top=%s" % str(e.sky.sky_material.sky_top_color))
		else:
			print("OK   夜景不是全黑：ambient=%.2f sky_top_lum=%.4f" % [e.ambient_light_energy, e.sky.sky_material.sky_top_color.get_luminance()])
		if e.glow_enabled == false:
			_fail("夜晚辉光被关闭（窗户发光看不到）")
		_night_em = _emission_of_first_window()
		if _night_em < 1.0:
			_fail("夜晚窗户自发光未生效 em=%.2f" % _night_em)
		else:
			print("OK   夜晚窗户暖色自发光 em=%.2f" % _night_em)
		if not _env_mgr.is_night():
			_fail("is_night() 判定错误")
	elif _frames == 112:
		_press(KEY_F1)
	elif _frames == 220:
		_day_checks("DAY-again")
		_day_em = _emission_of_first_window()
		if _env_mgr.get_preset_name() != "DAY":
			_fail("F1 未切回白天（%s）" % _env_mgr.get_preset_name())
		if _day_em > 0.01:
			_fail("切回白天后窗户仍在发光 em=%.2f" % _day_em)
		if _sun.light_energy < 1.0:
			_fail("切回白天后太阳能量不足 %.3f" % _sun.light_energy)
		else:
			print("OK   F1 切回 DAY（窗户自发光 %.2f → %.2f）" % [_night_em, _day_em])
		if _env_mgr.is_night():
			_fail("白天仍被判定为夜晚")
	elif _frames == 222:
		_press(KEY_F2)
	elif _frames == 330:
		var e: Environment = _env_mgr.get_environment()
		_day_checks("SUNSET")
		if _env_mgr.get_preset_name() != "SUNSET":
			_fail("F2 未切到黄昏（%s）" % _env_mgr.get_preset_name())
		var c: Color = _sun.light_color
		if not (c.r > 0.9 and c.g < c.r and c.b < c.g):
			_fail("黄昏阳光不是暖色 %s" % str(c))
		else:
			print("OK   F2 黄昏暖色阳光 %s energy=%.2f" % [str(c), _sun.light_energy])
		if e.fog_density <= 0.0008:
			_fail("黄昏雾浓度未加强 %.5f" % e.fog_density)
		if _emission_of_first_window() < 0.8:
			_fail("黄昏窗户未点亮 em=%.2f" % _emission_of_first_window())
		else:
			print("OK   黄昏窗户已点亮")
		if _env_mgr.is_night():
			_fail("黄昏被误判为夜晚（night_factor=%.2f）" % _env_mgr.get_night_factor())
		else:
			print("OK   黄昏未被误判为夜晚（night_factor=%.2f）" % _env_mgr.get_night_factor())
	elif _frames == 332:
		_press(KEY_F4)
	elif _frames == 340:
		if not _env_mgr.is_auto_cycle():
			_fail("F4 未开启自动昼夜")
		else:
			print("OK   F4 开启自动昼夜")
		_env_mgr.set_time_of_day(0.0)
	elif _frames == 430:
		var e: Environment = _env_mgr.get_environment()
		_day_checks("AUTO-00:00")
		if not _env_mgr.is_night():
			_fail("自动昼夜 00:00 未判定为夜晚")
		if _sun.light_energy > 0.4:
			_fail("自动昼夜 00:00 阳光能量过高 %.3f" % _sun.light_energy)
		_env_mgr.set_time_of_day(12.0)
	elif _frames == 520:
		_day_checks("AUTO-12:00")
		if _env_mgr.is_night():
			_fail("自动昼夜 12:00 误判为夜晚")
		if _sun.light_energy < 0.9:
			_fail("自动昼夜 12:00 阳光能量过低 %.3f" % _sun.light_energy)
		if _env_mgr.get_sun_pitch() < 50.0:
			_fail("自动昼夜 12:00 太阳高度角异常 %.1f" % _env_mgr.get_sun_pitch())
		else:
			print("OK   自动昼夜 12:00 太阳高度角 %.1f°" % _env_mgr.get_sun_pitch())
		_env_mgr.set_time_of_day(18.2)
	elif _frames == 610:
		_day_checks("AUTO-18:12")
		var c: Color = _sun.light_color
		if _sun.light_energy < 0.6:
			_fail("自动昼夜 18:12 阳光偏暗 %.3f" % _sun.light_energy)
		if not (c.r > c.b):
			_fail("自动昼夜 18:12 光色不暖 %s" % str(c))
		if _env_mgr.is_night():
			_fail("自动昼夜 18:12 被误判为夜晚（night_factor=%.2f）" % _env_mgr.get_night_factor())
		if _env_mgr.get_sun_pitch() > 40.0:
			_fail("自动昼夜 18:12 太阳仍过高 %.1f°" % _env_mgr.get_sun_pitch())
		else:
			print(
				"OK   自动昼夜 18:12 太阳高度角 %.1f° 光色 %s night_factor=%.2f"
				% [_env_mgr.get_sun_pitch(), str(c), _env_mgr.get_night_factor()]
			)
		_env_mgr.set_time_of_day(22.0)
	elif _frames == 700:
		var c2: Color = _sun.light_color
		if not _env_mgr.is_night():
			_fail("自动昼夜 22:00 未判定为夜晚（night_factor=%.2f）" % _env_mgr.get_night_factor())
		elif _sun.light_energy > 0.4:
			_fail("自动昼夜 22:00 月光能量过高 %.3f" % _sun.light_energy)
		elif _emission_of_first_window() < 1.0:
			_fail("自动昼夜 22:00 窗户未点亮 em=%.2f" % _emission_of_first_window())
		else:
			print(
				"OK   自动昼夜 22:00 夜晚成立（月光 %.2f %s / 窗户 %.2f -> 到 24h 循环连续）"
				% [_sun.light_energy, str(c2), _emission_of_first_window()]
			)
		# 连续性抽样：相邻 5 分钟不应出现方向光角度断崖
		var max_jump := 0.0
		var at_t := 0.0
		var at_what := ""
		var prev_pitch: float = _env_mgr._params_for_time(0.0)["sun_pitch_deg"]
		var prev_yaw: float = _env_mgr._params_for_time(0.0)["sun_yaw_deg"]
		for i in range(1, 288):
			var tt: float = float(i) * (24.0 / 288.0)
			var pp: Dictionary = _env_mgr._params_for_time(tt)
			var dp: float = absf(float(pp["sun_pitch_deg"]) - prev_pitch)
			var dy: float = absf(wrapf(float(pp["sun_yaw_deg"]) - prev_yaw, -180.0, 180.0))
			if maxf(dp, dy) > max_jump:
				max_jump = maxf(dp, dy)
				at_t = tt
				at_what = ("pitch %.1f->%.1f" % [prev_pitch, float(pp["sun_pitch_deg"])]) if dp > dy else ("yaw %.1f->%.1f" % [prev_yaw, float(pp["sun_yaw_deg"])])
			prev_pitch = float(pp["sun_pitch_deg"])
			prev_yaw = float(pp["sun_yaw_deg"])
		if max_jump > 12.0:
			_fail("全天光照角度存在断崖：相邻 5 分钟最大跳变 %.1f° @t=%.2f (%s)" % [max_jump, at_t, at_what])
		else:
			print("OK   全天光照连续：相邻 5 分钟最大角度跳变 %.1f° @t=%.2f (%s)" % [max_jump, at_t, at_what])
		_press(KEY_F4)
	elif _frames == 710:
		if _env_mgr.is_auto_cycle():
			_fail("F4 再次按下未关闭自动昼夜")
		else:
			print("OK   F4 关闭自动昼夜")
		_mgr.set_mode(2)
		Input.action_press("move_forward")
	elif _frames == 770:
		Input.action_release("move_forward")
		if absf(_player.global_position.z - 78.0) < 1.0:
			_fail("昼夜系统启用后玩家无法移动 pos=%s" % str(_player.global_position))
		else:
			print("OK   玩家探索仍正常 z=%.1f" % _player.global_position.z)
		# env_day.tres 未被污染
		var disk: Environment = load("res://materials/env_day.tres")
		if disk.sky.sky_material.sky_top_color != Color(0.255, 0.49, 0.804, 1.0):
			_fail("res://materials/env_day.tres 被运行期修改污染 %s" % str(disk.sky.sky_material.sky_top_color))
		else:
			print("OK   env_day.tres 未被运行期修改污染")
		print("=== RESULT ===")
		if _fails.is_empty():
			print("TASK02_VERIFY_PASS")
		else:
			for f in _fails:
				print("FAIL: %s" % f)
			print("TASK02_VERIFY_FAIL")
		quit(0 if _fails.is_empty() else 2)
		return true
	return false


func _fail(msg: String) -> void:
	_fails.append(msg)
	print("FAIL: %s" % msg)
