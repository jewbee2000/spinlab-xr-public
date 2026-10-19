class_name LabGeometry
extends Node3D
## Original, metrically consistent training fixture. Numerical rotor correction
## radius is intentionally magnified for legibility in a standalone headset.

var rotor: Node3D
var guard: Node3D
var probe: Node3D
var kit_rotor: Node3D
var mass_markers: Array[MeshInstance3D] = []
var guard_handle: StaticBody3D
var rotor_grab: StaticBody3D
var probe_grab: StaticBody3D
var probe_home_button: StaticBody3D
var physical_buttons: Array = []
var physical_by_action: Dictionary = {}
var operating_console: Node3D
var monitor_mount: Node3D
var guard_preview := -1.0
var guard_travel_m := 0.43
var _guard_closed := false

var _assembly: Node3D
var _lower_plane: Node3D
var _upper_plane: Node3D
var _probe_carriage: Node3D
var _status_light: MeshInstance3D
var _phase_light: MeshInstance3D
var _rotor_label: Label3D
var _exploded := false
var _built := false
var _was_mounted := false
var _materials: Dictionary = {}
var _meshes: Dictionary = {}
var _guard_action: StaticBody3D
var _kit_action: StaticBody3D
var _mounted_action: StaticBody3D

const CENTER := Vector3(0.0, 1.125, -1.4)


func _ready() -> void:
	_build_materials()
	_build_room()
	_build_bench()
	_build_station()
	_build_guard()
	_build_probe()
	_build_tray()
	_build_operating_console()
	monitor_mount=Node3D.new()
	monitor_mount.name="AnalyzerMonitorMount"
	monitor_mount.position=Vector3(-1.55,1.45,-1.20)
	monitor_mount.rotation.y=deg_to_rad(50.0)
	add_child(monitor_mount)
	_built = true
	update_state({"rpm": 0.0, "time": 0.0, "mounted": false, "guard_closed": false,
		"sensor_position_mm": 0.0, "masses": [], "angles": [], "mode": "single"})


func _build_materials() -> void:
	_mat("navy", Color("182b3c"), 0.65, 0.34)
	_mat("steel", Color("8eacbb"), 0.82, 0.26)
	_mat("aluminum", Color("bdccd0"), 0.72, 0.31)
	_mat("black", Color("101b22"), 0.3, 0.48)
	_mat("rubber", Color("182128"), 0.05, 0.87)
	_mat("table", Color("253e4b"), 0.42, 0.61)
	_mat("floor", Color("101c27"), 0.1, 0.84)
	_mat("wall", Color("162735"), 0.05, 0.92)
	_mat("grid", Color("294654"), 0.0, 0.95)
	_mat("cyan", Color("4ee6e5"), 0.35, 0.28, true)
	_mat("orange", Color("ff8b38"), 0.35, 0.35)
	_mat("amber", Color("f1bd62"), 0.65, 0.26)
	_mat("white", Color("dbeaf1"), 0.0, 0.9, true)
	_mat("muted", Color("86a9bb"), 0.0, 0.9, true)
	_mat("red", Color("fc665d"), 0.0, 0.5, true)
	_mat("green", Color("70f5bc"), 0.0, 0.5, true)
	var glass := _mat("glass", Color(0.28, 0.65, 0.75, 0.09), 0.1, 0.2)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	glass.no_depth_test = false


