extends Node3D

const Science = preload("res://scripts/rotor_lab.gd")
const Geometry = preload("res://scripts/lab_geometry.gd")
const Button3D = preload("res://scripts/lab_button.gd")
const Chart3D = preload("res://scripts/panel_chart.gd")
const HandVisual = preload("res://scripts/virtual_hand.gd")
const DirectContact = preload("res://scripts/direct_interaction.gd")
const Tutorial = preload("res://scripts/lab_tutorial.gd")
const LessonPanel = preload("res://scripts/tutorial_panel.gd")
const ControllerVisual = preload("res://scripts/virtual_controller.gd")
const HandGuide = preload("res://scripts/hand_control_guide.gd")
const CapsenseHand = preload("res://scripts/controller_capsense_hand.gd")
const Navigation = preload("res://scripts/operator_navigation.gd")
const APP_VERSION = "0.6.0"
const TEAL = Color("6ce5c9")
const INK = Color("e6f1f5")
const DIM = Color("9db7c6")
var model = Science.new()
var geometry
var rig: XROrigin3D
var camera: Camera3D
var xr_interface: XRInterface
var xr_active := false
var station := Node3D.new()
var controls := Node3D.new()
var buttons: Array = []
var readouts: Dictionary = {}
var chart
var chart_kind := "sweep"
var tab := "balance"
var status := "Welcome. Load the rotor, home the probe, and close the guard."
var coach := true
var exploded := false
var elapsed_ui := 0.0
var active_plane := 0
var controllers: Array = []
var desktop_hover
var mouse_drag := false
var last_mouse := Vector2.ZERO
var desktop_yaw := 0.25
var desktop_pitch := -0.22
var desktop_distance := 3.15
var saved_path := ""
var report_directory := "user://reports"
var capture_path := ""
var capture_frames := 0
var sound_on := false
var kit_home: Transform3D
var audio: AudioStreamPlayer3D
var audio_playback: AudioStreamGeneratorPlayback
var audio_phase := 0.0
var desktop_status: Label
var runtime_samples: Array = []
var perf_elapsed := 0.0
var perf_frames := 0
var perf_max_delta := 0.0
var dial_nodes: Dictionary = {}
var button_latches: Dictionary = {}
var frame_latches: Dictionary = {}
var frame_depths: Dictionary = {}
var grab_owners: Dictionary = {}
var reach_assist := false
var station_distance := 0.65
var interaction_events: Array = []
var input_focused := true
var app_has_focus := true
var xr_has_focus := true
## Override before entering the tree for isolated tests; empty path is memory-only.
var tutorial_settings_path := "user://tutorial.cfg"
var tutorial_autostart := true
var tutorial
var tutorial_panel
var control_backplate: MeshInstance3D
var lesson_navigation: Array = []
var menu_open := false
var menu_tab_buttons: Dictionary = {}
var monitor: Node3D
var walk_enabled := true
var walk_distance_m := 0.0
var height_changed := false
var motion_armed := false
var height_armed := false
var guide_marker: MeshInstance3D
var guide_step_id := ""
var guide_paused := false
## Optional override for deterministic controller/navigation tests.
var head_tracking_override = null
var recenter_pending_frames := 0
var guide_anchor_pending := true

func _ready() -> void:
	name="SpinLabXR"
	model.async_processing=true
	tutorial=Tutorial.new(tutorial_settings_path)
	_setup_world()
	add_child(station)
	station.position.z=station_distance
	geometry=Geometry.new()
	station.add_child(geometry)
	buttons.append_array(geometry.physical_buttons)
	# Room geometry stays fixed when the operator adjusts workbench height.
	geometry.get_node("Workshop").reparent(self,true)
	kit_home=geometry.kit_rotor.transform
	_setup_xr()
	_build_controls()
	_build_instrument()
	_build_dials()
	_build_guide()
	_build_desktop_hud()
	_setup_sound()
	if tutorial_autostart and tutorial.should_autostart():
		tutorial.start(_tutorial_context());_place_guide()
	if not tutorial.settings_error.is_empty():status=tutorial.settings_error+"; using default tutorial preferences."
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="): capture_path=arg.trim_prefix("--capture=")
		if arg=="--showcase":
			model.mount_rotor();model.home_probe();model.toggle_guard();model.begin_run("sweep")
	_update_ui()
	print("SPINLAB_NATIVE_READY version=",APP_VERSION," xr=",xr_active," input=direct-hands scientific=single,two-plane,tach-LS,resonance,repeatability")

func _setup_world() -> void:
	var env=WorldEnvironment.new()
	var e=Environment.new()
	e.background_mode=Environment.BG_COLOR
	e.background_color=Color("08131f")
	e.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color=Color("a1bfd7")
	e.ambient_light_energy=0.7
	e.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	env.environment=e
	add_child(env)
	var light=DirectionalLight3D.new()
	light.rotation_degrees=Vector3(-50,-25,0)
	light.light_color=Color("d5eaff")
	light.light_energy=1.6
	add_child(light)
	var fill=DirectionalLight3D.new()
	fill.rotation_degrees=Vector3(-30,145,0)
	fill.light_color=Color("6ccfe7")
	fill.light_energy=0.6
	add_child(fill)

func _setup_xr() -> void:
	rig=XROrigin3D.new()
	add_child(rig)
	var xr_camera=XRCamera3D.new()
	xr_camera.near=0.05
	xr_camera.far=40
	rig.add_child(xr_camera)
	xr_interface=XRServer.find_interface("OpenXR")
	if OS.has_feature("android") and xr_interface and (xr_interface.is_initialized() or xr_interface.initialize()):
		xr_active=true
		get_viewport().use_xr=true
		xr_interface.connect("session_focussed",_set_xr_focus.bind(true))
		for event in ["session_visible","session_synchronized","session_stopping","session_loss_pending"]:
			xr_interface.connect(event,_set_xr_focus.bind(false))
		xr_interface.connect("pose_recentered",_on_pose_recentered)
		xr_has_focus=xr_interface.get_session_state()==OpenXRInterface.SESSION_STATE_FOCUSED
		input_focused=app_has_focus and xr_has_focus
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		camera=xr_camera
		if xr_interface.has_method("set_display_refresh_rate"): xr_interface.set_display_refresh_rate(72.0)
		for hand in ["left_hand","right_hand"]:
			var controller=XRController3D.new()
			controller.tracker=hand
			controller.pose="aim"
			rig.add_child(controller)
			var grip_node=XRController3D.new()
			grip_node.tracker=hand;grip_node.pose="grip";rig.add_child(grip_node)
			var ray=RayCast3D.new()
			ray.target_position=Vector3(0,0,-4)
			ray.collision_mask=2
			controller.add_child(ray)
			var beam=MeshInstance3D.new()
			var beam_mesh=CylinderMesh.new()
			beam_mesh.top_radius=0.0015;beam_mesh.bottom_radius=0.0015;beam_mesh.height=3
			beam_mesh.radial_segments=6
			beam.mesh=beam_mesh
			beam.material_override=_material(TEAL,true)
			beam.rotation.x=PI/2;beam.position.z=-1.5
			controller.add_child(beam)
			beam.visible=false
			var entry=_make_hand_entry(controller,grip_node)
			entry.ray=ray;entry.beam=beam
			controllers.append(entry)
			controller.button_pressed.connect(_controller_pressed.bind(entry))
			controller.button_released.connect(_controller_released.bind(entry))
	else:
		camera=Camera3D.new()
		camera.fov=58
		camera.near=0.05;camera.far=40
		add_child(camera)
		xr_camera.queue_free()
		_desktop_camera()
		if OS.has_feature("android"): status="OpenXR did not initialize. Check headset launch category and runtime; see device log."

func _material(color: Color, unshaded := false) -> StandardMaterial3D:
	var m=StandardMaterial3D.new()
	m.albedo_color=color
	m.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED if unshaded else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	return m

func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var m=MeshInstance3D.new()
	var mesh=BoxMesh.new();mesh.size=size;m.mesh=mesh
	m.material_override=_material(color,true)
	m.position=pos;parent.add_child(m)
	return m

func _label(parent: Node3D, text: String, pos: Vector3, font_size := 30, pixel_size := 0.00065, color := INK) -> Label3D:
	var l=Label3D.new()
	l.text=text;l.position=pos;l.font_size=font_size;l.pixel_size=pixel_size*1.4
	l.modulate=color;l.outline_size=0
	l.horizontal_alignment=HORIZONTAL_ALIGNMENT_LEFT
	l.vertical_alignment=VERTICAL_ALIGNMENT_TOP
	parent.add_child(l)
	return l

