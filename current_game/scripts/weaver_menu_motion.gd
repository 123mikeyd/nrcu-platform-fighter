extends Control
# Lightweight 2D presentation only: no world, models, physics or skeletons.
var clock := 0.0
var loading := false
func _ready():
 mouse_filter=Control.MOUSE_FILTER_IGNORE
 set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
func _process(delta):
 clock+=delta
 queue_redraw()
func _draw():
 var sx=size.x/1280.0;var sy=size.y/720.0
 # Sparse slow gold motes, concentrated away from navigation.
 for i in 32:
  var x=450.0+fmod(float(i)*173.7+sin(clock*.13+float(i))*13.0,810.0)
  var y=fmod(float(i)*97.1-clock*(3.0+float(i%4)),720.0)
  var a=.10+.16*(sin(clock*.6+float(i))+1.0)*.5
  draw_circle(Vector2(x*sx,y*sy),1.0+float(i%2)*.7,Color(.93,.76,.40,a))
 # Fine moving light along the title rule; no flashes.
 var x=64.0+fmod(clock*24.0,318.0)
 draw_line(Vector2(64*sx,252*sy),Vector2(382*sx,252*sy),Color(.67,.51,.27,.5),1.0)
 draw_line(Vector2(x*sx,252*sy),Vector2(minf(382,x+28)*sx,252*sy),Color(.97,.82,.53,.85),2.0)
 if loading:
  for i in 14:
   var y=105.0+float(i)*39.0
   var x0=fmod(clock*190.0+float(i)*41.0,1600.0)-240.0
   draw_line(Vector2(x0*sx,y*sy),Vector2((x0+220)*sx,(y-90)*sy),Color(.87,.70,.37,.15),1.0)
