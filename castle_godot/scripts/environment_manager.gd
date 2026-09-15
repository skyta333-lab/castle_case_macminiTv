extends Node
class_name EnvironmentManager
## environment_manager.gd
## 昼夜与环境系统：把静态"白天展示"升级为 DAY / SUNSET / NIGHT 三态 + 连续时间流逝。
##
## 负责：
##   - DirectionalLight3D（太阳 / 月亮）的角度、能量、颜色
##   - 程序化天空（天顶 / 地平线 / 地面颜色、天空亮度）
##   - Environment 曝光、环境光、雾、SSAO、Glow
##   - 城堡窗户自发光（夜间暖色灯光策略：只改材质，不新增任何实时灯）
##   - 快捷键 F1 白天 / F2 黄昏 / F3 夜晚 / F4 自动昼夜
##   - 向 HUD 推送 "Time / Mode / Auto Cycle" 状态
##
## 性能说明：
##   91 个 Win_Glass 网格全部走"材质自发光"路线（按源材质去重后共享同一份副本），
##   不创建任何 OmniLight3D / SpotLight3D，夜间开启成本接近 0。

signal preset_changed(preset_name: String)
signal time_of_day_changed(time_of_day: float)

enum Preset { DAY, SUNSET, NIGHT }

## 自动昼夜的关键时间点（小时 → 预设），中间线性插值
const CYCLE_KEYFRAMES: Array = [
	{"t": 0.0, "preset": Preset.NIGHT},
	{"t": 5.0, "preset": Preset.NIGHT},
	{"t": 6.5, "preset": Preset.SUNSET},
	{"t": 9.0, "preset": Preset.DAY},
	{"t": 16.5, "preset": Preset.DAY},
	{"t": 18.0, "preset": Preset.SUNSET},
	{"t": 20.0, "preset": Preset.NIGHT},
	{"t": 24.0, "preset": Preset.NIGHT},
]

@export_group("Node References")
## 承载 Environment 的 WorldEnvironment
@export var world_environment_path: NodePath = ^"../WorldEnvironment"
## 太阳 / 月光
@export var sun_path: NodePath = ^"../SunLight"
## 城堡根节点（用于收集窗户网格）
@export var castle_path: NodePath = ^"../Castle"

@export_group("Presets (留空则使用脚本内置默认值)")
## 白天预设
@export var day_preset: EnvironmentPreset
## 黄昏预设
@export var sunset_preset: EnvironmentPreset
## 夜晚预设
@export var night_preset: EnvironmentPreset

@export_group("Startup")
## 启动预设
@export var start_preset: Preset = Preset.DAY
## 启动时刻（小时，0~24）
@export_range(0.0, 24.0, 0.01) var start_time_of_day: float = 12.0
## 启动时是否直接进入自动昼夜
@export var auto_cycle_on_start: bool = false

@export_group("Auto Cycle")
## 自动昼夜下走完 24 小时所需的真实秒数（越大越慢）
@export_range(10.0, 3600.0, 1.0) var day_length_seconds: float = 180.0
## 预设切换的整体过渡时长（秒）
@export_range(0.05, 5.0, 0.05) var transition_seconds: float = 1.2
## 自动昼夜下每帧追随目标参数的平滑时长（秒）
@export_range(0.05, 2.0, 0.05) var cycle_smoothing_seconds: float = 0.4

@export_group("Night Windows")
## 是否启用"窗户自发光"夜间灯光策略
@export var window_glow_enabled: bool = true
## 被视为窗户的节点名关键字
@export var window_node_keyword: String = "Win_"

@export_group("HUD")
## HUD 状态刷新间隔（秒）
@export_range(0.05, 2.0, 0.05) var hud_refresh_interval: float = 0.25

var _sun: DirectionalLight3D
var _world_env: WorldEnvironment
var _castle: Node3D
var _env: Environment
var _sky_mat: ProceduralSkyMaterial
var _presets: Array[EnvironmentPreset] = []

var _params: Dictionary = {}
var _from_params: Dictionary = {}
var _target_params: Dictionary = {}
var _transition_t: float = 1.0
var _transition_duration: float = 0.0

