extends RefCounted
## Caller-owned per-entity discrete committed pose authority; no nodes or timers.
const TEK_MAP := {"idle":"Idle","walk":"Walk","run":"Run","initial_dash":"Run","turn":"Walk","brake":"Walk","jump_startup":"Jump","rising":"Jump","falling":"Jump","fast_fall":"Jump","landing":"Jump"}
const TURBO_MAP := {"idle":"Idle","walk":"Walk","run":"Run","initial_dash":"Run","turn":"Walk","brake":"Walk","jump_startup":"Jump","rising":"Jump","falling":"FallLoop","fast_fall":"FallLoop","landing":"Landing"}
const BASIC := {"GoalkeeperKick":59.0/60,"AirSideKick":.5,"AirDownKick":38.0/30,"MeleeHorizontal":.8,"MeleeBackhand":.8}
const OFFSETS := {"Idle":-.224,"Walk":.066,"Run":.086,"Block":-.061,"Hit":-.112}
var _profile: Dictionary = {}
var _last_tick := -1
var _elapsed := 0.0
var _last_clip := ""
var _identity := ""
var _loco := ""
var _jumps := -1
var _land_left := 0.0
var _output: Dictionary = {}
var _generation = null
var _lifecycle = null
var _episode := 0
var _revision := 0
func reset() -> void:
	_last_tick = -1; _elapsed = 0; _last_clip = ""; _identity = ""; _loco = ""; _jumps = -1; _land_left = 0
	_output.clear(); _generation = null; _lifecycle = null; _episode = 0; _revision = 0
func configure(manifest: Dictionary) -> PackedStringArray:
	_profile.clear(); reset()
	var errors := _validate_manifest(manifest)
	if errors.is_empty(): _profile = manifest.duplicate(true)
	return errors
