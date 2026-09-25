extends RefCounted
# Runtime seconds -> retained native source frames. Contact uses the inverse.
const CLOCK={
 "ForwardBackhand":[Vector2(.10,1),Vector2(.30,20),Vector2(.43,27),Vector2(.58,33),Vector2(1.05,64)],
 "GroundPalmSlam":[Vector2(.10,1),Vector2(.38,24),Vector2(.53,33),Vector2(.68,38),Vector2(1.15,76)]}
const ENTRY=.10
const EXIT=.14
static func frame_at(clip:String,time:float)->float:
 var points=CLOCK[clip]
 for i in range(1,points.size()):
  if time<=points[i].x:return lerpf(points[i-1].y,points[i].y,clampf(inverse_lerp(points[i-1].x,points[i].x,time),0,1))
 return points[-1].y
static func time_at(clip:String,frame:float)->float:
 var points=CLOCK[clip]
 for i in range(1,points.size()):
  if frame<=points[i].y:return lerpf(points[i-1].x,points[i].x,clampf(inverse_lerp(points[i-1].y,points[i].y,frame),0,1))
 return points[-1].x
static func duration(clip:String)->float:return CLOCK[clip][-1].x+EXIT
