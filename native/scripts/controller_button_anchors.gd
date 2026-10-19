class_name ControllerButtonAnchors
extends RefCounted
## Resting physical button centers from the pinned Quest 2 GLB, in grip space.
## Positions include every authored mesh/parent/root transform. Press travel
## supplies the outward cap normal; no procedural XY layout is invented here.

const ASSET_DIRECTORY := "res://assets/controllers/oculus-touch-v3/"
static var _cache: Dictionary = {}


static func for_hand(side: String) -> Dictionary:
	var key := "left" if side in ["left","left_hand"] else "right"
	if _cache.has(key):return _cache[key].duplicate(true)
	var packed := load(ASSET_DIRECTORY+key+".glb") as PackedScene
	if packed==null:return {}
	var model := packed.instantiate() as Node3D
	var result: Dictionary={}
	var letters: Array=["X","Y"] if key=="left" else ["A","B"]
	for index in range(2):
		var letter: String=letters[index]
		var prefix := letter.to_lower()+"_button"
		var mesh := model.find_child(prefix,true,false) as MeshInstance3D
		var minimum := model.find_child(prefix+"_pressed_min",true,false) as Node3D
		var maximum := model.find_child(prefix+"_pressed_max",true,false) as Node3D
		if mesh==null or minimum==null or maximum==null:
			push_error("Quest 2 button anchor not found: "+prefix)
			continue
		var normal := (_to_grip(minimum).origin-_to_grip(maximum).origin).normalized()
		if normal.length_squared()<0.9:
			push_error("Quest 2 button has no authored press direction: "+prefix)
			continue
		result["primary" if index==0 else "secondary"]={"letter":letter,
			"center":_to_grip(mesh)*mesh.get_aabb().get_center(),"normal":normal,"mesh_name":prefix}
	model.free()
	_cache[key]=result
	return result.duplicate(true)


static func _to_grip(node: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var cursor: Node=node
	while cursor!=null:
		if cursor is Node3D:result=cursor.transform*result
		cursor=cursor.get_parent()
	return result
