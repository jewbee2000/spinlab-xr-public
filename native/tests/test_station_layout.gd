extends SceneTree
## Readout plaques must stay bounded and cannot cover physical operating caps
## or the three actual adjustments from seated/standing front working poses.
const Placement = preload("res://scripts/target_callout_placement.gd")

class SilentApp extends "res://scripts/main.gd":
	func _init() -> void:
		narration_enabled=false;narration_settings_path="";tutorial_settings_path="";tutorial_autostart=false
	func _setup_sound() -> void:pass

var checks := 0
var failures := 0
var app
var capture_directory := ""

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):capture_directory=argument.trim_prefix("--capture-dir=")
	call_deferred("_run")

func _check(condition: bool, caption: String) -> void:
	checks+=1
	if not condition:failures+=1;push_error("STATION LAYOUT: "+caption)

func _run() -> void:
	app=SilentApp.new();root.add_child(app);app.set_process(false);app.set_process_unhandled_input(false);app.model.async_processing=false
	_check(app.dial_nodes.keys().size()==2 and app.dial_nodes.has("mass") and app.dial_nodes.has("angle"),"Exactly two front knobs; probe adjustment belongs to real micrometer")
	var action_counts: Dictionary={}
	for body in app.station.find_children("*","CollisionObject3D",true,false):
		var action: String=str(body.get_meta("action",""))
		if not action.is_empty():action_counts[action]=int(action_counts.get(action,0))+1
	for action in ["home","dial:probe","dial:mass","dial:angle","speed"]:
		_check(action_counts.get(action,0)==1,"One unambiguous physical actuator for "+action)
	for action in action_counts:_check(not str(action).begins_with("nudge:"),"No redundant +/- adjustment caps")
	var readout_bounds: Dictionary={}
	for key in ["probe","mass","angle"]:
		var label: Label3D=app.readouts[key]
		var plaque: Node3D=label.get_parent()
		var meshes: Array=plaque.find_children("*","MeshInstance3D",false,false)
		if key=="probe":
			_check(plaque.name.ends_with("Readout") and meshes.size()==1 and meshes[0].mesh is BoxMesh,"Probe readout has one fixed compact backing")
			_check(plaque.find_children("*","CollisionObject3D",true,false).is_empty(),"Readout cannot intercept a physical press")
			readout_bounds[key]=meshes[0].global_transform*meshes[0].mesh.get_aabb()
			_check(meshes[0].mesh.size.x<=0.15 and meshes[0].mesh.size.y<=0.06,"Probe readout remains compact")
		else:
			_check(plaque==app.dial_nodes[key] and label.horizontal_alignment==HORIZONTAL_ALIGNMENT_CENTER,"Adjustment label is printed directly on its own knob")
			_check(meshes.size()==2,"Knob has only its existing disc and rim tick, with no separate label panel")
		for probe_value in [0.0,6.0,15.0]:
			for plane in range(2):
				app.model.sensor_position_mm=probe_value;app.active_plane=plane;app.model.masses[plane]=2.0;app.model.angles[plane]=359.5;app._update_ui()
				_test_text_fit(label,key)
	var controls: Dictionary={}
	var control_faces: Dictionary={}
	for button in app.geometry.physical_buttons:
		controls[button.action]=button.global_transform*AABB(Vector3(-button.width_m/2,-button.height_m/2,-0.012),Vector3(button.width_m,button.height_m,0.034))
		control_faces[button.action]=_front_face(button,button.width_m,button.height_m,0.023)
	for key in ["mass","angle"]:
		var knob: Node3D=app.dial_nodes[key]
		controls["dial:"+key]=knob.global_transform*AABB(Vector3(-0.05,-0.05,-0.024),Vector3(0.1,0.1,0.048))
		control_faces["dial:"+key]=_front_face(knob,0.094,0.094,0.024)
	controls["dial:probe"]=app.geometry.probe_grab.global_transform*AABB(Vector3(-0.045,-0.04,-0.04),Vector3(0.09,0.08,0.08))
	control_faces["dial:probe"]=_front_face(app.geometry.probe_grab,0.065,0.056,0.029)
	control_faces["guard_open"]=_front_face(app.geometry.guard_handle,0.20,0.028,0.045)
	var closed_face: Array[Vector3]=[]
	for point in control_faces.guard_open:closed_face.append(point-Vector3(0,app.geometry.guard_travel_m,0))
	control_faces["guard_closed"]=closed_face
	var tray_bounds: AABB=app.geometry.kit_rotor.global_transform*AABB(Vector3(-0.221,-0.024,-0.221),Vector3(0.442,0.105,0.442))
	for key in readout_bounds:
		for action in controls:
			_check(not readout_bounds[key].intersects(controls[action]),"Readout "+key+" does not touch actuator "+action)
	# MASS/ANGLE glyphs stay within their existing knob faces (checked below),
	# so they add no silhouette. Only the probe has a separate plaque to test.
	var visual_obstacles: Dictionary=readout_bounds.duplicate()
	# Actual user heights with symmetric eye separation; standing, seated, and
	# modest side approaches are checked at the default height.
	for height in [1.20,1.40,1.65]:
		for x in [-0.45,0.0,0.45]:
			for eye_offset in [-0.032,0.032]:
				var eye:=Vector3(x+eye_offset,height,0.12)
				for key in visual_obstacles:
					var hidden_actions: Array=[]
					for action in control_faces:
						var face: Array[Vector3]=control_faces[action]
						if Placement._pyramid_intersects(eye,face,visual_obstacles[key]):hidden_actions.append(action)
					if Placement._pyramid_intersects(eye,Placement._projected_face(eye,tray_bounds),visual_obstacles[key]):hidden_actions.append("tray rotor")
					_check(hidden_actions.is_empty(),"Readout %s leaves operating controls visible at eye %.2f/%.2f: %s" % [key,x,height,str(hidden_actions)])
	app.model.sensor_position_mm=6;app.model.masses=[0.0,0.0];app.model.angles=[0.0,0.0];app.active_plane=0;app._update_ui()
	if not capture_directory.is_empty():await _render_qa()
	app.queue_free();await process_frame
	print("STATION LAYOUT TESTS: %d checks, %d failures" % [checks,failures]);quit(0 if failures==0 else 1)

