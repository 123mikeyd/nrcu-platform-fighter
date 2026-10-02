extends SkeletonModifier3D
# Cosmetic shared "dozing" pose for sleeping fighters (Mephisto sleep kit).
# Runs after the fighter's own animation/pose code as a SkeletonModifier3D and
# only adds a forward head/neck/chest droop with a slow breathing sway and nod,
# and lets both arms hang limp (upper arm + forearm swing toward straight down
# with a small pendulum sway).
# Owns no timer, damage, input, collision or gameplay state: it reads the
# fighter's sleep_remaining and blends itself in/out.
var actor: Node3D
var weight := 0.0
var clock := 0.0
var last_ms := 0
var chain: Array = []   # [[bone_index, degrees], ...] parent -> child
const HEAD_NAMES := ["Head", "mixamorig_Head", "DEF-spine.006"]
const NECK_NAMES := ["neck", "Neck", "mixamorig_Neck", "DEF-spine.004"]
const CHEST_NAMES := ["Spine", "mixamorig_Spine2", "DEF-spine.003"]
const CHEST_DEG := 7.0
const NECK_DEG := 12.0
const HEAD_DEG := 20.0
# Limp arms (Mike 09-29: "can we make the arms go limp?")
const ARM_SETS := [
	["LeftArm", "LeftForeArm", "LeftHand"], ["RightArm", "RightForeArm", "RightHand"],
	["mixamorig_LeftArm", "mixamorig_LeftForeArm", "mixamorig_LeftHand"], ["mixamorig_RightArm", "mixamorig_RightForeArm", "mixamorig_RightHand"],
	["DEF-upper_arm.L", "DEF-forearm.L", "DEF-hand.L"], ["DEF-upper_arm.R", "DEF-forearm.R", "DEF-hand.R"],
]
const UPPER_LIMP := 0.9          # how far the upper arm goes toward hanging straight
const FORE_LIMP := 0.85
const ARM_OUT := 0.16            # slight outward hang so arms don't sink into the torso
const ARM_FWD := 0.08
var arms: Array = []             # [[upper, fore, hand], ...]
var chest_index := -1
var last_hang := NAN             # diagnostics: mean hand.y - upper-arm.y after limp
func setup(fighter: Node3D) -> void:
	actor = fighter
	chain.clear()
	var sk := get_skeleton()
	if sk == null: return
	for entry in [[CHEST_NAMES, CHEST_DEG], [NECK_NAMES, NECK_DEG], [HEAD_NAMES, HEAD_DEG]]:
		for n in entry[0]:
			var i := sk.find_bone(n)
			if i >= 0:
				chain.append([i, entry[1]]); break
	arms.clear()
	for arm_set in ARM_SETS:
		var ids := [sk.find_bone(arm_set[0]), sk.find_bone(arm_set[1]), sk.find_bone(arm_set[2])]
		if ids[0] >= 0 and ids[1] >= 0 and ids[2] >= 0: arms.append(ids)
	chest_index = chain[0][0] if not chain.is_empty() else -1
func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or actor == null or not is_instance_valid(actor) or chain.is_empty(): return
	var now := Time.get_ticks_msec()
	var dt := clampf((now - last_ms) / 1000.0, 0.0, 0.1) if last_ms > 0 else 0.0
	last_ms = now
	var asleep: bool = actor.sleep_remaining > 0 and actor.stocks > 0
	weight = move_toward(weight, 1.0 if asleep else 0.0, dt / (0.22 if asleep else 0.12))
	if weight <= 0.001: return
	clock += dt
	var w := smoothstep(0.0, 1.0, weight)
	var facing: float = actor.facing if absf(actor.facing) > 0.1 else 1.0
	# World-space pitch about +Z; conjugated into skeleton space so mirrored or
	# differently-oriented rigs all droop toward the fighter's facing side.
	var B := sk.global_transform.basis
	var Binv := B.inverse()
	var breathe := sin(clock * 2.1)
	var nod := sin(clock * 1.05)
	for link in chain:
		var i: int = link[0]
		var deg: float = link[1]
		if i == chain[0][0]: deg += 2.5 * breathe
		if i == chain[-1][0]: deg += 4.0 * nod
		var angle := deg_to_rad(deg) * w * -facing
		var rot_s := Binv * Basis(Vector3(0, 0, 1), angle) * B
		var gp := sk.get_bone_global_pose(i)
		sk.set_bone_global_pose(i, Transform3D((rot_s * gp.basis), gp.origin))
	# Limp arms, applied after the chest droop so they hang from the slumped torso.
	var X := sk.global_transform
	var chest_w: Vector3 = X * sk.get_bone_global_pose(chest_index).origin if chest_index >= 0 else actor.global_position + Vector3.UP
	for arm_i in arms.size():
		var ids: Array = arms[arm_i]
		var swing := deg_to_rad(3.0) * sin(clock * 2.1 + float(arm_i) * 1.3)
		var shoulder: Vector3 = X * sk.get_bone_global_pose(ids[0]).origin
		var out := Vector3(shoulder.x - chest_w.x, 0, shoulder.z - chest_w.z)
		out = out.normalized() if out.length() > 0.001 else Vector3.ZERO
		var hang := (Vector3.DOWN + out * ARM_OUT + Vector3(facing * ARM_FWD, 0, 0)).normalized()
		hang = Basis(Vector3(0, 0, 1), swing) * hang
		_aim_bone(sk, ids[0], ids[1], hang, UPPER_LIMP * w)
		var fore_hang := (Vector3.DOWN + Vector3(facing * ARM_FWD * 1.5, 0, 0) + out * ARM_OUT * 0.5).normalized()
		_aim_bone(sk, ids[1], ids[2], fore_hang, FORE_LIMP * w)
	var hs := 0.0
	for ids in arms:
		hs += (X * sk.get_bone_global_pose(ids[2]).origin).y - (X * sk.get_bone_global_pose(ids[0]).origin).y
	last_hang = hs / arms.size() if arms.size() > 0 else NAN
func _aim_bone(sk: Skeleton3D, bone: int, child: int, world_dir: Vector3, amount: float) -> void:
	# Rotate bone (about its own origin) so bone->child points toward world_dir.
	var X := sk.global_transform
	var a: Vector3 = X * sk.get_bone_global_pose(bone).origin
	var b: Vector3 = X * sk.get_bone_global_pose(child).origin
	var d := b - a
	if d.length() < 0.0001: return
	var q := Quaternion(d.normalized(), world_dir.normalized())
	q = Quaternion.IDENTITY.slerp(q, clampf(amount, 0.0, 1.0))
	var B := X.basis
	var rot_s := B.inverse() * Basis(q) * B
	var gp := sk.get_bone_global_pose(bone)
	sk.set_bone_global_pose(bone, Transform3D(rot_s * gp.basis, gp.origin))