func _mat(key: String, color: Color, metal: float, rough: float, unshaded := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metal
	material.roughness = rough
	if unshaded:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_materials[key] = material
	return material


func _build_room() -> void:
	var room := Node3D.new()
	room.name = "Workshop"
	add_child(room)
	_box(room, "Floor", Vector3(7.0, 0.08, 7.0), Vector3(0, -0.045, -1.0), "floor")
	_box(room, "AcousticBackWall", Vector3(7, 3.4, 0.1), Vector3(0, 1.65, -3.6), "wall")
	_box(room, "LeftWall", Vector3(0.08, 3.4, 7), Vector3(-3.45, 1.65, -1), "wall")
	var floor_lines: Array[Transform3D] = []
	for i in range(-6, 7):
		floor_lines.append(Transform3D(Basis.IDENTITY, Vector3(i * 0.5, 0.001, -1)))
	_batch(room, "FloorGridLong", _box_mesh(Vector3(0.008, 0.002, 6.5)), "grid", floor_lines)
	var cross_lines: Array[Transform3D] = []
	for i in range(-6, 7):
		cross_lines.append(Transform3D(Basis.IDENTITY, Vector3(0, 0.002, -1 + i * 0.5)))
	_batch(room, "FloorGridCross", _box_mesh(Vector3(6.5, 0.002, 0.008)), "grid", cross_lines)
	for x in [-2.7, -1.85, 1.85, 2.7]:
		_box(room, "WallLuminaire", Vector3(0.025, 1.6, 0.018), Vector3(x, 1.85, -3.53), "cyan")
	_box(room, "BackConsole", Vector3(2.55, 0.72, 0.45), Vector3(0, 0.36, -3.2), "navy")
	_box(room, "ConsoleTop", Vector3(2.65, 0.045, 0.51), Vector3(0, 0.74, -3.2), "steel")
	var drawers: Array[Transform3D] = []
	for x in [-0.8, 0.0, 0.8]:
		for y in [0.16, 0.37, 0.58]:
			drawers.append(Transform3D(Basis.IDENTITY, Vector3(x, y, -2.97)))
	_batch(room, "ConsoleHandles", _box_mesh(Vector3(0.34, 0.014, 0.028)), "aluminum", drawers)
	_label(room, "SPINLAB   /   PRECISION DYNAMICS", Vector3(0, 2.1, -3.53), 0.0010, "white")
	_label(room, "VIRTUAL ENGINEERING LABORATORY", Vector3(0, 1.86, -3.53), 0.00052, "muted")


func _build_bench() -> void:
	var bench := Node3D.new()
	bench.name = "IsolationWorkbench"
	add_child(bench)
	_box(bench, "IsolatedTabletop", Vector3(1.7, 0.085, 0.95), Vector3(0, 0.85, -1.4), "table")
	_box(bench, "FrontAluminumApron", Vector3(1.7, 0.065, 0.025), Vector3(0, 0.79, -0.92), "navy")
	_box(bench, "FrontAccent", Vector3(1.56, 0.006, 0.008), Vector3(0, 0.815, -0.901), "cyan")
	var leg_transforms: Array[Transform3D] = []
	var feet_transforms: Array[Transform3D] = []
	for x in [-0.735, 0.735]:
		for z in [-1.79, -1.01]:
			leg_transforms.append(Transform3D(Basis.IDENTITY, Vector3(x, 0.41, z)))
			feet_transforms.append(Transform3D(Basis.IDENTITY, Vector3(x, 0.035, z)))
	_batch(bench, "ExtrusionLegs", _box_mesh(Vector3(0.055, 0.75, 0.055)), "navy", leg_transforms)
	_batch(bench, "VibrationIsolators", _cylinder_mesh(0.059, 0.06), "rubber", feet_transforms)
	_box(bench, "RearCrossBrace", Vector3(1.5, 0.04, 0.04), Vector3(0, 0.25, -1.79), "steel")
	for x in [-0.735, 0.735]:
		_box(bench, "SideBrace", Vector3(0.04, 0.04, 0.80), Vector3(x, 0.25, -1.4), "steel")
	_label(bench, "SPINLAB  •  ROTORDYNAMICS STATION", Vector3(-0.17, 0.774, -0.903), 0.00048, "white")
	_label(bench, "SYNTHETIC TRAINING HARDWARE", Vector3(0, 0.701, -0.901), 0.00034, "muted")
	var hole_transforms: Array[Transform3D] = []
	for x in range(-7, 8):
		for z in range(-3, 4):
			hole_transforms.append(Transform3D(Basis.IDENTITY, Vector3(x * 0.1, 0.894, -1.4 + z * 0.1)))
	_batch(bench, "OpticalTableMountingHoles", _cylinder_mesh(0.004, 0.002), "black", hole_transforms)


func _build_station() -> void:
	_assembly = Node3D.new()
	_assembly.name = "ReactionWheelDynamometer"
	add_child(_assembly)
	_box(_assembly, "GraniteMetrologyBase", Vector3(0.68, 0.065, 0.62), Vector3(0, 0.938, -1.4), "black")
	_box(_assembly, "BaseTop", Vector3(0.65, 0.012, 0.59), Vector3(0, 0.976, -1.4), "navy")
	for x in [-0.276, 0.276]:
		for z in [-1.65, -1.15]:
			_cylinder(_assembly, "BaseFastener", 0.011, 0.006, Vector3(x, 0.987, z), "steel")
	_cylinder(_assembly, "MotorHousing", 0.11, 0.105, Vector3(0, 1.023, -1.4), "navy")
	_cylinder(_assembly, "BearingCarrier", 0.076, 0.035, Vector3(0, 1.086, -1.4), "steel")
	_cylinder(_assembly, "PrecisionSpindle", 0.023, 0.25, Vector3(0, 1.13, -1.4), "aluminum")
	_torus(_assembly, "BearingAccent", 0.067, 0.073, Vector3(0, 1.107, -1.4), "cyan")
	rotor = _make_rotor(_assembly, "MountedRotor", CENTER)
	_lower_plane = rotor.get_node("PlaneA")
	_upper_plane = rotor.get_node("PlaneB")
	var pickup := _action(_assembly, "RotorMountInteraction", "mount", Vector3(0.47, 0.25, 0.47), CENTER)
	pickup.set_meta("description", "Load or unload reaction wheel")
	_mounted_action = pickup
	for i in range(4):
		var marker := _box(rotor, "CorrectionMass%d" % i, Vector3(0.044, 0.025, 0.035), Vector3.ZERO, "amber")
		marker.visible = false
		mass_markers.append(marker)
	_box(_assembly, "InstrumentFront", Vector3(0.53, 0.047, 0.03), Vector3(0, 0.965, -1.071), "navy")
	_status_light = _box(_assembly, "StateIndicator", Vector3(0.026, 0.008, 0.008), Vector3(-0.23, 0.97, -1.051), "cyan")
	_rotor_label = _label(_assembly, "ROTOR A  /  AWAITING LOAD", Vector3(0.025, 0.964, -1.05), 0.00030, "white")
	# A separate optical tachometer makes phase measurement visible and legible.
	_box(_assembly, "TachometerStem", Vector3(0.027, 0.15, 0.028), Vector3(-0.277, 1.06, -1.53), "steel")
	_box(_assembly, "OpticalTachometer", Vector3(0.065, 0.046, 0.058), Vector3(-0.277, 1.15, -1.53), "navy")
	_phase_light = _box(_assembly, "PhasePickup", Vector3(0.012, 0.018, 0.02), Vector3(-0.241, 1.15, -1.53), "cyan")
	_label(_assembly, "PHASE", Vector3(-0.277, 1.2, -1.50), 0.00028, "muted")


func _make_rotor(parent: Node3D, node_name: String, pos: Vector3) -> Node3D:
	var wheel := Node3D.new()
	wheel.name = node_name
	wheel.position = pos
	parent.add_child(wheel)
	_cylinder(wheel, "InertiaDisc", 0.221, 0.048, Vector3.ZERO, "black")
	_cylinder(wheel, "MachinedFace", 0.205, 0.009, Vector3(0, 0.029, 0), "steel")
	_cylinder(wheel, "CentralHub", 0.064, 0.093, Vector3(0, 0.022, 0), "navy")
	_cylinder(wheel, "HubCap", 0.044, 0.012, Vector3(0, 0.075, 0), "aluminum")
	var plane_a := Node3D.new()
	plane_a.name = "PlaneA"
	wheel.add_child(plane_a)
	_torus(plane_a, "CorrectionRingA", 0.171, 0.180, Vector3(0, 0.039, 0), "amber")
	var plane_b := Node3D.new()
	plane_b.name = "PlaneB"
	plane_b.position.y = -0.1
	wheel.add_child(plane_b)
	_torus(plane_b, "CorrectionRingB", 0.171, 0.180, Vector3(0, 0.039, 0), "cyan")
	_cylinder(plane_b, "LowerBalancePlane", 0.205, 0.013, Vector3(0, 0.023, 0), "navy")
	var bolt_transforms: Array[Transform3D] = []
	var spoke_transforms: Array[Transform3D] = []
	var tick_transforms: Array[Transform3D] = []
	for i in range(12):
		var angle := float(i) * TAU / 12.0
		var point := Vector3(sin(angle) * 0.13, 0.038, cos(angle) * 0.13)
		bolt_transforms.append(Transform3D(Basis.IDENTITY, point))
	for i in range(6):
		var angle := float(i) * TAU / 6.0
		spoke_transforms.append(Transform3D(Basis(Vector3.UP, angle), Vector3(sin(angle) * 0.117, 0.036, cos(angle) * 0.117)))
	for i in range(36):
		var angle := float(i) * TAU / 36.0
		tick_transforms.append(Transform3D(Basis(Vector3.UP, angle), Vector3(sin(angle) * 0.195, 0.036, cos(angle) * 0.195)))
	_batch(wheel, "RadialMachining", _box_mesh(Vector3(0.018, 0.005, 0.088)), "navy", spoke_transforms)
	_batch(wheel, "CaptiveFasteners", _cylinder_mesh(0.008, 0.008), "aluminum", bolt_transforms)
	_batch(wheel, "AngularScale", _box_mesh(Vector3(0.003, 0.003, 0.010)), "white", tick_transforms)
	_box(wheel, "ZeroDegreePhaseFlag", Vector3(0.028, 0.006, 0.028), Vector3(0, 0.039, 0.211), "cyan")
	return wheel


func _build_guard() -> void:
	guard = Node3D.new()
	guard.name = "CounterbalancedLiftGuard"
	guard.position = Vector3(0, 0.99, -1.7)
	add_child(guard)
	var frame_transforms: Array[Transform3D] = []
	for x in [-0.30, 0.30]:
		for z in [0.01, 0.60]:
			frame_transforms.append(Transform3D(Basis.IDENTITY.scaled(Vector3(0.014, 0.40, 0.014)), Vector3(x, 0.20, z)))
		for y in [0.015, 0.39]:
			frame_transforms.append(Transform3D(Basis.IDENTITY.scaled(Vector3(0.014, 0.014, 0.60)), Vector3(x, y, 0.30)))
	for z in [0.01, 0.60]:
		for y in [0.015, 0.39]:
			frame_transforms.append(Transform3D(Basis.IDENTITY.scaled(Vector3(0.60, 0.014, 0.014)), Vector3(0, y, z)))
	_batch(guard, "GuardExtrusions", _box_mesh(Vector3.ONE), "aluminum", frame_transforms)
	for x in [-0.299, 0.299]:
		_box(guard, "SidePolycarbonate", Vector3(0.002, 0.375, 0.57), Vector3(x, 0.20, 0.30), "glass")
	_box(guard, "FrontPolycarbonate", Vector3(0.58, 0.375, 0.002), Vector3(0, 0.20, 0.599), "glass")
	_box(guard, "GuardHandle", Vector3(0.20, 0.028, 0.031), Vector3(0, 0.29, 0.638), "orange")
	for x in [-0.085, 0.085]:
		_box(guard, "HandleBracket", Vector3(0.02, 0.028, 0.045), Vector3(x, 0.29, 0.617), "orange")
	_guard_action = _action(guard, "GuardHandleInteraction", "guard", Vector3(0.29, 0.13, 0.15), Vector3(0, 0.29, 0.61))
	_guard_action.set_meta("description", "Open or close interlocked enclosure")
	_guard_action.set_meta("grab_kind", "guard")
	guard_handle = _guard_action
	_label(guard, "INTERLOCKED ENCLOSURE", Vector3(0, 0.34, 0.612), 0.00031, "white")
	_box(guard, "GuardLatch", Vector3(0.028, 0.044, 0.026), Vector3(0.28, 0.025, 0.622), "orange")
	for x in [-0.33, 0.33]:
		_box(self, "LiftGuideRail", Vector3(0.028, 0.91, 0.034), Vector3(x, 1.425, -1.70), "navy")
		_box(guard, "LiftBearingBlock", Vector3(0.050, 0.10, 0.060), Vector3(x, 0.23, 0), "steel")
	_box(self, "LiftTopCrossmember", Vector3(0.71, 0.035, 0.055), Vector3(0, 1.89, -1.70), "steel")


func _build_probe() -> void:
	probe = Node3D.new()
	probe.name = "MicrometerProbeStage"
	probe.position = Vector3(0.47, 0.94, -1.41)
	add_child(probe)
	_box(probe, "ProbeStageBase", Vector3(0.30, 0.065, 0.30), Vector3.ZERO, "navy")
	for z in [-0.10, 0.10]:
		_box(probe, "DovetailRail", Vector3(0.29, 0.017, 0.021), Vector3(0, 0.046, z), "steel")
	_probe_carriage = Node3D.new()
	_probe_carriage.name = "SensorCarriage"
	probe.add_child(_probe_carriage)
	_box(_probe_carriage, "CrossSlide", Vector3(0.15, 0.04, 0.24), Vector3(0, 0.069, 0), "aluminum")
	_box(_probe_carriage, "SensorMast", Vector3(0.037, 0.18, 0.045), Vector3(0, 0.167, 0), "navy")
	_box(_probe_carriage, "Accelerometer", Vector3(0.07, 0.047, 0.06), Vector3(-0.03, 0.235, 0), "cyan")
	var sensor_tip := _cylinder(_probe_carriage, "ProbeTip", 0.011, 0.13, Vector3(-0.103, 0.235, 0), "steel")
	sensor_tip.rotation.z = PI / 2
	var screw := _cylinder(probe, "LeadScrew", 0.011, 0.29, Vector3(0.045, 0.07, 0), "steel")
	screw.rotation.z = PI / 2
	var barrel := _cylinder(probe, "MicrometerBarrel", 0.021, 0.10, Vector3(0.19, 0.07, 0), "aluminum")
	barrel.rotation.z = PI / 2
	var thimble := _cylinder(probe, "KnurledMicrometer", 0.028, 0.065, Vector3(0.27, 0.07, 0), "navy")
	thimble.rotation.z = PI / 2
	var knurl_transforms: Array[Transform3D] = []
	for i in range(16):
		var angle := i * TAU / 16.0
		knurl_transforms.append(Transform3D(Basis(Vector3.RIGHT, angle), Vector3(0.27, 0.07 + sin(angle) * 0.028, cos(angle) * 0.028)))
	_batch(probe, "MicrometerGripRibs", _box_mesh(Vector3(0.055, 0.004, 0.004)), "steel", knurl_transforms)
	probe_grab = _action(probe, "MicrometerGrabInteraction", "dial:probe", Vector3(0.090, 0.080, 0.080), Vector3(0.27, 0.07, 0))
	probe_grab.set_meta("grab_kind", "dial")
	probe_grab.set_meta("dial", "probe")
	probe_grab.set_meta("dial_axis", Vector3.RIGHT)
	probe_home_button = preload("res://scripts/lab_button.gd").new()
	probe.add_child(probe_home_button)
	probe_home_button.position = Vector3(0.025, 0.065, 0.14)
	probe_home_button.configure("HOME", "home", 0.085, 0.042, Color("285b4c"))
	probe_home_button.text_label.font_size=24
	probe_home_button.text_label.pixel_size=0.00070
	probe_home_button.set_meta("physical",true)
	physical_buttons.append(probe_home_button)
	_label(probe, "PROBE  /  HOME", Vector3(0, 0.002, 0.155), 0.0003, "white")
	_label(probe, "10 µm / DIV", Vector3(0.21, 0.12, 0.06), 0.00025, "muted")
	# Cable is a deliberately simplified routed harness, without costly physics.
	_box(probe, "SensorCableVertical", Vector3(0.013, 0.22, 0.013), Vector3(0.065, 0.13, -0.055), "black")
	_box(probe, "SensorCableRoute", Vector3(0.09, 0.013, 0.013), Vector3(0.11, 0.027, -0.055), "black")


func _build_tray() -> void:
	var tray := Node3D.new()
	tray.name = "RotorLoadingTray"
	tray.position = Vector3(-0.57, 0.908, -1.35)
	add_child(tray)
	_box(tray, "ToolTray", Vector3(0.42, 0.025, 0.51), Vector3.ZERO, "navy")
	_box(tray, "FoamInsert", Vector3(0.39, 0.01, 0.48), Vector3(0, 0.018, 0), "rubber")
	for x in [-0.21, 0.21]:
		_box(tray, "TrayEdge", Vector3(0.009, 0.025, 0.51), Vector3(x, 0.02, 0), "steel")
	_label(tray, "ROTOR CASSETTE", Vector3(0, 0.002, 0.265), 0.00034, "white")
	kit_rotor = _make_rotor(tray, "PickupRotor", Vector3(0, 0.070, 0))
	kit_rotor.scale = Vector3.ONE * 0.82
	kit_rotor.get_node("PlaneB").visible = false
	_kit_action = _action(kit_rotor, "RotorGrabInteraction", "mount", Vector3(0.47, 0.16, 0.47), Vector3.ZERO)
	_kit_action.set_meta("grab_kind", "rotor")
	_kit_action.set_meta("description", "Grab reaction wheel or select to load")
	rotor_grab = _kit_action
	var bolt_tray := _box(tray, "CorrectionMassKit", Vector3(0.19, 0.026, 0.055), Vector3(0, 0.035, 0.19), "black")
	for i in range(4):
		_box(bolt_tray, "MassKit%d" % i, Vector3(0.026, 0.012, 0.03), Vector3(-0.06 + i * 0.04, 0.02, 0), "amber")


func _build_operating_console() -> void:
	# A real bench apron rather than a floating menu. Its upward-facing slope
	# leaves the tray, lift handle, spindle, probe, and front dials unobstructed.
	operating_console=Node3D.new()
	operating_console.name="PhysicalOperatingConsole"
	operating_console.position=Vector3(0,0.70,-0.84)
	operating_console.rotation.x=deg_to_rad(-35)
	add_child(operating_console)
	_box(operating_console,"ConsoleChassis",Vector3(1.64,0.30,0.060),Vector3.ZERO,"navy")
	_box(operating_console,"ConsoleFaceplate",Vector3(1.61,0.276,0.007),Vector3(0,0,0.034),"black")
	_box(operating_console,"ConsoleAccent",Vector3(1.55,0.003,0.003),Vector3(0,-0.130,0.040),"cyan")
	for x in [-0.615,-0.211,0.394]:
		_box(operating_console,"ConsoleGroupDivider",Vector3(0.002,0.23,0.002),Vector3(x,0.004,0.040),"steel")
	for x in [-0.78,0.78]:
		for y in [-0.123,0.123]:
			var fastener=_cylinder(operating_console,"ConsoleCaptiveFastener",0.0045,0.004,Vector3(x,y,0.041),"steel")
			fastener.rotation.x=PI/2
	_label(operating_console,"DRIVE",Vector3(-0.711,0.115,0.043),0.00048,"white")
	_label(operating_console,"PREPARE / RUN",Vector3(-0.405,0.115,0.043),0.00048,"cyan")
	_label(operating_console,"BALANCE / IDENTIFY + CORRECT",Vector3(0.085,0.115,0.043),0.00046,"cyan")
	_label(operating_console,"ANALYZE / SESSION",Vector3(0.598,0.125,0.043),0.00043,"cyan")
	var emergency=_console_button("E-STOP","estop",Vector3(-0.711,0.002,0.058),0.138,0.105,Color("a8333c"))
	var mushroom := CylinderMesh.new()
	mushroom.top_radius=0.052;mushroom.bottom_radius=0.052;mushroom.height=0.018
	mushroom.radial_segments=24
	emergency.face.mesh=mushroom
	emergency.face.rotation.x=PI/2
	emergency.front_z_m=0.009
	emergency.text_label.font_size=29
	emergency.text_label.pixel_size=0.00063
	var halo=_torus(operating_console,"EmergencyStopBackingRing",0.056,0.066,Vector3(-0.711,0.002,0.046),"amber")
	halo.rotation.x=PI/2
	_label(operating_console,"LATCH / RESET",Vector3(-0.711,-0.101,0.043),0.00034,"white")
	var run := [["HOME","home"],["BASELINE","baseline"],["STOP","stop"],["RESET /\nRELEASE","recover"]]
	for i in range(run.size()):
		var pos=Vector3(-0.500+(i%2)*0.190,0.053-(i/2)*0.106,0.054)
		_console_button(run[i][0],run[i][1],pos,0.170,0.072,Color("285b4c") if i==1 else Color("244353"))
	var balance := [["FIT\nTRIAL","fit_trial"],["MEASURE\nTRIAL A","trial_a"],["MEASURE\nTRIAL B","trial_b"],["SOLVE","solve"],["APPLY\nCORRECTION","apply"],["VERIFY","verify"]]
	for i in range(balance.size()):
		var pos=Vector3(-0.110+(i%3)*0.195,0.053-(i/3)*0.106,0.054)
		_console_button(balance[i][0],balance[i][1],pos,0.170,0.072,Color("285b4c") if i in [3,5] else Color("244353"))
	var analysis := [["REPEAT","repeat"],["SWEEP","sweep"],["PLANE A/B","plane"],["MODE","mode"],["CHART","chart"],["SAVE REPORT","save"]]
	for i in range(analysis.size()):
		var pos=Vector3(0.505+(i%2)*0.185,0.075-(i/2)*0.075,0.054)
		_console_button(analysis[i][0],analysis[i][1],pos,0.160,0.054,Color("244353"))


func _console_button(caption: String, command: String, pos: Vector3, width: float, height: float, color: Color):
	var button=preload("res://scripts/lab_button.gd").new()
	button.name="Physical_"+command
	operating_console.add_child(button)
	button.position=pos
	button.configure(caption,command,width,height,color)
	button.text_label.font_size=25 if height>0.06 else 23
	button.text_label.pixel_size=0.00068
	button.set_meta("physical",true)
	button.set_meta("console",true)
	physical_buttons.append(button)
	physical_by_action[command]=button
	return button


func update_state(t: Dictionary) -> void:
	if not _built:
		return
	var rpm := float(t.get("rpm", 0.0))
	var seconds := float(t.get("time", 0.0))
	var mounted := bool(t.get("mounted", false))
	var guard_closed := bool(t.get("guard_closed", false))
	_guard_closed = guard_closed
	var mode := str(t.get("mode", "single")).to_lower()
	var two_plane := mode.contains("two") or mode.contains("couple") or mode == "2"
	rotor.visible = mounted
	# Leave a grabbed rotor's transform untouched; the interaction controller owns it.
	if not kit_rotor.has_meta("held") or not bool(kit_rotor.get_meta("held", false)):
		kit_rotor.visible = not mounted
		_kit_action.collision_layer = 1 if not mounted else 0
	_mounted_action.collision_layer = 1
	guard.position.y = 0.99 + guard_fraction() * guard_travel_m
	rotor.rotation.y = fmod(seconds * rpm * TAU / 60.0 * 0.022, TAU)
	_upper_plane.visible = two_plane or _exploded
	_upper_plane.position.y = -0.15 if _exploded else -0.1
	_lower_plane.position.y = 0.05 if _exploded else 0.0
	_probe_carriage.position.x = clampf((float(t.get("sensor_position_mm", 6.0)) - 6.0) / 6.0, -1.0, 1.0) * 0.072
	_status_light.material_override = _materials["green" if mounted and guard_closed else "orange"]
	_phase_light.visible = mounted and (rpm < 5.0 or fmod(seconds * rpm / 60.0, 1.0) < 0.3)
	_rotor_label.text = "ROTOR A  /  %04d RPM" % int(rpm) if mounted else "ROTOR A  /  AWAITING LOAD"
	var masses: Variant = t.get("masses", [])
	var angles: Variant = t.get("angles", [])
	for i in range(mass_markers.size()):
		var marker := mass_markers[i]
		marker.visible = false
		if i >= masses.size():
			continue
		var entry: Variant = masses[i]
		var mass := 0.0
		var angle := 0.0
		var plane := i % 2 if two_plane else 0
		if entry is Dictionary:
			mass = float(entry.get("mass_g", entry.get("mass", 0.0)))
			angle = float(entry.get("angle_deg", entry.get("angle", 0.0)))
			plane = int(entry.get("plane", plane))
		else:
			mass = float(entry)
			if i < angles.size():
				angle = float(angles[i])
		if mass <= 0.0 or not mounted:
			continue
		var radians := deg_to_rad(angle)
		var y := 0.060 if plane == 0 else -0.040
		if _exploded:
			y += 0.05 if plane == 0 else -0.05
		marker.position = Vector3(sin(radians) * 0.178, y, cos(radians) * 0.178)
		marker.rotation.y = radians
		marker.scale.y = clampf(0.5 + mass * 0.15, 0.5, 2.0)
		marker.visible = true
	_was_mounted = mounted


func guard_fraction() -> float:
	return clampf(guard_preview, 0, 1) if guard_preview >= 0.0 else 0.0 if _guard_closed else 1.0


func set_guard_preview(fraction: float) -> void:
	guard_preview = clampf(fraction, 0, 1)
	guard.position.y = 0.99 + guard_preview * guard_travel_m


func set_exploded(enabled: bool) -> void:
	_exploded = enabled
	if not _built:
		return
	_lower_plane.position.y = 0.05 if enabled else 0.0
	_upper_plane.position.y = -0.15 if enabled else -0.1
	_upper_plane.visible = true


func _box(parent: Node3D, node_name: String, size: Vector3, pos: Vector3, material: String) -> MeshInstance3D:
	return _mesh(parent, node_name, _box_mesh(size), pos, material)


func _box_mesh(size: Vector3) -> BoxMesh:
	var key := "box:%s" % str(size)
	if not _meshes.has(key):
		var shape := BoxMesh.new()
		shape.size = size
		_meshes[key] = shape
	return _meshes[key]


func _cylinder(parent: Node3D, node_name: String, radius: float, height: float, pos: Vector3, material: String) -> MeshInstance3D:
	return _mesh(parent, node_name, _cylinder_mesh(radius, height), pos, material)


func _cylinder_mesh(radius: float, height: float) -> CylinderMesh:
	var key := "cylinder:%f:%f" % [radius, height]
	if not _meshes.has(key):
		var shape := CylinderMesh.new()
		shape.top_radius = radius
		shape.bottom_radius = radius
		shape.height = height
		shape.radial_segments = 24
		shape.rings = 1
		_meshes[key] = shape
	return _meshes[key]


func _torus(parent: Node3D, node_name: String, inner: float, outer: float, pos: Vector3, material: String) -> MeshInstance3D:
	var key := "torus:%f:%f" % [inner, outer]
	if not _meshes.has(key):
		var shape := TorusMesh.new()
		shape.inner_radius = inner
		shape.outer_radius = outer
		shape.rings = 32
		shape.ring_segments = 8
		_meshes[key] = shape
	return _mesh(parent, node_name, _meshes[key], pos, material)


func _mesh(parent: Node3D, node_name: String, shape: Mesh, pos: Vector3, material: String) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = node_name
	mesh.mesh = shape
	mesh.position = pos
	mesh.material_override = _materials[material]
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh)
	return mesh


func _batch(parent: Node3D, node_name: String, mesh: Mesh, material: String, transforms: Array[Transform3D]) -> MultiMeshInstance3D:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = transforms.size()
	for i in range(transforms.size()):
		multi.set_instance_transform(i, transforms[i])
	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multi
	instance.set_meta("callout_instance_transforms", transforms.duplicate())
	instance.material_override = _materials[material]
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance


func _label(parent: Node3D, value: String, pos: Vector3, pixels: float, material: String) -> Label3D:
	var label := Label3D.new()
	label.name = "Label"
	label.text = value
	label.position = pos
	label.pixel_size = pixels
	label.font_size = 32
	label.modulate = (_materials[material] as StandardMaterial3D).albedo_color
	label.outline_size = 3
	label.outline_modulate = Color("0c1821")
	label.shaded = false
	label.double_sided = true
	parent.add_child(label)
	return label


func _action(parent: Node3D, node_name: String, action: String, size: Vector3, pos: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = pos
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("action", action)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)
	return body
