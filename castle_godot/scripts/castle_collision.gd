extends Node3D
class_name CastleCollisionBuilder
## castle_collision.gd
## 为城堡与地面程序化生成"合理简化"的静态碰撞体。
##
## 目标：可玩优先 + 可接受的性能。
##   - 只为关键体块（台基 / 前庭 / 主体量 / 各塔楼基座 / 入口台阶）建立少量
##     BoxShape3D 与 CylinderShape3D，总计约 20 个；
##   - **绝不**把模型里 655 个 Mesh 全部转成 ConcavePolygonShape3D（那是数百个
##     高开销凹多边形，既慢又不符合任务书"避免数百个高开销碰撞体"的约束）；
##   - 所有形状尺寸都从模型实际 AABB / 节点变换读取，模型换了也不用改代码；
##   - 台阶与台基高差用"斜面 Box"代替，避免 CharacterBody3D 被 0.8m 的竖直
##     立面卡住（Godot 的 move_and_slide 不会自动上台阶）。
##
## 模型实测结构（模型坐标，与 GLB 节点一致）：
##   Ground_Meadow      230 x 1 x 230，顶面 y = 0
##   Rock_Podium        顶面 y = 4.0（x -39.3~40.7，z -38.6~42.9）
##   Rock_Podium_Cap    顶面 y = 4.8（x -39~39，z -39~39）—— 实际可行走台基顶
##   Forecourt          顶面 y = 4.0（x -16~16，z 26~52）—— 门前平台
##   Stair_Step_01..05  5 级台阶，z 57.6 → 50.6，y 0 → 4.0
##   Gate_Door_W/E      大门，节点原点 (∓5.8, 9.5, 24.6)

@export_group("Ground")
## 是否生成地面碰撞
@export var build_ground: bool = true
## 内层草地（Ground_Meadow）顶面高度
@export var ground_top_y: float = 0.0
## 内层草地半边长（Ground_Meadow 为 230 x 230）
@export var ground_half_extent: float = 115.0
## 外层兜底草地平面（Ground / PlaneMesh 600x600）顶面高度
@export var base_plane_top_y: float = -1.02
## 外层草地半边长
@export var base_plane_half_extent: float = 300.0

@export_group("Castle")
## 是否生成城堡碰撞
@export var build_castle: bool = true
## 城堡根节点
@export var castle_path: NodePath = ^"../Castle"
## 碰撞体所在物理层（1 = 世界静态几何，玩家 mask 命中它）
@export_flags_3d_physics var collision_layer: int = 1

@export_group("Slope")
## 是否生成门前台阶斜面（替代 5 级台阶的竖直立面）
@export var build_front_ramp: bool = true
## 台阶斜面底端（草地一侧）
@export var ramp_bottom: Vector3 = Vector3(0.0, 0.0, 58.6)
## 台阶斜面顶端（前庭平台一侧）
## 台阶斜面顶端（前庭平台一侧）。
## 注意：必须正好落在 Forecourt 前立面 z=52 上（y=4.0），否则玩家会撞进
## 前庭平台的方块内部而被卡住。
@export var ramp_top: Vector3 = Vector3(0.0, 4.0, 52.0)
## 台阶斜面宽度
@export var ramp_width: float = 20.0
## 斜面厚度
@export var slope_thickness: float = 0.4
## 是否生成台基 Cap 高差斜面（4.0 → 4.8）
@export var build_cap_step: bool = true
## Cap 前缘 z
@export var cap_edge_z: float = 39.0
## Cap 斜面水平长度
@export var cap_step_length: float = 2.0
## Cap 斜面宽度（x 跨度）
@export var cap_step_width: float = 40.0
## Cap 顶面比前庭平台高出的高度
@export var cap_step_delta: float = 0.8

## 需要生成碰撞的网格节点 -> 形状类型。
## box  : 直接使用该网格的世界 AABB 作为长方体（适合方形体块）
## cylinder : 以 AABB 的 X/Z 较小边为直径、Y 为高（适合塔身）
const CASTLE_BLOCKS: Array = [
	{"node": "Rock_Podium", "shape": "box"},
	{"node": "Rock_Podium_Cap", "shape": "box"},
	{"node": "Forecourt", "shape": "box"},
	{"node": "Mass_Mid", "shape": "box"},
	{"node": "Mass_Upper", "shape": "box"},
	{"node": "LowWall_W", "shape": "box"},
	{"node": "LowWall_C", "shape": "box"},
	{"node": "LowWall_E", "shape": "box"},
	{"node": "Tower_C1_Main_Shaft", "shape": "cylinder"},
	{"node": "Tower_C2_Front_Shaft", "shape": "cylinder"},
	{"node": "Tower_C3_Rear_Shaft", "shape": "cylinder"},
	{"node": "Tower_L1_Shaft", "shape": "cylinder"},
	{"node": "Tower_R1_Shaft", "shape": "cylinder"},
	{"node": "Tower_L2_Shaft", "shape": "cylinder"},
	{"node": "Tower_R2_Shaft", "shape": "cylinder"},
	{"node": "Tower_L3_Shaft", "shape": "cylinder"},
	{"node": "Tower_R3_Shaft", "shape": "cylinder"},
	{"node": "Tower_L4_Shaft", "shape": "cylinder"},
	{"node": "Tower_R4_Shaft", "shape": "cylinder"},
]


