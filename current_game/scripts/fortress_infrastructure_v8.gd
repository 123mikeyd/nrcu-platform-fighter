extends RefCounted
# Original visual-only access engineering. No physics, processing or camera writes.
# Coordinates describe walking-surface TOPS, not the centres of the treads.
static func beam(s, a: Vector3,b: Vector3,width: float,mat: Material, title: String):
    var n: MeshInstance3D=s.box((a+b)*0.5,Vector3(width,a.distance_to(b),width),mat)
    n.quaternion=Quaternion(Vector3.UP,(b-a).normalized())
    n.name=title
    n.set_meta("attachment_a",a);n.set_meta("attachment_b",b)
    return n

static func landing(s,p: Vector3,size: Vector2,title: String):
    var n: MeshInstance3D=s.box(p-Vector3(0,0.10,0),Vector3(size.x,0.20,size.y),s.tread)
    n.name=title;n.set_meta("surface_top",p.y)
    # Rear rail leaves the front-to-back switchback connection unobstructed.
    for h in [0.43,0.88]:s.pipe(p+Vector3(-size.x/2,h,-size.y/2),p+Vector3(size.x/2,h,-size.y/2),0.032,s.alloy)
    for dx in [-size.x/2,size.x/2]:s.pipe(p+Vector3(dx,0,-size.y/2),p+Vector3(dx,0.88,-size.y/2),0.036,s.alloy)
    return n

static func flight(s,a: Vector3,b: Vector3,count: int,title: String):
    var first:int=s.get_child_count()
    var dx:float=(b.x-a.x)/count
    var dy:float=(b.y-a.y)/count
    for i in count:
        var top:float=a.y+dy*(i+1)
        var n:MeshInstance3D=s.box(Vector3(a.x+dx*(i+0.5),top-0.065,a.z),Vector3(abs(dx)+0.012,0.13,1.20),s.tread)
        n.name="Tread%02d"%i;n.set_meta("surface_top",top)
        # Thin wear edge, not illuminated hazard stripes.
        s.box(Vector3(a.x+dx*(i+1)-sign(dx)*0.028,top+0.006,a.z),Vector3(0.05,0.012,1.16),s.alloy)
    for zoff in [-0.56,0.56]:
        beam(s,a+Vector3(0,-0.20,zoff),b+Vector3(0,-0.20,zoff),0.16,s.steel,"ContinuousStringer")
        for h in [0.44,0.90]:s.pipe(a+Vector3(0,h,zoff),b+Vector3(0,h,zoff),0.033,s.alloy)
        for i in range(0,count+1,4):
            var p:Vector3=a.lerp(b,float(i)/count)+Vector3(0,0,zoff)
            s.pipe(p,p+Vector3(0,0.90,0),0.038,s.alloy)
    var group:Node3D=s.collect_detail(first,title)
    group.set_meta("lower_landing",a);group.set_meta("upper_landing",b)
    group.set_meta("step_count",count)
    return group

static func build(s):
    var first:int=s.get_child_count()
    # Side service tower only: keep the central turbine and combat silhouettes clear.
    var levels=[1.74,5.48,9.98,14.48]
    for x in [-18.0,-10.0]:
        for z in [-8.76,-10.24]:
            var column:MeshInstance3D=s.box(Vector3(x,-14.7,z),Vector3(0.19,60.0,0.19),s.steel)
            column.name="ServiceTowerColumn"
        for y in levels:
            s.box(Vector3(x,y-0.21,-9.5),Vector3(1.55,0.22,3.55),s.steel)
            # Short triangular landing brackets land inside the vertical columns.
            for dx in [-0.62,0.62]:beam(s,Vector3(x,y-1.15,-8.76),Vector3(x+dx,y-0.2,-8.76),0.12,s.alloy,"LandingKneeBracket")
    var a:=Vector3(-18,1.74,-8.2)
    var b:=Vector3(-10,5.48,-8.2)
    var c:=Vector3(-10,5.48,-9.6)
    var d:=Vector3(-18,9.98,-9.6)
    var e:=Vector3(-18,9.98,-8.2)
    var f:=Vector3(-10,14.48,-8.2)
    flight(s,a,b,20,"LowerFlight")
    flight(s,c,d,24,"ReturnFlight")
    flight(s,e,f,24,"UpperFlight")
    for p in [a,Vector3(-10,5.48,-8.9),Vector3(-18,9.98,-8.9),f]:
        landing(s,p,Vector2(1.5,2.6),"SwitchbackLanding")
    # Physical bridges to EXISTING apparatus service deck and left 5.4/14.4 galleries.
    landing(s,Vector3(-18,1.74,-8.7),Vector2(1.5,1.1),"ApparatusDeckConnection")
    for y in [5.48,14.48]:
        landing(s,Vector3(-10.6,y,-11.6),Vector2(1.7,6.1),"ExistingGalleryBridge")
        beam(s,Vector3(-10.6,y-1.2,-14.9),Vector3(-10.6,y-0.2,-11.6),0.16,s.steel,"GalleryWallBracket")
        s.box(Vector3(-10.6,y-0.6,-14.8),Vector3(0.55,1.4,0.22),s.alloy)
    s.collect_detail(first,"ConnectedServiceStairsV8")
    first=s.get_child_count()
    # The old rust crossbar and V braces now end in seated gussets and deck ties.
    for side in [-1.0,1.0]:
        var x:float=side*7.0
        beam(s,Vector3(x,-0.8,1.5),Vector3(x,-2,1.5),0.23,s.steel,"CrossbarDeckHanger")
        beam(s,Vector3(x,-1.2,-2),Vector3(x,-1.2,1.5),0.22,s.steel,"OriginalVBraceUpperSeat")
        s.box(Vector3(x,-0.82,1.5),Vector3(0.65,0.18,0.6),s.alloy)
        s.box(Vector3(x,-2,1.5),Vector3(0.46,0.48,0.48),s.alloy)
        var joint:=Vector3(side*4.55,-5,-2)
        s.box(joint,Vector3(0.62,0.60,0.64),s.alloy)
        beam(s,joint,Vector3(side*6.6,-5,-10.75),0.24,s.steel,"TrussToApparatusColumn")
        beam(s,Vector3(side*6.6,-5,-10.75),Vector3(side*6.6,1.9,-10.5),0.20,s.steel,"ColumnLoadTie")
        # Collar captures both the original structural column and the new tie.
        s.box(Vector3(side*6.6,-5,-10.75),Vector3(0.82,0.75,0.96),s.alloy)
        for xx in [6.6,12.5,17.5]:
            beam(s,Vector3(side*(xx+2),-2,-10.5),Vector3(side*xx,-2,-10.75),0.14,s.alloy,"ExistingSaddleBraceClosure")
    beam(s,Vector3(-4.55,-5,-2),Vector3(4.55,-5,-2),0.22,s.steel,"UnderdeckLowerChord")
    s.collect_detail(first,"AttachedUnderdeckSupportsV8")