func _button(parent: Node3D, caption: String, command: String, pos: Vector3, width := 0.66, height := 0.062, color := Color("244353")):
	var button=Button3D.new()
	parent.add_child(button)
	button.interaction_layer=2 if parent==controls or controls.is_ancestor_of(parent) else 1
	button.set_meta("ui",button.interaction_layer==2)
	button.set_meta("physical",button.interaction_layer==1)
	button.position=pos
	button.configure(caption,command,width,height,color)
	buttons.append(button)
	return button

func _build_controls() -> void:
	add_child(controls)
	control_backplate=_box(controls,Vector3(0.88,0.80,0.028),Vector3(0,-0.035,0),Color("132634"))
	_label(controls,"STATION CONTROLS",Vector3(-0.39,0.335,0.024),27,0.00059,TEAL)
	for i in range(3):
		var keys=["balance","diagnostic","session"]
		var titles=["BALANCE","ANALYZE","SESSION"]
		menu_tab_buttons[keys[i]]=_button(controls,titles[i],"tab:"+keys[i],Vector3(-0.27+i*0.27,0.255,0.027),0.25,0.055)
	_button(controls,"B / Y   CLOSE MENU","menu:close",Vector3(0,-0.365,0.029),0.78,0.055)
	_rebuild_menu()

func _rebuild_menu() -> void:
	_reset_pokes()
	for button in buttons.duplicate():
		if button.get_meta("menu",false):buttons.erase(button);button.queue_free()
	var items: Array=[]
	match tab:
		"balance":items=[["FIT KNOWN TRIAL +0.250 g","fit_trial"],["MEASURE TRIAL · PLANE A","trial_a"],["MEASURE TRIAL · PLANE B","trial_b"],["SOLVE INFLUENCE MATRIX","solve"],["FIT CALCULATED CORRECTION","apply"],["VERIFY CORRECTED ROTOR","verify"],["REPEATABILITY · THREE RUNS","repeat"],["ACTIVE PLANE: A / B","plane"]]
		"diagnostic":items=[["RUN RESONANCE SPEED SWEEP","sweep"],["CHART: TIME / ORDER / SWEEP","chart"],["TEST SPEED: 900 /1200 /1500","speed"],["INJECT SENSOR DISCONNECT","fault_sensor"],["INJECT TACHOMETER LOSS","fault_tach"],["EXPLODE / ASSEMBLE FIXTURE","explode"],["MOTOR SONIFICATION: ON/OFF","sound"],["GUIDED COACH: ON / OFF","coach"]]
		"session":items=[["SAVE TRACEABLE JSON REPORT","save"],["PAUSE / RESUME FLOATING GUIDE","tutorial:toggle"],["RESTART FLOATING GUIDE","tutorial:restart"],["SKIP CURRENT GUIDE LESSON","tutorial:skip_step"],["GUIDE AT STARTUP: ON/OFF","tutorial:startup"],["RECENTER AT WORKBENCH","recenter"],["JOYSTICK WALKING: ON/OFF","walk_toggle"],["NEW SESSION · RESET LAB","new"]]
	for i in items.size():
		var caption=str(items[i][0])
		if items[i][1]=="tutorial:startup":caption="GUIDE AT STARTUP: "+("ON" if tutorial.startup_enabled else "OFF")
		if items[i][1]=="tutorial:toggle":caption="PAUSE FLOATING GUIDE" if tutorial.active else "RESUME FLOATING GUIDE" if guide_paused else "START FLOATING GUIDE"
		if items[i][1]=="walk_toggle":caption="JOYSTICK WALKING: "+("ON" if walk_enabled else "OFF")
		var color=Color("6b303b") if items[i][1]=="estop" else Color("285b4c") if items[i][1] in ["baseline","solve","verify"] else Color("244353")
		var button=_button(controls,_wrap_text(caption,20),items[i][1],Vector3(-0.205+(i%2)*0.41,0.155-(i/2)*0.115,0.029),0.39,0.095,color)
		button.set_meta("menu",true)
	for key in menu_tab_buttons:
		var button=menu_tab_buttons[key]
		button.normal_color=Color("28735e") if key==tab else Color("244353")
		button.set_meta("selected",key==tab);button.hover(false)
	_sync_menu_visibility()

func _sync_menu_visibility() -> void:
	controls.visible=menu_open
	for button in buttons:
		if is_instance_valid(button) and button.get_meta("ui",false):button.set_enabled(menu_open)

func _set_menu_open(open: bool) -> void:
	_cancel_hand_interactions()
	menu_open=open;reach_assist=open
	motion_armed=false;height_armed=false
	for entry in controllers:
		entry.trigger_armed=false
		entry.hand.visible=entry.tracked and not open
		entry.controller_visual.visible=entry.tracked and open
		entry.capsense_hand.set_active(open and input_focused and _head_tracking_valid(),entry.tracked)
		_update_hand_guide(entry)
		if is_instance_valid(entry.beam):entry.beam.visible=false
	if open:_place_menu()
	_sync_menu_visibility();_update_ui()

func _place_menu() -> void:
	var forward=-camera.global_basis.z;forward.y=0
	if forward.length_squared()<0.01:forward=Vector3.FORWARD
	forward=forward.normalized()
	var right=forward.cross(Vector3.UP)
	# Prefer the operator's forward space, then a clear side of the fixture.
	for offset in [forward*0.70,forward*0.60-right*0.75,forward*0.60+right*0.75,forward*0.50-right*1.05,forward*0.50+right*1.05,forward*0.50-right*1.40,forward*0.50+right*1.40,forward*0.60-right*0.80+Vector3(0,0.50,0),forward*0.60+right*0.80+Vector3(0,0.50,0)]:
		controls.global_position=camera.global_position+offset+Vector3(0,-0.04,0)
		controls.look_at(camera.global_position,Vector3.UP,true)
		if _menu_placement_clear():return

func _menu_placement_clear() -> bool:
	var bounds=AABB(controls.to_global(Vector3(-0.46,-0.44,-0.03)),Vector3.ZERO)
	for x in [-0.46,0.46]:
		for y in [-0.44,0.40]:
			for z in [-0.03,0.04]:bounds=bounds.expand(controls.to_global(Vector3(x,y,z)))
	for obstacle in [AABB(Vector3(-0.40,0.93,-1.78),Vector3(0.80,1.02,0.82)),AABB(Vector3(0.30,0.89,-1.65),Vector3(0.58,0.40,0.48)),AABB(Vector3(-0.86,0.59,-1.91),Vector3(1.72,0.32,1.12)),AABB(Vector3(-0.36,0.80,-0.91),Vector3(0.72,0.31,0.16))]:
		if bounds.intersects(station.global_transform*obstacle):return false
	# Transform all eight display corners: an untranslated rear-screen AABB is
	# no longer valid for the yawed left-side monitor.
	if is_instance_valid(monitor) and bounds.intersects(monitor.global_transform*AABB(Vector3(-0.94,-0.54,-0.06),Vector3(1.88,1.08,0.12))):return false
	return true

