extends Node3D
class_name NightLighting
## night_lighting.gd
## 夜景灯光组：主入口暖光 + 两侧补光 + 主塔轮廓补光 + 台基点缀。
##
## 设计要点：
##   - 灯光在 _ready 时按 light_specs 一次性创建，**数量固定**，运行期不再新增（不会累积）；
##   - 亮度跟随昼夜系统的 night factor（白天自动熄灭），自动昼夜模式下平滑跟随；
##   - 全部 OmniLight3D、默认关闭阴影，避免 Mac mini 上多灯阴影把 GPU 打满。

@export_group("Node References")
## 昼夜系统（提供 get_night_factor()）。留空则尝试 ../EnvironmentManager
@export var environment_manager_path: NodePath = ^"../EnvironmentManager"

@export_group("Lights")
## 灯光规格列表，留空使用脚本内置默认 6 盏。
## 每项支持键：name / position / color / energy / range / attenuation / shadow
@export var light_specs: Array = []

@export_group("Night Response")
## 夜晚程度低于该值时灯光整体隐藏
@export_range(0.0, 1.0, 0.01) var visible_threshold: float = 0.02
## 白天残留亮度比例（0 = 白天全灭）
@export_range(0.0, 1.0, 0.01) var day_scale: float = 0.0
## 亮度响应指数，>1 表示入夜后才明显亮起
@export_range(0.2, 4.0, 0.05) var response_exponent: float = 1.35
## 是否允许阴影（默认关；开启会显著增加开销）
@export var enable_shadows: bool = false
## 调试用：忽略昼夜系统，强制常亮
@export var force_on: bool = false

## 默认灯光规格（世界坐标）
const DEFAULT_SPECS: Array = [
	{
		"name": "GateWarm", "position": Vector3(0.0, 8.5, 30.5),
		"color": Color(1.0, 0.72, 0.42), "energy": 7.0, "range": 32.0, "attenuation": 1.4,
	},
	{
		"name": "ForecourtWest", "position": Vector3(-18.0, 9.0, 30.0),
		"color": Color(0.62, 0.78, 1.0), "energy": 3.2, "range": 36.0, "attenuation": 1.2,
	},
	{
		"name": "ForecourtEast", "position": Vector3(18.0, 9.0, 30.0),
		"color": Color(0.62, 0.78, 1.0), "energy": 3.2, "range": 36.0, "attenuation": 1.2,
	},
	{
		"name": "TowerRimLow", "position": Vector3(0.0, 30.0, 16.0),
		"color": Color(1.0, 0.86, 0.62), "energy": 5.0, "range": 46.0, "attenuation": 1.0,
	},
	{
		"name": "TowerRimHigh", "position": Vector3(0.0, 62.0, -2.0),
		"color": Color(0.78, 0.86, 1.0), "energy": 3.6, "range": 52.0, "attenuation": 0.9,
	},
	{
		"name": "PodiumAccent", "position": Vector3(-24.0, 8.0, 34.0),
		"color": Color(1.0, 0.66, 0.38), "energy": 2.6, "range": 22.0, "attenuation": 1.6,
	},
]

var _lights: Array[OmniLight3D] = []
var _base_energy: Array[float] = []
var _env_mgr: Node = null
var _night_factor: float = 0.0
var _scale: float = 0.0


func _ready() -> void:
	add_to_group("night_lighting")
	_env_mgr = get_node_or_null(environment_manager_path)
	build_lights()
	_apply(_read_night_factor())


func _process(_delta: float) -> void:
	_apply(_read_night_factor())


## 按 light_specs（或内置默认）重建灯光。可重复调用，重复调用不会让灯光数量增长。
func build_lights() -> void:
	_clear_lights()
	var specs: Array = light_specs if not light_specs.is_empty() else DEFAULT_SPECS
	for spec in specs:
		if typeof(spec) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = spec
		var light := OmniLight3D.new()
		light.name = String(d.get("name", "NightLight"))
		light.position = d.get("position", Vector3.ZERO)
		light.light_color = d.get("color", Color(1.0, 1.0, 1.0))
		light.omni_range = float(d.get("range", 28.0))
		light.omni_attenuation = float(d.get("attenuation", 1.0))
		light.shadow_enabled = enable_shadows and bool(d.get("shadow", false))
		light.light_energy = 0.0
		light.visible = false
		add_child(light)
		_lights.append(light)
		_base_energy.append(float(d.get("energy", 4.0)))


# ---------------------------------------------------------------------------
# 查询接口（供验证脚本 / 性能报告使用）
# ---------------------------------------------------------------------------

## 灯光数量（固定值，运行期不增长）
func get_light_count() -> int:
	return _lights.size()


## 灯光节点列表
func get_lights() -> Array[OmniLight3D]:
	return _lights


## 当前总亮度（只有夜间 > 0）
func get_light_energy_total() -> float:
	var total: float = 0.0
	for light in _lights:
		if light.visible:
			total += light.light_energy
	return total


## 当前昼夜响应系数（0 = 白天，1 = 全亮）
func get_light_scale() -> float:
	return _scale


func get_night_factor() -> float:
	return _night_factor


# ---------------------------------------------------------------------------
# 内部
# ---------------------------------------------------------------------------

func _clear_lights() -> void:
	for light in _lights:
		light.queue_free()
	_lights.clear()
	_base_energy.clear()


func _read_night_factor() -> float:
	if force_on:
		return 1.0
	if _env_mgr == null or not _env_mgr.has_method("get_night_factor"):
		_env_mgr = get_node_or_null(environment_manager_path)
		if _env_mgr == null or not _env_mgr.has_method("get_night_factor"):
			return 0.0
	return clampf(float(_env_mgr.call("get_night_factor")), 0.0, 1.0)


func _apply(factor: float) -> void:
	_night_factor = factor
	var curve: float = pow(clampf(factor, 0.0, 1.0), response_exponent)
	_scale = lerpf(day_scale, 1.0, curve)
	var visible_now: bool = _scale > visible_threshold
	for i in _lights.size():
		var light := _lights[i]
		light.visible = visible_now
		light.light_energy = _base_energy[i] * _scale