func sample(c: Dictionary, tick: int) -> Dictionary:
	var errors := _validate_context(c,tick)
	if not errors.is_empty(): return {"ok":false,"diagnostics":errors,"route":"unsupported_use_explicit_legacy_route"}
	if _generation != c.generation or _lifecycle != c.lifecycle_revision or tick < _last_tick: reset()
	_generation = c.generation; _lifecycle = c.lifecycle_revision
	var turbo: bool = _profile.character_id == "turbofit"
	var delta := maxf(0,tick-_last_tick)/60.0 if _last_tick >= 0 else 0.0
	var loco := str(c.locomotion)
	var state := loco
	var retained_grace := _land_left
	if not turbo:
		_land_left = .1 if loco == "landing" and _loco != loco else maxf(0,_land_left-delta)
		if loco not in ["landing","idle"]: _land_left = 0
		if _land_left > 0: state = "landing"
		elif loco == "landing": state = "idle"
	var clip: String = (TURBO_MAP if turbo else TEK_MAP).get(state,"Idle")
	var identity := str(c.get("episode_id",state))
	var request: Dictionary = c.presentation
	var mode := "local"
	var age := 0.0
	var duration := 0.0
	if c.get("hit",false) or c.status == "hitstun":
		clip = "HitReactRight" if turbo else "Hit"; state = "hit"; identity = str(c.get("hit_id","hit"))
	elif not c.caught.is_empty():
		clip = "BlockIdle" if turbo else "Electrocution"; state = "caught"; identity = str(c.caught.activation_id); age = c.caught.elapsed; mode = "local" if turbo else "raw"
	elif not c.grab.is_empty():
		var g: Dictionary = c.grab
		state = "grab"; identity = str(g.activation_id)+":"+str(g.phase); age = g.elapsed; mode = "raw"
		clip = "GrabEnd"
		if g.phase == "startup": clip = "GrabStart"; age = age*(13.0/24)/.20 if age <= .20 else 13.0/24+age-.20
		elif g.phase == "hold": clip = "GrabLoop"; age = fmod(age,1.25) if age > 1.25 else age
	elif turbo:
		if c.get("shielding",false) or c.action == "block" or (c.action == "movement_lock" and str(request.get("activation_id","")).is_empty()):
			clip = "BlockIdle"; identity = "shield"
		elif request.get("move","") == "power_chord":
			clip = "TwoHandCombo"; identity = str(request.activation_id)+":"+str(request.phase); age = request.age; mode = "charge"
			if request.phase == "release":
				mode = "release"
				if age > .3333334: clip = "Idle"; identity += ":return"; mode = "return"
		elif request.get("move","") in ["sound_wave","sound_orb","rising_chord"]:
			mode = str(request.move); clip = {"sound_wave":"TwoHandCombo","sound_orb":"BlockIdle","rising_chord":"Jump"}[mode]; identity = str(request.activation_id); age = request.age
		elif c.action == "recovery" or not c.recovery_id.is_empty():
			clip = "Jump"; identity = str(c.recovery_id)
		elif BASIC.has(request.get("clip","")):
			clip = request.clip; identity = str(request.activation_id); mode = "retime"; age = request.elapsed; duration = BASIC[clip]
	else:
		if not c.recovery_id.is_empty():
			clip = "RaiseWall"; state = "recovery"; identity = str(c.recovery_id); age = c.recovery_elapsed; duration = .65; mode = "retime"
		elif c.action in ["movement_lock","block"]: clip = "Block"; state = "block"; identity = state
		elif c.action == "recovery": clip = "Jump"; state = "recovery"
		elif not c.strike_id.is_empty():
			state = "strike"; identity = str(c.strike_id); clip = "Kick" if c.get("strike_move","") in ["LOW SWEEP","DOWN STRIKE"] else "Punch"
			if c.get("source_melee",false) or c.get("strike_move","") in ["UPPERCUT","UP AIR","LOW SWEEP","DOWN STRIKE"]: age = c.strike_elapsed; duration = .32; mode = "retime"
			if c.get("source_melee",false) and c.get("strike_move","") == "SIDE STRIKE" and _profile.sources[0].has("derived_source"):
				clip = "SwingPunchV1"; mode = "raw"
		if not c.force_id.is_empty() and c.recovery_id.is_empty():
			clip = "ForcePush"; state = "force"; identity = str(c.force_id); age = c.force_source_time; mode = "raw"
	# Support is a committed presentation episode, never a terrain state.
	# Resolve it only after all action/status winners, without a second clock.
	var support: Dictionary = c.get("support",{})
	if not support.is_empty() and not c.get("hit",false) and not c.get("frozen",false) and c.status == "normal" and not c.grounded and c.action in ["","neutral","none"] and c.strike_id.is_empty() and c.recovery_id.is_empty() and c.force_id.is_empty() and c.grab.is_empty() and c.caught.is_empty() and str(request.get("activation_id","")).is_empty() and not c.get("shielding",false):
		clip = "Idle"; state = "supported"; identity = "support:"+str(support.get("generation",c.generation))+":"+str(support.carrier)
	var restart: bool = identity != _identity if turbo or state in ["hit","strike","recovery","force","grab","caught","supported"] or _output.get("state","") == "supported" else false
	var new_jump: bool = (loco == "jump_startup" and _loco != loco) or (loco == "rising" and (_loco not in ["rising","jump_startup"] or int(c.air_jumps_left) < _jumps))
	if not turbo and state in ["rising","jump_startup"] and new_jump: restart = true
	var changed := _output.is_empty() or restart or clip != _last_clip
	var stopped: bool = c.get("stopped",false) or c.get("frozen",false) or c.get("hitstop",false) or c.status == "frozen"
	# Priority is already resolved: irrelevant lower-priority transitions cannot
	# restart a Hit; a new same-tick hit can replace a frozen/paused episode.
	var synchronous_interrupt: bool = changed and (state in ["hit","grab","caught"] or _output.get("state","") in ["grab","caught"] or (_output.get("state","") == "supported" and support.is_empty() and c.status != "frozen" and not c.get("frozen",false)))
	if (not changed and tick == _last_tick) or (stopped and not _output.is_empty() and not synchronous_interrupt):
		_land_left = retained_grace
		_last_tick = tick
		return _output.duplicate(true)
	if changed: _episode += 1
	_elapsed = 0.0 if restart or clip != _last_clip else _elapsed+delta
	if mode == "local": age = maxf(0,float(c.get("elapsed",_elapsed))) if turbo else _elapsed
	var source: Dictionary = _profile.sources[0]
	for candidate in _profile.sources:
		if candidate.clips.has(clip): source = candidate; break
	if not source.clips.has(clip): return {"ok":false,"diagnostics":["missing source clip: "+clip]}
	var length: float = source.clips[clip]
	var seconds := age
	match mode:
		"retime": seconds = clampf(age/duration,0,1)*length
		"sound_wave": seconds = age/.7*length
		"release": seconds = 19.0/30+age
		"return": seconds = age-1.0/3
		"charge":
			var frame := lerpf(1,16,sin(minf(age/.25,1)*PI/2))
			if age > .25: frame = 15+cos((age-.25)*TAU/.9)
			seconds = (frame-1)/30
	if turbo and mode == "local" and clip in ["Walk","Run"]: seconds *= clampf(absf(c.velocity.x)/(2.5 if clip == "Walk" else 7.5),.55,1.6)
	if not turbo:
		if state == "rising": seconds = minf(seconds,length*.65)
		elif state in ["falling","fast_fall"]: seconds = length
		elif state == "landing": seconds = 0
		elif state == "recovery" and mode == "local": seconds = length*.65
	var looping: bool = clip in (["Idle","Walk","Run","FallLoop","BlockIdle"] if turbo else ["Idle","Walk","Run","Block"])
	seconds = fmod(seconds,length) if looping else minf(seconds,length)
	_last_tick = tick; _last_clip = clip; _identity = identity; _loco = loco; _jumps = c.air_jumps_left
	var facing: float = request.facing if turbo and mode != "local" and state != "caught" else c.facing
	if state == "grab": facing = c.grab.facing
	var offset := 0.0
	if not turbo and (c.grounded or state == "supported") and state not in ["grab","caught"]:
		offset = OFFSETS.get(clip,(-.038 if clip == "Kick" else -.106) if state == "strike" and c.get("strike_move","") in ["UPPERCUT","UP AIR","LOW SWEEP","DOWN STRIKE"] else 0.0)
	var placement := Transform3D(Basis(Vector3.UP,facing*PI/2).scaled(Vector3.ONE*float(_profile.visual_scale)),Vector3(0,offset,0))
	_revision += 1
	var rendering := {"source_asset":source.source_asset,"skeleton_path":source.skeleton_path,"player_path":source.player_path,"clip":clip,"source_seconds":seconds,"time_policy":0,"modelplacement":placement,"facing":facing,"blend_policy":"discrete_committed_no_blend"}
	if clip == "SwingPunchV1": rendering.derived_source = source.derived_source.duplicate(true)
	rendering.fallback = "TEMP: caught uses accepted BlockIdle" if turbo and state == "caught" else ""
	_output = rendering.duplicate(true)
	_output.merge({"ok":true,"state":state,"episode_id":[_generation,_lifecycle,_episode,identity],"pose_revision":_revision,"rendering_request":rendering})
	return _output.duplicate(true)

