extends Control
var points:Array[Vector2]=[]
var completed=0
func _draw():
 for i in range(points.size()-1):
  var a=points[i];var b=points[i+1]
  var count=maxi(1,int(a.distance_to(b)/15))
  for j in range(count+1):
   draw_circle(a.lerp(b,float(j)/count),3.0,Color("b4efc6") if i<completed else Color("556974"))
