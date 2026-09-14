extends Node3D
class_name FireworksController
## fireworks_controller.gd
## 可重复触发的烟花系统（GPUParticles3D）。
##
## 设计要点：
##   - 发射位来自场景中的子节点（Marker3D，默认 4 个），脚本为每个发射位创建一个
##     one_shot 的 GPUParticles3D；粒子数量 = 发射位数 × particle_amount，**恒定不累积**；
##   - 多发射位按 spawn_interval 循环齐射，每轮随机挑选 burst_count 个发射位，轮内错峰；
##   - 夜晚最明显：亮度/粒子量跟随昼夜系统的 night factor（白天压到 day_visibility）；
##   - F5 开关；关闭时立即停止发射（在飞的粒子自然消亡，不会无限累积）。
##
## 可调参数：enabled / spawn_interval / burst_count / particle_amount（另有 stagger、配色等）。

@export_group("State")
## 是否正在发射（F5 切换；演示模式也会打开它）
@export var enabled: bool = false

@export_group("Node References")
## 昼夜系统（提供 get_night_factor()）。留空则尝试 ../EnvironmentManager
@export var environment_manager_path: NodePath = ^"../EnvironmentManager"

@export_group("Timing")
## 两轮齐射之间的基础间隔（秒）
@export_range(0.1, 30.0, 0.05) var spawn_interval: float = 1.8
## 间隔随机抖动比例（0.35 表示 ±35%）
@export_range(0.0, 0.9, 0.01) var interval_jitter: float = 0.35
## 每轮点亮的发射位数量
@export_range(1, 8, 1) var burst_count: int = 2
## 同一轮内各发射位的最大错峰延迟（秒）
@export_range(0.0, 2.0, 0.01) var burst_stagger: float = 0.45
## 打开后的首次发射延迟（秒）
@export_range(0.0, 10.0, 0.05) var start_delay: float = 0.6

@export_group("Particles")
## 每个发射位的粒子数量
@export_range(32, 2048, 16) var particle_amount: int = 220
## 单个粒子寿命（秒）
@export_range(0.4, 6.0, 0.1) var particle_lifetime: float = 2.4
## 爆炸初速下限 / 上限
@export var particle_speed_min: float = 12.0
@export var particle_speed_max: float = 26.0
## 粒子重力（负值向下）
@export var particle_gravity: float = -7.0
## 是否开启拖尾（高画质更漂亮，低画质由 quality 关闭）
@export var trails_enabled: bool = true

@export_group("Night Response")
## 是否随昼夜变暗（白天压低可见度）
@export var night_only: bool = true
## 白天可见度比例（0 = 白天完全不可见）
@export_range(0.0, 1.0, 0.01) var day_visibility: float = 0.22

## 无子发射位时的兜底发射位（世界坐标，位于城堡上空）
const DEFAULT_LAUNCH_POINTS: Array = [
	Vector3(-70.0, 110.0, 60.0),
	Vector3(80.0, 120.0, 30.0),
	Vector3(0.0, 135.0, 90.0),
	Vector3(40.0, 125.0, -80.0),
]

## 配色板（每次发射随机取色）
const PALETTE: Array = [
	Color(1.0, 0.85, 0.35),
	Color(1.0, 0.45, 0.62),
	Color(0.55, 0.85, 1.0),
	Color(0.72, 1.0, 0.6),
	Color(0.95, 0.6, 1.0),
]

var _pads: Array[Node3D] = []
var _systems: Array[GPUParticles3D] = []
var _materials: Array[StandardMaterial3D] = []
var _queue: Array = []
var _env_mgr: Node = null
var _timer: float = 0.0
var _fired_total: int = 0
var _volley_total: int = 0
var _night_factor: float = 0.0
var _visibility_scale: float = 1.0
var _quality_scale: float = 1.0
var _applied_amount: int = 0


func _ready() -> void:
	add_to_group("fireworks")
	_env_mgr = get_node_or_null(environment_manager_path)
	_collect_pads()
	_build_systems()
	_timer = start_delay
	_apply_night_scale()
	if not enabled:
		_stop_emitting()
	_refresh_hud()


