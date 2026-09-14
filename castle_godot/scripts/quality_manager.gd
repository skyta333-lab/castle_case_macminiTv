extends Node
class_name QualityManager
## quality_manager.gd
## 画质档管理器（LOW / MEDIUM / HIGH）。
##
## 设计目标（TASK05）："能测 → 能切质量 → 能定位问题"。
##   - 只通过**已有子系统的公开接口**下发设置，不重建任何节点/资源；
##   - 三档全部走同一套代码路径，切换只改参数，因此任意档位都能互相切换且不报错；
##   - Mac mini 默认 MEDIUM（稳定优先）。
##
## 快捷键：7 = LOW，8 = MEDIUM，9 = HIGH。
##
## 每一档控制的项：
##   MSAA / FXAA / 渲染分辨率比例、太阳阴影距离与质量、Glow、Fog、SSAO、
##   窗户自发光强度、烟花粒子数量与拖尾、夜景灯点亮数量、摄像机 far、
##   小装饰物可见距离、粒子绘制距离。

signal quality_changed(level: int, level_name: String)

enum Level { LOW = 0, MEDIUM = 1, HIGH = 2 }

const LEVEL_NAMES: Array[String] = ["LOW", "MEDIUM", "HIGH"]

## 三档具体取值。键名即 get_effective_settings() 的返回键，便于验证脚本逐项对比。
## 重要：MEDIUM 的取值与 TASK02~TASK04 已验证的默认外观完全一致（不产生任何视觉回退），
##       LOW 才是"稳定优先"的降级档，HIGH 在 MEDIUM 之上继续加料。
##      glow / fog / ssao 三个键是"总开关与"语义：画质档为 true 时由昼夜预设决定，
##      为 false 时强制关闭（LOW 关 Glow / Fog / SSAO，即使白天预设里是开的）。
const LEVEL_SETTINGS: Array = [
	{
		# ---- LOW：稳定优先，画面明显降级但场景结构完整 ----
		"msaa": Viewport.MSAA_DISABLED,
		"screen_space_aa": Viewport.SCREEN_SPACE_AA_FXAA,
		"render_scale": 0.75,
		"shadow_enabled": true,
		"shadow_max_distance": 150.0,
		"shadow_blur": 0.3,
		"light_angular_distance": 0.0,
		"glow_enabled": false,
		"fog_enabled": false,
		"ssao_enabled": false,
		"window_emission_scale": 0.6,
		"particle_scale": 0.25,
		"particle_trails": false,
		"night_light_budget": 3,
		"camera_far": 700.0,
		"prop_visibility_end": 70.0,
		"particle_draw_distance": 300.0,
	},
	{
		# ---- MEDIUM：Mac mini 默认档，与既有验收外观一致 ----
		"msaa": Viewport.MSAA_4X,
		"screen_space_aa": Viewport.SCREEN_SPACE_AA_DISABLED,
		"render_scale": 1.0,
		"shadow_enabled": true,
		"shadow_max_distance": 320.0,
		"shadow_blur": 1.0,
		"light_angular_distance": 0.0,
		"glow_enabled": true,
		"fog_enabled": true,
		"ssao_enabled": true,
		"window_emission_scale": 1.0,
		"particle_scale": 1.0,
		"particle_trails": true,
		"night_light_budget": -1,
		"camera_far": 950.0,
		"prop_visibility_end": 140.0,
		"particle_draw_distance": 0.0,
	},
	{
		# ---- HIGH：画质加料（更远的柔和阴影 / 更亮的窗光 / 不做任何可见性剔除）----
		"msaa": Viewport.MSAA_4X,
		"screen_space_aa": Viewport.SCREEN_SPACE_AA_DISABLED,
		"render_scale": 1.0,
		"shadow_enabled": true,
		"shadow_max_distance": 520.0,
		"shadow_blur": 1.6,
		"light_angular_distance": 1.2,
		"glow_enabled": true,
		"fog_enabled": true,
		"ssao_enabled": true,
		"window_emission_scale": 1.15,
		"particle_scale": 1.0,
		"particle_trails": true,
		"night_light_budget": -1,
		"camera_far": 1500.0,
		"prop_visibility_end": 0.0,
		"particle_draw_distance": 0.0,
	},
]

