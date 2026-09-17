extends Node3D
## Render-only consumer. The installed GGB GLB is static, not an animated fighter.
const MODEL = preload("res://assets/ggb/ggb.glb")
const PRESENTATION_SCALE := 0.48186128424
# v0.2 source presentation only; committed clocks and gameplay remain unchanged.
const NORMAL_HOVER := 0.16
const IDLE_FLAP_AMPLITUDE := 0.14
var model: Node3D
var meshes: Array[MeshInstance3D] = []
var wings: Array[Node3D] = []
# Keep per-instance materials alive until children finish teardown.
var originals: Array[Material] = []
var output: Dictionary = {}
var is_lead := false
var lead_material: StandardMaterial3D
var phase := 0.0
var _last_tick := -1
var _rest: Dictionary = {}
var _reaction: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ggb/electrocution_samples.json"))
func reset() -> void:
	output.clear()
	_last_tick = -1
	phase = 0
	is_lead = false
	for node in _rest: node.transform = _rest[node]
	rotation = Vector3(0,.48,0)
	position.y = NORMAL_HOVER
	for i in meshes.size(): meshes[i].set_surface_override_material(0,originals[i])
func _ready() -> void:
	scale = Vector3.ONE * PRESENTATION_SCALE
	position.y = NORMAL_HOVER
	model = MODEL.instantiate()
	add_child(model)
	_rest[model] = model.transform
	for node in model.find_children("*","Node3D",true,false): _rest[node] = node.transform
	meshes.append(model.find_child("Gumy_Mascot",true,false))
	for side in ["L","R"]:
		wings.append(model.find_child("Gumy_WingHinge_"+side,true,false))
		meshes.append(model.find_child("Gumy_Wing_"+side,true,false))
	for mesh in meshes:
		var material: Material = mesh.get_active_material(0).duplicate()
		originals.append(material)
		mesh.set_surface_override_material(0,material)
	lead_material = StandardMaterial3D.new()
	lead_material.albedo_color = Color(.31,.31,.33)
	lead_material.metallic = .72
	lead_material.roughness = .88
	lead_material.cull_mode = BaseMaterial3D.CULL_DISABLED
func present(snapshot: Dictionary, committed_tick: int) -> void:
	if committed_tick < _last_tick: reset()
	var delta := maxf(0,committed_tick-_last_tick)/60.0 if _last_tick >= 0 else 0.0
	_last_tick = committed_tick
	var stopped: bool = snapshot.get("hitstop",false) or snapshot.get("stopped",false)
	var status: String = snapshot.get("status","normal")
	var relation: Dictionary = snapshot.get("electrocution",{})
	var grounded: bool = snapshot.get("grounded",true)
	var velocity: Vector3 = snapshot.get("velocity",Vector3.ZERO)
	var request: Dictionary = snapshot.get("presentation",{})
	var special: Dictionary = snapshot.get("special",{})
	var state: String = snapshot.get("locomotion","idle" if grounded else "airborne")
	var identity := state
	var facing: float = snapshot.get("facing",1)
	if not str(request.get("activation_id","")).is_empty() and not str(request.get("move","")).is_empty():
		state = str(request.move)
		if state == "heavy_drop": state = "LeadFeet" if request.get("lead",false) else "landing"
		if state == "charge" and special.get("phase","") == "recovery": state = "charge_release"
		identity = str(request.activation_id)+":"+state
		facing = float(request.get("facing",facing))
	if not snapshot.get("enabled",true) or status in ["disabled","ko","respawning","eliminated"]:
		state = "inactive"
		identity = state
	elif snapshot.get("frozen",false) or status == "frozen":
		state = "frozen"
		identity = state
	elif not str(relation.get("activation_id","")).is_empty():
		state = "electrocution"
		identity = "electrocution:"+str(relation.activation_id)
	elif snapshot.get("hit",false) or status == "hitstun":
		state = "hit"
		identity = "hit:"+str(snapshot.get("hit_id","hit"))
	if state in ["inactive","frozen","electrocution","hit"]:
		facing = float(snapshot.get("facing",1))
	var changed: bool = output.is_empty() or output.identity != identity
	var seconds := maxf(0,float(relation.get("elapsed",0))) if state == "electrocution" else 0.0
	if not changed and (stopped or state in ["frozen","inactive"] or (delta == 0 and seconds == output.seconds)): return
	is_lead = state == "LeadFeet"
	for i in meshes.size(): meshes[i].set_surface_override_material(0,lead_material if is_lead else originals[i])
	var fallback := "Static GGB + source procedural wings: no imported animation clip for "+state
	output = {"clip":"","state":state,"identity":identity,"phase":phase,"seconds":seconds,"blend":1.0,"fallback":fallback}
	# Freeze the complete last committed reaction/pose; thaw restores rest first.
	if state == "frozen": return
	position.y = 0.0 if is_lead else NORMAL_HOVER
	for node in _rest: node.transform = _rest[node]
	var interrupted: bool = state in ["hit","inactive","electrocution"]
	if not stopped and state != "inactive": phase += delta*(8.0 if grounded else 38.0)
	var amplitude := 0.0 if interrupted else IDLE_FLAP_AMPLITUDE if grounded else .62
	for i in wings.size():
		var side := -1.0 if i == 0 else 1.0
		wings[i].rotation.z = side*(.70 if is_lead else .38+amplitude*sin(phase))
		wings[i].rotation.y = -side*1.25 if is_lead else 0.0
	rotation.y = facing*.48
	model.position.y = .025*sin(phase*.5) if not grounded and not is_lead and not interrupted else 0.0
	model.rotation.z = clampf(-velocity.x*.009,-.08,.08) if not grounded and not is_lead else 0.0
	if state == "electrocution":
		var samples: Array = _reaction.samples
		var cursor := clampf(seconds*float(_reaction.fps),0,samples.size()-1)
		var index := int(cursor)
		var next := mini(index+1,samples.size()-1)
		for node_name in samples[index]:
			var node: Node3D = model.find_child(node_name,true,false)
			var a: Array = samples[index][node_name].rotation
			var b: Array = samples[next][node_name].rotation
			node.quaternion = Quaternion(a[0],a[1],a[2],a[3]).slerp(Quaternion(b[0],b[1],b[2],b[3]),cursor-index)
		output.fallback = "Source 96fps sampled rigid Electrocution; no GLB clip"
	output.phase = phase
