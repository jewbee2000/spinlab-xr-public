extends Node3D

const Science = preload("res://scripts/rotor_lab.gd")
const Geometry = preload("res://scripts/lab_geometry.gd")
const Button3D = preload("res://scripts/lab_button.gd")
const Chart3D = preload("res://scripts/panel_chart.gd")
const HandVisual = preload("res://scripts/virtual_hand.gd")
const DirectContact = preload("res://scripts/direct_interaction.gd")
const Tutorial = preload("res://scripts/lab_tutorial.gd")
const LessonPanel = preload("res://scripts/tutorial_panel.gd")
const APP_VERSION = "0.4.0"
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
var tab := "operate"
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

func _ready() -> void:
	name="SpinLabXR"
	model.async_processing=true
	tutorial=Tutorial.new(tutorial_settings_path)
	_setup_world()
	add_child(station)
	station.position.z=station_distance
	geometry=Geometry.new()
	station.add_child(geometry)
	buttons.append(geometry.probe_home_button)
	kit_home=geometry.kit_rotor.transform
	_setup_xr()
	_build_controls()
	_build_instrument()
	_build_dials()
	_build_desktop_hud()
	_setup_sound()
	if tutorial_autostart and tutorial.should_autostart():
		tutorial.start(_tutorial_context());tab="learn";_rebuild_menu()
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
		xr_interface.connect("pose_recentered",_cancel_hand_interactions)
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
			ray.collision_mask=1
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
	button.position=pos
	button.configure(caption,command,width,height,color)
	buttons.append(button)
	return button

func _build_controls() -> void:
	station.add_child(controls)
	controls.position=Vector3(-0.46,1.50,-1.08)
	control_backplate=_box(controls,Vector3(0.82,0.76,0.025),Vector3(0,-0.04,0),Color("132634"))
	_label(controls,"SPINLAB XR  /  DIRECT HANDS",Vector3(-0.37,0.314,0.021),27,0.00059,TEAL)
	for i in range(5):
		var keys=["operate","balance","diagnostic","session","learn"]
		var titles=["OPERATE","BALANCE","ANALYZE","SESSION","LEARN"]
		_button(controls,titles[i],"tab:"+keys[i],Vector3(-0.32+i*0.16,0.235,0.027),0.15,0.052)
	tutorial_panel=LessonPanel.new();controls.add_child(tutorial_panel);tutorial_panel.configure()
	buttons.append_array(tutorial_panel.interactive_buttons)
	lesson_navigation=[_button(controls,"LESSON / NEXT","tutorial:open_next",Vector3(-0.195,-0.34,0.029),0.37,0.055),_button(controls,"SKIP TUTORIAL","tutorial:skip",Vector3(0.195,-0.34,0.029),0.37,0.055)]
	_rebuild_menu()

func _rebuild_menu() -> void:
	_reset_pokes()
	for b in buttons.duplicate():
		if b.get_meta("menu",false):
			buttons.erase(b);b.queue_free()
	tutorial_panel.set_panel_active(tab=="learn")
	control_backplate.mesh.size=Vector3(0.82,0.84 if tab=="learn" else 0.76,0.025)
	control_backplate.position.y=-0.08 if tab=="learn" else -0.04
	for button in lesson_navigation:
		button.visible=tab!="learn" and tutorial.active
		button.set_enabled(button.visible)
	if tab=="learn":
		_refresh_tutorial();return
	var items: Array=[]
	match tab:
		"operate":items=[["LOAD ROTOR / CARTRIDGE","mount"],["HOME VIBRATION PROBE","home"],["CLOSE / OPEN GUARD","guard"],["RECORD BASELINE","baseline"],["STOP / CONTROLLED COAST","stop"],["EMERGENCY STOP","estop"],["RELEASE / RESET FAULT","recover"],["MODE: SINGLE / TWO PLANE","mode"]]
		"balance":items=[["FIT KNOWN TRIAL +0.250 g","fit_trial"],["MEASURE TRIAL · PLANE A","trial_a"],["MEASURE TRIAL · PLANE B","trial_b"],["SOLVE INFLUENCE MATRIX","solve"],["FIT CALCULATED CORRECTION","apply"],["VERIFY CORRECTED ROTOR","verify"],["REPEATABILITY · THREE RUNS","repeat"],["ACTIVE PLANE: A / B","plane"]]
		"diagnostic":items=[["RUN RESONANCE SPEED SWEEP","sweep"],["CHART: TIME / ORDER / SWEEP","chart"],["TEST SPEED: 900 /1200 /1500","speed"],["INJECT SENSOR DISCONNECT","fault_sensor"],["INJECT TACHOMETER LOSS","fault_tach"],["EXPLODE / ASSEMBLE FIXTURE","explode"],["MOTOR SONIFICATION: ON/OFF","sound"],["GUIDED COACH: ON / OFF","coach"]]
		"session":items=[["SAVE TRACEABLE JSON REPORT","save"],["HANDS / REACH ASSIST: ON-OFF","assist"],["NEW SESSION · RESET LAB","new"],["LOWER STATION · SEATED","lower"],["RAISE STATION · STANDING","raise"],["MOVE BENCH: NEAR / FAR","distance"],["RECENTER STATION","recenter"],["EXIT APPLICATION","exit"]]
	for i in items.size():
		var color=Color("6b303b") if items[i][1]=="estop" else Color("285b4c") if items[i][1] in ["baseline","solve","verify"] else Color("244353")
		var b=_button(controls,_wrap_text(items[i][0],22),items[i][1],Vector3(-0.195+(i%2)*0.39,0.135-(i/2)*0.115,0.029),0.37,0.095,color)
		b.set_meta("menu",true)