func _build_instrument() -> void:
	monitor=Node3D.new();monitor.name="AnalyzerMonitor";station.add_child(monitor)
	monitor.transform=geometry.monitor_mount.transform
	_box(monitor,Vector3(1.86,1.06,0.065),Vector3(0,0,-0.02),Color("0b1118"))
	_box(monitor,Vector3(1.78,0.98,0.008),Vector3(0,0,0.019),Color("10232f"))
	# A floor-fixed base with overlapping telescopic sections keeps its foot on
	# the floor while station height changes move the screen/bracket only.
	var floor_stand=Node3D.new();floor_stand.name="AnalyzerFloorStand";add_child(floor_stand)
	var base=station.to_global(Vector3(monitor.position.x,0,monitor.position.z));base.y=0
	floor_stand.global_transform=Transform3D(Basis(Vector3.UP,monitor.rotation.y),base)
	_box(floor_stand,Vector3(0.10,0.98,0.08),Vector3(0,0.515,-0.08),Color("354b58"))
	var foot=_box(floor_stand,Vector3(0.55,0.025,0.33),Vector3(0,0.0125,-0.06),Color("1c303d"));foot.name="AnalyzerStandFoot"
	_box(monitor,Vector3(0.074,0.62,0.06),Vector3(0,-0.57,-0.08),Color("536c7b"))
	_label(monitor,"SPINLAB  /  TACH-SYNCHRONOUS ANALYZER",Vector3(-0.84,0.45,0.034),30,0.00074,TEAL)
	readouts["speed"]=_label(monitor,"0 RPM",Vector3(-0.84,0.35,0.034),50,0.00080)
	readouts["amplitude"]=_label(monitor,"",Vector3(-0.84,0.23,0.034),32,0.00072)
	readouts["phase"]=_label(monitor,"",Vector3(-0.84,0.15,0.034),26,0.00065,DIM)
	readouts["quality"]=_label(monitor,"",Vector3(-0.84,0.04,0.034),28,0.00065,DIM)
	readouts["solution"]=_label(monitor,"",Vector3(-0.84,-0.08,0.034),28,0.00066)
	readouts["result"]=_label(monitor,"",Vector3(-0.84,-0.21,0.034),28,0.00066,TEAL)
	readouts["chart"]=_label(monitor,"",Vector3(0.03,0.34,0.034),24,0.00062,TEAL)
	chart=Chart3D.new();chart.width_m=0.76;chart.height_m=0.43;chart.position=Vector3(0.035,-0.16,0.034);monitor.add_child(chart)
	readouts["axis"]=_label(monitor,"",Vector3(0.035,-0.19,0.034),23,0.00060,DIM)
	readouts["status"]=_label(monitor,"",Vector3(-0.84,-0.33,0.034),26,0.00060,DIM)
	readouts["coach"]=_label(monitor,"",Vector3(-0.84,-0.405,0.034),25,0.00058,TEAL)
	readouts["hands"]=_label(station,"B/Y MENU  ·  GUIDE ADVANCES AUTOMATICALLY  ·  X REVIEW\nLEFT STICK HEIGHT  ·  RIGHT STICK WALK",Vector3(-0.73,0.49,-0.89),23,0.00055,TEAL)

func _build_guide() -> void:
	tutorial_panel=LessonPanel.new();tutorial_panel.name="FloatingGuide";add_child(tutorial_panel);tutorial_panel.configure()
	guide_marker=MeshInstance3D.new();var mesh=SphereMesh.new();mesh.radius=0.012;mesh.height=0.024;guide_marker.mesh=mesh;guide_marker.material_override=_material(TEAL,true);add_child(guide_marker);guide_marker.visible=false
	_place_guide()

func _place_guide() -> void:
	if not is_instance_valid(tutorial_panel) or not is_instance_valid(camera):return
	var forward=-camera.global_basis.z;forward.y=0
	if forward.length_squared()<0.01:forward=Vector3.FORWARD
	forward=forward.normalized()
	var right=forward.cross(Vector3.UP)
	# Prefer a near upper-right reading position. Test actual guard/probe mesh
	# instances rather than accepting a disjoint card AABB:
	# foreground hardware can still cross the text's sightlines.
	var obstacles:Array[AABB]=[]
	var renderers:Array=[]
	if is_instance_valid(geometry):
		for branch in [geometry.guard,geometry.probe]:renderers.append_array(branch.find_children("*","GeometryInstance3D",true,false))
		for child in geometry.get_children():
			if child is GeometryInstance3D and str(child.name).begins_with("Lift"):renderers.append(child)
	for item in renderers:
		if not item.is_visible_in_tree() or str(item.name).begins_with("GuardGlass"):continue
		if str(item.name)=="GuardExtrusions":
			# CPU construction bounds also work with the headless dummy renderer,
			# where MultiMesh instance-transform readback returns identity.
			for x in [-0.30,0.30]:
				for z in [0.01,0.60]:obstacles.append((item.global_transform*AABB(Vector3(x-0.007,0.0,z-0.007),Vector3(0.014,0.40,0.014))).grow(0.008))
				for y in [0.015,0.39]:obstacles.append((item.global_transform*AABB(Vector3(x-0.007,y-0.007,0.0),Vector3(0.014,0.014,0.60))).grow(0.008))
			for z in [0.01,0.60]:
				for y in [0.015,0.39]:obstacles.append((item.global_transform*AABB(Vector3(-0.30,y-0.007,z-0.007),Vector3(0.60,0.014,0.014))).grow(0.008))
		elif item is MeshInstance3D and item.mesh:obstacles.append((item.global_transform*item.mesh.get_aabb()).grow(0.008))
		elif item is MultiMeshInstance3D and item.multimesh and item.multimesh.mesh:
			for i in item.multimesh.instance_count:obstacles.append((item.global_transform*item.multimesh.get_instance_transform(i)*item.multimesh.mesh.get_aabb()).grow(0.008))
	if is_instance_valid(monitor):obstacles.append(monitor.global_transform*AABB(Vector3(-0.94,-0.54,-0.06),Vector3(1.88,1.08,0.12)))
	for angle in [22.0,35.0,48.0,60.0,72.0,85.0]:
		var azimuth=deg_to_rad(angle)
		var direction=forward*cos(azimuth)+right*sin(azimuth)
		tutorial_panel.global_position=camera.global_position+direction*1.15+Vector3(0,0.16,0)
		tutorial_panel.look_at(camera.global_position,Vector3.UP,true)
		var clear=true
		for x in [-0.45,-0.225,0.0,0.225,0.45]:
			for y in [-0.31,-0.155,0.0,0.155,0.31]:
				var point=tutorial_panel.to_global(Vector3(x,y,0.008))
				for obstacle in obstacles:
					if obstacle.has_point(point) or obstacle.intersects_segment(camera.global_position,point)!=null:clear=false;break
				if not clear:break
			if not clear:break
		if clear:return

func _build_dials() -> void:
	for i in range(3):
		var kinds=["probe","mass","angle"]
		var knob=StaticBody3D.new();knob.set_meta("action","dial:"+kinds[i]);knob.set_meta("dial",kinds[i])
		knob.set_meta("grab_kind","dial")
		dial_nodes[kinds[i]]=knob
		knob.position=Vector3(-0.25+i*0.25,1.02,-0.84);station.add_child(knob)
		var mesh=MeshInstance3D.new();var cyl=CylinderMesh.new();cyl.top_radius=0.047;cyl.bottom_radius=0.047;cyl.height=0.045;cyl.radial_segments=24;mesh.mesh=cyl;mesh.rotation.x=PI/2;mesh.material_override=_material(Color("426777"));knob.add_child(mesh)
		var shape=CollisionShape3D.new();var sphere=SphereShape3D.new();sphere.radius=0.060;shape.shape=sphere;knob.add_child(shape)
		var tick=_box(knob,Vector3(0.004,0.026,0.004),Vector3(0,0.022,0.025),TEAL)
		knob.set_meta("tick",tick)
		readouts[kinds[i]]=_label(station,"",knob.position+Vector3(-0.10,-0.095,0.025),25,0.00056,TEAL)
		_button(station,"−", "nudge:"+kinds[i]+":-1",knob.position+Vector3(-0.077,-0.15,0),0.07,0.045)
		_button(station,"+", "nudge:"+kinds[i]+":1",knob.position+Vector3(0.077,-0.15,0),0.07,0.045)

func _build_desktop_hud() -> void:
	if xr_active:return
	var layer=CanvasLayer.new();add_child(layer)
	var label=Label.new();label.text="SPINLAB XR  /  NATIVE ENGINEERING LAB    v"+APP_VERSION+"\nDrag right mouse to orbit · Wheel to zoom · Click world controls · M menu · 1/2/3 tabs · Space guide next · Backspace guide back"
	label.position=Vector2(24,18);label.add_theme_font_size_override("font_size",18);label.modulate=TEAL;layer.add_child(label)
	desktop_status=Label.new();desktop_status.position=Vector2(24,930);desktop_status.add_theme_font_size_override("font_size",16);desktop_status.modulate=DIM;layer.add_child(desktop_status)
	var hud=HBoxContainer.new();hud.position=Vector2(24,90);layer.add_child(hud)
	for entry in [["Load","mount"],["Home","home"],["Guard","guard"],["Baseline","baseline"],["Trial fit","fit_trial"],["Trial A","trial_a"],["Trial B","trial_b"],["Solve","solve"],["Apply","apply"],["Verify","verify"],["Sweep","sweep"],["E-stop","estop"],["Save","save"]]:
		var b=Button.new();b.text=entry[0];b.pressed.connect(_action.bind(entry[1]));hud.add_child(b)

