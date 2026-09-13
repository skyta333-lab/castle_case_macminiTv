extends SceneTree
## tools/verify_project.gd
## 命令行自检脚本：无需图形界面即可验证 castle_godot 工程是否可正常加载。
## 用法：
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path <工程目录> --script res://tools/verify_project.gd
## 退出码 0 表示全部检查通过，非 0 表示存在失败项。

const MAIN_SCENE := "res://scenes/main.tscn"
const MODEL_PATH := "res://assets/models/castle_ref_model.glb"

var _checks: Array = []


func _initialize() -> void:
	print("=== castle_godot 工程自检 ===")
	print("Godot 版本: %s" % Engine.get_version_info()["string"])

	_check_file("project.godot", "res://project.godot")
	_check_file("主场景 main.tscn", MAIN_SCENE)
	_check_file("城堡模型 castle_ref_model.glb", MODEL_PATH)
	_check_file("材质 ground_grass.tres", "res://materials/ground_grass.tres")
	_check_file("环境 env_day.tres", "res://materials/env_day.tres")
	_check_file("脚本 castle_showcase.gd", "res://scripts/castle_showcase.gd")

	# 1) 模型导入结果可加载且为 PackedScene
	var model_res: Resource = load(MODEL_PATH)
	if model_res is PackedScene:
		var inst: Node = (model_res as PackedScene).instantiate()
		var mesh_count: int = _count_meshes(inst)
		_ok("模型加载为 PackedScene", true)
		_ok("模型网格节点数 %d (>0)" % mesh_count, mesh_count > 0)
		root.add_child(inst)
		await process_frame
		var aabb: AABB = _merge_aabb(inst)
		_ok("模型世界包围盒有效 (高度 %.2f > 0)" % aabb.size.y, aabb.size.y > 0.0)
		print("    模型世界包围盒尺寸: %s , 中心: %s" % [str(aabb.size), str(aabb.get_center())])
		inst.queue_free()
	else:
		_ok("模型加载为 PackedScene", false)

	# 2) 主场景实例化 + 节点校验
	var scene_res: Resource = load(MAIN_SCENE)
	if scene_res is PackedScene:
		_ok("主场景加载为 PackedScene", true)
		var scene: Node = (scene_res as PackedScene).instantiate()
		var required := {
			"WorldEnvironment": "WorldEnvironment",
			"SunLight": "DirectionalLight3D",
			"Ground": "MeshInstance3D",
			"Castle": "Node3D",
			"MainCamera": "Camera3D",
		}
		for node_name in required.keys():
			var found: Node = scene.get_node_or_null(NodePath(node_name))
			_ok("场景节点 %s (%s)" % [node_name, required[node_name]],
				found != null and found.get_class() == required[node_name])
		var cam: Camera3D = scene.get_node_or_null("MainCamera")
		if cam != null:
			_ok("主相机为 current", cam.current)
		var env_node: WorldEnvironment = scene.get_node_or_null("WorldEnvironment")
		if env_node != null:
			_ok("WorldEnvironment 已配置 Environment 资源", env_node.environment != null)
		root.add_child(scene)
		await process_frame
		await process_frame
		print("    场景已挂载到 SceneTree 并稳定运行 2 帧")
		scene.queue_free()
	else:
		_ok("主场景加载为 PackedScene", false)

	# 汇总
	var failed: Array = _checks.filter(func(c): return not c.ok)
	print("---")
	print("检查项总数: %d , 失败: %d" % [_checks.size(), failed.size()])
	for c in failed:
		print("  [FAIL] %s" % c.name)
	if failed.is_empty():
		print("RESULT: ALL CHECKS PASSED")
	else:
		print("RESULT: FAILED")
	quit(0 if failed.is_empty() else 1)


func _check_file(label: String, path: String) -> void:
	_ok("文件存在 %s (%s)" % [label, path], FileAccess.file_exists(path))


func _ok(name: String, condition: bool) -> void:
	_checks.append({"name": name, "ok": condition})
	print("[%s] %s" % ["OK  " if condition else "FAIL", name])


func _count_meshes(node: Node) -> int:
	var n: int = 1 if node is MeshInstance3D else 0
	for child in node.get_children():
		n += _count_meshes(child)
	return n


func _merge_aabb(node: Node) -> AABB:
	var result: AABB = AABB()
	var first: bool = true
	for vi in _collect_visuals(node):
		var box: AABB = vi.global_transform * vi.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result


func _collect_visuals(node: Node) -> Array:
	var out: Array = []
	if node is VisualInstance3D:
		out.append(node)
	for child in node.get_children():
		out.append_array(_collect_visuals(child))
	return out
