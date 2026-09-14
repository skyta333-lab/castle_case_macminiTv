extends Node
class_name InteractionController
## interaction_controller.gd
## 交互中枢（TASK03）：把玩家中央准星射线（RayCast3D）与场景里的 Interactable 连起来。
##
## 数据流（单向，无回环）：
##   PlayerController.InteractRay  ──(每帧复制激活相机的 transform)──▶ 射线
##        │ is_colliding() / get_collider()
##        ▼
##   InteractionController  ──▶ GameHud.set_prompt("Press E to interact …")
##        │ 按下 interact（E）
##        ▼
##   Interactable.interact(actor)  ──▶ 具体行为（POI 面板 / 正门开合 …）
##
## 本脚本内部【不出现任何具体热点的名字】，新增交互物只需继承 Interactable 并放进场景。

@export_group("Nodes")
## 玩家（PlayerController）
@export var player_path: NodePath = ^"../Player"
## POI 容器（根节点，用于 F8 一次性收集所有热点）
@export var poi_root_path: NodePath = ^"../PoiSet"

@export_group("Behaviour")
## 启动时是否直接显示 POI marker（默认关，F8 开）
@export var markers_visible_on_start: bool = false
## 空手（准星没指到东西）时的提示文本，留空即隐藏
@export var idle_prompt: String = ""

var _player: PlayerController
var _hud: GameHud
var _poi_root: Node
var _target: Interactable
var _panel_poi: PoiInteractable
var _markers_visible := false
var _poi_nodes: Array[Node] = []
var _ready_done := false


func _ready() -> void:
	add_to_group("interaction_controller")
	_player = get_node_or_null(player_path) as PlayerController
	_hud = get_tree().get_first_node_in_group("hud") as GameHud
	_poi_root = get_node_or_null(poi_root_path)
	_refresh_poi_nodes()
	set_markers_visible(markers_visible_on_start)
	# POI 子树可能在本节点之后 _ready，延后一帧再收一次，保证 marker 一次性全部置位
	call_deferred("_refresh_poi_nodes")
	call_deferred("_apply_marker_state")
	_ready_done = true


func _process(_delta: float) -> void:
	_update_target()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_poi_markers"):
		set_markers_visible(not _markers_visible)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("interact"):
		if _player == null or not _player.active:
			return
		handle_interact()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------
# 对外接口（HUD / 自动化验证脚本使用）

## 当前准星锁定的交互物
func get_target() -> Interactable:
	return _target


## 当前是否有可交互目标
func has_target() -> bool:
	return _target != null


## 当前展开中的 POI 面板所属热点
func get_panel_poi() -> PoiInteractable:
	return _panel_poi


## 场景里的热点总数
func get_poi_count() -> int:
	return _poi_nodes.size()


## 收集到的热点列表
func get_poi_nodes() -> Array[Node]:
	return _poi_nodes


## F8：批量显示 / 隐藏所有 POI marker
func set_markers_visible(value: bool) -> void:
	_markers_visible = value
	_apply_marker_state()


func are_markers_visible() -> bool:
	return _markers_visible


## 执行一次交互（E 键走这里，自动化验证也走这里）
func handle_interact() -> void:
	# 面板已展开：先让热点自己处理"关闭"，避免绕过它的 interact() 造成状态不同步
	if _panel_poi != null and is_instance_valid(_panel_poi) and _panel_poi.is_panel_open():
		_panel_poi.interact(_player)
		if not _panel_poi.is_panel_open():
			_panel_poi = null
		_update_target()
		return

	var current := _target
	if current == null:
		return
	current.interact(_player)
	_panel_poi = current if current is PoiInteractable and (current as PoiInteractable).is_panel_open() else null
	_update_target()


# ---------------------------------------------------------------------------

func _refresh_poi_nodes() -> void:
	if not is_inside_tree():
		return
	if _poi_root != null:
		_poi_nodes = _poi_root.find_children("*", "Area3D", true, false)
	else:
		_poi_nodes = get_tree().get_nodes_in_group("poi")
	# 只保留真正的 Interactable
	var filtered: Array[Node] = []
	for n in _poi_nodes:
		if n is Interactable:
			filtered.append(n)
	_poi_nodes = filtered


func _apply_marker_state() -> void:
	if not is_inside_tree():
		return
	if _poi_nodes.is_empty():
		_refresh_poi_nodes()
	for n in _poi_nodes:
		if n.has_method("set_marker_visible"):
			n.call("set_marker_visible", _markers_visible)


func _update_target() -> void:
	var ray: RayCast3D = null
	if _player != null and _player.active:
		ray = _player.get_interact_ray()

	var found: Interactable = null
	if ray != null and ray.is_colliding():
		var collider := ray.get_collider()
		if collider is Interactable and (collider as Interactable).can_interact(_player):
			found = collider
	_target = found
	_update_prompt()


func _update_prompt() -> void:
	if _hud == null:
		return
	if _panel_poi != null and is_instance_valid(_panel_poi) and _panel_poi.is_panel_open():
		_hud.set_prompt(_panel_poi.get_interaction_text())
		return
	if _target != null:
		_hud.set_prompt(_target.get_interaction_text())
	else:
		_hud.set_prompt(idle_prompt)