func _action(command: String, input_kind: String="") -> void:
	if command.begins_with("tutorial:"):
		_tutorial_action(command);return
	if command=="menu:close":_set_menu_open(false);return
	if command=="menu:toggle":_set_menu_open(not menu_open);return
	if not grab_owners.is_empty() and (command in ["home","mode","plane","fit_trial","apply","speed","explode"] or command.begins_with("nudge:")):
		status="Release the held fixture control before changing its setup."
		_update_ui();return
	if command in ["baseline","trial_a","trial_b","verify","sweep","repeat"] and not grab_owners.is_empty():
		status="Release the rotor, guard handle, and dials before starting the spindle."
		_update_ui();return
	if command.begins_with("tab:"):
		tab=command.trim_prefix("tab:")
		if tab not in ["balance","diagnostic","session"]:tab="balance"
		tutorial.observe(_tutorial_context(),{"command":command,"ok":true,"input_kind":input_kind})
		_rebuild_menu();_update_ui();return
	if command.begins_with("nudge:"):
		var parts=command.split(":");var steps={"probe":0.05,"mass":0.025,"angle":5.0};_set_dial(parts[1],_dial_value(parts[1])+float(parts[2])*steps[parts[1]]);return
	var result: Dictionary={"ok":true,"message":""}
	match command:
		"mount":result={"ok":true,"message":"Rotor is already mounted."} if model.mounted else model.mount_rotor()
		"home":result=model.home_probe()
		"guard":result=model.toggle_guard();geometry.guard_preview=-1.0
		"baseline","trial_a","trial_b","verify","sweep","repeat":result=model.begin_run(command)
		"stop":result=model.stop()
		"estop":result=model.emergency_stop()
		"recover":result=model.release_estop() if model.estop else model.reset_fault()
		"fault_sensor":result=model.inject_fault("sensor")
		"fault_tach":result=model.inject_fault("tach")
		"mode":
			result=model.set_mode("two_plane" if model.mode=="single" else "single")
			if result.ok:active_plane=0
		"plane":active_plane=1-active_plane if model.mode=="two_plane" else 0;result.message="Editing correction plane "+("A" if active_plane==0 else "B")
		"fit_trial":result=model.fit_trial(active_plane)
		"solve":result=model.solve_balance()
		"apply":result=model.apply_solution()
		"speed":result=model.set_test_speed(1200 if model.test_rpm==900 else 1500 if model.test_rpm==1200 else 900)
		"chart":chart_kind="time" if chart_kind=="sweep" else "order" if chart_kind=="time" else "sweep";result.message="Analyzer view: "+chart_kind
		"explode":exploded=not exploded;geometry.set_exploded(exploded);result.message="Exploded teaching view" if exploded else "Assembled operating view"
		"coach":coach=not coach;result.message="Guided coach enabled" if coach else "Expert mode: use measured amplitude and phase."
		"sound":sound_on=not sound_on;result.message="Motor sonification enabled" if sound_on else "Motor sonification muted"
		"save":_save_report();return
		"new":
			result=model.reset()
			if result.ok:
				_cancel_hand_interactions();active_plane=0;geometry.guard_preview=-1.0;saved_path=""
		"lower":_cancel_hand_interactions();station.position.y=clampf(station.position.y-0.1,-0.5,0.3);result.message="Station lowered."
		"raise":_cancel_hand_interactions();station.position.y=clampf(station.position.y+0.1,-0.5,0.3);result.message="Station raised."
		"distance":_cancel_hand_interactions();station_distance=0.82 if station_distance<0.70 and station_distance>0.60 else 0.45 if station_distance>0.70 else 0.65;station.position.z=station_distance;result.message="Bench reach adjusted. Withdraw your hand before the next press."
		"assist":_set_menu_open(not menu_open);return
		"walk_toggle":walk_enabled=not walk_enabled;motion_armed=false;result.message="Joystick walking "+("enabled" if walk_enabled else "disabled")
		"recenter":
			_cancel_hand_interactions();rig.position=Vector3.ZERO;station.position.y=0;motion_armed=false;height_armed=false
			if xr_active:XRServer.center_on_hmd(XRServer.RESET_BUT_KEEP_TILT,true)
			else:_desktop_camera()
			recenter_pending_frames=2
			if menu_open:_place_menu()
			else:_place_guide()
			result.message="Returned to the workbench. Release the sticks before moving again."
		"method":result.message="Baseline → known trial per plane → solve A·C = −V₀ → remove trial → fit solution → verify."
		"exit":get_tree().quit();return
		_:return
	status=result.get("message","")
	tutorial.observe(_tutorial_context(),{"command":command,"ok":result.get("ok",false),"input_kind":input_kind})
	_update_ui()

func _dial_value(kind: String) -> float:
	return float(model.sensor_position_mm) if kind=="probe" else float(model.masses[active_plane]) if kind=="mass" else float(model.angles[active_plane])

func _tutorial_context() -> Dictionary:
	return {"mounted":model.mounted,"homed":model.homed,"guard_closed":model.guard_closed,"estop":model.estop,"fault":model.fault,"rpm":model.rpm,"running":model.running,"processing":model.processing,"sensor_position_mm":model.sensor_position_mm,"masses":model.masses.duplicate(),"angles":model.angles.duplicate(),"mode":model.mode,"active_plane":active_plane,"test_rpm":model.test_rpm,"radius_mm":model.radius_mm,"records":model.records,"baseline":model.baseline,"trial_a":model.trial_a,"trial_b":model.trial_b,"solution":model.solution,"latest":model.latest,"tab":tab,"chart_kind":chart_kind,"reach_assist":reach_assist,"exploded":exploded,"sound_on":sound_on,"coach":coach,"saved_report":not saved_path.is_empty() and FileAccess.file_exists(saved_path),"grab_owners_empty":grab_owners.is_empty(),"menu_open":menu_open,"walk_distance_m":walk_distance_m,"height_changed":height_changed}

func _refresh_tutorial() -> void:
	if tutorial==null or not is_instance_valid(tutorial_panel):return
	var view=tutorial.view(_tutorial_context())
	for entry in controllers:entry.control_guide.set_context(tutorial.active,bool(view.ready),int(view.index)==0,walk_enabled,entry.held!="",not grab_owners.is_empty())
	tutorial_panel.update_view(view)
	tutorial_panel.set_panel_active(tutorial.active and not menu_open and (not xr_active or _head_tracking_valid()))
	if view.id!=guide_step_id:
		guide_step_id=view.id
	var offset=tutorial_panel.global_position-camera.global_position
	if tutorial.active and (offset.length()>2.6 or offset.normalized().dot(-camera.global_basis.z)<-0.1):_place_guide()
	guide_marker.visible=false
	for button in buttons:
		if is_instance_valid(button):button.guide_highlight=false
	if tutorial.active and not menu_open:
		var target: Node3D=geometry.physical_by_action.get(str(view.target),null)
		if target is LabButton:target.guide_highlight=true
		match str(view.target):
			"rotor","mount":target=geometry.rotor_grab
			"guard":target=geometry.guard_handle
			"dial:probe":target=geometry.probe_grab
		if is_instance_valid(target) and target.is_visible_in_tree():
			guide_marker.global_position=target.global_position+Vector3(0,0.08,0);guide_marker.visible=true

func _tutorial_action(command: String) -> void:
	var context=_tutorial_context()
	match command:
		"tutorial:skip":tutorial.skip();guide_paused=true;status="Guide paused. Resume it from Session in the B/Y menu."
		"tutorial:toggle":
			if tutorial.active:tutorial.skip();guide_paused=true;status="Guide paused."
			elif guide_paused:tutorial.active=true;guide_paused=false;tutorial.observe(context);status="Guide resumed. Close the menu to continue."
			else:tutorial.start(context);status="Floating guide started. Close the menu to follow it."
		"tutorial:startup":
			var result=tutorial.set_startup(not tutorial.startup_enabled)
			status="Guide at startup: "+("ON" if tutorial.startup_enabled else "OFF") if result.ok else result.message
		"tutorial:restart":tutorial.start(context);guide_paused=false;status="Floating guide restarted. Lab measurements are preserved."
		"tutorial:practice":
			_set_menu_open(false);status="Follow the physical balancing instructions. Correct actions advance the guide automatically."
		"tutorial:back":status=tutorial.back().message
		"tutorial:skip_step":status=tutorial.skip_step().message
		"tutorial:next","tutorial:open_next":status=tutorial.next(context).get("message","")
		"tutorial:touch":tutorial.observe(context,{"command":"tutorial:touch","ok":true})
		_:return
	if command in ["tutorial:restart","tutorial:toggle"]:_place_guide()
	if menu_open:_rebuild_menu()
	_update_ui()

func _tutorial_report() -> Dictionary:
	var view=tutorial.view(_tutorial_context())
	return {"active":tutorial.active,"step_id":view.id,"step_index":tutorial.index,"step_count":tutorial.steps.size(),"completed":tutorial.completed,"startup_enabled":tutorial.startup_enabled,"note":"Work-instruction progress records confirmed steps, separate from operator qualification; inspect the independent scientific verification."}

