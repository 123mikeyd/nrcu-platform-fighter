extends RefCounted
const HEROES=["teknium","turbofit","doge_man","ggb","witcheer","mephisto"]
# Deliberate provisional sequence, not a kit-completeness or difficulty ranking.
const ORDER=["bobo","ice_mage","witcheer","ggb","turbofit","doge_man","teknium","mephisto"]
var hero=""
var route:Array=[]
var index=0
func choose(id:String):
 if id not in HEROES:return
 hero=id;index=0;route=ORDER.duplicate();route.erase(hero)
func finish(won:bool):
 if won and not complete():index+=1
func complete()->bool:return not route.is_empty() and index>=route.size()
func opponent()->String:return "" if complete() or route.is_empty() else route[index]
