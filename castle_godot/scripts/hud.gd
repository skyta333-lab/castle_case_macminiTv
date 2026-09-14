extends CanvasLayer
class_name GameHud
## hud.gd
## 统一 HUD。各子系统只调用这里的公开方法，避免互相耦合：
##   - 操作说明（左上，常驻）
##   - 状态信息（右上：镜头模式 / 昼夜状态）
##   - 画质信息（右上第二行）
##   - 准星 + 交互提示（中央）
##   - POI 面板（中下）
##   - 性能读数（左下，F7 开关）

@onready var controls_label: Label = $ControlsLabel
@onready var status_label: Label = $StatusLabel
@onready var quality_label: Label = $QualityLabel
@onready var crosshair_label: Label = $CrosshairLabel
@onready var prompt_label: Label = $PromptLabel
@onready var poi_title_label: Label = $PoiTitleLabel
@onready var poi_desc_label: Label = $PoiDescLabel
@onready var perf_label: Label = $PerfLabel

var _mode_text: String = ""
var _env_text: String = ""


func _ready() -> void:
	add_to_group("hud")
	_mode_text = "Camera: Showcase (1)"
	_env_text = "Time 12:00 | DAY | Auto OFF"
	_refresh_status()
	set_quality_status("MEDIUM")
	set_crosshair_visible(false)
	set_prompt("")
	hide_poi()
	set_perf_visible(false)


## 镜头模式（第一行）
func set_mode_name(mode_name: String) -> void:
	_mode_text = "Camera: %s" % mode_name
	_refresh_status()


## 昼夜 / 时间状态（第二行，多行内容用换行拼）
func set_environment_status(text: String) -> void:
	_env_text = text
	_refresh_status()


## 画质档位
func set_quality_status(text: String) -> void:
	if quality_label != null:
		quality_label.text = "Quality: %s" % text


func set_crosshair_visible(visible_now: bool) -> void:
	if crosshair_label != null:
		crosshair_label.visible = visible_now


## 准星下的交互提示，传空串即隐藏
func set_prompt(text: String) -> void:
	if prompt_label == null:
		return
	prompt_label.text = text
	prompt_label.visible = text != ""


func show_poi(title: String, description: String) -> void:
	if poi_title_label != null:
		poi_title_label.text = title
		poi_title_label.visible = true
	if poi_desc_label != null:
		poi_desc_label.text = "%s\n\n[E] Close" % description
		poi_desc_label.visible = true


func hide_poi() -> void:
	if poi_title_label != null:
		poi_title_label.visible = false
	if poi_desc_label != null:
		poi_desc_label.visible = false


func is_poi_visible() -> bool:
	return poi_title_label != null and poi_title_label.visible


func set_perf_visible(visible_now: bool) -> void:
	if perf_label != null:
		perf_label.visible = visible_now


func is_perf_visible() -> bool:
	return perf_label != null and perf_label.visible


func set_perf_text(text: String) -> void:
	if perf_label != null:
		perf_label.text = text


func _refresh_status() -> void:
	if status_label != null:
		status_label.text = "%s\n%s" % [_mode_text, _env_text]