func _set_dial(kind: String, value: float) -> void:
	var previous=_dial_value(kind)
	var r: Dictionary
	if kind=="probe":r=model.set_probe(clampf(snappedf(value,0.01),0,12))
	elif kind=="mass":r=model.set_correction(active_plane,clampf(snappedf(value,0.001),0,2),model.angles[active_plane])
	else:r=model.set_correction(active_plane,model.masses[active_plane],fposmod(snappedf(value,0.5),360))
	status=r.get("message","")
	tutorial.observe(_tutorial_context(),{"command":"dial:"+kind,"ok":r.get("ok",false),"changed":not is_equal_approx(previous,_dial_value(kind))})

func _coach_text(t: Dictionary) -> String:
	if tutorial!=null and tutorial.active:
		var lesson=tutorial.view(_tutorial_context())
		return "%s / %s · %s"%[lesson.progress,lesson.title,"Step confirmed" if lesson.ready else "Follow the work instruction"]
	if not coach:return "EXPERT LAB / "+model.mode.replace("_"," ").to_upper()+" / Active correction plane "+("A" if active_plane==0 else "B")
	if t.get("fault","")!="":return "FAULT RECOVERY / wait for zero speed; release E-stop, close guard, then reset."
	if t.get("running",false):return "ACQUIRING / keep guard closed. Tach reference separates 1× vibration from noise."
	if t.get("rpm",0)>0:return "COASTING / drive is removed; wait for zero speed before opening guard."
	if not model.mounted:return "01 PREPARE / reach the tray rotor; hold grip, carry it upright to the spindle, then release."
	if not model.homed:return "02 REFERENCE / home the vibration probe, then close the guard."
	if model.baseline.is_empty():return "03 BASELINE / close guard and record the unmodified rotor response."
	if model.trial_a.is_empty():return "04 IDENTIFY / open guard → fit known trial in plane A → close guard → Trial A."
	if model.mode=="two_plane" and model.trial_b.is_empty():return "05 CROSS-COUPLING / select plane B; fit its trial relative to baseline and measure Trial B."
	if model.solution.is_empty():return "06 SOLVE / use the measured complex influence coefficients to calculate correction."
	return "07 VERIFY / open guard → Fit Calculated Correction removes trials → close guard → Verify."

func _update_ui() -> void:
	if readouts.is_empty():return
	tutorial.observe(_tutorial_context())
	_refresh_tutorial()
	var t=model.telemetry()
	readouts.speed.text="%d RPM   /   %s"%[roundi(model.rpm),model.mode.replace("_"," ").to_upper()]
	var amps=t.get("amplitudes_um",[0.0,0.0]);var phases=t.get("phases_deg",[0.0,0.0])
	readouts.amplitude.text="A: %.3f µm    B: %.3f µm"%[float(amps[0]),float(amps[1])]
	var observable=t.get("phase_observable",[true,true])
	var phase_a="%.1f°"%float(phases[0]) if observable[0] else "--"
	var phase_b="%.1f°"%float(phases[1]) if observable[1] else "--"
	readouts.phase.text="Phase A %s / B %s   ·  1× peak"%[phase_a,phase_b]
	readouts.coach.text=_wrap_text(_coach_text(t),100)
	readouts.status.text=_wrap_text(status,113)
	readouts.probe.text="PROBE\n%.2f mm"%model.sensor_position_mm
	readouts.mass.text="MASS %s\n%.3f g"%["A" if active_plane==0 else "B",model.masses[active_plane]]
	readouts.angle.text="ANGLE\n%.1f°"%model.angles[active_plane]
	for kind in dial_nodes:
		var knob=dial_nodes[kind]
		var value=_dial_value(kind)
		var turns=value/0.5 if kind=="probe" else value/0.5 if kind=="mass" else value/360.0
		var tick=knob.get_meta("tick")
		tick.position=Vector3(-sin(turns*TAU)*0.022,cos(turns*TAU)*0.022,0.025)
		tick.rotation.z=turns*TAU
	readouts.result.text=("E-STOP LATCHED") if model.estop else ("FAULT · "+model.fault.to_upper()) if model.fault!="" else "ANALYZING / TACH LS + DFT" if model.processing else "ACQUIRING %d%%"%roundi(t.get("run_progress",0.0)*100) if model.running else "COASTING / KEEP GUARD CLOSED" if model.rpm>0.1 else "ZERO SPEED / DRIVE INHIBITED" if not model.guard_closed else "READY / GUARDED"
	var noise=float(model.latest.get("noise_rms_um",0))
	readouts.quality.text="Tach LS · %.3f µm residual noise\n1024 Hz / 1024 samples · %d records"%[noise,model.records.size()]
	if model.latest.has("repeatability"):
		var stats=model.latest.repeatability.sensor_a
		readouts.quality.text="n=3 · mean %.4f µm · s %.4f µm\nType A SEM %.4f µm (not total uncertainty)"%[stats.mean_um,stats.sample_std_um,stats.standard_error_um]
	if not model.solution.is_empty():
		readouts.solution.text="A %.3f g @ %.1f° · B %.3f g @ %.1f°\nInfluence matrix condition: %.2f"%[model.solution.mass_a_g,model.solution.angle_a_deg,model.solution.mass_b_g,model.solution.angle_b_deg,model.solution.condition_number]
	else:readouts.solution.text="IC calibration / baseline + independent trial(s) required."
	if model.latest.get("kind","")=="verify" and not model.running and not model.processing and model.rpm<0.1 and model.fault=="" and not model.estop:
		var reductions=model.latest.get("reduction_percent",[0.0,0.0])
		readouts.result.text=("VERIFIED" if model.latest.get("verified",false) else "RE-RUN REQUIRED" if model.latest.get("configuration_changed",false) else "CORRECTION REQUIRED")+" / A %.1f%% reduction"%reductions[0]
	if is_instance_valid(desktop_status):desktop_status.text=status+"\n"+_coach_text(t)
	_update_chart()

func _wrap_text(text: String, columns: int) -> String:
	var line="";var out=""
	for word in text.split(" "):
		if line.length()+word.length()>columns:out+=line+"\n";line=""
		line+=word+" "
	return out+line

func _update_chart() -> void:
	var points: Array=[]
	var max_y=1.0;var max_x=1800.0;var min_y=0.0
	if chart_kind=="time":
		var samples=model.waveform
		for i in samples.size():
			var v=samples[i]
			var value=float(v.get("value",v.get("y",0))) if v is Dictionary else float(v.y) if v is Vector2 else float(v)
			points.append(Vector2(float(i)/1024.0,value));max_y=maxf(max_y,absf(value)*1.1)
		min_y=-max_y;max_x=maxf(float(samples.size())/1024.0,0.001)
		readouts.chart.text="RAW SENSOR / waveform + noise [µm]"
		readouts.axis.text="0 s                 TIME                  %.2f s"%max_x
	elif chart_kind=="order":
		for i in model.spectrum.size():
			var p=model.spectrum[i]
			var x=float(p.get("frequency_hz",p.get("frequency",i))) if p is Dictionary else float(p.x) if p is Vector2 else float(i)
			var y=float(p.get("amplitude_um",p.get("amplitude",0))) if p is Dictionary else float(p.y) if p is Vector2 else float(p)
			points.append(Vector2(x,y));max_y=maxf(max_y,y*1.1)
		max_x=100.0;readouts.chart.text="ORDER DIAGNOSTIC / DFT amplitude [µm]"
		readouts.axis.text="0 Hz        1× = %.1f Hz            100 Hz"%(model.test_rpm/60.0)
	else:
		for p in model.sweep_points:
			var value=float(p.get("amplitude_um",p.get("amplitude",0))) if p is Dictionary else float(p.y)
			var rpm_value=float(p.get("rpm",0)) if p is Dictionary else float(p.x)
			points.append(Vector2(rpm_value,value));max_y=maxf(max_y,value*1.1)
		readouts.chart.text="RESONANCE SWEEP / 1× peak [µm]"
		readouts.axis.text="0        600        1200       1800 RPM"
	chart.set_points(points,0,max_x,min_y,max_y)

