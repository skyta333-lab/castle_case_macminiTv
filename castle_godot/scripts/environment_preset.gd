extends Resource
class_name EnvironmentPreset
## environment_preset.gd
## 单个昼夜预设的全部关键参数：天空 / 太阳（月亮）/ 环境光 / 曝光 / 雾 / 辉光 / 窗户自发光。
##
## 设计：
##   - 每个字段都用 @export 暴露，可直接在检查器里调，也可另存为 .tres 复用；
##   - 内置 DAY / SUNSET / NIGHT 三套默认值（静态工厂方法），
##     environment_manager.gd 若未在检查器里指定自定义预设，就回退到这些默认值；
##   - to_params() 输出参数字典，供环境管理器做插值过渡（昼夜连续变化）。

@export var preset_name: String = "DAY"
## 夜晚程度（0 = 白天 / 黄昏，1 = 完全夜晚）：供烟花、演示模式等系统判断昼夜
@export_range(0.0, 1.0, 0.01) var night_factor: float = 0.0

@export_group("Sky")
## 天顶颜色
@export var sky_top_color: Color = Color(0.255, 0.49, 0.804, 1.0)
## 地平线颜色
@export var sky_horizon_color: Color = Color(0.749, 0.847, 0.941, 1.0)
## 地面（天空球下半）底部颜色
@export var ground_bottom_color: Color = Color(0.196, 0.267, 0.184, 1.0)
## 地面（天空球下半）地平线颜色
@export var ground_horizon_color: Color = Color(0.6, 0.678, 0.62, 1.0)
## 天空整体亮度倍率
@export_range(0.0, 4.0, 0.01) var sky_energy: float = 1.0
## 程序化天空的"太阳圆盘"张角（度），越小越锐利
@export_range(0.0, 90.0, 0.5) var sun_angle_max: float = 30.0

@export_group("Sun / Moon")
@export var sun_color: Color = Color(1.0, 0.957, 0.878, 1.0)
@export_range(0.0, 8.0, 0.01) var sun_energy: float = 1.35
## 太阳高度角（度）：90 = 正上方，0 = 地平线，负值 = 落到地平线以下
@export_range(-90.0, 90.0, 0.5) var sun_pitch_deg: float = 52.0
## 太阳方位角（度）
@export_range(-180.0, 180.0, 1.0) var sun_yaw_deg: float = -40.0

@export_group("Ambient")
@export var ambient_color: Color = Color(0.749, 0.847, 0.941, 1.0)
@export_range(0.0, 4.0, 0.01) var ambient_energy: float = 1.0
## 环境光中来自天空的比例
@export_range(0.0, 1.0, 0.01) var ambient_sky_contribution: float = 1.0

@export_group("Tonemap")
@export_range(0.1, 4.0, 0.01) var exposure: float = 1.0
@export_range(1.0, 16.0, 0.5) var tonemap_white: float = 6.0

@export_group("Fog")
@export var fog_enabled: bool = true
@export var fog_color: Color = Color(0.784, 0.859, 0.922, 1.0)
@export_range(0.0, 0.02, 0.0001) var fog_density: float = 0.0008
@export_range(0.0, 4.0, 0.01) var fog_light_energy: float = 1.0
@export_range(0.0, 1.0, 0.01) var fog_sky_affect: float = 1.0

@export_group("Glow")
@export var glow_enabled: bool = true
@export_range(0.0, 4.0, 0.05) var glow_intensity: float = 0.5
@export_range(0.0, 1.0, 0.01) var glow_bloom: float = 0.05
@export_range(0.0, 4.0, 0.05) var glow_hdr_threshold: float = 1.0

@export_group("SSAO")
@export var ssao_enabled: bool = true
@export_range(0.1, 8.0, 0.1) var ssao_intensity: float = 1.6

@export_group("Night Windows")
## 窗户材质自发光强度（0 = 不发光，白天用 0；不新增任何实时灯）
@export_range(0.0, 8.0, 0.05) var window_emission_energy: float = 0.0
## 窗户自发光颜色（暖色）
@export var window_emission_color: Color = Color(1.0, 0.78, 0.42, 1.0)


## 输出参数字典（供环境管理器插值与套用）
func to_params() -> Dictionary:
	return {
		"night_factor": night_factor,
		"sky_top_color": sky_top_color,
		"sky_horizon_color": sky_horizon_color,
		"ground_bottom_color": ground_bottom_color,
		"ground_horizon_color": ground_horizon_color,
		"sky_energy": sky_energy,
		"sun_angle_max": sun_angle_max,
		"sun_color": sun_color,
		"sun_energy": sun_energy,
		"sun_pitch_deg": sun_pitch_deg,
		"sun_yaw_deg": sun_yaw_deg,
		"ambient_color": ambient_color,
		"ambient_energy": ambient_energy,
		"ambient_sky_contribution": ambient_sky_contribution,
		"exposure": exposure,
		"tonemap_white": tonemap_white,
		"fog_enabled": fog_enabled,
		"fog_color": fog_color,
		"fog_density": fog_density,
		"fog_light_energy": fog_light_energy,
		"fog_sky_affect": fog_sky_affect,
		"glow_enabled": glow_enabled,
		"glow_intensity": glow_intensity,
		"glow_bloom": glow_bloom,
		"glow_hdr_threshold": glow_hdr_threshold,
		"ssao_enabled": ssao_enabled,
		"ssao_intensity": ssao_intensity,
		"window_emission_energy": window_emission_energy,
		"window_emission_color": window_emission_color,
	}