var _preset_index: int = Preset.DAY
var _auto_cycle: bool = false
var _time_of_day: float = 12.0
var _hud_timer: float = 0.0
var _window_materials: Array[StandardMaterial3D] = []
## 画质档覆盖（由 quality_manager 注入）：glow_enabled / fog_enabled / ssao_enabled / window_emission_scale
var _quality: Dictionary = {}

## 磁盘上的预设资源（可在检查器里直接调参）；缺失或类型不符时回退到脚本内置默认值
const PRESET_RESOURCE_PATHS: Array[String] = [
	"res://materials/env_day_preset.tres",
	"res://materials/env_sunset.tres",
	"res://materials/env_night.tres",
]


func _load_preset_resource(idx: int) -> EnvironmentPreset:
	var path: String = PRESET_RESOURCE_PATHS[idx]
	if not ResourceLoader.exists(path):
		return null
	var res: Resource = load(path)
	var preset := res as EnvironmentPreset
	if preset == null:
		push_warning("[environment] %s 不是 EnvironmentPreset，改用内置默认预设" % path)
	return preset


func _ready() -> void:
	add_to_group("environment_manager")

	_sun = get_node_or_null(sun_path) as DirectionalLight3D
	_world_env = get_node_or_null(world_environment_path) as WorldEnvironment
	_castle = get_node_or_null(castle_path) as Node3D

	_presets = []
	for i in range(3):
		var p: EnvironmentPreset = null
		match i:
			0: p = day_preset
			1: p = sunset_preset
			2: p = night_preset
		if p == null:
			p = _load_preset_resource(i)
		if p == null:
			p = [EnvironmentPreset.make_day(), EnvironmentPreset.make_sunset(), EnvironmentPreset.make_night()][i]
		_presets.append(p)

	_prepare_environment()
	_collect_window_materials()

	_preset_index = start_preset
	_time_of_day = fmod(maxf(start_time_of_day, 0.0), 24.0)
	_auto_cycle = auto_cycle_on_start
	_params = _presets[_preset_index].to_params()
	_from_params = _params.duplicate()
	_target_params = _params.duplicate()
	_transition_t = 1.0
	_apply(_params)

	print(
		"[environment] ready | preset=%s time=%.2f auto=%s sun=%s windows=%d day_length=%.0fs"
		% [get_preset_name(), _time_of_day, str(_auto_cycle), str(_sun != null), _window_materials.size(), day_length_seconds]
	)
	print(
		"[environment] presets = %s（来源：检查器 > materials/*.tres > 脚本内置默认值）"
		% str(PRESET_RESOURCE_PATHS)
	)
	_refresh_hud()


func _process(delta: float) -> void:
	if _auto_cycle:
		_time_of_day = fmod(_time_of_day + delta * 24.0 / maxf(day_length_seconds, 1.0), 24.0)
		_set_target(_params_for_time(_time_of_day), cycle_smoothing_seconds)
		time_of_day_changed.emit(_time_of_day)

	if _transition_t < 1.0:
		_transition_t = minf(1.0, _transition_t + delta / maxf(_transition_duration, 0.001))
		_params = _lerp_params(_from_params, _target_params, _transition_t)
		_apply(_params)

	_hud_timer += delta
	if _hud_timer >= hud_refresh_interval:
		_hud_timer = 0.0
		_refresh_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("env_day"):
		set_preset(Preset.DAY)
	elif event.is_action_pressed("env_sunset"):
		set_preset(Preset.SUNSET)
	elif event.is_action_pressed("env_night"):
		set_preset(Preset.NIGHT)
	elif event.is_action_pressed("env_auto_cycle"):
		set_auto_cycle(not _auto_cycle)


# ---------------------------------------------------------------------------
# 对外 API
# ---------------------------------------------------------------------------

## 切换到指定预设（关闭自动昼夜）
func set_preset(index: int) -> void:
	_preset_index = clampi(index, 0, _presets.size() - 1)
	_auto_cycle = false
	_set_target(_presets[_preset_index].to_params(), transition_seconds)
	preset_changed.emit(get_preset_name())
	_refresh_hud(true)