@export_group("Node References")
## 昼夜 / 环境系统（提供 set_quality_profile 与 get_sun）
@export var environment_manager_path: NodePath = ^"../EnvironmentManager"
## 夜景灯光组（提供 set_light_budget）
@export var night_lighting_path: NodePath = ^"../NightLights"
## 烟花系统（提供 set_quality_scale / set_particle_draw_distance）
@export var fireworks_path: NodePath = ^"../Fireworks"
## 城堡根节点（小装饰物可见距离）
@export var castle_path: NodePath = ^"../Castle"
## 展示相机
@export var showcase_camera_path: NodePath = ^"../MainCamera"
## 玩家（其第一 / 第三人称相机也要跟随 far 设置）
@export var player_path: NodePath = ^"../Player"

@export_group("Startup")
## 启动画质档：Mac mini 默认 MEDIUM
@export var start_level: Level = Level.MEDIUM
## 启动即应用
@export var apply_on_ready: bool = true

@export_group("Visibility (小装饰物剔除)")
## 几何体对角线小于该值（米）的网格视为"小装饰物"，参与可见距离剔除
@export_range(0.5, 30.0, 0.1) var prop_diagonal_threshold: float = 4.0
## 不参与剔除的节点名关键字（窗户要保持夜景发光效果，远处也要亮）
@export var prop_exclude_keywords: Array[String] = ["Win_"]
## 是否启用小装饰物可见距离剔除（HIGH 档自动不剔除）
@export var enable_prop_culling: bool = true

var _level: int = Level.MEDIUM
var _env_mgr: Node = null
var _night_lights: Node = null
var _fireworks: Node = null
var _castle: Node3D = null
var _showcase_camera: Camera3D = null
var _player: Node3D = null
var _viewport: Viewport = null
## 参与可见距离剔除的小装饰物（_ready 时一次性收集，运行期不变化）
var _props: Array[MeshInstance3D] = []
## 玩家的两台相机（第一 / 第三人称）
var _player_cameras: Array[Camera3D] = []


func _ready() -> void:
	add_to_group("quality_manager")

	_env_mgr = get_node_or_null(environment_manager_path)
	_night_lights = get_node_or_null(night_lighting_path)
	_fireworks = get_node_or_null(fireworks_path)
	_castle = get_node_or_null(castle_path) as Node3D
	_showcase_camera = get_node_or_null(showcase_camera_path) as Camera3D
	_player = get_node_or_null(player_path) as Node3D
	_viewport = get_viewport()

	_collect_props()
	_collect_player_cameras()

	print(
		"[quality] ready | default=%s props=%d（可见剔除阈值 %.1fm）"
		% [LEVEL_NAMES[_level], _props.size(), prop_diagonal_threshold]
	)
	if apply_on_ready:
		set_level(start_level)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("quality_low"):
		set_level(Level.LOW)
	elif event.is_action_pressed("quality_medium"):
		set_level(Level.MEDIUM)
	elif event.is_action_pressed("quality_high"):
		set_level(Level.HIGH)


# ---------------------------------------------------------------------------
# 对外 API
# ---------------------------------------------------------------------------

## 切换画质档（0=LOW / 1=MEDIUM / 2=HIGH）。可重复调用、可任意顺序切换。
func set_level(level: int) -> void:
	_level = clampi(level, 0, LEVEL_NAMES.size() - 1)
	var s: Dictionary = LEVEL_SETTINGS[_level]

	_apply_viewport(s)
	_apply_shadows(s)
	_apply_environment(s)
	_apply_fireworks(s)
	_apply_night_lights(s)
	_apply_cameras(s)
	_apply_prop_visibility(s)
	_refresh_hud()

	quality_changed.emit(_level, LEVEL_NAMES[_level])
	print("[quality] level = %s | %s" % [LEVEL_NAMES[_level], str(get_effective_settings())])


## 按名字切换：LOW / MEDIUM / HIGH
func set_level_by_name(level_name: String) -> void:
	var idx: int = LEVEL_NAMES.find(level_name.to_upper())
	if idx < 0:
		push_warning("[quality] 未知画质档：%s" % level_name)
		return
	set_level(idx)


func get_level() -> int:
	return _level


func get_level_name() -> String:
	return LEVEL_NAMES[_level]


## 当前生效的画质参数（验证脚本 / 性能报告用）
func get_effective_settings() -> Dictionary:
	return (LEVEL_SETTINGS[_level] as Dictionary).duplicate()


## 按档位索引取参数（不改状态，用于对比）
func get_settings_for(level: int) -> Dictionary:
	return (LEVEL_SETTINGS[clampi(level, 0, LEVEL_NAMES.size() - 1)] as Dictionary).duplicate()


## 参与可见距离剔除的小装饰物数量（性能报告用）
func get_prop_count() -> int:
	return _props.size()