func _build_instrument() -> void:
	var panel=Node3D.new();panel.position=Vector3(0.99,1.40,-1.28);station.add_child(panel)
	_box(panel,Vector3(0.87,0.95,0.024),Vector3.ZERO,Color("132634"))
	_label(panel,"LIVE / TACH-SYNCHRONOUS ANALYZER",Vector3(-0.40,0.44,0.021),28,0.00061,TEAL)
	readouts["speed"]=_label(panel,"0 RPM",Vector3(-0.40,0.36,0.021),59,0.00078)
	readouts["amplitude"]=_label(panel,"A: 0.000 um    B: 0.000 um",Vector3(-0.40,0.26,0.021),30,0.00061)
	readouts["phase"]=_label(panel,"Phase: --   /   1x synchronous peak",Vector3(-0.40,0.208,0.021),23,0.00060,DIM)
	readouts["chart"]=_label(panel,"SPEED SWEEP / um peak vs RPM",Vector3(-0.40,0.139,0.021),23,0.00057,TEAL)
	chart=Chart3D.new();chart.position=Vector3(-0.36,-0.195,0.024);panel.add_child(chart)
	readouts["axis"]=_label(panel,"0           600          1200          1800 RPM",Vector3(-0.36,-0.214,0.021),21,0.00058,DIM)
	readouts["quality"]=_label(panel,"Acquire a baseline to see measurement quality.",Vector3(-0.40,-0.273,0.021),24,0.00057,DIM)
	readouts["solution"]=_label(panel,"Correction: measured trial runs required.",Vector3(-0.40,-0.335,0.021),24,0.00057)
	readouts["result"]=_label(panel,"STANDBY / INTERLOCKS ACTIVE",Vector3(-0.40,-0.413,0.021),27,0.00061,TEAL)
	var board=Node3D.new();board.position=Vector3(0,2.09,-1.95);station.add_child(board)
	_box(board,Vector3(1.72,0.37,0.025),Vector3.ZERO,Color("10232f"))
	readouts["coach"]=_label(board,"",Vector3(-0.80,0.14,0.022),30,0.00068)
	readouts["status"]=_label(board,"",Vector3(-0.80,-0.028,0.022),24,0.00061,DIM)
	readouts["method"]=_label(station,"MEASURE > IDENTIFY > CORRECT > VERIFY\nInfluence coefficients | Tach LS | Resonance | Repeatability\nIndependent synthetic training lab. No qualification claims.",Vector3(-0.88,2.68,-2.8),28,0.00072,TEAL)
	readouts["hands"]=_label(station,"HANDS / touch buttons with the index tip. Grip nearby handles and turn dials.\nB/Y: menu · hold B/Y: reach assist · left stick: height",Vector3(-0.74,0.74,-0.82),23,0.00053,TEAL)

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
	var label=Label.new();label.text="SPINLAB XR  /  NATIVE ENGINEERING LAB    v"+APP_VERSION+"\nDrag right mouse to orbit · Wheel to zoom · Click world controls · 1/2/3/4/5 menu tabs (5: Learn)"
	label.position=Vector2(24,18);label.add_theme_font_size_override("font_size",18);label.modulate=TEAL;layer.add_child(label)
	desktop_status=Label.new();desktop_status.position=Vector2(24,930);desktop_status.add_theme_font_size_override("font_size",16);desktop_status.modulate=DIM;layer.add_child(desktop_status)
	var hud=HBoxContainer.new();hud.position=Vector2(24,90);layer.add_child(hud)
	for entry in [["Load","mount"],["Home","home"],["Guard","guard"],["Baseline","baseline"],["Trial fit","fit_trial"],["Trial A","trial_a"],["Trial B","trial_b"],["Solve","solve"],["Apply","apply"],["Verify","verify"],["Sweep","sweep"],["E-stop","estop"],["Save","save"]]:
		var b=Button.new();b.text=entry[0];b.pressed.connect(_action.bind(entry[1]));hud.add_child(b)

