extends SceneTree
func _initialize():call_deferred("run")
func run():
    var dust=load("res://scripts/ggb_dust.gd").new()
    root.add_child(dust)
    var puff=dust.puffs[0]
    if puff.position.x<0.75 or puff.material_override.shading_mode!=BaseMaterial3D.SHADING_MODE_UNSHADED:
        printerr("FAIL: impact puffs hidden inside body/arena shadows")
        dust.free();quit(1);return
    dust._process(0.3)
    if puff.position.x>1.5 or puff.scale.x>2:
        printerr("FAIL: dust must stay compact")
        dust.free();quit(1);return
    dust.free()
    print("PASS: compact dust clears body silhouette and stays readable in dark arena")
    quit()