## 按名字切换：DAY / SUNSET / NIGHT
func set_preset_by_name(preset_name: String) -> void:
	match preset_name.to_upper():
		"DAY":
			set_preset(Preset.DAY)
		"SUNSET":
			set_preset(Preset.SUNSET)
		"NIGHT":
			set_preset(Preset.NIGHT)
		_:
			push_warning("[environment] 未知预设：%s" % preset_name)


## 开关自动昼夜
func set_auto_cycle(enabled: bool) -> void:
	_auto_cycle = enabled
	if enabled:
		_set_target(_params_for_time(_time_of_day), transition_seconds)
	_refresh_hud(true)


func is_auto_cycle() -> bool:
	return _auto_cycle


## 当前预设名（自动昼夜下返回最接近当前时间的预设名）
func get_preset_name() -> String:
	if _auto_cycle:
		var idx: int = _nearest_preset_index(_time_of_day)
		return "AUTO/%s" % _presets[idx].preset_name
	return _presets[_preset_index].preset_name


## 直接设定时刻（自动昼夜 / 基准脚本用）
func set_time_of_day(hours: float, apply_now: bool = true) -> void:
	_time_of_day = fmod(fposmod(hours, 24.0), 24.0)
	if apply_now:
		if _auto_cycle:
			_set_target(_params_for_time(_time_of_day), transition_seconds)
		else:
			# 固定预设模式下只改时刻，预设不变
			pass
	_refresh_hud(true)


func get_time_of_day() -> float:
	return _time_of_day


## "18:30" 形式的时间字符串
func get_time_string() -> String:
	var h: int = int(floor(_time_of_day)) % 24
	var m: int = int(floor((_time_of_day - floor(_time_of_day)) * 60.0))
	return "%02d:%02d" % [h, m]


## 是否处于夜晚（用于烟花 / 演示模式的昼夜判断）
func is_night() -> bool:
	return get_night_factor() > 0.5


## 夜晚程度 0~1（DAY/SUNSET = 0，NIGHT = 1，自动昼夜下平滑过渡）
func get_night_factor() -> float:
	return float(_params.get("night_factor", 0.0))


## 当前太阳高度角（度）
func get_sun_pitch() -> float:
	return float(_params.get("sun_pitch_deg", 0.0))


## 画质档覆盖：由 quality_manager 注入
## 支持键：glow_enabled / fog_enabled / ssao_enabled / window_emission_scale
func set_quality_profile(profile: Dictionary) -> void:
	_quality = profile.duplicate()
	_apply(_params)


## 当前完整参数字典（基准脚本 / 调试用）
func get_params() -> Dictionary:
	return _params.duplicate()


## 太阳 / 月光节点（其他系统需要改阴影等参数时用）
func get_sun() -> DirectionalLight3D:
	return _sun


## 运行期 Environment（已被本管理器复制，改它不会污染 res:// 资源）
func get_environment() -> Environment:
	return _env


## 窗户自发光材质数量（性能报告用）
func get_window_material_count() -> int:
	return _window_materials.size()


# ---------------------------------------------------------------------------
# 内部：环境准备
# ---------------------------------------------------------------------------

func _prepare_environment() -> void:
	if _world_env == null or _world_env.environment == null:
		push_warning("[environment] 未找到 WorldEnvironment，昼夜系统仅作用于太阳光")
		return
	# 运行期复制，避免污染 res://materials/env_day.tres
	_env = _world_env.environment.duplicate(true)
	if _env.sky != null:
		_env.sky = _env.sky.duplicate(true)
		if _env.sky.sky_material is ProceduralSkyMaterial:
			_sky_mat = (_env.sky.sky_material as ProceduralSkyMaterial).duplicate(true)
			_env.sky.sky_material = _sky_mat
	_world_env.environment = _env
	# 环境光来源保持"天空"：夜间靠 ambient_light_energy 压低而不是直接熄灭
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY


## 收集窗户网格的材质，按源材质去重后改为自发光副本
func _collect_window_materials() -> void:
	_window_materials.clear()
	if _castle == null or not window_glow_enabled:
		return
	var cache: Dictionary = {}
	for node in _find_window_meshes(_castle):
		var mi := node as MeshInstance3D
		var mesh := mi.mesh
		if mesh == null:
			continue
		for i in range(mesh.get_surface_count()):
			var src: Material = mi.get_surface_override_material(i)
			if src == null and mesh != null:
				src = mesh.surface_get_material(i)
			var key: int = 0 if src == null else int(src.get_instance_id())
			var mat: StandardMaterial3D = cache.get(key)
			if mat == null:
				mat = _make_window_material(src)
				cache[key] = mat
				_window_materials.append(mat)
			mi.set_surface_override_material(i, mat)