func _save_report() -> void:
	var stamp=Time.get_datetime_string_from_system().replace(":","-")
	var directory=report_directory
	var directory_error=DirAccess.make_dir_recursive_absolute(directory)
	if directory_error!=OK:
		saved_path="";status="Report directory is unavailable: "+error_string(directory_error);_update_ui();return
	saved_path=directory+"/spinlab-"+stamp+"-"+str(Time.get_ticks_usec())+".json"
	var report=model.report();report["application"]="SpinLab XR";report["version"]=APP_VERSION;report["captured_at"]=Time.get_datetime_string_from_system();report["xr_active"]=xr_active
	report["interaction_mode"]="touch-controller virtual hands for physical controls; controller pointers for an explicit menu"
	report["operator_navigation"]={"walk_distance_m":walk_distance_m,"walking_enabled":walk_enabled,"height_m":station.position.y,"menu_open":menu_open}
	report["interaction_events"]=interaction_events.duplicate(true)
	report["runtime_samples"]=runtime_samples.duplicate(true)
	report["runtime_note"]="Application-loop timing samples; not compositor, GPU-frame-time, or comfort acceptance."
	report["tutorial"]=_tutorial_report()
	var file=FileAccess.open(saved_path,FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(report,"\t"));file.flush()
		var write_error=file.get_error();file.close()
		if write_error==OK:
			status="REPORT SAVED / "+ProjectSettings.globalize_path(saved_path)
			tutorial.observe(_tutorial_context(),{"command":"save","ok":true})
			print("SPINLAB_REPORT ",ProjectSettings.globalize_path(saved_path))
		else:
			DirAccess.remove_absolute(saved_path);saved_path="";status="Report write failed: "+error_string(write_error)
	else:
		status="Report could not be written: "+str(FileAccess.get_open_error());saved_path=""
	_update_ui()

func _controller_pressed(input_name: String, entry: Dictionary) -> void:
	if not input_focused:return
	if input_name=="by_button":
		_set_menu_open(not menu_open);return
	if input_name=="ax_button" and not menu_open:
		if tutorial.active:
			_tutorial_action("tutorial:back" if str(entry.node.tracker)=="left_hand" else "tutorial:next")
		return
	if input_name=="trigger_click" and menu_open and entry.get("tracked",false) and entry.get("aim_tracked",false) and entry.get("trigger_armed",false):
		entry.trigger_armed=false
		var ray=entry.ray
		if not is_instance_valid(ray):return
		ray.force_raycast_update()
		if ray.is_colliding():
			var target=ray.get_collider()
			if target is LabButton and target.get_meta("ui",false) and target.enabled and target.is_visible_in_tree():
				_physical_action(target.action,"pointer");_haptic(entry,0.22)

func _controller_released(input_name: String, entry: Dictionary) -> void:
	if input_name=="trigger_click" and input_focused and entry.get("tracked",false) and entry.get("aim_tracked",false):entry.trigger_armed=true

func _make_hand_entry(controller: Node3D, grip_node: Node3D) -> Dictionary:
	var side=str(controller.tracker) if controller.get("tracker")!=null else "right_hand"
	var hand=HandVisual.new();hand.configure(side);grip_node.add_child(hand)
	var controller_visual=ControllerVisual.new();controller_visual.configure(side);grip_node.add_child(controller_visual);controller_visual.visible=false
	var control_guide=HandGuide.new();control_guide.configure(side);grip_node.add_child(control_guide)
	var capsense_hand=CapsenseHand.new();capsense_hand.configure(side);rig.add_child(capsense_hand)
	if xr_active:
		controller_visual.enable_runtime()
		capsense_hand.enable_runtime(xr_interface)
	var hint=Label3D.new();hint.font_size=25;hint.pixel_size=0.00065;hint.position=Vector3(0.08,0.04,0.04);hint.modulate=TEAL;hint.outline_size=0;hint.billboard=BaseMaterial3D.BILLBOARD_ENABLED;grip_node.add_child(hint)
	var reticle=MeshInstance3D.new();var sphere=SphereMesh.new();sphere.radius=0.005;sphere.height=0.010;reticle.mesh=sphere;reticle.material_override=_material(TEAL,true);controller.add_child(reticle);reticle.visible=false
	return {"node":controller,"grip_node":grip_node,"hand":hand,"controller_visual":controller_visual,"control_guide":control_guide,"capsense_hand":capsense_hand,"reticle":reticle,"hint":hint,"held":"","held_target":null,"dial":"","raw":0.0,"contacts":{},"near":null,"tracked":false,"aim_tracked":false,"trigger_armed":false,"grip_down":false,"grip_armed":false,"by_started":-1,"by_handled":false,"ray":null,"beam":null}

func _update_hand_guide(entry: Dictionary) -> void:
	entry.control_guide.update_placement(entry.grip_node.global_position,camera.global_transform,input_focused and entry.get("tracked",false) and not menu_open and _head_tracking_valid())

func _haptic(entry: Dictionary, amplitude: float=0.25) -> void:
	if xr_active and entry.node is XRController3D:entry.node.trigger_haptic_pulse("haptic",0,amplitude,0.035,0)

func _interaction_event(kind: String, target: String) -> void:
	interaction_events.append({"time_s":model.time,"kind":kind,"target":target})
	if interaction_events.size()>512:interaction_events.pop_front()
	print("SPINLAB_INTERACTION ",kind," ",target)
	if tutorial!=null:tutorial.observe(_tutorial_context(),{"kind":kind,"target":target,"ok":kind not in ["fingertip","reach_assist","pointer"]})

func _physical_action(command: String, input_kind: String="fingertip") -> void:
	_interaction_event(input_kind,command)
	if input_kind=="fingertip":tutorial.observe(_tutorial_context(),{"command":"tutorial:touch","ok":true})
	if command=="mount":status="Reach the tray rotor and hold grip. Carry it upright onto the spindle, then release.";return
	if command=="guard":status="Grip the orange enclosure handle nearby. Lift to open; lower fully to latch.";return
	_action(command,input_kind)

func _reset_pokes() -> void:
	button_latches.clear();frame_latches.clear();frame_depths.clear()
	for entry in controllers:entry.contacts.clear()
	for button in buttons:
		if is_instance_valid(button):button.set_depression(0.0);button.hover(false)

func _process_pokes(entry: Dictionary, tip: Vector3, delta: float, tracked: bool=true) -> void:
	if not tracked or menu_open or entry.held!="":
		entry.contacts.clear();return
	var alive: Dictionary={}
	for button in buttons.duplicate():
		if not is_instance_valid(button) or button.is_queued_for_deletion() or not button.enabled or not button.is_visible_in_tree() or not button.get_meta("physical",false):continue
		var id=button.get_instance_id();alive[id]=true
		if not entry.contacts.has(id):entry.contacts[id]=DirectContact.PushContact.new()
		var point=button.to_local(tip)-Vector3(0,0,button.front_z_m)
		var response=entry.contacts[id].process(point,Vector2(button.width_m,button.height_m)*0.5,delta,tracked)
		frame_latches[id]=frame_latches.get(id,false) or response.latched
		frame_depths[id]=maxf(float(frame_depths.get(id,0.0)),float(response.depth))
		if response.hover:button.hover(true)
		if response.pressed and not button_latches.get(id,false):
			button_latches[id]=true
			_haptic(entry)
			_physical_action(button.action)
	for id in entry.contacts.keys():
		if not alive.has(id):entry.contacts.erase(id)

func _finish_pokes() -> void:
	var next_latches: Dictionary={}
	for button in buttons:
		if not is_instance_valid(button):continue
		var id=button.get_instance_id()
		button.set_depression(float(frame_depths.get(id,0.0)))
		next_latches[id]=frame_latches.get(id,false)
	button_latches=next_latches

func _target_distance(target: Node3D, point: Vector3) -> float:
	if not is_instance_valid(target) or not target.is_visible_in_tree():return INF
	var result=INF
	for child in target.get_children():
		if not child is CollisionShape3D or child.disabled:continue
		var local=child.to_local(point)
		var closest=local
		if child.shape is BoxShape3D:
			var half=child.shape.size*0.5;closest=local.clamp(-half,half)
		elif child.shape is SphereShape3D:
			if local.length()>child.shape.radius:closest=local.normalized()*child.shape.radius
		else:continue
		result=minf(result,point.distance_to(child.to_global(closest)))
	return result

func _find_near_grabbable(palm: Vector3) -> Node3D:
	var targets: Array=[geometry.guard_handle,geometry.rotor_grab,geometry.probe_grab]
	targets.append_array(dial_nodes.values())
	var nearest: Node3D=null;var best=0.055
	for target in targets:
		if not is_instance_valid(target) or grab_owners.has(_grab_resource(target)):continue
		if target==geometry.rotor_grab and model.mounted:continue
		var distance=_target_distance(target,palm)
		if distance<best:best=distance;nearest=target
	return nearest