func _action(command: String, input_kind: String="") -> void:
	if command.begins_with("tutorial:"):
		_tutorial_action(command);return
	if not grab_owners.is_empty() and (command in ["home","mode","plane","fit_trial","apply","speed","explode"] or command.begins_with("nudge:")):
		status="Release the held fixture control before changing its setup."
		_update_ui();return
	if command in ["baseline","trial_a","trial_b","verify","sweep","repeat"] and not grab_owners.is_empty():
		status="Release the rotor, guard handle, and dials before starting the spindle."
		_update_ui();return
	if command.begins_with("tab:"):
		tab=command.trim_prefix("tab:")
		if tab=="learn" and not tutorial.active:tutorial.start(_tutorial_context())
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
		"mode":result=model.set_mode("two_plane" if model.mode=="single" else "single");active_plane=0
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
		"assist":reach_assist=not reach_assist;_reset_pokes();result.message="Reach assist enabled for menu buttons. Mechanical handles still require a nearby grip." if reach_assist else "Direct hands: touch buttons and grip nearby handles."
		"recenter":_cancel_hand_interactions();station.position.y=0;XRServer.center_on_hmd(XRServer.RESET_BUT_KEEP_TILT,true) if xr_active else _desktop_camera();result.message="Station recentered."
		"method":result.message="Baseline → known trial per plane → solve A·C = −V₀ → remove trial → fit solution → verify."
		"exit":get_tree().quit();return
		_:return
	status=result.get("message","")
	tutorial.observe(_tutorial_context(),{"command":command,"ok":result.get("ok",false),"input_kind":input_kind})
	_update_ui()

func _dial_value(kind: String) -> float:
	return float(model.sensor_position_mm) if kind=="probe" else float(model.masses[active_plane]) if kind=="mass" else float(model.angles[active_plane])

func _tutorial_context() -> Dictionary:
	return {"mounted":model.mounted,"homed":model.homed,"guard_closed":model.guard_closed,"estop":model.estop,"fault":model.fault,"rpm":model.rpm,"running":model.running,"processing":model.processing,"sensor_position_mm":model.sensor_position_mm,"masses":model.masses.duplicate(),"angles":model.angles.duplicate(),"mode":model.mode,"active_plane":active_plane,"test_rpm":model.test_rpm,"radius_mm":model.radius_mm,"records":model.records,"baseline":model.baseline,"trial_a":model.trial_a,"trial_b":model.trial_b,"solution":model.solution,"latest":model.latest,"tab":tab,"chart_kind":chart_kind,"reach_assist":reach_assist,"exploded":exploded,"sound_on":sound_on,"coach":coach,"saved_report":not saved_path.is_empty() and FileAccess.file_exists(saved_path),"grab_owners_empty":grab_owners.is_empty()}

func _refresh_tutorial() -> void:
	if tutorial==null or not is_instance_valid(tutorial_panel):return
	var view=tutorial.view(_tutorial_context())
	view["startup_enabled"]=tutorial.startup_enabled
	view["can_back"]=tutorial.index>0
	tutorial_panel.update_view(view)
	for button in lesson_navigation:
		button.visible=tab!="learn" and tutorial.active
		button.set_enabled(button.visible)
	lesson_navigation[0].set_caption("LESSON / NEXT" if view.ready else "OPEN LESSON")

