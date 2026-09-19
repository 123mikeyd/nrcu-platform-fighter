extends SceneTree
const Specials = preload("res://scripts/core/kits/turbofit_specials.gd")
const Wave = preload("res://scripts/core/kits/turbofit_wave.gd")
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok: failures += 1; printerr("FAIL: ",label)
func _initialize() -> void:
	var kit = Specials.new()
	if not kit.start("emit:1",Vector2.LEFT,1):
		check(false,"side special must emit detached Sound Wave request"); quit(1); return
	var effects: Array = kit.collect(7,Vector3(4,5,0),[])
	check(effects.size() == 1, "one spawn request")
	if effects.size() == 1:
		var e: Dictionary = effects[0]
		check(e.kind == "spawn_wave" and e.source == 7 and e.activation_id == "emit:1" and e.facing == -1, "spawn identity and directional commit")
		check(e.position == Vector3(3.2,6,0), "authored .8 horizontal and 1 vertical spawn offset")
		var wave = Wave.new(); wave.start(e.activation_id,e.source,2,e.position,e.facing)
		kit.cancel(); wave.tick(.1)
		check(wave.snapshot().active and wave.snapshot().source == 7, "episode cancellation cannot erase already emitted wave")
	check(kit.collect(7,Vector3.ZERO,[]).is_empty(), "no duplicate spawn after cancellation")
	kit.start("emit:2",Vector2.RIGHT,-1)
	check(kit.snapshot().cooldown == .55, "wave cooldown")
	kit.tick(.55)
	check(kit.snapshot().phase == "idle", "wave action expiry")
	kit.start("rise:1",Vector2(-1,-1),1)
	effects = kit.collect(7,Vector3.ZERO,[])
	check(effects.size() == 1, "up diagonal dispatches recovery not wave")
	if effects.size() == 1:
		var e: Dictionary = effects[0]
		check(e.kind == "recovery_request" and e.facing == 1 and e.activation_id == "rise:1", "shared recovery committed current facing")
		check(e.vertical_speed == 13.5 and e.active_seconds == .38 and e.cooldown_seconds == .65 and e.spend_recovery and e.jumps_used == 2, "source-backed recovery host request")
		var recovery = load(e.ability_script).new(e.facing,e.activation_id)
		var hit: Dictionary = recovery.contact(7,8,Vector3.UP,1)
		check(hit.damage == 12 and hit.base_knockback == 5.5, "uses existing shared recovery contact contract")
	kit.cancel()
	check(not kit.start("deadzone",Vector2(.05,0),1), "legacy nonzero deadzone does not secretly charge")
	kit.start("down-diagonal",Vector2(1,1),-1)
	check(kit.snapshot().move == "sound_orb" and kit.snapshot().facing == -1, "down wins side, preserves facing")
	kit.cancel()
	for interruption in ["interrupted","disabled","frozen"]:
		kit.start("hold:"+interruption,Vector2.ZERO,1); kit.tick(2)
		kit.tick(0,{interruption:true,"advance":false})
		check(kit.snapshot().phase == "idle", "charge cleanup: "+interruption)
	if failures == 0: print("PASS core Turbofit special dispatch spawn shared recovery")
	quit(1 if failures else 0)