func _grab_resource(target: Node3D) -> Variant:
	return "dial:"+str(target.get_meta("dial")) if str(target.get_meta("grab_kind",""))=="dial" else target.get_instance_id()

func _begin_near_grab(entry: Dictionary, palm: Vector3) -> bool:
	if menu_open or entry.held!="":return false
	var target=_find_near_grabbable(palm)
	if target==null:return false
	if model.running or model.processing or model.rpm>0.1:
		status="Wait for zero speed before gripping the fixture or its adjustments.";_haptic(entry,0.12);return false
	var kind=str(target.get_meta("grab_kind",""))
	if kind=="rotor" and (model.guard_closed or model.estop):status="Open the guard and release E-stop before loading.";return false
	grab_owners[_grab_resource(target)]=entry.node
	entry.held=kind;entry.held_target=target
	entry.previous_basis=target.global_basis.inverse()*entry.grip_node.global_basis
	if kind=="rotor":
		geometry.kit_rotor.set_meta("held",true)
		entry.grab_offset=entry.grip_node.global_transform.affine_inverse()*geometry.kit_rotor.global_transform
		status="Carry the rotor upright to the spindle. Release grip when centered to seat it."
	elif kind=="guard":
		entry.guard_start=geometry.guard_fraction();entry.guard_palm_y=palm.y
		status="Lift the handle to open. Lower it fully to engage the guard interlock."
	elif kind=="dial":
		entry.dial=str(target.get_meta("dial"));entry.raw=_dial_value(entry.dial)
		status="Turn your wrist around the dial axis. Grip release ends the adjustment."
	_haptic(entry,0.30);_interaction_event("grip_begin",kind)
	return true

func _update_held(entry: Dictionary, palm: Vector3) -> void:
	if entry.held=="":return
	if not is_instance_valid(entry.held_target):_release_near_grab(entry,true);return
	if entry.held=="rotor":
		geometry.kit_rotor.global_transform=entry.grip_node.global_transform*entry.grab_offset
	elif entry.held=="guard":
		var handle=geometry.guard_handle.global_position
		if absf(palm.x-handle.x)>0.25 or absf(palm.z-handle.z)>0.25:_release_near_grab(entry,true);return
		var fraction=clampf(entry.guard_start+(palm.y-entry.guard_palm_y)/geometry.guard_travel_m,0,1)
		if model.guard_closed and fraction>0.035:
			var opened=model.toggle_guard()
			if not opened.ok:_release_near_grab(entry,true);return
		geometry.set_guard_preview(fraction)
	elif entry.held=="dial":
		if _target_distance(entry.held_target,palm)>0.16:_release_near_grab(entry,true);return
		var basis_now=entry.held_target.global_basis.inverse()*entry.grip_node.global_basis
		var q=Quaternion(basis_now*entry.previous_basis.inverse())
		var axis=entry.held_target.get_meta("dial_axis",Vector3.BACK)
		var signed_vector=Vector3(q.x,q.y,q.z).dot(axis.normalized())
		var twist=clampf(wrapf(2.0*atan2(signed_vector,q.w),-PI,PI),-0.35,0.35)
		entry.previous_basis=basis_now
		var rate=0.5/TAU if entry.dial in ["probe","mass"] else 180.0/PI
		entry.raw+=twist*rate
		entry.raw=fposmod(entry.raw,360) if entry.dial=="angle" else clampf(entry.raw,0,12 if entry.dial=="probe" else 2)
		if absf(twist)>0.0001:_set_dial(entry.dial,entry.raw)

func _release_near_grab(entry: Dictionary, cancelled: bool=false) -> void:
	var held=str(entry.held)
	if held=="":return
	if is_instance_valid(entry.held_target):grab_owners.erase(_grab_resource(entry.held_target))
	if held=="rotor":
		var spindle=station.to_global(Geometry.CENTER)
		var upright=geometry.kit_rotor.global_basis.y.normalized().dot(station.global_basis.y.normalized())>0.78
		var aligned=geometry.kit_rotor.global_position.distance_to(spindle)<0.17 and upright
		geometry.kit_rotor.set_meta("held",false)
		geometry.kit_rotor.transform=kit_home
		if not cancelled and aligned:
			var result=model.mount_rotor();status=result.message
			if result.ok:_haptic(entry,0.5);_interaction_event("rotor_seated","spindle")
		else:status="Rotor returned to tray. Release it centered and upright over the spindle to seat it."
	elif held=="guard":
		if not cancelled and geometry.guard_fraction()<0.045 and not model.guard_closed:
			var result=model.toggle_guard();status=result.message
			if result.ok:geometry.set_guard_preview(0);_haptic(entry,0.45);_interaction_event("guard_latched","closed")
		elif not model.guard_closed:status="Guard interlock open. Lower the orange handle fully to latch it."
	_interaction_event("grip_cancel" if cancelled else "grip_release",held)
	entry.held="";entry.held_target=null;entry.dial="";entry.contacts.clear()
	_update_ui()

func _cancel_hand_interactions() -> void:
	for entry in controllers:
		_release_near_grab(entry,true);entry.grip_armed=false;entry.grip_down=false;entry.by_started=-1;entry.by_handled=false;entry.trigger_armed=false
	_reset_pokes()

func _set_xr_focus(focused: bool) -> void:
	xr_has_focus=focused
	_apply_input_focus()

func _on_pose_recentered() -> void:
	_cancel_hand_interactions();motion_armed=false;height_armed=false;recenter_pending_frames=2

func _apply_input_focus() -> void:
	input_focused=app_has_focus and xr_has_focus
	if not input_focused:
		for entry in controllers:
			entry.control_guide.visible=false
			entry.capsense_hand.set_active(false,false)
	motion_armed=false;height_armed=false
	guide_anchor_pending=true
	_cancel_hand_interactions()
	if not input_focused and is_instance_valid(model) and (model.running or model.processing):
		model.stop()
		status="Focus lost. Acquisition stopped; the simulated rotor coasts. Restart deliberately after returning."

func _update_controllers(delta: float) -> void:
	frame_latches.clear();frame_depths.clear()
	for button in buttons:
		if is_instance_valid(button):button.hover(false)
	for entry in controllers:
		var c=entry.node
		var pose=entry.grip_node.get_pose()
		var tracked=input_focused and entry.grip_node.get_has_tracking_data() and pose!=null and pose.tracking_confidence==XRPose.XR_TRACKING_CONFIDENCE_HIGH
		var aim_tracked=tracked
		if c.has_method("get_has_tracking_data"):
			var aim_pose=c.get_pose()
			aim_tracked=tracked and c.get_has_tracking_data() and aim_pose!=null and aim_pose.tracking_confidence==XRPose.XR_TRACKING_CONFIDENCE_HIGH
		entry.tracked=tracked;entry.aim_tracked=aim_tracked
		if not aim_tracked:entry.trigger_armed=false
		entry.hand.visible=tracked and not menu_open
		entry.controller_visual.visible=tracked and menu_open
		entry.capsense_hand.set_active(menu_open and input_focused and _head_tracking_valid(),tracked)
		_update_hand_guide(entry)
		entry.hint.visible=tracked and not menu_open
		entry.reticle.visible=false
		if is_instance_valid(entry.beam):entry.beam.visible=false
		if not tracked:
			_release_near_grab(entry,true);entry.contacts.clear();entry.grip_down=false;entry.grip_armed=false;entry.trigger_armed=false
			continue
		if not entry.get("logged_ready",false):
			entry.logged_ready=true;print("SPINLAB_CONTROLLER_READY tracker=",c.tracker," hands_or_pointer=true")
		var grip=c.get_float("grip");var trigger=c.get_float("trigger")
		if aim_tracked and trigger<0.2:entry.trigger_armed=true
		if menu_open:
			entry.contacts.clear();entry.grip_armed=false;entry.grip_down=false
			entry.controller_visual.update_inputs({"trigger":trigger,"grip":grip,"stick":c.get_vector2("primary"),"stick_click":c.is_button_pressed("primary_click"),"primary_click":c.is_button_pressed("ax_button"),"secondary_click":c.is_button_pressed("by_button"),"primary_touch":c.is_button_pressed("ax_touch"),"secondary_touch":c.is_button_pressed("by_touch"),"stick_touch":c.is_button_pressed("primary_touch"),"trigger_touch":c.is_button_pressed("trigger_touch")},delta)
			if aim_tracked and is_instance_valid(entry.ray) and is_instance_valid(entry.beam):
				entry.ray.force_raycast_update()
				var length=3.0
				if entry.ray.is_colliding():
					var target=entry.ray.get_collider()
					if target is LabButton and target.enabled and target.is_visible_in_tree():
						target.hover(true);length=c.global_position.distance_to(entry.ray.get_collision_point())
						entry.reticle.global_position=entry.ray.get_collision_point();entry.reticle.visible=true
				entry.beam.mesh.height=length;entry.beam.position.z=-length/2;entry.beam.visible=true
			continue
		if grip<0.2:entry.grip_armed=true
		var down=grip>0.2 if entry.grip_down else grip>=0.65
		if down and not entry.grip_down and entry.grip_armed:
			_begin_near_grab(entry,entry.hand.palm_global());entry.grip_armed=false
		elif not down and entry.grip_down:_release_near_grab(entry)
		entry.grip_down=down
		entry.hand.set_pose(trigger,grip,c.is_button_pressed("primary_touch") or c.is_button_pressed("ax_touch"),entry.held!="")
		_update_held(entry,entry.hand.palm_global())
		_process_pokes(entry,entry.hand.index_tip_global(),delta,true)
		var near=_find_near_grabbable(entry.hand.palm_global()) if entry.held=="" else null
		entry.near=near
		entry.hint.text="HOLD / "+entry.held.to_upper() if entry.held!="" else "GRIP / "+str(near.get_meta("grab_kind","")).to_upper() if is_instance_valid(near) else ""
	_update_navigation(delta)
	_finish_pokes()

