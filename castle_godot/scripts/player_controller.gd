extends CharacterBody3D
class_name PlayerController
## player_controller.gd
## 玩家探索控制器：第一人称 / 第三人称共用同一个 CharacterBody3D。
##
## 职责：
##   - WASD 移动、Shift 冲刺、Space 跳跃、重力、鼠标视角
##   - 提供当前激活相机的访问口，供交互射线（RayCast3D）使用
##   - 被 camera_mode_manager.gd 启用 / 停用（展示环绕模式下完全冻结）
##
## 说明：镜头模式（1 展示 / 2 第一人称 / 3 第三人称）由 camera_mode_manager.gd 统一切换，
##       本脚本只负责"玩家这一侧"的行为。

enum CameraMode {
	FIRST_PERSON, ## 第一人称：相机位于头部
	THIRD_PERSON, ## 第三人称：相机挂在 SpringArm3D 末端
}

@export_group("Movement")
## 常规行走速度（单位/秒）
@export var walk_speed: float = 18.0
## 冲刺速度（按住 Shift，单位/秒）
@export var sprint_speed: float = 40.0
## 跳跃初速度
@export var jump_velocity: float = 13.0
## 重力缩放（乘以工程重力 9.8）
@export var gravity_scale: float = 2.0
## 地面加速度（越大越跟手）
@export var ground_acceleration: float = 12.0
## 空中加速度
@export var air_acceleration: float = 2.5
## 掉落到该高度以下视为"坠落"，自动复位到出生点
@export var fall_limit_y: float = -60.0

@export_group("Look")
## 鼠标灵敏度
@export var mouse_sensitivity: float = 0.0030
## 俯仰下限 / 上限（度）
@export var pitch_min_deg: float = -85.0
@export var pitch_max_deg: float = 85.0

@export_group("Camera & Ray Nodes")
## 头部节点（承载相机与俯仰）
@export var head_path: NodePath = ^"Head"
## 第一人称相机
@export var first_person_camera_path: NodePath = ^"Head/Camera3D"
## 第三人称弹簧臂
@export var third_person_arm_path: NodePath = ^"Head/SpringArm3D"
## 第三人称相机（SpringArm3D 的子节点）
@export var third_person_camera_path: NodePath = ^"Head/SpringArm3D/Camera3D"
## 交互射线（由 interaction_controller 读取）
@export var interact_ray_path: NodePath = ^"InteractRay"
## 交互射线长度
@export var interact_distance: float = 9.0

## 当前相机模式
var camera_mode: int = CameraMode.FIRST_PERSON
## 是否处于"玩家操控"状态（展示环绕模式下为 false）
var active: bool = false
## 出生点（坠落复位用）
var respawn_point: Vector3 = Vector3.ZERO

var _head: Node3D
var _fp_camera: Camera3D
var _arm: SpringArm3D
var _tp_camera: Camera3D
var _ray: RayCast3D
var _pitch: float = 0.0


func _ready() -> void:
	add_to_group("player")
	_head = get_node_or_null(head_path) as Node3D
	_fp_camera = get_node_or_null(first_person_camera_path) as Camera3D
	_arm = get_node_or_null(third_person_arm_path) as SpringArm3D
	_tp_camera = get_node_or_null(third_person_camera_path) as Camera3D
	_ray = get_node_or_null(interact_ray_path) as RayCast3D
	respawn_point = global_position
	set_active(false)


## 启用 / 停用玩家（停用时冻结物理与输入，避免与展示环绕抢相机）
func set_active(value: bool) -> void:
	active = value
	set_physics_process(value)
	set_process(value)
	set_process_input(value)
	if not value:
		velocity = Vector3.ZERO
	_apply_camera_mode()


## 切换第一 / 第三人称（由 camera_mode_manager 调用）
func set_camera_mode(mode: int) -> void:
	camera_mode = mode
	_apply_camera_mode()


## 当前用于渲染的相机
func get_active_camera() -> Camera3D:
	if camera_mode == CameraMode.THIRD_PERSON and _tp_camera != null:
		return _tp_camera
	return _fp_camera


## 交互射线节点（RayCast3D）
func get_interact_ray() -> RayCast3D:
	return _ray


## 瞬移（出生 / 复位）
func teleport_to(target: Vector3) -> void:
	global_position = target
	velocity = Vector3.ZERO
	_pitch = 0.0
	if _head != null:
		_head.rotation.x = 0.0


func _apply_camera_mode() -> void:
	if _fp_camera != null:
		_fp_camera.current = active and camera_mode == CameraMode.FIRST_PERSON
	if _tp_camera != null:
		_tp_camera.current = active and camera_mode == CameraMode.THIRD_PERSON


func _process(_delta: float) -> void:
	_update_interact_ray()


func _update_interact_ray() -> void:
	if _ray == null:
		return
	var cam: Camera3D = get_active_camera()
	if cam == null:
		return
	_ray.global_transform = cam.global_transform
	_ray.target_position = Vector3(0.0, 0.0, -interact_distance)
	_ray.force_raycast_update()


func _input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		apply_look((event as InputEventMouseMotion).relative)


## 应用一次鼠标位移到视角（水平 = 偏航，垂直 = 俯仰并夹紧）。
## 独立成公开方法，便于 headless 自动化验证（无显示服务器时鼠标无法进入捕获态）。
func apply_look(relative: Vector2) -> void:
	rotate_y(-relative.x * mouse_sensitivity)
	_pitch = clampf(
		_pitch - relative.y * mouse_sensitivity,
		deg_to_rad(pitch_min_deg),
		deg_to_rad(pitch_max_deg)
	)
	if _head != null:
		_head.rotation.x = _pitch


## 当前俯仰角（弧度），供 HUD / 自动化验证读取
func get_pitch() -> float:
	return _pitch


func _physics_process(delta: float) -> void:
	var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	if not is_on_floor():
		velocity.y -= gravity * gravity_scale * delta

	if is_on_floor() and Input.is_action_pressed("jump"):
		velocity.y = jump_velocity

	var input_dir := _read_move_input()
	var basis := global_transform.basis
	var direction := (basis.x * input_dir.x + basis.z * input_dir.y)
	direction.y = 0.0
	if direction.length_squared() > 0.0:
		direction = direction.normalized()

	var speed := sprint_speed if Input.is_action_pressed("sprint") else walk_speed
	var accel := ground_acceleration if is_on_floor() else air_acceleration
	var blend: float = clampf(accel * delta, 0.0, 1.0)
	velocity.x = lerpf(velocity.x, direction.x * speed, blend)
	velocity.z = lerpf(velocity.z, direction.z * speed, blend)

	move_and_slide()

	if global_position.y < fall_limit_y:
		teleport_to(respawn_point)


func _read_move_input() -> Vector2:
	var dir := Vector2.ZERO
	if Input.is_action_pressed("move_forward"):
		dir.y -= 1.0
	if Input.is_action_pressed("move_backward"):
		dir.y += 1.0
	if Input.is_action_pressed("move_left"):
		dir.x -= 1.0
	if Input.is_action_pressed("move_right"):
		dir.x += 1.0
	return dir.limit_length(1.0)