# ---------------------------------------------------------------------------
# 三套内置默认预设
# ---------------------------------------------------------------------------

## 白天：与原有 env_day.tres 的观感保持一致（略提亮）
static func make_day() -> EnvironmentPreset:
	var p := EnvironmentPreset.new()
	p.preset_name = "DAY"
	p.night_factor = 0.0
	p.sky_top_color = Color(0.255, 0.49, 0.804, 1.0)
	p.sky_horizon_color = Color(0.749, 0.847, 0.941, 1.0)
	p.ground_bottom_color = Color(0.196, 0.267, 0.184, 1.0)
	p.ground_horizon_color = Color(0.6, 0.678, 0.62, 1.0)
	p.sky_energy = 1.0
	p.sun_angle_max = 30.0
	p.sun_color = Color(1.0, 0.957, 0.878, 1.0)
	p.sun_energy = 1.35
	p.sun_pitch_deg = 52.0
	p.sun_yaw_deg = -40.0
	p.ambient_color = Color(0.749, 0.847, 0.941, 1.0)
	p.ambient_energy = 1.0
	p.ambient_sky_contribution = 1.0
	p.exposure = 1.0
	p.tonemap_white = 6.0
	p.fog_enabled = true
	p.fog_color = Color(0.784, 0.859, 0.922, 1.0)
	p.fog_density = 0.0008
	p.fog_light_energy = 1.0
	p.fog_sky_affect = 1.0
	p.glow_enabled = true
	p.glow_intensity = 0.5
	p.glow_bloom = 0.05
	p.glow_hdr_threshold = 1.1
	p.ssao_enabled = true
	p.ssao_intensity = 1.6
	p.window_emission_energy = 0.0
	return p


## 黄昏：低角度暖阳 + 橙紫天空 + 厚雾 + 少量灯光
static func make_sunset() -> EnvironmentPreset:
	var p := EnvironmentPreset.new()
	p.preset_name = "SUNSET"
	p.night_factor = 0.0
	p.sky_top_color = Color(0.176, 0.235, 0.478, 1.0)
	p.sky_horizon_color = Color(0.965, 0.549, 0.286, 1.0)
	p.ground_bottom_color = Color(0.106, 0.09, 0.118, 1.0)
	p.ground_horizon_color = Color(0.451, 0.286, 0.243, 1.0)
	p.sky_energy = 1.0
	p.sun_angle_max = 18.0
	p.sun_color = Color(1.0, 0.588, 0.302, 1.0)
	p.sun_energy = 1.05
	p.sun_pitch_deg = 9.0
	p.sun_yaw_deg = 70.0
	p.ambient_color = Color(0.855, 0.553, 0.42, 1.0)
	p.ambient_energy = 0.55
	p.ambient_sky_contribution = 1.0
	p.exposure = 1.0
	p.tonemap_white = 6.0
	p.fog_enabled = true
	p.fog_color = Color(0.925, 0.62, 0.451, 1.0)
	p.fog_density = 0.0016
	p.fog_light_energy = 1.25
	p.fog_sky_affect = 0.85
	p.glow_enabled = true
	p.glow_intensity = 0.9
	p.glow_bloom = 0.15
	p.glow_hdr_threshold = 1.0
	p.ssao_enabled = true
	p.ssao_intensity = 1.2
	p.window_emission_energy = 1.2
	p.window_emission_color = Color(1.0, 0.741, 0.376, 1.0)
	return p


## 夜晚：深蓝夜空 + 微弱月光 + 暖色窗户 + 冷雾，保证城堡轮廓仍可辨认
static func make_night() -> EnvironmentPreset:
	var p := EnvironmentPreset.new()
	p.preset_name = "NIGHT"
	p.night_factor = 1.0
	p.sky_top_color = Color(0.019, 0.031, 0.086, 1.0)
	p.sky_horizon_color = Color(0.058, 0.082, 0.161, 1.0)
	p.ground_bottom_color = Color(0.008, 0.012, 0.027, 1.0)
	p.ground_horizon_color = Color(0.047, 0.058, 0.11, 1.0)
	p.sky_energy = 0.55
	p.sun_angle_max = 6.0
	# 夜里这盏 DirectionalLight3D 当作"月光"用：冷色、低能量、从另一侧照
	p.sun_color = Color(0.55, 0.686, 1.0, 1.0)
	p.sun_energy = 0.17
	p.sun_pitch_deg = 58.0
	p.sun_yaw_deg = 140.0
	p.ambient_color = Color(0.157, 0.216, 0.412, 1.0)
	p.ambient_energy = 0.28
	p.ambient_sky_contribution = 1.0
	p.exposure = 0.9
	p.tonemap_white = 6.0
	p.fog_enabled = true
	p.fog_color = Color(0.09, 0.118, 0.251, 1.0)
	p.fog_density = 0.0022
	p.fog_light_energy = 0.6
	p.fog_sky_affect = 0.7
	p.glow_enabled = true
	p.glow_intensity = 1.1
	p.glow_bloom = 0.2
	p.glow_hdr_threshold = 0.85
	p.ssao_enabled = false
	p.ssao_intensity = 1.0
	p.window_emission_energy = 2.6
	p.window_emission_color = Color(1.0, 0.722, 0.376, 1.0)
	return p