func _update_navigation(delta: float) -> void:
	if not input_focused or menu_open or not grab_owners.is_empty() or not _head_tracking_valid():
		motion_armed=false;height_armed=false;return
	var left: Dictionary={};var right: Dictionary={}
	for entry in controllers:
		if str(entry.node.tracker)=="left_hand":left=entry
		if str(entry.node.tracker)=="right_hand":right=entry
	if not left.is_empty() and left.tracked:
		var stick=left.node.get_vector2("primary")
		if absf(stick.y)<0.2:height_armed=true
		if height_armed and absf(stick.y)>0.35:
			var previous=station.position.y
			station.position.y=clampf(previous+stick.y*minf(delta,0.05)*0.25,-0.5,0.3)
			if not is_equal_approx(previous,station.position.y):
				height_changed=true;_reset_pokes();tutorial.observe(_tutorial_context(),{"command":"height","ok":true})
	else:height_armed=false
	if right.is_empty() or not right.tracked or not walk_enabled:
		motion_armed=false;return
	var stick=right.node.get_vector2("primary")
	if stick.length()<Navigation.DEADZONE:motion_armed=true
	if not motion_armed:return
	var step=Navigation.movement(stick,-camera.global_basis.z,delta)
	if step.length_squared()<0.0000001:return
	var current=camera.global_position
	var allowed=Navigation.constrain_motion(current,step,station.to_global(Vector3(0,0,-1.4)),Vector2(0.85,0.475),0.18)
	var applied=allowed-current;applied.y=0
	if applied.length_squared()>0.0000001:
		rig.global_position+=applied
		tutorial_panel.global_position+=applied
		walk_distance_m+=applied.length();_reset_pokes()
		tutorial.observe(_tutorial_context(),{"command":"walk","ok":true})

func _head_tracking_valid() -> bool:
	if head_tracking_override!=null:return bool(head_tracking_override)
	if not camera.global_transform.is_finite():return false
	if not xr_active:return true
	var tracker=XRServer.get_tracker("head")
	if not tracker is XRPositionalTracker:return false
	var pose=tracker.get_pose("default")
	return pose!=null and pose.has_tracking_data and pose.tracking_confidence==XRPose.XR_TRACKING_CONFIDENCE_HIGH

func _desktop_camera() -> void:
	if xr_active:return
	var target=station.to_global(Vector3(0,1.37,-1.45))
	camera.position=target+Vector3(sin(desktop_yaw)*cos(desktop_pitch),-sin(desktop_pitch),cos(desktop_yaw)*cos(desktop_pitch))*desktop_distance
	camera.look_at(target)

func _unhandled_input(event: InputEvent) -> void:
	if xr_active:return
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_RIGHT:mouse_drag=event.pressed
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:desktop_distance=clampf(desktop_distance+(0.15 if event.button_index==MOUSE_BUTTON_WHEEL_DOWN else -0.15),1.6,5);_desktop_camera()
		if event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
			var query=PhysicsRayQueryParameters3D.create(camera.project_ray_origin(event.position),camera.project_ray_origin(event.position)+camera.project_ray_normal(event.position)*8)
			var hit=get_world_3d().direct_space_state.intersect_ray(query)
			if not hit.is_empty() and hit.collider.is_visible_in_tree() and (not hit.collider is LabButton or hit.collider.enabled):_action(str(hit.collider.get_meta("action","")))
	if event is InputEventMouseMotion and mouse_drag:desktop_yaw-=event.relative.x*0.004;desktop_pitch=clampf(desktop_pitch-event.relative.y*0.003,-0.9,0.15);_desktop_camera()
	if event is InputEventKey and event.pressed:
		if event.keycode in [KEY_1,KEY_2,KEY_3]:_action("tab:"+["balance","diagnostic","session"][event.keycode-KEY_1])
		if event.keycode==KEY_M:_set_menu_open(not menu_open)
		if event.keycode==KEY_SPACE:_tutorial_action("tutorial:next")
		if event.keycode==KEY_BACKSPACE:_tutorial_action("tutorial:back")

func _setup_sound() -> void:
	audio=AudioStreamPlayer3D.new();audio.position=Vector3(0,1.1,-1.4);station.add_child(audio)
	var stream=AudioStreamGenerator.new();stream.mix_rate=22050;stream.buffer_length=0.1;audio.stream=stream;audio.volume_db=-24;audio.play();audio_playback=audio.get_stream_playback()

func _update_sound() -> void:
	if not audio_playback:return
	var frames=mini(audio_playback.get_frames_available(),2205)
	var frequency=60.0+model.rpm/12.0
	var gain=0.12*clampf(model.rpm/1800.0,0,1) if sound_on else 0.0
	for i in frames:
		audio_phase=fposmod(audio_phase+TAU*frequency/22050.0,TAU)
		var value=sin(audio_phase)*gain
		audio_playback.push_frame(Vector2(value,value))

func _process(delta: float) -> void:
	if not input_focused or not _head_tracking_valid():guide_anchor_pending=true
	elif guide_anchor_pending:
		guide_anchor_pending=false
		if menu_open:_place_menu()
		else:_place_guide()
	if recenter_pending_frames>0:
		recenter_pending_frames-=1
		if recenter_pending_frames==0:
			if menu_open:_place_menu()
			else:_place_guide()
	model.tick(minf(delta,0.05))
	if tutorial.active and input_focused and not menu_open and (not xr_active or _head_tracking_valid()):
		var progress=tutorial.tick(minf(delta,0.05),_tutorial_context())
		if progress.get("advanced",false) or progress.get("finished",false):_update_ui()
	var t={"rpm":model.rpm,"time":model.time,"mounted":model.mounted,"guard_closed":model.guard_closed,"sensor_position_mm":model.sensor_position_mm,"masses":model.masses,"angles":model.angles,"mode":model.mode}
	geometry.update_state(t)
	if xr_active:_update_controllers(delta)
	if xr_active:
		perf_elapsed+=delta;perf_frames+=1;perf_max_delta=maxf(perf_max_delta,delta)
		if perf_elapsed>=5.0:
			var sample={"wall_time":Time.get_ticks_msec()/1000.0,"app_loop_fps":perf_frames/perf_elapsed,"max_app_delta_ms":perf_max_delta*1000.0,"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)}
			runtime_samples.append(sample)
			print("SPINLAB_PERF ",JSON.stringify(sample))
			perf_elapsed=0;perf_frames=0;perf_max_delta=0
	_update_sound()
	elapsed_ui+=delta
	if elapsed_ui>0.16:_update_ui();elapsed_ui=0
	if capture_path!="":
		capture_frames+=1
		if capture_frames>120:
			get_viewport().get_texture().get_image().save_png(capture_path)
			print("SPINLAB_CAPTURE ",capture_path)
			get_tree().quit()

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_PAUSED,NOTIFICATION_APPLICATION_FOCUS_OUT] and is_instance_valid(model):
		app_has_focus=false;_apply_input_focus()
	elif what in [NOTIFICATION_APPLICATION_RESUMED,NOTIFICATION_APPLICATION_FOCUS_IN]:
		app_has_focus=true;_apply_input_focus()

func _exit_tree() -> void:
	if is_instance_valid(audio):audio.stop()
	audio_playback=null
	model=null