func _tutorial_action(command: String) -> void:
	var context=_tutorial_context()
	match command:
		"tutorial:skip":
			tutorial.skip();tab="operate";status="Tutorial paused. Open Learn to restart; startup preference is unchanged."
		"tutorial:startup":
			var result=tutorial.set_startup(not tutorial.startup_enabled)
			status="Tutorial at startup: "+("ON" if tutorial.startup_enabled else "OFF") if result.ok else result.message
		"tutorial:restart":
			tutorial.start(context);tab="learn";status="Tutorial restarted. Your lab measurements are preserved."
		"tutorial:practice":
			var target_tab=str(tutorial.view(context).get("practice_tab",""))
			if target_tab.is_empty():return
			tab=target_tab
			status="Follow the lesson on the coach board. Open Learn / Next when ready."
		"tutorial:back":
			status=tutorial.back().message;tab="learn"
		"tutorial:skip_step":
			var result=tutorial.skip_step()
			status=result.message;tab="operate" if result.get("finished",false) else "learn"
		"tutorial:next","tutorial:open_next":
			var result=tutorial.next(context)
			status=result.get("message","")
			tab="operate" if result.get("finished",false) else "learn"
		"tutorial:touch":
			tutorial.observe(context,{"command":"tutorial:touch","ok":true})
			status="Practice press registered. Withdraw your finger to release the button."
		_:return
	_rebuild_menu();_update_ui()

func _tutorial_report() -> Dictionary:
	var view=tutorial.view(_tutorial_context())
	return {"active":tutorial.active,"step_id":view.id,"step_index":tutorial.index,"step_count":tutorial.steps.size(),"completed":tutorial.completed,"startup_enabled":tutorial.startup_enabled,"note":"Tutorial progress is self-paced guidance, separate from measurement verification or operator qualification."}

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
		return "%s / %s\n%s"%[lesson.progress,lesson.title,"Ready: open Learn / Next to continue." if lesson.ready else lesson.hint]
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
	readouts.coach.text=_wrap_text(_coach_text(t),92)
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
	var directory="user://reports"
	DirAccess.make_dir_recursive_absolute(directory)
	saved_path=directory+"/spinlab-"+stamp+"-"+str(Time.get_ticks_usec())+".json"
	var report=model.report();report["application"]="SpinLab XR";report["version"]=APP_VERSION;report["captured_at"]=Time.get_datetime_string_from_system();report["xr_active"]=xr_active
	report["interaction_mode"]="touch-controller virtual hands; direct fingertip presses and nearby grips"
	report["interaction_events"]=interaction_events.duplicate(true)
	report["runtime_samples"]=runtime_samples.duplicate(true)
	report["runtime_note"]="Application-loop timing samples; not compositor, GPU-frame-time, or comfort acceptance."
	report["tutorial"]=_tutorial_report()
	var file=FileAccess.open(saved_path,FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(report,"\t"));file.close()
		status="REPORT SAVED / "+ProjectSettings.globalize_path(saved_path)
		tutorial.observe(_tutorial_context(),{"command":"save","ok":true})
	else:status="Report could not be written: "+str(FileAccess.get_open_error())
	print("SPINLAB_REPORT ",ProjectSettings.globalize_path(saved_path))
	_update_ui()

func _controller_pressed(input_name: String, entry: Dictionary) -> void:
	if input_name=="by_button":
		entry.by_started=Time.get_ticks_msec();entry.by_handled=false
	if input_name=="ax_button":_action("chart")
	if input_name=="trigger_click" and reach_assist and entry.get("tracked",false) and entry.held=="":
		var ray=entry.ray;ray.force_raycast_update()
		if ray.is_colliding():
			var target=ray.get_collider()
			if target is LabButton and target.enabled and target.is_visible_in_tree():
				_physical_action(str(target.get_meta("action","")),"reach_assist");_haptic(entry,0.22)

func _controller_released(input_name: String, entry: Dictionary) -> void:
	if input_name=="by_button" and entry.by_started>=0:
		if not entry.by_handled and Time.get_ticks_msec()-entry.by_started<850:
			var tabs=["operate","balance","diagnostic","session","learn"]
			_action("tab:"+tabs[(tabs.find(tab)+1)%tabs.size()])
		entry.by_started=-1