func _find_window_meshes(root: Node) -> Array:
	var out: Array = []
	if root is MeshInstance3D and String(root.name).contains(window_node_keyword):
		out.append(root)
	for child in root.get_children():
		out.append_array(_find_window_meshes(child))
	return out


func _make_window_material(src: Material) -> StandardMaterial3D:
	var mat: StandardMaterial3D = null
	if src is StandardMaterial3D:
		mat = (src as StandardMaterial3D).duplicate(true) as StandardMaterial3D
	else:
		mat = StandardMaterial3D.new()
	mat.resource_name = "WinGlassNightEmissive"
	mat.emission_enabled = false
	mat.emission = Color(1.0, 0.78, 0.42, 1.0)
	mat.emission_energy_multiplier = 0.0
	mat.emission_operator = BaseMaterial3D.EMISSION_OP_ADD
	return mat


# ---------------------------------------------------------------------------
# 内部：参数计算与应用
# ---------------------------------------------------------------------------

func _set_target(params: Dictionary, duration: float) -> void:
	_from_params = _params.duplicate() if not _params.is_empty() else params.duplicate()
	_target_params = params
	_transition_duration = duration
	_transition_t = 0.0


## 根据时刻计算目标参数：关键帧之间插值 + 太阳/月亮角度按时间连续推进
func _params_for_time(t: float) -> Dictionary:
	var base: Dictionary = _preset_blend_at(t)
	base["sun_pitch_deg"] = _pitch_for_time(t)
	base["sun_yaw_deg"] = _yaw_for_time(t)
	return base


## 高度角：白天走正弦弧线（6:00 地平线 / 12:00 最高 62° / 18:00 落回地平线），
## 夜间沿用预设的"月光"高度角，并在日出日落前后各 1 小时内平滑衔接，保证全天无跳变。
func _pitch_for_time(t: float) -> float:
	if t >= 6.0 and t < 18.0:
		return 62.0 * sin(PI * (t - 6.0) / 12.0)
	var base_pitch: float = float(_preset_blend_at(t)["sun_pitch_deg"])
	if t >= 18.0 and t < 19.0:
		return lerpf(0.0, base_pitch, t - 18.0)
	if t >= 5.0 and t < 6.0:
		return lerpf(base_pitch, 0.0, t - 5.0)
	return base_pitch


## 方位角：白天 6:00(-150°) → 18:00(+70°) 连续西移；
## 夜间从 18:00 的 70° 继续同向缓慢西移，6:00 回到日出点（数值差 360°，方向一致）。
## 全程不做角度取模，避免最短路径插值在 180° 处反向绕圈。
func _yaw_for_time(t: float) -> float:
	if t >= 6.0 and t < 18.0:
		return -150.0 + (t - 6.0) / 12.0 * 220.0
	var night_hours: float = fposmod(t - 18.0, 24.0)
	return 70.0 + night_hours * (140.0 / 12.0)


## 关键帧之间的预设参数插值（不含太阳角度修正）
func _preset_blend_at(t: float) -> Dictionary:
	var i: int = 0
	for k in range(CYCLE_KEYFRAMES.size() - 1):
		if t >= float(CYCLE_KEYFRAMES[k]["t"]) and t <= float(CYCLE_KEYFRAMES[k + 1]["t"]):
			i = k
			break
	var t0: float = float(CYCLE_KEYFRAMES[i]["t"])
	var t1: float = float(CYCLE_KEYFRAMES[i + 1]["t"])
	var w: float = 0.0 if t1 <= t0 else clampf((t - t0) / (t1 - t0), 0.0, 1.0)
	var p0: Dictionary = _presets[int(CYCLE_KEYFRAMES[i]["preset"])].to_params()
	var p1: Dictionary = _presets[int(CYCLE_KEYFRAMES[i + 1]["preset"])].to_params()
	return _lerp_params(p0, p1, w)


