extends SceneTree
## tools/benchmark.gd
## TASK05 基准测试脚本（真实渲染，非 headless）：
##   场景 × 画质档 矩阵采样，输出每组的 average_fps / minimum_fps / 1% low / average_frame_ms
##   以及 Draw Call、对象数、节点数、静态内存等旁证指标。
##
## 场景：
##   1. DAY + Showcase          —— 白天展示环绕
##   2. NIGHT + Showcase        —— 夜晚展示环绕（含夜景灯）
##   3. NIGHT + Fireworks       —— 夜晚 + 烟花齐射
##   4. Player Exploration      —— 第一人称实走探索（真实按下 W 前进）
##
## 档位：
##   LOW / MEDIUM / HIGH（对应 7 / 8 / 9，默认 MEDIUM）
##
## 用法（必须带窗口，否则只能测到 headless 空转）：
##   Godot --path . --resolution 1600x900 --script res://tools/benchmark.gd
##
## 结果写入：res://docs/benchmark_results.json，并在 stdout 打印表格与 JSON。
## 退出码 0 = 全部跑完。

const MAIN_SCENE := "res://scenes/main.tscn"
const OUT_JSON := "res://docs/benchmark_results.json"

## 采样参数（秒）
const WARMUP_SECONDS := 1.6
const SAMPLE_SECONDS := 5.0

## 探索场景每个走路 tick（0.25s）的转角（度）。固定 6°/tick，
## 保证 LOW / MEDIUM / HIGH 三轮走出完全相同的轨迹与朝向，结果才可比。
const WALK_TURN_PER_TICK_DEG := 6.0
const WALK_TICK_SECONDS := 0.25

const LEVELS: Array[int] = [0, 1, 2]

const SCENARIOS: Array[Dictionary] = [
	{"key": "DAY_SHOWCASE", "label": "DAY + Showcase", "mode": 1, "preset": "DAY", "fireworks": false, "walk": false},
	{"key": "NIGHT_SHOWCASE", "label": "NIGHT + Showcase", "mode": 1, "preset": "NIGHT", "fireworks": false, "walk": false},
	{"key": "NIGHT_FIREWORKS", "label": "NIGHT + Fireworks", "mode": 1, "preset": "NIGHT", "fireworks": true, "walk": false},
	{"key": "PLAYER_EXPLORATION", "label": "Player Exploration", "mode": 2, "preset": "DAY", "fireworks": false, "walk": true},
]

var _scene: Node = null
var _quality: Node = null
var _env_mgr: Node = null
var _fireworks: Node = null
var _camera_mode: Node = null
var _player: Node3D = null
var _spawn := Vector3.ZERO
var _runs: Array[Dictionary] = []


func _initialize() -> void:
	_run.call_deferred()


# ---------------------------------------------------------------------------
# 工具
# ---------------------------------------------------------------------------

func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _seconds(s: float) -> void:
	await create_timer(s).timeout


func _wait_night(target: float, timeout: float = 8.0) -> float:
	var elapsed := 0.0
	while elapsed < timeout:
		var f: float = float(_env_mgr.call("get_night_factor"))
		if absf(f - target) <= 0.02:
			return f
		await create_timer(0.05).timeout
		elapsed += 0.05
	return float(_env_mgr.call("get_night_factor"))


func _monitor(key: int) -> float:
	return Performance.get_monitor(key)


func _machine_info() -> Dictionary:
	var mem := OS.get_memory_info()
	var info := {
		"machine_label": "Mac mini non-TV",
		"os": OS.get_name() + " " + OS.get_version(),
		"processor": OS.get_processor_name(),
		"cpu_count": OS.get_processor_count(),
		"memory_total_mb": int(round(float(mem.get("physical", 0)) / 1048576.0)),
		"gpu": RenderingServer.get_video_adapter_name(),
		"gpu_api": RenderingServer.get_video_adapter_api_version(),
		"driver": "Vulkan" if RenderingServer.get_rendering_device() != null else "opengl/other",
	}
	return info


func _godot_info() -> Dictionary:
	var v := Engine.get_version_info()
	var size := DisplayServer.window_get_size()
	return {
		"version": String(v["string"]),
		"major": int(v["major"]),
		"minor": int(v["minor"]),
		"patch": int(v["patch"]),
		"renderer": ProjectSettings.get_setting("rendering/renderer/rendering_method", "unknown"),
		"resolution": [size.x, size.y],
		# 实测值：window_get_vsync_mode 与 Engine.max_fps，避免写死结论
		"vsync_mode": DisplayServer.window_get_vsync_mode(),
		"vsync_enabled": DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED,
		"max_fps": Engine.max_fps,
		"refresh_rate_hz": DisplayServer.screen_get_refresh_rate(),
	}