func _process(delta: float) -> void:
	_apply_night_scale()
	_process_queue(delta)
	if not enabled:
		return
	_timer -= delta
	if _timer <= 0.0:
		fire_volley()
		_timer = _next_interval()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("fireworks_toggle"):
		set_enabled(not enabled)


# ---------------------------------------------------------------------------
# 公开接口
# ---------------------------------------------------------------------------

## 开关烟花（F5 / 演示模式调用）
func set_enabled(value: bool) -> void:
	enabled = value
	if value:
		_timer = start_delay
	else:
		_queue.clear()
		_stop_emitting()
	_refresh_hud()


## 向 HUD 推送烟花状态（HUD 缺失时静默跳过）
func _refresh_hud() -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("set_fireworks_status"):
		hud.call("set_fireworks_status", enabled)


func is_enabled() -> bool:
	return enabled


## 立刻齐射一轮（不等 spawn_interval；验证脚本 / 演示模式用）
func fire_volley() -> void:
	if _systems.is_empty():
		return
	_volley_total += 1
	var count: int = clampi(burst_count, 1, _systems.size())
	var order: Array = []
	for i in _systems.size():
		order.append(i)
	order.shuffle()
	for k in count:
		var delay: float = 0.0
		if k > 0 and burst_stagger > 0.0:
			delay = randf_range(0.0, burst_stagger)
		_queue.append({"index": int(order[k]), "delay": delay})
	_fired_total += count


## 立刻触发指定发射位（index < 0 表示全部）
func fire_burst_now(index: int = -1) -> void:
	if _systems.is_empty():
		return
	if index < 0:
		for i in _systems.size():
			_launch(i)
		_fired_total += _systems.size()
	elif index < _systems.size():
		_launch(index)
		_fired_total += 1


## 画质缩放（TASK05 由 quality_manager 注入）：同时影响粒子数量与拖尾
func set_quality_scale(scale_value: float, use_trails: bool = true) -> void:
	_quality_scale = clampf(scale_value, 0.05, 1.0)
	trails_enabled = use_trails
	for sys in _systems:
		sys.trail_enabled = use_trails
	_apply_night_scale()


func get_pad_count() -> int:
	return _pads.size()


## 当前排队中的延迟发射（队列长度 / 各自剩余延迟），验证脚本用
func get_pending_delays() -> Array:
	var out: Array = []
	for item in _queue:
		out.append(float(item.get("delay", 0.0)))
	return out


## 正在发射的粒子系统数量
func get_emitting_count() -> int:
	var n := 0
	for sys in _systems:
		if sys.emitting:
			n += 1
	return n


func get_system_count() -> int:
	return _systems.size()


func get_launch_points() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for pad in _pads:
		out.append(pad.global_position)
	return out


## 单发满配粒子数
func get_particle_amount() -> int:
	return particle_amount


## 粒子预算（发射位 × 每发粒子数 × 画质系数），恒定值，不随时间增长
func get_total_particle_budget() -> int:
	var per_system: int = _applied_amount if _applied_amount > 0 else particle_amount
	return _systems.size() * per_system


## 当前可见度系数（夜晚 1.0，白天 day_visibility）
func get_visibility_scale() -> float:
	return _visibility_scale


func get_night_factor() -> float:
	return _night_factor


## 累计发射次数（验证脚本判断"确实在发射"）
func get_fired_total() -> int:
	return _fired_total


func get_volley_total() -> int:
	return _volley_total


func get_pending_count() -> int:
	return _queue.size()


## 各发射位的当前粒子数（用于确认没有无限累积）
func get_system_amounts() -> Array[int]:
	var out: Array[int] = []
	for sys in _systems:
		out.append(sys.amount)
	return out


# ---------------------------------------------------------------------------
# 内部
# ---------------------------------------------------------------------------

func _next_interval() -> float:
	var jitter: float = clampf(interval_jitter, 0.0, 0.9)
	return maxf(0.05, spawn_interval * randf_range(1.0 - jitter, 1.0 + jitter))


func _stop_emitting() -> void:
	for sys in _systems:
		sys.emitting = false