func _number(value) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0
func _validate_manifest(m: Dictionary) -> PackedStringArray:
	for key in ["character_id","source_asset","source_sha256","visual_scale","foot_origin","sources"]:
		if not m.has(key): return PackedStringArray(["missing manifest: "+key])
	if m.character_id not in ["teknium","turbofit"]: return PackedStringArray(["unsupported character"])
	if m.visual_scale != 1.25 or not m.foot_origin is Vector3 or not m.foot_origin.is_finite(): return PackedStringArray(["invalid approved placement metadata"])
	if not m.sources is Array or m.sources.is_empty(): return PackedStringArray(["missing imported sources"])
	if not m.sources[0] is Dictionary: return PackedStringArray(["invalid primary source"])
	var base: Dictionary = m.sources[0]
	for s in m.sources:
		if not s is Dictionary: return PackedStringArray(["invalid source record"])
		for key in ["source_asset","source_sha256","skeleton_path","player_path","names","parents","rests","clips","skeleton_placement"]:
			if not s.has(key): return PackedStringArray(["missing source: "+key])
		if not s.source_asset is String or not s.source_asset.begins_with("res://") or not s.source_asset.ends_with(".glb"): return PackedStringArray(["invalid source asset"])
		if not s.source_sha256 is String or s.source_sha256.length() != 64 or not s.source_sha256.is_valid_hex_number(): return PackedStringArray(["invalid source hash"])
		for path in [s.skeleton_path,s.player_path]:
			if not path is NodePath or path.is_empty() or path.is_absolute() or path.get_subname_count() != 0: return PackedStringArray(["invalid imported path"])
		if not s.names is Array or not s.parents is Array or not s.rests is Array or s.names.is_empty() or s.names.size() != s.parents.size() or s.names.size() != s.rests.size(): return PackedStringArray(["incomplete topology"])
		var seen := {}
		for b in s.names.size():
			if not s.names[b] is String or s.names[b].is_empty() or seen.has(s.names[b]): return PackedStringArray(["invalid bone name"])
			seen[s.names[b]] = true
			if not s.parents[b] is int or s.parents[b] < -1 or s.parents[b] >= b: return PackedStringArray(["invalid bone hierarchy"])
			if not s.rests[b] is Transform3D or not s.rests[b].is_finite(): return PackedStringArray(["invalid bone rest"])
		if not s.skeleton_placement is Transform3D or not s.skeleton_placement.is_finite() or s.skeleton_placement != base.skeleton_placement: return PackedStringArray(["alternate source placement mismatch"])
		if s.names != base.names or s.parents != base.parents or s.rests != base.rests: return PackedStringArray(["alternate source topology/rest mismatch; retargeting unsupported"])
		if not s.clips is Dictionary or s.clips.is_empty(): return PackedStringArray(["missing clip inventory"])
		if s.has("derived_source"):
			if m.character_id != "teknium" or s.source_sha256 != preload("res://scripts/core/presentation/teknium_swing_source.gd").BASE_SHA or s.derived_source != preload("res://scripts/core/presentation/teknium_swing_source.gd").identity() or s.clips.get("SwingPunchV1",0) != .32: return PackedStringArray(["invalid derived source identity"])
		elif s.clips.has("SwingPunchV1"): return PackedStringArray(["untrusted derived clip"])
		for clip in s.clips:
			if not _number(s.clips[clip]) or s.clips[clip] <= 0: return PackedStringArray(["invalid clip duration"])
	if base.source_asset != m.source_asset or base.source_sha256 != m.source_sha256: return PackedStringArray(["profile/source identity mismatch"])
	var required := ["Idle","Walk","Run","Jump","Block","Hit","Punch","Kick","RaiseWall","ForcePush","GrabStart","GrabLoop","GrabEnd","Electrocution"] if m.character_id == "teknium" else ["Idle","Walk","Run","Jump","Landing","FallLoop","BlockIdle","HitReactRight","AirSideKick","AirDownKick","GoalkeeperKick","MeleeHorizontal","MeleeBackhand","TwoHandCombo"]
	for clip in required:
		var found := false
		for s in m.sources:
			if s.clips.has(clip): found = true
		if not found: return PackedStringArray(["incomplete imported clip coverage: "+clip])
	return PackedStringArray()

