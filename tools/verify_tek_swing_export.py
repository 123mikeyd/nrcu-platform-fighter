"""Isolated export evidence; never writes builds or production project settings."""
from pathlib import Path
import export_core_lab as exporter
import argparse
import shutil

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--engine', required=True, help='Godot executable name or path')
args = parser.parse_args()
engine = shutil.which(args.engine)
if not engine:
    parser.error('Engine executable not found')

root = Path(__file__).resolve().parent.parent
out = root / '.verification/core/teknium-swing-punch'
stage = out / 'export-project'
exporter.prepare_project(root, stage)
(stage / 'swing_probe.gd').write_text('''extends Node3D
const Host = preload("res://scripts/core/collision/collision_host.gd")
const View = preload("res://scripts/core/presentation/teknium_presenter.gd")
var host = Host.new()
var view = View.new()
var tick := 0
var label: Label
var face := 1
func _ready():
    var errors = host.configure(load("res://data/collision/generated/teknium.tres"),"export-swing-v1")
    print("SWING_EXPORT_CONFIG ",errors)
    add_child(view)
    var camera := Camera3D.new(); add_child(camera); camera.position = Vector3(0,1.1,6); camera.projection = Camera3D.PROJECTION_ORTHOGONAL; camera.size = 3.2
    var light := DirectionalLight3D.new(); add_child(light); light.rotation_degrees = Vector3(-35,-25,0)
    var env := WorldEnvironment.new(); env.environment = Environment.new(); env.environment.background_mode = Environment.BG_COLOR; env.environment.background_color = Color(.1,.12,.16); env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.environment.ambient_light_color = Color.WHITE; env.environment.ambient_light_energy = .7; add_child(env)
    var canvas := CanvasLayer.new(); add_child(canvas)
    var row := HBoxContainer.new(); canvas.add_child(row)
    for time in [0.0,.075,.115,.167,.20,.32]:
        var button := Button.new(); button.text = str(time); row.add_child(button); button.pressed.connect(sample.bind(time))
    var button := Button.new(); button.text = "Mirror"; row.add_child(button); button.pressed.connect(mirror)
    label = Label.new(); label.position = Vector2(8,48); canvas.add_child(label)
    sample(.075)
    if "--verify-and-quit" in OS.get_cmdline_user_args():
        for f in [-1,1]:
            face = f
            for time in [0.0,.075,.115,.167,.20,.32]: sample(time)
        print("PASS: exported swing actual-bone canonical parity")
        get_tree().quit()
func mirror():
    face *= -1; sample(.167)
func sample(time: float):
    var c := {"generation":1,"lifecycle_revision":0,"status":"normal","locomotion":"idle","action":"basic","grounded":true,"facing":face,"air_jumps_left":2,"velocity":Vector3.ZERO,"presentation":{},"strike_id":"swing","strike_move":"SIDE STRIKE","strike_elapsed":time,"source_melee":true,"recovery_id":"","force_id":"","grab":{},"caught":{},"entity_id":1}
    host.commit(c,tick,Transform3D.IDENTITY,{}); tick += 1
    var record: Dictionary = host.telemetry()
    view.present_canonical(record)
    if not record.get("ok",false) or not view.model.visible:
        push_error("export derived source failed closed "+str(record)); return
    var r: Dictionary = record.pose_request
    var pose: Dictionary = host.sampler.sample(r.clip,r.source_seconds,r.time_policy)
    for b in view.skeleton.get_bone_count():
        if not (view.skeleton.global_transform*view.skeleton.get_bone_global_pose(b)).is_equal_approx(r.modelplacement*pose[str(view.skeleton.get_bone_name(b))]): push_error("export bone mismatch")
    label.text = "SwingPunchV1 / source %.3fs / facing %d\\nSame authored keys: canonical renderer + authoritative sampler" % [time,face]
    print("SWING_EXPORT_POSE ",time," ",face," ",r.derived_source)
''')
(stage / 'swing_probe.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://swing_probe.gd" id="1"]\n[node name="SwingProbe" type="Node3D"]\nscript = ExtResource("1")\n')
text = (stage / 'project.godot').read_text().replace('res://scenes/training_lab.tscn', 'res://swing_probe.tscn')
(stage / 'project.godot').write_text(text)
web = out / 'web-probe'
web.mkdir(exist_ok=True)
common = [engine, '--headless', '--path', str(stage)]
exporter.run_checked(common + ['--editor', '--import'], out / 'probe-import.log')
exporter.run_checked(common + ['--export-release', 'Web LAN', str(web / 'index.html')], out / 'probe-export.log')
exporter.run_checked([engine, '--headless', '--main-pack', str(web / 'index.pck'), '--', '--verify-and-quit'], out / 'exported-pck-probe.log')
print(web / 'index.html')
