extends SceneTree
## tools/verify_interaction.gd
## TASK03 自检脚本（headless，无需显示服务器）：
##   1. 场景与碰撞体装配健全性
##   2. 玩家落地 / WASD 移动未受交互系统影响
##   3. 准星射线能稳定命中 6 个 POI 热点（每个热点一个用例）
##   4. 提示文本 / POI 说明面板（E 开合、可关闭）
##   5. 正门门叶开合动画（运行时改 transform，不动 GLB）
##   6. F8 marker 批量显隐
##
## 用法：
##   Godot --headless --path . --script res://tools/verify_interaction.gd
## 退出码 0 = 全部通过；1 = 存在失败项。

const MAIN_SCENE := "res://scenes/main.tscn"
## Player/Head 的本地高度（player.tscn 中 Head 位于 (0, 2.6, 0)）
const EYE_HEIGHT := 2.6

## 用例：站位（地面 y=4.0 的前庭/台基上） / 准星瞄向 / 期望命中的 POI
var _cases: Array = [
	{
		"label": "正门",
		"stand": Vector3(0.0, 4.4, 34.0),
		"aim": Vector3(0.0, 7.0, 26.2),
		"expect": "POI_Gate",
	},
	{
		"label": "中央主塔",
		"stand": Vector3(0.0, 4.4, 34.0),
		"aim": Vector3(0.0, 13.0, 30.5),
		"expect": "POI_CentralTower",
	},
	{
		"label": "西塔",
		"stand": Vector3(-10.0, 4.4, 36.0),
		"aim": Vector3(-10.0, 13.0, 27.0),
		"expect": "POI_WestTower",
	},
	{
		"label": "东塔",
		"stand": Vector3(10.0, 4.4, 36.0),
		"aim": Vector3(10.0, 13.0, 27.0),
		"expect": "POI_EastTower",
	},
	{
		"label": "门前旗帜",
		"stand": Vector3(-15.0, 4.4, 38.0),
		"aim": Vector3(-15.0, 11.0, 29.0),
		"expect": "POI_GateBanners",
	},
	{
		"label": "台基露台",
		"stand": Vector3(-25.0, 4.4, 41.5),
		"aim": Vector3(-25.0, 5.5, 34.0),
		"expect": "POI_PodiumTerrace",
	},
]

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(label: String, ok: bool, detail: String = "") -> void:
	var suffix := ("  -> " + detail) if detail != "" else ""
	if ok:
		_pass += 1
		print("  [PASS] %s%s" % [label, suffix])
	else:
		_fail += 1
		print("  [FAIL] %s%s" % [label, suffix])