func _make_hand_entry(controller: Node3D, grip_node: Node3D) -> Dictionary:
	var hand=HandVisual.new();hand.configure(str(controller.tracker) if controller is XRController3D else "right_hand");grip_node.add_child(hand)
	var hint=Label3D.new();hint.font_size=25;hint.pixel_size=0.00065;hint.position=Vector3(0.08,0.04,0.04);hint.modulate=TEAL;hint.outline_size=0;hint.billboard=BaseMaterial3D.BILLBOARD_ENABLED;grip_node.add_child(hint)
	return {"node":controller,"grip_node":grip_node,"hand":hand,"hint":hint,"held":"","held_target":null,"dial":"","raw":0.0,"contacts":{},"near":null,"tracked":false,"grip_down":false,"grip_armed":false,"by_started":-1,"by_handled":false,"ray":null,"beam":null}

func _haptic(entry: Dictionary, amplitude: float=0.25) -> void:
	if xr_active and entry.node is XRController3D:entry.node.trigger_haptic_pulse("haptic",0,amplitude,0.035,0)

func _interaction_event(kind: String, target: String) -> void:
	interaction_events.append({"time_s":model.time,"kind":kind,"target":target})
	if interaction_events.size()>512:interaction_events.pop_front()
	print("SPINLAB_INTERACTION ",kind," ",target)
	if tutorial!=null:tutorial.observe(_tutorial_context(),{"kind":kind,"target":target,"ok":kind not in ["fingertip","reach_assist"]})

func _physical_action(command: String, input_kind: String="fingertip") -> void:
	_interaction_event(input_kind,command)
	if command=="mount":status="Reach the tray rotor and hold grip. Carry it upright onto the spindle, then release.";return
	if command=="guard":status="Grip the orange enclosure handle nearby. Lift to open; lower fully to latch.";return
	_action(command,input_kind)

func _reset_pokes() -> void:
	button_latches.clear();frame_latches.clear();frame_depths.clear()
	for entry in controllers:entry.contacts.clear()
	for button in buttons:
		if is_instance_valid(button):button.set_depression(0.0);button.hover(false)

func _process_pokes(entry: Dictionary, tip: Vector3, delta: float, tracked: bool=true) -> void:
	if not tracked or entry.held!="" or entry.grip_down:
		entry.contacts.clear();return
	var alive: Dictionary={}
	for button in buttons.duplicate():
		if not is_instance_valid(button) or button.is_queued_for_deletion() or not button.enabled or not button.is_visible_in_tree():continue
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
	if entry.held!="":return false
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
		_release_near_grab(entry,true);entry.grip_armed=false;entry.grip_down=false;entry.by_started=-1;entry.by_handled=false
	_reset_pokes()

func _set_xr_focus(focused: bool) -> void:
	xr_has_focus=focused
	_apply_input_focus()

func _apply_input_focus() -> void:
	input_focused=app_has_focus and xr_has_focus
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
		entry.tracked=tracked
		entry.hand.visible=tracked;entry.hint.visible=tracked
		if not tracked:
			_release_near_grab(entry,true);entry.contacts.clear();entry.grip_down=false;entry.grip_armed=false
			entry.beam.visible=false;continue
		if not entry.get("logged_ready",false):
			entry.logged_ready=true
			print("SPINLAB_CONTROLLER_READY tracker=",c.tracker," pose=grip hands=visible direct=true")
		var grip=c.get_float("grip");var trigger=c.get_float("trigger")
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
		entry.beam.visible=reach_assist and entry.held==""
		if entry.beam.visible:
			entry.ray.force_raycast_update()
			if entry.ray.is_colliding() and entry.ray.get_collider() is LabButton:
				var target=entry.ray.get_collider()
				if target.enabled and target.is_visible_in_tree():target.hover(true)
		if entry.by_started>=0 and not entry.by_handled and Time.get_ticks_msec()-entry.by_started>=850:
			entry.by_handled=true;_action("assist");_haptic(entry,0.3)
		var stick=c.get_vector2("primary")
		if c.tracker==StringName("left_hand") and absf(stick.y)>0.75 and grab_owners.is_empty():
			_reset_pokes();station.position.y=clampf(station.position.y+stick.y*delta*0.25,-0.5,0.3)
	_finish_pokes()

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
		if event.keycode in [KEY_1,KEY_2,KEY_3,KEY_4,KEY_5]:_action("tab:"+["operate","balance","diagnostic","session","learn"][event.keycode-KEY_1])

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
	model.tick(minf(delta,0.05))
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