# ---------------------------------------------------------------------------
# 场景配置
# ---------------------------------------------------------------------------

func _configure(scenario: Dictionary, scenario_index: int) -> void:
	_env_mgr.call("set_auto_cycle", false)
	_camera_mode.call("set_mode", int(scenario["mode"]))
	_env_mgr.call("set_preset_by_name", String(scenario["preset"]))
	_fireworks.call("set_enabled", bool(scenario["fireworks"]))
	if bool(scenario["walk"]):
		_reset_player_heading(0.0)
	if int(scenario["mode"]) == 1 and _scene.has_method("set_orbit_angle"):
		# 展示模式：把环绕相位错开，避免每个场景都停在同一个角度
		_scene.call("set_orbit_angle", float(scenario_index) * 47.0)
	var target := 1.0 if String(scenario["preset"]) == "NIGHT" else 0.0
	await _wait_night(target)
	if bool(scenario["fireworks"]):
		# 等至少一轮齐射真正打上去
		var waited := 0.0
		while float(_fireworks.call("get_fired_total")) < 4.0 and waited < 8.0:
			await create_timer(0.1).timeout
			waited += 0.1


## 把玩家复位到出生点并把朝向（yaw）显式设为 yaw_deg 度。
## teleport_to 只复位位置与俯仰、不复位 yaw，若不在每轮开始时显式重置，
## LOW 轮的转向会残留到 MEDIUM / HIGH 轮，导致三轮取样画面完全不同、结果不可比。
func _reset_player_heading(yaw_deg: float) -> void:
	_player.call("teleport_to", _spawn)
	var sens := float(_player.get("mouse_sensitivity"))
	if sens <= 0.0:
		return
	# apply_look(Vector2(x, 0)) 内部执行 rotate_y(-x * mouse_sensitivity)
	var delta := deg_to_rad(yaw_deg) - _player.global_rotation.y
	_player.call("apply_look", Vector2(-delta / sens, 0.0))


func _walk_tick() -> void:
	var sens := float(_player.get("mouse_sensitivity"))
	if sens > 0.0:
		# 每 tick 左转固定角度：走一条可复现的圆弧，且始终把城堡留在视野内
		_player.call("apply_look", Vector2(-deg_to_rad(WALK_TURN_PER_TICK_DEG) / sens, 0.0))
	var p: Vector3 = _player.global_position
	if p.z < -40.0 or p.z > 120.0 or absf(p.x) > 90.0:
		_player.call("teleport_to", _spawn)


# ---------------------------------------------------------------------------
# 采样
# ---------------------------------------------------------------------------