func _run() -> void:
	print("=== TASK03 verify: interaction & POI ===")

	var packed := load(MAIN_SCENE) as PackedScene
	if packed == null:
		_check("加载主场景", false, MAIN_SCENE)
		_finish()
		return
	var scene: Node = packed.instantiate()
	root.add_child(scene)
	for i in 5:
		await process_frame

	var player := scene.get_node_or_null("Player") as PlayerController
	var cam_mgr: Node = scene.get_node_or_null("CameraModeManager")
	var hud := scene.get_node_or_null("HUD") as GameHud
	var ic := scene.get_node_or_null("InteractionController") as InteractionController
	var poi_set: Node = scene.get_node_or_null("PoiSet")
	var collision: Node = scene.get_node_or_null("WorldCollision")
	var castle: Node = scene.get_node_or_null("Castle")

	# ---------------------------------------------------------------- A. 装配
	print("\n[A] 场景装配")
	_check("Player 节点存在", player != null)
	_check("CameraModeManager 存在", cam_mgr != null)
	_check("HUD 存在", hud != null)
	_check("InteractionController 存在", ic != null)
	_check("PoiSet 存在", poi_set != null)
	_check("Castle (GLB) 存在", castle != null)
	if player == null or ic == null or hud == null or cam_mgr == null or castle == null:
		_finish()
		return

	# 切到第一人称（自动化需要玩家激活 + 射线跟随相机）
	cam_mgr.call("set_mode", 2)
	await process_frame
	_check("切到第一人称后玩家被激活", player.active)

	var body_count := 0
	if collision != null:
		body_count = collision.get_child_count()
	_check("程序化碰撞体已生成", body_count > 0, "%d 个碰撞节点" % body_count)

	_check("InteractRay 为 RayCast3D 且已启用", player.get_interact_ray() != null and player.get_interact_ray().enabled)
	var ray_mask: int = player.get_interact_ray().collision_mask if player.get_interact_ray() != null else 0
	_check("InteractRay 掩码含交互层(4)", (ray_mask & 4) != 0, "mask=%d" % ray_mask)

	# InputMap：E / F8
	var e_ok := false
	var f8_ok := false
	if InputMap.has_action("interact"):
		for ev in InputMap.action_get_events("interact"):
			if ev is InputEventKey and (ev as InputEventKey).physical_keycode == KEY_E:
				e_ok = true
	if InputMap.has_action("toggle_poi_markers"):
		for ev in InputMap.action_get_events("toggle_poi_markers"):
			if ev is InputEventKey and (ev as InputEventKey).physical_keycode == KEY_F8:
				f8_ok = true
	_check("输入映射 interact = E", e_ok)
	_check("输入映射 toggle_poi_markers = F8", f8_ok)

	var pois := ic.get_poi_nodes()
	_check("POI 热点数量 >= 5", pois.size() >= 5, "%d 个" % pois.size())

	var titles := {}
	var descs := {}
	var all_have_text := true
	var all_hidden := true
	for n in pois:
		var poi := n as PoiInteractable
		if poi == null:
			all_have_text = false
			continue
		if poi.poi_title.strip_edges() == "" or poi.get_poi_description().strip_edges() == "":
			all_have_text = false
		titles[poi.poi_title] = true
		descs[poi.get_poi_description()] = true
		if poi.is_marker_visible():
			all_hidden = false
	_check("每个 POI 都有标题与说明", all_have_text)
	_check("POI 标题互不相同", titles.size() == pois.size(), "%d 个不同标题" % titles.size())
	_check("POI 说明互不相同且 >= 5 条", descs.size() >= 5, "%d 条不同说明" % descs.size())
	_check("marker 默认隐藏", all_hidden and not ic.are_markers_visible())

	# ---------------------------------------------------- B. 地面 / 移动不受影响
	print("\n[B] 玩家落地与移动（交互系统不得影响移动）")
	player.set_physics_process(true)
	var head_node := player.get_node_or_null("Head") as Node3D
	player.rotation.y = 0.0
	if head_node != null:
		head_node.rotation.x = 0.0
	player.teleport_to(Vector3(0.0, 5.0, 40.0))
	for i in 90:
		await physics_frame
	var ground_y := player.global_position.y
	_check(
		"玩家落地并稳定站在前庭平台",
		player.is_on_floor() and absf(player.velocity.y) < 0.1 and ground_y > 3.5 and ground_y < 5.0,
		"y=%.2f on_floor=%s" % [ground_y, str(player.is_on_floor())]
	)

	var start_z := player.global_position.z
	Input.action_press("move_forward")
	for i in 60:
		await physics_frame
	Input.action_release("move_forward")
	var moved := start_z - player.global_position.z
	_check("WASD 前进有效（热点体积不阻挡玩家）", moved > 1.0, "前进 %.2f m" % moved)

	# ------------------------------------------------------------ C. 射线命中
	print("\n[C] 准星射线命中各 POI")
	player.set_physics_process(false)
	var hit_map := {}
	for c in _cases:
		var stand: Vector3 = c["stand"]
		var aim: Vector3 = c["aim"]
		player.teleport_to(stand)
		await _aim_and_wait(player, aim, 3)
		var target := ic.get_target()
		var got: String = String(target.name) if target != null else "<空>"
		var ok: bool = got == c["expect"]
		hit_map[c["expect"]] = ok
		_check("准星指向「%s」命中 %s" % [c["label"], c["expect"]], ok, "实际命中 %s" % got)

	# ------------------------------------------------- D. 提示文本 / 说明面板
	print("\n[D] 交互提示与 POI 说明面板")
	player.teleport_to(_cases[1]["stand"])
	await _aim_and_wait(player, _cases[1]["aim"], 3)
	var poi_tower := ic.get_target() as PoiInteractable
	_check("射线锁定 PoiInteractable", poi_tower != null)
	if poi_tower != null:
		var prompt := hud.prompt_label.text
		_check("HUD 显示 E 交互提示", prompt.contains("E") and prompt.contains(poi_tower.poi_title), "\"%s\"" % prompt)
		_check("提示可见", hud.prompt_label.visible)

		ic.handle_interact()
		await process_frame
		_check("按 E 展开说明面板", poi_tower.is_panel_open() and hud.is_poi_visible())
		_check("面板标题正确", hud.poi_title_label.text == poi_tower.poi_title, "\"%s\"" % hud.poi_title_label.text)
		_check("面板正文含说明与关闭提示", hud.poi_desc_label.text.contains("[E] Close") and hud.poi_desc_label.text.length() > 30)

		ic.handle_interact()
		await process_frame
		_check("再按 E 关闭面板", not poi_tower.is_panel_open() and not hud.is_poi_visible())

		# 空手：准星指向天空时不应锁定任何热点，提示随之隐藏
		player.teleport_to(Vector3(0.0, 4.45, 40.0))
		await _aim_and_wait(player, Vector3(0.0, 80.0, 8.0), 3)
		_check("准星指向天空时无交互目标", ic.get_target() == null and not hud.prompt_label.visible)

	# ------------------------------------------------------------- E. 正门开合
	print("\n[E] 正门门叶开合（仅改运行时 transform）")
	var gate := poi_set.get_node_or_null("GateController") as GateController
	_check("GateController 存在", gate != null)
	if gate != null:
		_check("GLB 中门叶可独立控制", gate.is_available(), "Gate_Door_W / Gate_Door_E")
		var door := castle.get_node_or_null("Gate_Door_W") as Node3D
		var rest := door.transform if door != null else Transform3D()
		gate.set_open(true)
		var opened := await _wait_for(func(): return gate.get_progress() >= 0.9999999, 8000)
		_check("门叶开启动画完成", opened, "progress=%.6f" % gate.get_progress())
		if door != null:
			var angle := rad_to_deg(rest.basis.get_rotation_quaternion().angle_to(door.transform.basis.get_rotation_quaternion()))
			_check("门叶绕铰链旋转约 95°", absf(angle - gate.open_angle_degrees) < 5.0, "实测 %.1f°" % angle)
		gate.set_open(false)
		var closed := await _wait_for(func(): return gate.get_progress() <= 0.0000001, 8000)
		_check("门叶关闭动画完成", closed, "progress=%.6f" % gate.get_progress())
		if door != null:
			var delta := (door.transform.origin - rest.origin).length()
			var basis_delta := 0.0
			for col in 3:
				basis_delta = maxf(basis_delta, (door.transform.basis[col] - rest.basis[col]).length())
			_check(
				"关门后回到初始 transform",
				door.transform.is_equal_approx(rest),
				"Δorigin=%.8f Δbasis=%.8f" % [delta, basis_delta]
			)

	# --------------------------------------------------------------- F. F8 marker
	print("\n[F] F8 批量显隐 POI marker")
	ic.set_markers_visible(true)
	await process_frame
	var all_on := ic.are_markers_visible()
	for n in pois:
		var p := n as PoiInteractable
		if p != null and not p.is_marker_visible():
			all_on = false
	_check("F8 打开：全部 marker 可见", all_on)
	ic.set_markers_visible(false)
	await process_frame
	var all_off := not ic.are_markers_visible()
	for n in pois:
		var p := n as PoiInteractable
		if p != null and p.is_marker_visible():
			all_off = false
	_check("F8 关闭：全部 marker 隐藏", all_off)

	_finish()


