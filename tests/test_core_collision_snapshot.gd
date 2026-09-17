extends SceneTree
const BUILDER = "res://scripts/core/collision/collision_snapshot.gd"
const Profile = preload("res://scripts/core/collision/character_collision_profile.gd")
const Hurtbox = preload("res://scripts/core/collision/generated_hurtbox.gd")
const ASSET = "res://assets/teknium/teknium_animations.glb"
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok: failures += 1; print("FAIL: ", label)
func fixture() -> Resource:
	var p = Profile.new()
	p.character_id = "fixture"; p.source_asset = ASSET; p.source_sha256 = FileAccess.get_sha256(ASSET)
	p.body_radius = 0.2; p.body_height = 1.0
	p.visual_scale = 19; p.foot_origin = Vector3(0,99,0)
	var h = Hurtbox.new()
	h.hurtbox_id = "arm"; h.bone_name = "Hand"; h.radius = 0.5; h.height = 3.0
	h.local_transform = Transform3D(Basis(Vector3.FORWARD, PI/2), Vector3(0,2,0))
	p.hurtboxes.append(h)
	return p
func revision(p: Resource, seconds: float = 0.0) -> Dictionary:
	return {"source_asset":p.source_asset,"source_sha256":p.source_sha256,"clip":"Punch","seconds":seconds,"policy":0,"episode_id":"life1:attack1"}
func _init() -> void: call_deferred("run")
func run() -> void:
	check(ResourceLoader.exists(BUILDER), "snapshot builder exists")
	if failures: quit(1); return
	var p = fixture(); var service = load(BUILDER).new()
	check(service.configure(p, p.source_asset, p.source_sha256, "draft-1").is_empty(), "configure profile")
	# Parent-model pose already includes authored root; never apply visual_scale/foot_origin again.
	var pose := {"Hand":Transform3D(Basis(Vector3.UP,PI/2),Vector3(4,0,0))}
	var world := Transform3D(Basis(Vector3.UP,PI/2).scaled(Vector3.ONE*2),Vector3(10,20,30))
	var result: Dictionary = service.build("fighter-1",pose,world,revision(p))
	check(result.ok and result.primitives.size() == 1, "world primitive built")
	if result.primitives.size() == 1:
		var c: Dictionary = result.primitives[0]
		check(c.id == "arm" and c.a.is_equal_approx(Vector3(12,24,22)) and c.b.is_equal_approx(Vector3(8,24,22)), "exact composed endpoints")
		check(is_equal_approx(c.radius,1), "radius uniformly world scaled")
		check(result.aabb.is_equal_approx(AABB(Vector3(7,23,21),Vector3(6,2,2))), "full endpoint-radius world bounds")
	check(result.entity_id == "fighter-1" and result.profile_revision.revision == "draft-1" and result.pose_revision == revision(p), "explicit revisions")
	check(not result.has("body") and p.body_radius == 0.2 and p.hurtboxes[0].radius == 0.5, "body separate; source unchanged")
	if not failures: print("PASS: collision snapshot exact transform")
	quit(1 if failures else 0)