func _validate_context(c: Dictionary, tick: int) -> PackedStringArray:
	if _profile.is_empty(): return PackedStringArray(["policy not configured"])
	for key in ["generation","lifecycle_revision","status","locomotion","action","grounded","facing","air_jumps_left","velocity","presentation","strike_id","recovery_id","force_id","grab","caught"]:
		if not c.has(key): return PackedStringArray(["missing committed context: "+key])
	if tick < 0 or not c.generation is int or not c.lifecycle_revision is int or c.generation < 0 or c.lifecycle_revision < 0: return PackedStringArray(["invalid lifecycle/tick"])
	if c.action not in ["","neutral","landing_lock","none","basic","special","movement_lock","block","recovery"]: return PackedStringArray(["unsupported committed action"])
	if c.status not in ["normal","hitstun","frozen","caught"] or not TEK_MAP.has(c.locomotion): return PackedStringArray(["unsupported status/locomotion"])
	if not c.grounded is bool or not c.air_jumps_left is int or not c.velocity is Vector3 or not c.velocity.is_finite() or c.facing not in [-1,-1.0,1,1.0]: return PackedStringArray(["invalid committed placement/motion"])
	for key in ["strike_id","recovery_id","force_id","action"]:
		if not c[key] is String: return PackedStringArray(["invalid identity: "+key])
	for key in ["presentation","grab","caught"]:
		if not c[key] is Dictionary: return PackedStringArray(["invalid telemetry: "+key])
	if (c.status == "frozen" or c.get("frozen",false)) and (_output.is_empty() or _generation != c.generation or _lifecycle != c.lifecycle_revision or tick < _last_tick): return PackedStringArray(["frozen entry requires retained same-lifecycle committed pose"])
	if (c.get("hit",false) or c.status == "hitstun") and (not c.has("hit_id") or str(c.hit_id).is_empty()): return PackedStringArray(["hit identity required"])
	for pair in [["force_id","force_source_time"],["recovery_id","recovery_elapsed"]]:
		if not c[pair[0]].is_empty() and (not c.has(pair[1]) or not _number(c[pair[1]])): return PackedStringArray(["missing finite committed age: "+pair[1]])
	if not c.strike_id.is_empty():
		if c.get("strike_move","") not in ["SIDE STRIKE","AIR STRIKE","UPPERCUT","UP AIR","LOW SWEEP","DOWN STRIKE"]: return PackedStringArray(["explicit strike move required"])
		if (c.get("source_melee",false) or c.strike_move not in ["SIDE STRIKE","AIR STRIKE"]) and not _number(c.get("strike_elapsed",null)): return PackedStringArray(["directional strike age required"])
	if c.status == "caught" and c.caught.is_empty(): return PackedStringArray(["caught requires committed reciprocal relation"])
	for key in ["grab","caught"]:
		var relation: Dictionary = c[key]
		if relation.is_empty(): continue
		if str(relation.get("activation_id","")).is_empty() or not _number(relation.get("elapsed",null)): return PackedStringArray(["relation identity/phase age required"])
		if key == "grab":
			if _profile.character_id != "teknium": return PackedStringArray(["non-Teknium grab caster unsupported"])
			if relation.get("phase","") not in ["startup","hold","ending"] or relation.get("facing",0) not in [-1,-1.0,1,1.0]: return PackedStringArray(["invalid grab phase/facing"])
	if c.has("elapsed") and not _number(c.elapsed): return PackedStringArray(["invalid explicit elapsed"])
	if _profile.character_id == "turbofit" and (not c.strike_id.is_empty() or not c.force_id.is_empty()): return PackedStringArray(["Teknium ability identity on Turbofit"])
	var r: Dictionary = c.presentation
	var live: bool = not str(r.get("activation_id","")).is_empty()
	if c.action in ["basic","special"] and not live and c.strike_id.is_empty() and c.force_id.is_empty() and c.recovery_id.is_empty() and c.grab.is_empty(): return PackedStringArray(["action requires committed ability identity"])
	if _profile.character_id == "teknium" and live: return PackedStringArray(["foreign kit telemetry on Teknium"])
	if not r.is_empty() and (not str(r.get("clip","")).is_empty() or not str(r.get("move","")).is_empty()):
		if str(r.get("activation_id","")).is_empty() or r.get("facing",0) not in [-1,-1.0,1,1.0]: return PackedStringArray(["ability identity/facing required"])
		if BASIC.has(r.get("clip","")):
			if not _number(r.get("elapsed",null)): return PackedStringArray(["basic age required"])
		elif r.get("move","") in ["power_chord","sound_wave","sound_orb","rising_chord"]:
			if not _number(r.get("age",null)): return PackedStringArray(["special phase age required"])
			if r.get("phase","") not in (["anticipation","release"] if r.move == "power_chord" else ["active","recovery"]): return PackedStringArray(["unsupported ability phase"])
		else: return PackedStringArray(["unsupported ability"])
	return PackedStringArray()