## 把玩家摆到 stand，并把视角对准 aim（迭代 3 次以抵消相机实际位置偏差），
## 再额外等 frames 帧，让 InteractionController 完成一次目标判定。
func _aim_and_wait(player: PlayerController, aim: Vector3, frames: int) -> void:
	var head := player.get_node_or_null("Head") as Node3D
	for i in 3:
		var cam := player.get_active_camera()
		var eye: Vector3 = cam.global_position if cam != null else player.global_position + Vector3(0.0, EYE_HEIGHT, 0.0)
		var d := aim - eye
		player.rotation.y = atan2(-d.x, -d.z)
		if head != null:
			head.rotation.x = atan2(d.y, sqrt(d.x * d.x + d.z * d.z))
		await process_frame
	for i in frames:
		await process_frame


## 轮询等待条件成立（Tween 之类按真实时间推进，故用挂钟兜底）
func _wait_for(predicate: Callable, timeout_ms: int) -> bool:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < timeout_ms:
		if predicate.call():
			return true
		await process_frame
	return predicate.call()


func _finish() -> void:
	print("\n=== TASK03 verify result: %d passed, %d failed ===" % [_pass, _fail])
	if _fail == 0:
		print("TASK03_VERIFY_PASS")
	else:
		print("TASK03_VERIFY_FAIL")
	quit(0 if _fail == 0 else 1)
