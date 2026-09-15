extends Node
class_name PresentationController
## presentation_controller.gd
## 演示模式（F6）：一键把项目切到"给人看的城堡夜景"。
##
## 进入时自动：
##   1. 环境切到 NIGHT（并关闭自动昼夜，避免演示途中天亮）
##   2. 打开烟花
##   3. 切到展示相机（Showcase）并改用缓慢环绕速度
## 再次 F6 退出，并还原进入前的环境预设 / 自动昼夜 / 环绕速度。
##
## 所有外部依赖都用 NodePath 暴露，缺哪个就跳过哪一步，不会因为节点缺失崩溃。

@export_group("Node References")
@export var environment_manager_path: NodePath = ^"../EnvironmentManager"
@export var fireworks_path: NodePath = ^"../Fireworks"
@export var camera_mode_manager_path: NodePath = ^"../CameraModeManager"
@export var showcase_root_path: NodePath = ^".."

@export_group("Presentation")
## 进入演示模式时切换到的环境预设（0=DAY 1=SUNSET 2=NIGHT）
@export_range(0, 2, 1) var enter_preset: int = 2
## 演示模式的环绕速度（度/秒），要"缓慢"
@export_range(0.0, 30.0, 0.1) var orbit_speed: float = 3.0
## 是否在进入时打开烟花
@export var enable_fireworks: bool = true
## 启动即进入演示模式
@export var start_active: bool = false

var _env_mgr: Node = null
var _fireworks: Node = null
var _camera_mgr: Node = null
var _showcase: Node = null

var _active: bool = false
var _prev_preset_name: String = ""
var _prev_auto_cycle: bool = false
var _prev_orbit_speed: float = 0.0
var _prev_camera_mode: int = CameraModeManager.Mode.SHOWCASE


func _ready() -> void:
	add_to_group("presentation")
	_env_mgr = get_node_or_null(environment_manager_path)
	_fireworks = get_node_or_null(fireworks_path)
	_camera_mgr = get_node_or_null(camera_mode_manager_path)
	_showcase = get_node_or_null(showcase_root_path)
	_refresh_hud()
	if start_active:
		set_presentation(true)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("presentation_mode"):
		set_presentation(not _active)


# ---------------------------------------------------------------------------
# 公开接口
# ---------------------------------------------------------------------------

func set_presentation(value: bool) -> void:
	if value == _active:
		return
	if value:
		_enter()
	else:
		_exit()
	_active = value
	_refresh_hud()


func toggle() -> void:
	set_presentation(not _active)


func is_active() -> bool:
	return _active


## 演示模式下的目标环绕速度（验证脚本用）
func get_orbit_speed() -> float:
	return orbit_speed


func get_previous_preset_name() -> String:
	return _prev_preset_name


# ---------------------------------------------------------------------------
# 内部
# ---------------------------------------------------------------------------

func _enter() -> void:
	# 1) 环境：记录原状态 → NIGHT + 关自动昼夜
	if _camera_mgr != null and _camera_mgr.get("current_mode") != null:
		_prev_camera_mode = int(_camera_mgr.get("current_mode"))
	if _env_mgr != null:
		if _env_mgr.has_method("get_preset_name"):
			_prev_preset_name = String(_env_mgr.call("get_preset_name"))
		if _env_mgr.has_method("is_auto_cycle"):
			_prev_auto_cycle = bool(_env_mgr.call("is_auto_cycle"))
		if _env_mgr.has_method("set_auto_cycle"):
			_env_mgr.call("set_auto_cycle", false)
		if _env_mgr.has_method("set_preset"):
			_env_mgr.call("set_preset", enter_preset)
	# 2) 烟花
	if enable_fireworks:
		_set_fireworks(true)
	# 3) 展示相机 + 缓慢环绕
	if _showcase != null and _showcase.get("camera_orbit_speed") != null:
		_prev_orbit_speed = float(_showcase.get("camera_orbit_speed"))
	if _camera_mgr != null and _camera_mgr.has_method("set_mode"):
		_camera_mgr.call("set_mode", CameraModeManager.Mode.SHOWCASE)
	if _showcase != null and _showcase.get("camera_orbit_speed") != null:
		_showcase.set("camera_orbit_speed", orbit_speed)


func _exit() -> void:
	# 0) 还原镜头模式（演示前若在探索模式，退出后回到探索）
	if _camera_mgr != null and _prev_camera_mode != CameraModeManager.Mode.SHOWCASE:
		if _camera_mgr.has_method("set_mode"):
			_camera_mgr.call("set_mode", _prev_camera_mode)
	# 1) 还原环绕速度
	if _showcase != null and _showcase.get("camera_orbit_speed") != null:
		_showcase.set("camera_orbit_speed", _prev_orbit_speed)
	# 2) 关烟花
	_set_fireworks(false)
	# 3) 还原环境
	if _env_mgr != null:
		if _prev_preset_name != "" and _env_mgr.has_method("set_preset_by_name"):
			_env_mgr.call("set_preset_by_name", _prev_preset_name)
		if _env_mgr.has_method("set_auto_cycle"):
			_env_mgr.call("set_auto_cycle", _prev_auto_cycle)


func _set_fireworks(value: bool) -> void:
	if _fireworks == null or not _fireworks.has_method("set_enabled"):
		return
	_fireworks.call("set_enabled", value)


func _refresh_hud() -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("set_presentation_status"):
		hud.call("set_presentation_status", _active)