## 收集场景中的子接收点（Marker3D）；没有则用内置兜底点生成
func _collect_pads() -> void:
	_pads.clear()
	for child in get_children():
		if child is GPUParticles3D:
			continue
		if child is Node3D:
			_pads.append(child)
	if _pads.is_empty():
		for point in DEFAULT_LAUNCH_POINTS:
			var pad := Marker3D.new()
			pad.name = "Pad%d" % (get_child_count() + 1)
			pad.position = point
			add_child(pad)
			_pads.append(pad)


func _build_systems() -> void:
	for i in _pads.size():
		var sys := GPUParticles3D.new()
		sys.name = "Burst%d" % (i + 1)
		sys.amount = particle_amount
		sys.lifetime = particle_lifetime
		sys.one_shot = true
		sys.explosiveness = 1.0
		sys.fixed_fps = 30
		sys.local_coords = false
		sys.trail_enabled = trails_enabled
		sys.draw_pass_1 = _make_draw_mesh(i)
		sys.process_material = _make_process_material()
		sys.emitting = false
		_pads[i].add_child(sys)
		_systems.append(sys)


## 每个发射位使用独立的材质实例，便于单独改色（数量固定，不累积）
func _make_draw_mesh(index: int) -> QuadMesh:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = PALETTE[index % PALETTE.size()]
	mat.emission_enabled = true
	mat.emission = mat.albedo_color
	mat.emission_energy_multiplier = 3.0
	mat.disable_receive_shadows = true
	mat.disable_ambient_light = true
	var mesh := QuadMesh.new()
	mesh.size = Vector2(1.4, 1.4)
	mesh.material = mat
	_materials.append(mat)
	return mesh


func _make_process_material() -> ParticleProcessMaterial:
	var pmat := ParticleProcessMaterial.new()
	pmat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pmat.emission_sphere_radius = 0.5
	pmat.direction = Vector3(0.0, 1.0, 0.0)
	pmat.spread = 180.0
	pmat.initial_velocity_min = particle_speed_min
	pmat.initial_velocity_max = particle_speed_max
	pmat.gravity = Vector3(0.0, particle_gravity, 0.0)
	pmat.damping_min = 0.4
	pmat.damping_max = 1.4
	pmat.scale_min = 0.5
	pmat.scale_max = 1.6
	pmat.color = Color(1.0, 1.0, 1.0)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	ramp.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var tex := GradientTexture1D.new()
	tex.gradient = ramp
	pmat.color_ramp = tex
	return pmat


func _launch(index: int) -> void:
	if index < 0 or index >= _systems.size():
		return
	var sys := _systems[index]
	if sys == null:
		return
	if index < _materials.size():
		var color: Color = PALETTE[randi() % PALETTE.size()]
		_materials[index].albedo_color = color
		_materials[index].emission = color
	sys.restart()
	sys.emitting = true


func _process_queue(delta: float) -> void:
	if _queue.is_empty():
		return
	for i in range(_queue.size() - 1, -1, -1):
		var item: Dictionary = _queue[i]
		item["delay"] = float(item["delay"]) - delta
		if float(item["delay"]) <= 0.0:
			_launch(int(item["index"]))
			_queue.remove_at(i)


func _read_night_factor() -> float:
	if _env_mgr == null or not _env_mgr.has_method("get_night_factor"):
		_env_mgr = get_node_or_null(environment_manager_path)
		if _env_mgr == null or not _env_mgr.has_method("get_night_factor"):
			return 1.0
	return clampf(float(_env_mgr.call("get_night_factor")), 0.0, 1.0)


## 跟随昼夜调整可见度：夜晚 1.0，白天 day_visibility；同时乘上画质系数
func _apply_night_scale() -> void:
	_night_factor = _read_night_factor()
	var base: float = lerpf(day_visibility, 1.0, _night_factor) if night_only else 1.0
	_visibility_scale = clampf(base * _quality_scale, 0.0, 1.0)
	# 注意：amount 只在真正变化时赋值（改 amount 会重建粒子缓冲，不能每帧写）
	var target_amount: int = maxi(8, int(round(particle_amount * _quality_scale)))
	if target_amount != _applied_amount:
		_applied_amount = target_amount
		for sys in _systems:
			sys.amount = target_amount
	for sys in _systems:
		sys.amount_ratio = maxf(_visibility_scale, 0.05)
		sys.visible = _visibility_scale > 0.03
