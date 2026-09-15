extends Node
class_name CameraModeManager
## camera_mode_manager.gd
## 统一管理三种镜头模式，并负责鼠标捕获 / 释放：
##   1 = 展示环绕（保留原有 castle_showcase.gd 的自动环绕，默认模式）
##   2 = 第一人称探索
##   3 = 第三人称探索
##
## 设计要点：不改动 castle_showcase.gd 的原有逻辑，只在切换模式时把它的
## camera_orbit_speed 置 0（暂停环绕）或还原（恢复环绕）。

enum Mode {
	SHOWCASE = 1,
	FIRST_PERSON = 2,
	THIRD_PERSON = 3,
}

signal mode_changed(mode: int)

@export_group("Startup")
## 启动时进入的镜头模式
@export var start_mode: Mode = Mode.SHOWCASE

@export_group("Node References")
## 展示场景根节点（挂 castle_showcase.gd，用于暂停/恢复环绕）
@export var showcase_root_path: NodePath = ^".."
## 展示环绕相机
@export var showcase_camera_path: NodePath = ^"../MainCamera"
## 玩家节点
@export var player_path: NodePath = ^"../Player"
## 玩家出生点
@export var spawn_path: NodePath = ^"../PlayerSpawn"

var current_mode: int = Mode.SHOWCASE

var _showcase_root: Node = null
var _showcase_camera: Camera3D = null
var _player: PlayerController = null
var _spawn: Node3D = null
var _showcase_orbit_speed: float = 0.0


func _ready() -> void:
	add_to_group("camera_mode_manager")
	_showcase_root = get_node_or_null(showcase_root_path)
	_showcase_camera = get_node_or_null(showcase_camera_path) as Camera3D
	_player = get_node_or_null(player_path) as PlayerController
	_spawn = get_node_or_null(spawn_path) as Node3D
	if _showcase_root != null and _showcase_root.get("camera_orbit_speed") != null:
		_showcase_orbit_speed = float(_showcase_root.get("camera_orbit_speed"))
	if _player != null and _spawn != null:
		_player.respawn_point = _spawn.global_position
		_player.teleport_to(_spawn.global_position)
	set_mode(start_mode)


func set_mode(mode: int) -> void:
	current_mode = mode
	var use_player: bool = mode != Mode.SHOWCASE

	# 1) 展示环绕：玩家模式下暂停环绕并让出相机
	if _showcase_root != null and _showcase_root.has_method("get"):
		if _showcase_root.get("camera_orbit_speed") != null:
			_showcase_root.set("camera_orbit_speed", 0.0 if use_player else _showcase_orbit_speed)
	if _showcase_camera != null:
		_showcase_camera.current = not use_player

	# 2) 玩家：启用/停用并设置第一或第三人称
	if _player != null:
		if use_player:
			_player.set_camera_mode(
				PlayerController.CameraMode.THIRD_PERSON if mode == Mode.THIRD_PERSON
				else PlayerController.CameraMode.FIRST_PERSON
			)
			if _spawn != null:
				_player.respawn_point = _spawn.global_position
				_player.teleport_to(_spawn.global_position)
			_player.set_active(true)
			_capture_mouse()
		else:
			_player.set_active(false)
			_release_mouse()

	# 3) HUD
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("set_mode_name"):
		hud.set_mode_name(mode_display_name(mode))
	if hud != null and hud.has_method("set_crosshair_visible"):
		hud.set_crosshair_visible(use_player)

	mode_changed.emit(mode)


## 当前模式的中文/英文展示名
static func mode_display_name(mode: int) -> String:
	match mode:
		Mode.SHOWCASE:
			return "Showcase (1)"
		Mode.FIRST_PERSON:
			return "First-Person (2)"
		Mode.THIRD_PERSON:
			return "Third-Person (3)"
		_:
			return "Unknown"


## 供外部（演示模式 / 基准脚本）查询
func is_player_mode() -> bool:
	return current_mode != Mode.SHOWCASE


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("mode_showcase"):
		set_mode(Mode.SHOWCASE)
	elif event.is_action_pressed("mode_first_person"):
		set_mode(Mode.FIRST_PERSON)
	elif event.is_action_pressed("mode_third_person"):
		set_mode(Mode.THIRD_PERSON)
	elif event.is_action_pressed("toggle_mouse"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			_release_mouse()
		else:
			_capture_mouse()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED and is_player_mode():
			_capture_mouse()


func _capture_mouse() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _release_mouse() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
