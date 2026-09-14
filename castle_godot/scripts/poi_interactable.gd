extends Interactable
class_name PoiInteractable
## poi_interactable.gd
## 城堡兴趣点（Point of Interest）热点（TASK03）。
##
## 一个 POI = 一个 Area3D 热点体积 + 一份"标题 + 说明"文案 + 一个可开关的 3D marker。
##   - 准星指到时：HUD 中央显示 "Press E to interact  ·  <标题>"；
##   - 按 E：下方展开说明面板（标题 + 多行描述 + 关闭提示）；
##   - 再按 E（或控制器派发的关闭）：收起面板。
##
## marker（F8 开关）：
##   - 默认隐藏，仅用于验收 / 调试时一眼看到热点在哪里；
##   - 由 scenes/poi_marker.tscn 实例化，纯视觉节点，无碰撞体，
##     不会干扰射线检测，也不会被渲染成实心遮挡物（Label3D 关闭深度测试）。

## 热点的稳定 ID（写进 TASK03_DONE.md / 自检脚本使用）
@export var poi_id: String = "poi"
## 面板标题
@export var poi_title: String = "Point of Interest"
## 面板正文（多行）
@export_multiline var poi_description: String = ""
## marker 场景（留空则用默认 res://scenes/poi_marker.tscn）
@export var marker_scene: PackedScene
## marker 相对热点中心的抬高量
@export var marker_height: float = 0.0
## marker 缩放
@export var marker_scale: float = 1.0

## 初始 marker 场景路径（与 scenes/poi_marker.tscn 对齐）
const DEFAULT_MARKER_SCENE := "res://scenes/poi_marker.tscn"

## 被交互时发出（面板展开 / 收起都会发），供 TASK04 特效等外部系统联动
signal poi_interacted(poi: PoiInteractable, actor: Node)

var _marker: Node3D
var _panel_open: bool = false
var _hud: GameHud


func _ready() -> void:
	# 归入 poi 组，方便 interaction_controller 一次性收集与 F8 批量开关 marker
	add_to_group("poi")
	_build_marker()


## 准星指到时显示的提示：基础文案 + 热点名
func get_interaction_text() -> String:
	if _panel_open:
		return "Press E to close"
	return "%s  ·  %s" % [prompt_text, poi_title]


## 面板正文（子类可覆写为动态文案，例如正门热点会附带门扇开合状态）
func get_poi_description() -> String:
	return poi_description


func get_poi_title() -> String:
	return poi_title


## 按 E：面板展开 <-> 收起
func interact(actor: Node) -> void:
	if _panel_open:
		close_panel()
	else:
		open_panel()
	poi_interacted.emit(self, actor)


func open_panel() -> void:
	_panel_open = true
	var hud := _resolve_hud()
	if hud != null:
		hud.show_poi(poi_title, get_poi_description())


func close_panel() -> void:
	_panel_open = false
	var hud := _resolve_hud()
	if hud != null:
		hud.hide_poi()


func is_panel_open() -> bool:
	return _panel_open


## ---- marker ----------------------------------------------------------------

## F8 开关：由 interaction_controller 批量调用
func set_marker_visible(value: bool) -> void:
	if _marker == null:
		return
	_marker.visible = value


func is_marker_visible() -> bool:
	return _marker != null and _marker.visible


func get_marker() -> Node3D:
	return _marker


## ---- 内部 ------------------------------------------------------------------

func _resolve_hud() -> GameHud:
	if _hud == null and is_inside_tree():
		_hud = get_tree().get_first_node_in_group("hud") as GameHud
	return _hud


func _build_marker() -> void:
	var scene := marker_scene
	if scene == null:
		scene = load(DEFAULT_MARKER_SCENE) as PackedScene
	if scene == null:
		return
	_marker = scene.instantiate() as Node3D
	if _marker == null:
		return
	_marker.name = "Marker"
	add_child(_marker)
	_marker.position = Vector3(0, marker_height, 0)
	_marker.scale = Vector3.ONE * marker_scale
	_marker.visible = false
	var label := _marker.get_node_or_null("Label") as Label3D
	if label != null:
		label.text = poi_title