func _nearest_preset_index(t: float) -> int:
	var idx: int = Preset.NIGHT
	for k in range(CYCLE_KEYFRAMES.size() - 1):
		if t >= float(CYCLE_KEYFRAMES[k]["t"]) and t <= float(CYCLE_KEYFRAMES[k + 1]["t"]):
			var t0: float = float(CYCLE_KEYFRAMES[k]["t"])
			var t1: float = float(CYCLE_KEYFRAMES[k + 1]["t"])
			var w: float = 0.0 if t1 <= t0 else (t - t0) / (t1 - t0)
			idx = int(CYCLE_KEYFRAMES[k]["preset"]) if w < 0.5 else int(CYCLE_KEYFRAMES[k + 1]["preset"])
			break
	return idx


func _lerp_params(a: Dictionary, b: Dictionary, w: float) -> Dictionary:
	var out: Dictionary = {}
	for key in b.keys():
		var vb: Variant = b[key]
		var va: Variant = a.get(key, vb)
		if vb is float or vb is int:
			out[key] = lerpf(float(va), float(vb), w)
		elif vb is Color:
			out[key] = (va as Color).lerp(vb as Color, w)
		else:
			out[key] = vb if w >= 0.5 else va
	return out


func _apply(p: Dictionary) -> void:
	if _env != null:
		_env.tonemap_exposure = float(p.exposure)
		_env.tonemap_white = float(p.tonemap_white)
		_env.ambient_light_color = p.ambient_color
		_env.ambient_light_energy = float(p.ambient_energy)
		_env.ambient_light_sky_contribution = float(p.ambient_sky_contribution)
		_env.fog_enabled = bool(p.fog_enabled) and bool(_quality.get("fog_enabled", true))
		_env.fog_light_color = p.fog_color
		_env.fog_density = float(p.fog_density)
		_env.fog_light_energy = float(p.fog_light_energy)
		_env.fog_sky_affect = float(p.fog_sky_affect)
		_env.glow_enabled = bool(p.glow_enabled) and bool(_quality.get("glow_enabled", true))
		_env.glow_intensity = float(p.glow_intensity)
		_env.glow_bloom = float(p.glow_bloom)
		_env.glow_hdr_threshold = float(p.glow_hdr_threshold)
		_env.ssao_enabled = bool(p.ssao_enabled) and bool(_quality.get("ssao_enabled", true))
		_env.ssao_intensity = float(p.ssao_intensity)

	if _sky_mat != null:
		_sky_mat.sky_top_color = p.sky_top_color
		_sky_mat.sky_horizon_color = p.sky_horizon_color
		_sky_mat.ground_bottom_color = p.ground_bottom_color
		_sky_mat.ground_horizon_color = p.ground_horizon_color
		_sky_mat.sky_energy_multiplier = float(p.sky_energy)
		_sky_mat.sun_angle_max = float(p.sun_angle_max)

	if _sun != null:
		_sun.light_color = p.sun_color
		_sun.light_energy = float(p.sun_energy)
		var pitch: float = deg_to_rad(float(p.sun_pitch_deg))
		var yaw: float = deg_to_rad(float(p.sun_yaw_deg))
		_sun.transform.basis = Basis.from_euler(Vector3(-pitch, yaw, 0.0))

	_apply_window_emission(
		float(p.window_emission_energy) * float(_quality.get("window_emission_scale", 1.0)),
		p.window_emission_color
	)


func _apply_window_emission(energy: float, color: Color) -> void:
	for mat in _window_materials:
		mat.emission_enabled = energy > 0.001
		mat.emission = color
		mat.emission_energy_multiplier = energy


# ---------------------------------------------------------------------------
# 内部：HUD
# ---------------------------------------------------------------------------

func _refresh_hud(force: bool = false) -> void:
	if not force and _hud_timer < hud_refresh_interval:
		return
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("set_environment_status"):
		hud.set_environment_status(
			"Time: %s  |  %s\nAuto Cycle: %s  |  Sun %.0f°"
			% [get_time_string(), get_preset_name(), "ON" if _auto_cycle else "OFF", get_sun_pitch()]
		)