## 当前生效的摄像机 far
func get_camera_far() -> float:
	return float((LEVEL_SETTINGS[_level] as Dictionary)["camera_far"])


# ---------------------------------------------------------------------------
# 内部：逐项应用（全部走子系统公开接口，不新建节点）
# ---------------------------------------------------------------------------

func _apply_viewport(s: Dictionary) -> void:
	if _viewport == null:
		return
	_viewport.msaa_3d = int(s["msaa"])
	_viewport.screen_space_aa = int(s["screen_space_aa"])
	_viewport.scaling_3d_scale = float(s["render_scale"])


func _apply_shadows(s: Dictionary) -> void:
	var sun: DirectionalLight3D = null
	if _env_mgr != null and _env_mgr.has_method("get_sun"):
		sun = _env_mgr.call("get_sun") as DirectionalLight3D
	if sun == null:
		return
	sun.shadow_enabled = bool(s["shadow_enabled"])
	sun.directional_shadow_max_distance = float(s["shadow_max_distance"])
	sun.shadow_blur = float(s["shadow_blur"])
	sun.light_angular_distance = float(s["light_angular_distance"])


func _apply_environment(s: Dictionary) -> void:
	if _env_mgr == null or not _env_mgr.has_method("set_quality_profile"):
		return
	_env_mgr.call("set_quality_profile", {
		"glow_enabled": bool(s["glow_enabled"]),
		"fog_enabled": bool(s["fog_enabled"]),
		"ssao_enabled": bool(s["ssao_enabled"]),
		"window_emission_scale": float(s["window_emission_scale"]),
	})


func _apply_fireworks(s: Dictionary) -> void:
	if _fireworks == null:
		return
	if _fireworks.has_method("set_quality_scale"):
		_fireworks.call("set_quality_scale", float(s["particle_scale"]), bool(s["particle_trails"]))
	if _fireworks.has_method("set_particle_draw_distance"):
		_fireworks.call("set_particle_draw_distance", float(s["particle_draw_distance"]))


func _apply_night_lights(s: Dictionary) -> void:
	if _night_lights == null or not _night_lights.has_method("set_light_budget"):
		return
	_night_lights.call("set_light_budget", int(s["night_light_budget"]))


func _apply_cameras(s: Dictionary) -> void:
	var far: float = float(s["camera_far"])
	if _showcase_camera != null:
		_showcase_camera.far = far
	for cam in _player_cameras:
		if is_instance_valid(cam):
			cam.far = far


func _apply_prop_visibility(s: Dictionary) -> void:
	if not enable_prop_culling:
		return
	var end_distance: float = float(s["prop_visibility_end"])
	for mi in _props:
		if not is_instance_valid(mi):
			continue
		mi.visibility_range_end = end_distance
		mi.visibility_range_end_margin = 0.0 if end_distance <= 0.0 else 20.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


func _refresh_hud() -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("set_quality_status"):
		hud.set_quality_status(LEVEL_NAMES[_level])


# ---------------------------------------------------------------------------
# 内部：一次性收集
# ---------------------------------------------------------------------------

## 收集城堡里的小装饰物网格（对角线 < prop_diagonal_threshold 且名字不在排除表里）。
## 大件（塔楼、墙体、地面）不参与剔除，保证轮廓完整。
func _collect_props() -> void:
	_props.clear()
	if _castle == null:
		return
	for node in _find_small_meshes(_castle):
		_props.append(node)


func _find_small_meshes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		var mi := root as MeshInstance3D
		if _is_cullable_prop(mi):
			out.append(mi)
	for child in root.get_children():
		out.append_array(_find_small_meshes(child))
	return out


func _is_cullable_prop(mi: MeshInstance3D) -> bool:
	var mesh := mi.mesh
	if mesh == null:
		return false
	var name_str := String(mi.name)
	for kw in prop_exclude_keywords:
		if not kw.is_empty() and name_str.contains(kw):
			return false
	var aabb: AABB = mesh.get_aabb()
	return aabb.size.length() < prop_diagonal_threshold


func _collect_player_cameras() -> void:
	_player_cameras.clear()
	if _player == null:
		return
	for node in _find_cameras(_player):
		_player_cameras.append(node)


func _find_cameras(root: Node) -> Array[Camera3D]:
	var out: Array[Camera3D] = []
	if root is Camera3D:
		out.append(root as Camera3D)
	for child in root.get_children():
		out.append_array(_find_cameras(child))
	return out
