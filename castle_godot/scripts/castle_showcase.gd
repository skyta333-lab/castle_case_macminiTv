extends Node3D
## castle_showcase.gd
## 童话城堡展示场景的根节点脚本。
## 负责：初始化相机环绕参数、对齐相机朝向、打印场景自检信息。
## 所有可调参数均已用 @export 暴露，可在编辑器检查器中直接修改。

@export_group("Camera")
## 相机距场景中心的水平距离
@export var camera_distance: float = 260.0
## 相机高度
@export var camera_height: float = 95.0
## 相机注视点高度（城堡主体大约在 0~88 之间）
@export var camera_focus_height: float = 38.0
## 环绕速度（度/秒），0 表示静止不环绕
@export var camera_orbit_speed: float = 6.0
## 相机初始方位角（度）
@export var camera_start_angle: float = 35.0

@export_group("Sun")
## 阳光方位角环绕速度（度/秒），0 表示静止
@export var sun_orbit_speed: float = 0.0

@onready var _camera: Camera3D = $MainCamera
@onready var _sun: DirectionalLight3D = $SunLight
@onready var _castle: Node3D = $Castle

var _orbit_angle: float = 0.0


func _ready() -> void:
	_orbit_angle = camera_start_angle
	_apply_camera()
	print("[castle_godot] scene ready | castle loaded: %s" % str(_castle != null))
	var box: AABB = _world_aabb(_castle)
	print("[castle_godot] castle world AABB size = %s , center = %s" % [str(box.size), str(box.get_center())])


## 递归合并节点下所有 VisualInstance3D 的世界空间 AABB
func _world_aabb(node: Node) -> AABB:
	var out: AABB = AABB()
	var first: bool = true
	for visual in _collect_visuals(node):
		var box: AABB = visual.global_transform * visual.get_aabb()
		out = box if first else out.merge(box)
		first = false
	return out


func _collect_visuals(node: Node) -> Array:
	var out: Array = []
	if node is VisualInstance3D:
		out.append(node)
	for child in node.get_children():
		out.append_array(_collect_visuals(child))
	return out


func _process(delta: float) -> void:
	if camera_orbit_speed != 0.0:
		_orbit_angle = fmod(_orbit_angle + camera_orbit_speed * delta, 360.0)
		_apply_camera()
	if sun_orbit_speed != 0.0 and _sun != null:
		_sun.rotate_y(deg_to_rad(sun_orbit_speed * delta))


## 直接设置当前环绕方位角（度）并立即生效。
## 供基准脚本 / 演示模式用于把不同场景的环绕相位错开，避免画面重复。
func set_orbit_angle(deg: float) -> void:
	_orbit_angle = fmod(deg, 360.0)
	_apply_camera()


## 当前环绕方位角（度）
func get_orbit_angle() -> float:
	return _orbit_angle


func _apply_camera() -> void:
	if _camera == null:
		return
	var rad: float = deg_to_rad(_orbit_angle)
	_camera.global_position = Vector3(sin(rad) * camera_distance, camera_height, cos(rad) * camera_distance)
	_camera.look_at(Vector3(0.0, camera_focus_height, 0.0), Vector3.UP)
