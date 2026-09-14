extends PoiInteractable
class_name GatePoi
## gate_poi.gd
## 正门热点（TASK03 指定）：说明面板 + 驱动 gate_controller.gd 开合两扇门叶。
##
## 与普通 POI 的差别：一次 E 同时完成两件事——
##   1. 展开 / 收起正门说明面板（继承 PoiInteractable 的行为）；
##   2. 把两扇门叶从关闭摆到打开（或反向），因此面板说明里会附上实时门态。

## 同场景下的 GateController
@export var gate_controller_path: NodePath = ^"../GateController"

var _gate: GateController


func _ready() -> void:
	super._ready()
	_gate = get_node_or_null(gate_controller_path) as GateController


## 面板正文：基础说明 + 实时门态
func get_poi_description() -> String:
	if _gate == null:
		return poi_description
	var state := "OPEN" if _gate.is_open() else "CLOSED"
	var hint := "Press E again to swing the gate shut."
	if not _gate.is_open():
		hint = "Press E again to swing both gate leaves open."
	return "%s\n\nGate leaves: %s. %s" % [poi_description, state, hint]


func is_gate_open() -> bool:
	return _gate != null and _gate.is_open()


## 一次 E = 面板开合 + 门扇开合，两者同步
func interact(actor: Node) -> void:
	super.interact(actor)
	if _gate != null:
		_gate.toggle()
