extends Area3D
class_name Interactable
## interactable.gd
## 通用可交互物基类（TASK03）。
##
## 设计目标：把"可交互"从玩家控制器里彻底解耦出来。
##   - 任何希望被准星射线选中并交互的东西，都继承本类（本质是一个 Area3D），
##     并按需覆写下面两个接口：
##         func get_interaction_text() -> String   # 准星指到时显示的提示
##         func interact(actor: Node) -> void      # 按下 E 时执行的逻辑
##   - interaction_controller.gd 只负责"发现目标 → 显示提示 → 派发 interact()"，
##     内部不出现任何具体热点（POI / 门 / 机关）的名字。
##
## 物理约定（重要）：
##   - 交互物只占"交互层"（第 3 层，collision_layer = 4），玩家射线
##     （InteractRay，collision_mask = 5 = 1|4）能打到它；
##   - 交互物自己的 collision_mask = 0，不参与任何碰撞检测，
##     因此既不会被 CharacterBody3D 推挤，也完全不影响玩家移动；
##   - 交互物不生成物理阻挡，玩家可以直接穿过热点体积。

## 准星指到此物体时显示的提示文本
@export var prompt_text: String = "Press E to interact"
## 是否允许交互（可在运行时临时关闭某个热点）
@export var interaction_enabled: bool = true


## 交互提示文本（子类可覆写为动态文本）
func get_interaction_text() -> String:
	return prompt_text


## 是否允许被交互（子类可覆写，例如"需要钥匙"之类的条件）
func can_interact(_actor: Node) -> bool:
	return interaction_enabled


## 执行一次交互（子类覆写）
func interact(_actor: Node) -> void:
	pass


## 说明面板当前是否展开
func is_panel_open() -> bool:
	return false


## 主动收起说明面板
func close_panel() -> void:
	pass