func _front_face(body: Node3D, width: float, height: float, depth: float) -> Array[Vector3]:
	return [body.to_global(Vector3(-width/2,-height/2,depth)),body.to_global(Vector3(width/2,-height/2,depth)),body.to_global(Vector3(width/2,height/2,depth)),body.to_global(Vector3(-width/2,height/2,depth))]

func _test_text_fit(label: Label3D, key: String) -> void:
	var font: Font=ThemeDB.fallback_font
	var fits:=true
	var maximum_width:=0.0
	for line in label.text.split("\n"):
		var width: float=font.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,label.font_size).x*label.pixel_size
		fits=fits and width<=float(label.get_meta("max_width_m"))
		maximum_width=maxf(maximum_width,width)
	var total_height: float=font.get_height(label.font_size)*label.pixel_size*label.text.split("\n").size()
	_check(fits and label.position.y-total_height>=float(label.get_meta("min_y_m")),"Readout text fits fixed plaque at extreme "+key+" value")
	if label.has_meta("face_radius_m"):
		var vertical_limit: float=maxf(absf(label.position.y),absf(label.position.y-total_height))
		_check(Vector2(maximum_width/2,vertical_limit).length()<float(label.get_meta("face_radius_m"))-0.005,"Every glyph corner stays inside existing "+key+" knob face")

func _render_qa() -> void:
	DirAccess.make_dir_recursive_absolute(capture_directory)
	root.size=Vector2i(1800,1200)
	for layer in app.find_children("*","CanvasLayer",false,false):layer.hide()
	app.camera.fov=62
	app.camera.global_position=Vector3(0.0,1.65,1.05);app.camera.look_at(app.station.to_global(Vector3(0,1.0,-1.15)),Vector3.UP)
	await _save("station-controls.png")
	app.camera.global_position=Vector3(0.0,1.20,0.85);app.camera.look_at(app.station.to_global(Vector3(0,1.0,-1.15)),Vector3.UP)
	await _save("station-controls-seated.png")

func _save(filename: String) -> void:
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(capture_directory.path_join(filename))==OK,"Rendered station image saves: "+filename)