func _sample(scenario: Dictionary, seconds: float) -> Dictionary:
	var frame_ms: Array[float] = []
	var draw_calls: Array[float] = []
	var objects: Array[float] = []
	var primitives: Array[float] = []
	var firing := bool(scenario["fireworks"])
	var walking := bool(scenario["walk"])
	var fired_before := float(_fireworks.call("get_fired_total"))
	if walking:
		Input.action_press("move_forward")
	var walk_accum := 0.0
	var start := Time.get_ticks_usec()
	var last := start
	var elapsed := 0.0
	while elapsed < seconds:
		await process_frame
		var now := Time.get_ticks_usec()
		frame_ms.append(float(now - last) / 1000.0)
		last = now
		elapsed = float(now - start) / 1000000.0
		draw_calls.append(_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		objects.append(_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
		primitives.append(_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		if walking:
			walk_accum += frame_ms[-1] / 1000.0
			if walk_accum >= 0.25:
				walk_accum = 0.0
				_walk_tick()
	if walking:
		Input.action_release("move_forward")

	var fired_after := float(_fireworks.call("get_fired_total"))
	var worst := 0.0
	for ms in frame_ms:
		worst = maxf(worst, ms)
	var sorted: Array[float] = frame_ms.duplicate()
	sorted.sort()
	var idx_1pct := clampi(int(floor(float(sorted.size()) * 0.99)), 0, maxi(sorted.size() - 1, 0))
	var p99_ms: float = sorted[idx_1pct] if sorted.size() > 0 else 0.0
	var measured := float(elapsed)
	return {
		"frames": frame_ms.size(),
		"avg_frame_ms": _avg(frame_ms),
		"max_frame_ms": worst,
		"p99_frame_ms": p99_ms,
		"average_fps": float(frame_ms.size()) / measured if measured > 0.0 else 0.0,
		"minimum_fps": (1000.0 / worst) if worst > 0.0 else 0.0,
		"fps_1pct_low": (1000.0 / p99_ms) if p99_ms > 0.0 else 0.0,
		"avg_draw_calls": _avg(draw_calls),
		"avg_objects": _avg(objects),
		"avg_primitives": _avg(primitives),
		"nodes": int(_monitor(Performance.OBJECT_NODE_COUNT)),
		"static_memory_mb": _monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"night_factor": float(_env_mgr.call("get_night_factor")),
		"fireworks_enabled": bool(_fireworks.call("is_enabled")),
		"fireworks_fired_delta": int(fired_after - fired_before),
		"player_pos": str(_player.global_position.snapped(Vector3(0.1, 0.1, 0.1))),
		"player_yaw_deg": snappedf(rad_to_deg(_player.global_rotation.y), 0.1),
	}


func _avg(arr: Array[float]) -> float:
	if arr.is_empty():
		return 0.0
	var s := 0.0
	for v in arr:
		s += v
	return s / float(arr.size())


# ---------------------------------------------------------------------------
# 主流程
# ---------------------------------------------------------------------------

func _run() -> void:
	print("=== TASK05 基准测试（真实渲染）===")
	_scene = load(MAIN_SCENE).instantiate()
	root.add_child(_scene)
	await _frames(10)
	await _seconds(1.0)

	_quality = _scene.get_node_or_null("QualityManager")
	_env_mgr = _scene.get_node_or_null("EnvironmentManager")
	_fireworks = _scene.get_node_or_null("Fireworks")
	_camera_mode = _scene.get_node_or_null("CameraModeManager")
	_player = _scene.get_node_or_null("Player") as Node3D
	var spawn_node := _scene.get_node_or_null("PlayerSpawn") as Node3D
	_spawn = spawn_node.global_position if spawn_node != null else _player.global_position

	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	var machine := _machine_info()
	var godot := _godot_info()
	print("Machine: %s | %s | %s" % [machine["machine_label"], machine["processor"], machine["os"]])
	print("GPU: %s (%s)" % [machine["gpu"], machine["gpu_api"]])
	print("Godot: %s | renderer=%s | resolution=%s | vsync=%s(void=%d) | max_fps=%d | screen=%d Hz" % [
		godot["version"], godot["renderer"], str(godot["resolution"]),
		"ON" if bool(godot["vsync_enabled"]) else "OFF",
		int(godot["vsync_mode"]), int(godot["max_fps"]), int(round(float(godot["refresh_rate_hz"]))),
	])
	print("")

	for scenario_index in SCENARIOS.size():
		var scenario: Dictionary = SCENARIOS[scenario_index]
		for level in LEVELS:
			_quality.call("set_level", level)
			await _configure(scenario, scenario_index)
			await _seconds(WARMUP_SECONDS)
			var res := await _sample(scenario, SAMPLE_SECONDS)
			res["scenario"] = String(scenario["key"])
			res["scenario_label"] = String(scenario["label"])
			res["level"] = level
			res["level_name"] = String(_quality.call("get_level_name"))
			_runs.append(res)
			print("[%s × %s] avg=%.1f fps  min=%.1f fps  1%%low=%.1f fps  frame=%.2f ms  draw=%.0f  obj=%.0f  nodes=%d" % [
				String(scenario["label"]),
				String(res["level_name"]),
				float(res["average_fps"]),
				float(res["minimum_fps"]),
				float(res["fps_1pct_low"]),
				float(res["avg_frame_ms"]),
				float(res["avg_draw_calls"]),
				float(res["avg_objects"]),
				int(res["nodes"]),
			])

	# 复位到默认档与白天展示
	_quality.call("set_level", 1)
	_camera_mode.call("set_mode", 1)
	_env_mgr.call("set_preset_by_name", "DAY")
	_fireworks.call("set_enabled", false)

	var payload := {
		"machine": machine,
		"godot": godot,
		"sample_seconds": SAMPLE_SECONDS,
		"warmup_seconds": WARMUP_SECONDS,
		"levels": {"0": "LOW", "1": "MEDIUM", "2": "HIGH"},
		"runs": _runs,
	}
	var json := JSON.stringify(payload, "  ")
	var f := FileAccess.open(OUT_JSON, FileAccess.WRITE)
	if f != null:
		f.store_string(json)
		f.close()
		print("")
		print("结果已写入 %s" % OUT_JSON)
	else:
		print("[ERROR] 无法写入 %s" % OUT_JSON)

	print("")
	print("---JSON-BEGIN---")
	print(json)
	print("---JSON-END---")
	print("=== 基准测试完成：%d 组 ===" % _runs.size())
	quit(0)
