extends Node
class_name PerformanceHud
## performance_hud.gd
## 性能 HUD（F7 显示 / 隐藏）。
##
## 工作方式：
##   - 采样频率默认 4 次/秒（update_interval），隐藏时完全不采样，零开销；
##   - 全部读数来自引擎自带的 Performance 监视器，不需要任何外部 profiler；
##   - 只把文本推给 HUD 的 PerfLabel（左下角），与其它 HUD 元素互不干扰。
##
## 显示内容：FPS / 帧时间 / Draw Call 数 / 对象数 / 节点数 / 当前画质档 / 分辨率 / 玩家坐标

@export_group("Node References")
## HUD（提供 set_perf_visible / set_perf_text）
@export var hud_path: NodePath = ^"../HUD"
## 玩家节点（显示坐标）
@export var player_path: NodePath = ^"../Player"

@export_group("Sampling")
## 刷新间隔（秒）
@export_range(0.05, 2.0, 0.05) var update_interval: float = 0.25
## 启动时是否直接显示
@export var start_visible: bool = false

var _hud: Node = null
var _player: Node3D = null
var _timer: float = 0.0
var _visible: bool = false
var _last_text: String = ""


func _ready() -> void:
	add_to_group("performance_hud")
	_hud = get_node_or_null(hud_path)
	_player = get_node_or_null(player_path) as Node3D
	_visible = start_visible
	_push_visible()
	if _visible:
		_refresh()
	print("[perf_hud] ready | 初始状态=%s | 刷新间隔=%.2fs" % ["ON" if _visible else "OFF", update_interval])


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_perf_hud"):
		toggle()


func _process(delta: float) -> void:
	if not _visible:
		return
	_timer += delta
	if _timer < update_interval:
		return
	_timer = 0.0
	_refresh()


# ---------------------------------------------------------------------------
# 对外 API
# ---------------------------------------------------------------------------

func toggle() -> void:
	set_shown(not _visible)


func set_shown(value: bool) -> void:
	_visible = value
	_push_visible()
	if _visible:
		_refresh()
	print("[perf_hud] %s" % ("ON" if _visible else "OFF"))


func is_shown() -> bool:
	return _visible


## 最近一次采样的文本（验证脚本用）
func get_last_text() -> String:
	return _last_text


## 立即采样一次并返回文本（验证脚本用，不受可见状态限制）
func sample_now() -> String:
	_refresh()
	return _last_text


## 当前采样快照（性能报告 / 验证脚本用）
func get_metrics() -> Dictionary:
	return {
		"fps": Engine.get_frames_per_second(),
		"frame_ms": 1000.0 / maxf(float(Engine.get_frames_per_second()), 1.0),
		"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"physics_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"static_memory_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
	}


# ---------------------------------------------------------------------------
# 内部
# ---------------------------------------------------------------------------

func _push_visible() -> void:
	if _hud != null and _hud.has_method("set_perf_visible"):
		_hud.call("set_perf_visible", _visible)


func _refresh() -> void:
	if _hud == null or not _hud.has_method("set_perf_text"):
		return
	var m: Dictionary = get_metrics()
	var quality := "-"
	var qm := get_tree().get_first_node_in_group("quality_manager")
	if qm != null and qm.has_method("get_level_name"):
		quality = String(qm.call("get_level_name"))
	var res := "-"
	var vp := get_viewport()
	if vp != null:
		var size := vp.get_visible_rect().size
		res = "%dx%d (scale %.2f)" % [int(size.x), int(size.y), vp.scaling_3d_scale]
	var pos := "-"
	if _player != null and is_instance_valid(_player):
		var p: Vector3 = _player.global_position
		pos = "(%.1f, %.1f, %.1f)" % [p.x, p.y, p.z]
	_last_text = "FPS %d  |  Frame %.2f ms\nDraw Calls %d  |  Objects %d  |  Nodes %d\nQuality: %s  |  %s\nPlayer: %s" % [
		int(m["fps"]), float(m["frame_ms"]), int(m["draw_calls"]), int(m["objects"]), int(m["nodes"]),
		quality, res, pos,
	]
	_hud.call("set_perf_text", _last_text)
