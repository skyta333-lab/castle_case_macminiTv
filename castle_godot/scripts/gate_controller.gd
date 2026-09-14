extends Node3D
class_name GateController
## gate_controller.gd
## 城堡正门两扇门叶的开合动画（TASK03）。
##
## 背景（勘察结论）：
##   Blender 导出的 GLB 里，门叶是【可独立控制】的两个 MeshInstance3D：
##       Castle/Gate_Door_W  x -8.8 .. -2.8, y 4 .. 15, z 24.2 .. 25.0
##       Castle/Gate_Door_E  x  2.8 ..  8.8, y 4 .. 15, z 24.2 .. 25.0
##   二者分别以 x = ∓8.8（各自外缘）为铰链轴，绕世界 Y 轴向外（+Z，朝前庭）旋开。
##
## 实现要点：
##   - 全程【只改运行时 transform】，绝不修改 / 重导出 GLB，符合"禁止破坏 GLB"约束；
##   - 铰链位置在 _ready 时用门叶自身 AABB 在父空间下自动推算，模型微调后无需改代码；
##   - 旋转通过 Tween 驱动 _progress ∈ [0,1]，形成连续开合动画；
##   - 门叶没有碰撞体（GLB 原样导入），所以开门 / 关门都不会把玩家卡住。

## 西侧（左）门叶
@export var door_west_path: NodePath = ^"../../Castle/Gate_Door_W"
## 东侧（右）门叶
@export var door_east_path: NodePath = ^"../../Castle/Gate_Door_E"
## 完全打开时的旋转角度（度）
@export var open_angle_degrees: float = 95.0
## 完全开 / 关一次的耗时（秒）
@export var open_duration: float = 1.6
## 启动时是否自动处于打开状态
@export var auto_open_on_ready: bool = false

var _doors: Array[Node3D] = []
var _rest: Array[Transform3D] = []
var _hinges: Array[Vector3] = []
var _signs: Array[float] = []
var _progress: float = 0.0
var _tween: Tween
var _resolved := false


func _ready() -> void:
	_resolve_doors()
	_apply_progress(1.0 if auto_open_on_ready else 0.0)


## 门叶是否需要成功解析（模型缺少门叶时为 false）
func is_available() -> bool:
	return _doors.size() == 2


## 门是否处于打开状态
func is_open() -> bool:
	return _progress > 0.5


## 当前开合进度 0..1
func get_progress() -> float:
	return _progress


## 打开 / 关闭一次
func set_open(value: bool) -> void:
	_resolve_doors()
	if _doors.is_empty():
		return
	var target: float = 1.0 if value else 0.0
	if is_equal_approx(_progress, target):
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	var distance: float = absf(target - _progress)
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_method(_apply_progress, _progress, target, maxf(0.05, open_duration * distance))


## 开 <-> 关
func toggle() -> void:
	set_open(not is_open())


func get_door_node(side: String) -> Node3D:
	var index := 0 if side == "west" else 1
	return _doors[index] if index < _doors.size() else null


# ---------------------------------------------------------------------------

func _resolve_doors() -> void:
	if _resolved:
		return
	_resolved = true
	_register(get_node_or_null(door_west_path) as Node3D, -1.0)
	_register(get_node_or_null(door_east_path) as Node3D, 1.0)
	if _doors.is_empty():
		push_warning("[gate_controller] 未找到门叶节点，开合动画已跳过。")


## sign = -1（西叶，铰链在外缘最小值 x）；sign = +1（东叶，铰链在外缘最大值 x）
func _register(door: Node3D, sign: float) -> void:
	if door == null:
		return
	_rest.append(door.transform)
	_hinges.append(_resolve_hinge(door, sign))
	_signs.append(sign)
	_doors.append(door)


## 用门叶自身 AABB 在【父空间】下推算铰链点（只取 X / Z，绕 Y 轴旋转）
func _resolve_hinge(door: Node3D, sign: float) -> Vector3:
	var mesh := door as MeshInstance3D
	if mesh == null:
		return door.position
	var parent := door.get_parent() as Node3D
	var to_parent := Transform3D.IDENTITY
	if parent != null:
		to_parent = parent.global_transform.affine_inverse() * door.global_transform
	var box: AABB = to_parent * mesh.get_aabb()
	var center: Vector3 = box.get_center()
	var hinge_x: float = box.position.x if sign < 0.0 else box.position.x + box.size.x
	return Vector3(hinge_x, center.y, center.z)


func _apply_progress(value: float) -> void:
	_progress = value
	for i in _doors.size():
		var angle: float = deg_to_rad(open_angle_degrees) * value * _signs[i]
		_doors[i].transform = rotate_about_hinge(_rest[i], _hinges[i], angle)


## 绕"过 hinge 的竖直轴"旋转 rest（全部在门叶父节点坐标系下运算）
static func rotate_about_hinge(rest: Transform3D, hinge: Vector3, angle: float) -> Transform3D:
	var to_hinge := Transform3D(Basis(), hinge)
	var rotation := Transform3D(Basis(Vector3.UP, angle), Vector3.ZERO)
	var from_hinge := Transform3D(Basis(), -hinge)
	return to_hinge * rotation * from_hinge * rest
