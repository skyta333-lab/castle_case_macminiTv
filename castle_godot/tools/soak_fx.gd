extends SceneTree
## tools/soak_fx.gd
## TASK04 稳定性长跑脚本（headless，真实运行 10 分钟）：
##   在 NIGHT 预设 + 烟花开启（真实 spawn_interval 调度，不加速）下持续运行，
##   每 30 秒采样一次对象数量 / 节点数量 / 粒子系统数量 / 灯光数量 / 粒子总量，
##   用于证明"场景运行 10 分钟不持续增长对象数量"。
##
## 用法：
##   Godot --headless --path . --script res://tools/soak_fx.gd
## 退出码 0 = 稳定（无持续增长）；1 = 检测到增长。

const MAIN_SCENE := "res://scenes/main.tscn"
const DURATION := 600.0   # 10 分钟
const SAMPLE_INTERVAL := 30.0

var _fail := 0


func _count_nodes(root_node: Node) -> int:
	var n := 1
	for c in root_node.get_children():
		n += _count_nodes(c)
	return n


func _count_particles(root_node: Node) -> int:
	var n := 1 if root_node is GPUParticles3D else 0
	for c in root_node.get_children():
		n += _count_particles(c)
	return n


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("=== TASK04 soak: 10 分钟夜景 + 烟花稳定性长跑 ===")
	var packed := load(MAIN_SCENE) as PackedScene
	if packed == null:
		print("[FAIL] 主场景加载失败")
		quit(1)
		return
	var scene: Node = packed.instantiate()
	root.add_child(scene)
	for i in 10:
		await process_frame

	var env_mgr: Node = scene.get_node_or_null("EnvironmentManager")
	var fw := scene.get_node_or_null("Fireworks") as FireworksController
	var lights := scene.get_node_or_null("NightLights") as NightLighting
	if env_mgr == null or fw == null or lights == null:
		print("[FAIL] 缺少 EnvironmentManager / Fireworks / NightLights")
		quit(1)
		return

	env_mgr.call("set_preset", 2)   # NIGHT
	fw.set_enabled(true)            # 真实 spawn_interval 调度

	var samples: Array = []
	var elapsed := 0.0
	var max_pending := 0
	var max_amount_total := 0
	var max_lit := 0

	print("t(s)\tobjects\tnodes\tparticles\tlights\tparticle_amount_sum\tpending\tlit")
	while elapsed <= DURATION:
		var objects: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
		var nodes := _count_nodes(scene)
		var particles := _count_particles(scene)
		var light_count := lights.get_light_count()
		var amount_sum := 0
		for a in fw.get_system_amounts():
			amount_sum += int(a)
		var pending: int = fw.get_pending_count()
		var lit := 0
		for l in lights.get_lights():
			if l.visible and l.light_energy > 0.001:
				lit += 1
		max_pending = maxi(max_pending, pending)
		max_amount_total = maxi(max_amount_total, amount_sum)
		max_lit = maxi(max_lit, lit)
		samples.append({
			"t": elapsed, "objects": objects, "nodes": nodes, "particles": particles,
			"lights": light_count, "amount": amount_sum, "pending": pending, "lit": lit,
		})
		print("%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d" % [int(elapsed), objects, nodes, particles, light_count, amount_sum, pending, lit])
		if elapsed >= DURATION:
			break
		await create_timer(SAMPLE_INTERVAL).timeout
		elapsed += SAMPLE_INTERVAL

	var first: Dictionary = samples[0]
	var last: Dictionary = samples[samples.size() - 1]
	var obj_drift: int = int(last["objects"]) - int(first["objects"])
	var node_drift: int = int(last["nodes"]) - int(first["nodes"])

	# 峰值回归检查（对象数量不应单调增长：后 1/3 样本的均值 ≈ 前 1/3 均值）
	var n := samples.size()
	var head_sum := 0
	var tail_sum := 0
	var chunk: int = maxi(1, n / 3)
	for i in chunk:
		head_sum += int(samples[i]["objects"])
	for i in range(n - chunk, n):
		tail_sum += int(samples[i]["objects"])
	var head_avg: float = float(head_sum) / float(chunk)
	var tail_avg: float = float(tail_sum) / float(chunk)

	var ok := true
	if obj_drift > 200:
		print("[FAIL] 引擎对象数量持续增长：%d -> %d（漂移 %d）" % [int(first["objects"]), int(last["objects"]), obj_drift])
		ok = false
	else:
		print("[PASS] 引擎对象数量稳定：%d -> %d（漂移 %d）" % [int(first["objects"]), int(last["objects"]), obj_drift])
	if node_drift != 0:
		print("[FAIL] 场景节点数量变化：%d -> %d" % [int(first["nodes"]), int(last["nodes"])])
		ok = false
	else:
		print("[PASS] 场景节点数量恒定：%d" % int(last["nodes"]))
	if absf(tail_avg - head_avg) > 50.0:
		print("[FAIL] 对象数量后段均值偏离前段：%.1f -> %.1f" % [head_avg, tail_avg])
		ok = false
	else:
		print("[PASS] 对象数量无单调增长趋势：前段均值 %.1f / 后段均值 %.1f" % [head_avg, tail_avg])
	if int(last["particles"]) != int(first["particles"]):
		print("[FAIL] 粒子系统数量变化：%d -> %d" % [int(first["particles"]), int(last["particles"])])
		ok = false
	else:
		print("[PASS] 粒子系统数量恒定：%d 个" % int(last["particles"]))
	if int(last["lights"]) != int(first["lights"]):
		print("[FAIL] 灯光数量变化：%d -> %d" % [int(first["lights"]), int(last["lights"])])
		ok = false
	else:
		print("[PASS] 灯光数量恒定：%d 盏" % int(last["lights"]))
	print("[INFO] 峰值等待队列 = %d，峰值活跃粒子总量 = %d（单发配置 %d × %d 发射位）" % [max_pending, max_amount_total, fw.get_particle_amount(), fw.get_pad_count()])
	print("[INFO] 发次统计：volley=%d，fired=%d，夜景灯点亮峰值=%d" % [fw.get_volley_total(), fw.get_fired_total(), max_lit])
	print("[INFO] 烟花总粒子预算（恒定）=%d" % fw.get_total_particle_budget())

	print("\n=== TASK04 soak 结果：%s ===" % ("PASS（10 分钟无持续增长）" if ok else "FAIL"))
	quit(0 if ok else 1)
