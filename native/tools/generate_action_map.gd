extends SceneTree
func _initialize() -> void:
	var map=OpenXRActionMap.new()
	map.create_default_action_sets()
	var error=ResourceSaver.save(map,"res://openxr_action_map.tres")
	print("ACTION_MAP_GENERATED ",error)
	quit(error)
