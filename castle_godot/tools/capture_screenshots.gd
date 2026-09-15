extends SceneTree
## tools/capture_screenshots.gd
## TASK06 交付截图采集脚本（必须非 headless 运行，需要真实渲染后端）：
##   /path/to/Godot --path . --script res://tools/capture_screenshots.gd
##
## 依次生成 docs/screenshots/ 下四张截图：
##   01_day_exploration.png  白天第一人称探索（前庭望向城堡）
##   02_night_castle.png     夜景城堡（展示环绕机位，仅靠窗户自发光）
##   03_fireworks.png        夜间烟花齐射
##   04_performance_hud.png  性能 HUD + MEDIUM 画质档第一人称

const MAIN_SCENE := "res://scenes/main.tscn"
const OUT_DIR := "res://docs/screenshots"

const VIEW_POS := Vector3(0.0, 2.0, 88.0)
const VIEW_PITCH_DEG := 17.0

var _scene: Node
var _player: PlayerController
var _camera_mgr: Node
var _env_mgr: Node
var _fireworks: Node
var _perf_hud: Node
var _quality: Node

var _shots: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	print("=== TASK06 交付截图采集（真实渲染） ===")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	var packed := load(MAIN_SCENE) as PackedScene
	if packed == null:
		print("FAIL 主场景加载失败：%s" % MAIN_SCENE)
		quit(1)
		return

	_scene = packed.instantiate()
	root.add_child(_scene)
	await _frames(5)

	_player = _scene.get_node_or_null("Player") as PlayerController
	_camera_mgr = _scene.get_node_or_null("CameraModeManager")
	_env_mgr = _scene.get_node_or_null("EnvironmentManager")
	_fireworks = _scene.get_node_or_null("Fireworks")
	_perf_hud = _scene.get_node_or_null("PerformanceHud")
	_quality = _scene.get_node_or_null("QualityManager")

	if _player == null or _camera_mgr == null or _env_mgr == null:
		print("FAIL 关键节点缺失")
		quit(1)
		return

	await _frames(60)  # 等材质 / 着色器 / 环境资源就绪
	print("[shot] 场景就绪，开始采集")

	# ------------------------------------------------ 01 白天第一人称探索
	_press(KEY_F1)
	await _frames(30)
	print("[shot] 环境预设 = %s" % String(_env_mgr.call("get_preset_name")))
	await _enter_first_person()
	await _frames(45)
	await _shoot("01_day_exploration.png")

	# ------------------------------------------------ 02 夜景城堡（展示机位）
	_camera_mgr.call("set_mode", 1)
	_scene.set("camera_orbit_speed", 0.0)  # 冻结环绕，保证机位稳定可复现
	_press(KEY_F3)
	await _frames(280)  # 等夜景过渡（窗光 / 天空 / 曝光）完全落定
	print("[shot] 环境预设 = %s，night_factor=%.2f" % [
		String(_env_mgr.call("get_preset_name")),
		float(_env_mgr.call("get_night_factor"))
	])
	await _shoot("02_night_castle.png")

	# ------------------------------------------------ 03 夜间烟花
	if _fireworks != null:
		_fireworks.call("set_enabled", true)
		await _frames(20)
		_fireworks.call("fire_burst_now")  # 四个发射位同时开火（one_shot，粒子寿命 2.4s）
		await _frames(32)  # 约 0.5s：花球正在绽放
		print("[shot] 烟花：emitting=%d / %d 个系统，fired_total=%d" % [
			int(_fireworks.call("get_emitting_count")),
			int(_fireworks.call("get_system_count")),
			int(_fireworks.call("get_fired_total"))
		])
		await _shoot("03_fireworks.png")
		_fireworks.call("set_enabled", false)
		await _frames(20)
	else:
		print("FAIL 未找到 Fireworks 节点")

	# ------------------------------------------------ 04 性能 HUD
	_camera_mgr.call("set_mode", 2)
	await _frames(10)
	_press(KEY_F1)
	_press(KEY_8)  # MEDIUM 档
	await _frames(10)
	if _perf_hud != null and not bool(_perf_hud.call("is_shown")):
		_perf_hud.call("toggle")
	await _enter_first_person()
	await _frames(40)  # 等 HUD 刷新（0.25s 间隔）
	print("[shot] 画质档 = %s | 性能 HUD = %s" % [
		String(_quality.call("get_level_name")) if _quality != null else "?",
		str(bool(_perf_hud.call("is_shown"))) if _perf_hud != null else "?"
	])
	await _shoot("04_performance_hud.png")

	print("=== 截图完成：%d 张 ===" % _shots)
	quit(0)


# ---------------------------------------------------------------------------
# 机位控制
# ---------------------------------------------------------------------------

func _enter_first_person() -> void:
	_camera_mgr.call("set_mode", 2)  # 玩家激活（会先放到出生点）
	await _frames(5)
	_player.teleport_to(VIEW_POS)
	var head := _player.get_node_or_null("Head") as Node3D
	_player.rotation.y = 0.0  # 面朝 -Z，即城堡方向
	if head != null:
		head.rotation.x = deg_to_rad(VIEW_PITCH_DEG)
	await _physics(45)


func _shoot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var tex := root.get_texture()
	if tex == null:
		print("FAIL 无法获取根视口纹理（渲染后端未启动？）")
		return
	var img := tex.get_image()
	if img == null:
		print("FAIL 截图为空：%s" % file_name)
		return
	var path: String = OUT_DIR + "/" + file_name
	var err := img.save_png(path)
	_shots += 1
	print("  [shot] %s -> err=%d size=%dx%d" % [file_name, err, img.get_width(), img.get_height()])


# ---------------------------------------------------------------------------
# 小工具
# ---------------------------------------------------------------------------

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


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _physics(n: int) -> void:
	for i in n:
		await physics_frame