func _ready() -> void:
	_build()


## 生成的碰撞体总数（供自检脚本读取）
func get_collision_count() -> int:
	return get_child_count()


func _build() -> void:
	if build_ground:
		_build_ground()
	if build_castle:
		var castle: Node = get_node_or_null(castle_path)
		if castle == null:
			push_warning("[castle_collision] 未找到城堡节点 %s" % str(castle_path))
		else:
			for spec in CASTLE_BLOCKS:
				_build_block(castle, spec)
	if build_front_ramp:
		_build_slope("Col_FrontStairRamp", ramp_bottom, ramp_top, ramp_width)
	if build_cap_step:
		var low := Vector3(0.0, ramp_top.y, cap_edge_z + cap_step_length)
		var high := Vector3(0.0, ramp_top.y + cap_step_delta, cap_edge_z)
		_build_slope("Col_CapStepRamp", low, high, cap_step_width)
	print(
		"[castle_collision] static bodies = %d" % get_child_count()
	)


func _build_ground() -> void:
	# 内层：与 Ground_Meadow 对齐的草地台面
	var inner := BoxShape3D.new()
	inner.size = Vector3(ground_half_extent * 2.0, 6.0, ground_half_extent * 2.0)
	_make_body(
		"GroundBody_Meadow",
		inner,
		Transform3D(Basis(), Vector3(0.0, ground_top_y - 3.0, 0.0))
	)
	# 外层：与 Ground / PlaneMesh 对齐的兜底地面，避免玩家走出草地后无限下坠
	var outer := BoxShape3D.new()
	outer.size = Vector3(base_plane_half_extent * 2.0, 4.0, base_plane_half_extent * 2.0)
	_make_body(
		"GroundBody_Plane",
		outer,
		Transform3D(Basis(), Vector3(0.0, base_plane_top_y - 2.0, 0.0))
	)


func _build_block(castle: Node, spec: Dictionary) -> void:
	var target: Node = castle.get_node_or_null(NodePath(String(spec["node"])))
	if target == null or not (target is MeshInstance3D):
		push_warning("[castle_collision] 跳过缺失节点 %s" % String(spec["node"]))
		return
	var mesh_instance := target as MeshInstance3D
	var aabb: AABB = mesh_instance.global_transform * mesh_instance.get_aabb()
	var center: Vector3 = aabb.get_center()
	if String(spec["shape"]) == "cylinder":
		var shape := CylinderShape3D.new()
		shape.radius = minf(aabb.size.x, aabb.size.z) * 0.5
		shape.height = aabb.size.y
		_make_body("Col_%s" % String(spec["node"]), shape, Transform3D(Basis(), center))
	else:
		var shape := BoxShape3D.new()
		shape.size = aabb.size
		_make_body("Col_%s" % String(spec["node"]), shape, Transform3D(Basis(), center))


## 用一块绕 X 轴旋转的 Box 充当斜面。
## bottom/top 是斜面"上表面"的两端（top 应在 -Z 方向更高），
## Box 主体沿斜面法线向下偏移半个厚度，保证上表面正好经过 bottom → top 连线。
func _build_slope(
	body_name: String,
	bottom: Vector3,
	top: Vector3,
	width: float
) -> void:
	var delta := top - bottom
	var run := sqrt(delta.x * delta.x + delta.z * delta.z)
	if run < 0.001:
		return
	var length := delta.length()
	# 使 +Z 端向下的旋转角
	var angle := atan2(delta.y, -delta.z)
	var basis := Basis(Vector3.RIGHT, angle)
	var normal := Vector3(0.0, cos(angle), sin(angle))
	var center := (bottom + top) * 0.5 - normal * (slope_thickness * 0.5)
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, slope_thickness, length)
	_make_body(body_name, shape, Transform3D(basis, center))


func _make_body(body_name: String, shape: Shape3D, xform: Transform3D) -> void:
	var body := StaticBody3D.new()
	body.name = body_name
	body.collision_layer = collision_layer
	body.collision_mask = 0
	body.transform = xform
	var collision := CollisionShape3D.new()
	collision.name = "Shape"
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
