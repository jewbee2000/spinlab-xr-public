extends SceneTree
## Full-bound and finite-pyramid rejection plus actual station construction.
const Placement = preload("res://scripts/target_callout_placement.gd")
const Fixture = preload("res://scripts/lab_geometry.gd")
class QuietApplication extends "res://scripts/main.gd":
	func _setup_sound() -> void: pass
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("TARGET PLACEMENT: " + description)

func _run() -> void:
	_test_pure_placement()
	_test_volume_occlusion()
	_test_construction_bounds()
	_test_cached_capture()
	_test_actual_station()
	_test_application_views()
	print("TARGET CALLOUT PLACEMENT TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _head(position: Vector3 = Vector3(0, 1.65, 0)) -> Transform3D:
	return Transform3D(Basis.IDENTITY, position)

func _assert_safe(result: Dictionary, obstacles: Array, target: Vector3, description: String) -> void:
	_check(result.visible, description + " has a safe near candidate")
	if not result.visible: return
	_check(result.transform.origin.distance_to(target) <= 0.48, description + " stays beside its target")
	for obstacle in obstacles:
		_check(not result.bounds.grow(Placement.CLEARANCE_M).intersects(obstacle), description + " full bounds clear physical geometry")
	_check(result.bounds.position.y >= 0.015, description + " clears floor")
	_check(result.transform.basis.z.dot((_head().origin - result.transform.origin).normalized()) > 0.99, description + " readable side faces viewer")

func _test_pure_placement() -> void:
	var target := Transform3D(Basis.IDENTITY, Vector3(0, 1.1, -1))
	var clear: Dictionary = Placement.find_placement(target, _head(), [])
	_assert_safe(clear, [], target.origin, "Unobstructed target")
	var again: Dictionary = Placement.find_placement(target, _head(), [])
	_check(clear == again, "Placement is deterministic")
	var other_head: Transform3D = _head(Vector3(0.05, 1.65, 0))
	var moved: Dictionary = Placement.find_placement(target, other_head, [], {"preferred_candidate": clear.candidate_index})
	_check(moved.visible and moved.transform.origin.is_equal_approx(clear.transform.origin), "Head movement turns the callout but does not drag its target-local origin")
	var translated: Transform3D = target.translated(Vector3(0.12, 0.20, 0.08))
	var followed: Dictionary = Placement.find_placement(translated, _head(), [], {"preferred_candidate": clear.candidate_index})
	_check(followed.visible and (followed.transform.origin - clear.transform.origin).is_equal_approx(translated.origin - target.origin), "A moved mechanism carries its callout offset with it")
	var blocked: Array = [AABB(target.origin - Vector3.ONE, Vector3.ONE * 2)]
	_check(not Placement.find_placement(target, _head(), blocked).visible, "Surrounded target hides instead of using an intersecting fallback")
	_check(not Placement.find_placement(target, _head(), [], {"candidate_offsets": []}).visible, "No candidates gives no visual fallback")
	_check(not Placement.find_placement(target, _head(), [], {"candidate_offsets": [Vector3(2,0,0)]}).visible, "Remote candidates are rejected instead of becoming a world card")
	_check(not Placement.find_placement(target, _head(), ["bad bounds"]).visible, "Missing/invalid bounds fail closed")
	_check(not Placement.find_placement(Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), target.origin), _head(), []).visible, "Singular target transform fails closed")
	_check(not Placement.find_placement(target, _head(), [], {"size": Vector3.ZERO}).visible, "Invalid callout size fails closed")
	_check(not Placement.find_placement(target, _head(), [], {"target_bounds": AABB()}).visible, "Missing target extent fails closed rather than hiding its silhouette check")
	_check(not Placement.find_placement(target, _head(), [], {"eye_half_separation": -0.04}).visible, "Invalid stereo separation fails closed")
	_check(not Placement.find_placement(target, _head(), [], {"max_target_distance": INF}).visible, "Unbounded target distance is rejected")
	var under_floor := Transform3D(Basis.IDENTITY, Vector3(0,-1,-1))
	_check(not Placement.find_placement(under_floor, _head(), []).visible, "No prompt can intersect the floor limit")
	var touch: AABB = clear.bounds.grow(0.005)
	var alternative: Dictionary = Placement.find_placement(target, _head(), [touch])
	_check(not alternative.visible or alternative.candidate_index != clear.candidate_index, "Intersecting full card rejects an otherwise preferred center")
	var only: Dictionary = Placement.find_placement(target, _head(), [touch], {"candidate_offsets": [Placement.DEFAULT_OFFSETS[clear.candidate_index]]})
	_check(not only.visible, "Card corner collision cannot pass a center-point check")

func _test_volume_occlusion() -> void:
	var eye := Vector3.ZERO
	var face: Array[Vector3] = [Vector3(-0.12,-0.05,-1),Vector3(0.12,-0.05,-1),Vector3(0.12,0.05,-1),Vector3(-0.12,0.05,-1)]
	_check(Placement._pyramid_intersects(eye, face, AABB(Vector3(0.022,0.011,-0.52),Vector3(0.002,0.002,0.004))), "Tiny interior occluder between sample rays is rejected by whole-volume visibility")
	_check(not Placement._pyramid_intersects(eye, face, AABB(Vector3(0.15,0.1,-0.52),Vector3.ONE*0.01)), "Obstacle outside the viewing pyramid is clear")
	_check(not Placement._pyramid_intersects(eye, face, AABB(Vector3(-0.01,-0.01,-1.5),Vector3.ONE*0.02)), "Geometry behind the callout cannot occlude it")
	_check(Placement._pyramid_intersects(eye, face, AABB(Vector3(-0.005,-0.005,-0.005),Vector3.ONE*0.01)), "Viewer inside opaque geometry fails visibility")
	var target := Transform3D(Basis.IDENTITY, Vector3(0,1.1,-1))
	var option: Dictionary = {"candidate_offsets": [Vector3(0.22,0,0.10)], "eye_half_separation": 0.0}
	var initial: Dictionary = Placement.find_placement(target, _head(), [], option)
	_check(initial.visible, "Fixed candidate clear before foreground occluder")
	if not initial.visible: return
	var corners: Array[Vector3] = Placement._face_corners(initial.transform, Placement.DEFAULT_SIZE)
	var interior: Vector3 = corners[0].lerp(corners[1], 0.31).lerp(corners[3].lerp(corners[2], 0.31), 0.63)
	var blocker := AABB(_head().origin.lerp(interior,0.45)-Vector3.ONE*0.001,Vector3.ONE*0.002)
	_check(not initial.bounds.intersects(blocker), "Regression occluder is separate from callout physical bounds")
	_check(not Placement.find_placement(target, _head(), [blocker], option).visible, "A separate foreground obstruction hides the whole callout")
	var glass_option: Dictionary = option.duplicate(true)
	glass_option.occluders = []
	_check(Placement.find_placement(target, _head(), [blocker], glass_option).visible, "Transparent foreground geometry need not obscure a nonintersecting prompt")
	_check(not Placement.find_placement(target, _head(), [initial.bounds], glass_option).visible, "Transparent geometry still forbids physical interpenetration")
	# Eye-separated finite pyramids are tested independently, never just a
	# center-eye ray. This off-axis point lies inside the left-eye silhouette.
	var left_eye: Vector3 = _head().origin - Vector3.RIGHT*0.04
	var edge: Vector3 = corners[0].lerp(corners[3],0.5)
	var stereo_point: Vector3 = left_eye.lerp(edge,0.2) + initial.transform.basis.x * 0.0004
	var stereo_box := AABB(stereo_point-Vector3.ONE*0.0001,Vector3.ONE*0.0002)
	_check(Placement._pyramid_intersects(left_eye,corners,stereo_box), "Stereo regression touches the left-eye card silhouette")
	_check(not Placement._pyramid_intersects(_head().origin,corners,stereo_box), "Stereo regression misses the center-eye silhouette")
	var stereo_option: Dictionary = option.duplicate(true)
	stereo_option.eye_half_separation = 0.04
	_check(not Placement.find_placement(target,_head(),[stereo_box],stereo_option).visible, "Occlusion of either eye hides the visual")

func _test_construction_bounds() -> void:
	var branch := Node3D.new()
	root.add_child(branch)
	branch.position = Vector3(0.3,0.2,-0.4)
	branch.rotation.y = 0.4
	var box := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.2,0.1,0.3)
	box.mesh = mesh
	box.position = Vector3(0.4,1.0,-0.7)
	branch.add_child(box)
	var before: Dictionary = Placement.collect_world_aabbs(branch)
	_check(before.complete and before.bounds.size() == 1 and before.bounds[0] == box.global_transform*mesh.get_aabb(), "Mesh construction bounds use CPU mesh data and full world transform")
	var transparent := StandardMaterial3D.new()
	transparent.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	transparent.albedo_color.a = 0.1
	box.material_override = transparent
	_check(Placement.collect_world_aabbs(branch).bounds.size() == 1 and Placement.collect_world_aabbs(branch,[],true).bounds.is_empty(), "Transparent glass remains physical but is omitted from opaque sightline geometry")
	transparent.albedo_color.a = 1.0
	_check(Placement.collect_world_aabbs(branch,[],true).bounds.size() == 1, "Alpha render mode with full opacity still blocks visibility")
	transparent.albedo_color.a = 0.1
	box.visible = false
	_check(Placement.collect_world_aabbs(branch).bounds.is_empty(), "Hidden geometry cannot supply obsolete bounds")
	box.visible = true
	_check(Placement.collect_world_aabbs(branch,[box]).bounds.is_empty(), "Explicit callout/menu exclusion does not recurse into excluded targets")
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = 2
	var transforms: Array[Transform3D] = [Transform3D(Basis.IDENTITY,Vector3(-0.8,1,-1)),Transform3D(Basis(Vector3.UP,0.7).scaled(Vector3(1,2,0.5)),Vector3(0.9,1.4,-1.5))]
	for instance_index in range(2): multi.set_instance_transform(instance_index,transforms[instance_index])
	var batch := MultiMeshInstance3D.new()
	batch.multimesh = multi
	batch.set_meta("callout_instance_transforms",transforms)
	branch.add_child(batch)
	var collected: Dictionary = Placement.collect_world_aabbs(branch,[box])
	_check(collected.complete and collected.bounds.size() == 2, "All MultiMesh instances use cached CPU construction transforms headlessly")
	for instance_index in range(2):
		_check(collected.bounds[instance_index] == batch.global_transform*transforms[instance_index]*mesh.get_aabb(), "MultiMesh scaled/rotated instance has correct world bound")
	multi.visible_instance_count = 1
	_check(Placement.collect_world_aabbs(branch,[box]).bounds.size() == 1, "Hidden MultiMesh instances do not block callouts")
	batch.remove_meta("callout_instance_transforms")
	if DisplayServer.get_name() == "headless": _check(not Placement.collect_world_aabbs(branch,[box]).complete, "Missing headless MultiMesh construction metadata is reported, never replaced with identity transforms")
	branch.free()

func _test_actual_station() -> void:
	var fixture = Fixture.new()
	root.add_child(fixture)
	# The live station is translated +0.65m toward the user. Testing the fixture
	# at identity is equivalent to translating its standing viewer by -0.65m.
	var head: Transform3D = _head(Vector3(0,1.65,-0.65))
	var available: int = 0
	var total: int = 0
	for mounted in [false,true]:
		for closed in [false,true]:
			fixture.update_state({"mounted":mounted,"guard_closed":closed,"sensor_position_mm":6.0,"rpm":0.0,"time":0.0,"masses":[],"angles":[],"mode":"single"})
			var physical: Dictionary = Placement.collect_world_aabbs(fixture)
			var opaque: Dictionary = Placement.collect_world_aabbs(fixture,[],true)
			_check(physical.complete and opaque.complete, "Actual fixture construction bounds complete for guard/rotor state")
			var targets: Array = fixture.physical_buttons.duplicate()
			targets.append(fixture.guard_handle)
			targets.append(fixture.rotor if mounted else fixture.rotor_grab)
			for target in targets:
				total += 1
				var transform: Transform3D = target.global_transform
				var bounds := AABB(transform.origin-Vector3.ONE*0.012,Vector3.ONE*0.024)
				if target is LabButton: bounds = transform*AABB(Vector3(-target.width_m*.5,-target.height_m*.5,-0.014),Vector3(target.width_m,target.height_m,.03))
				var visual: Node3D = target
				if target == fixture.rotor_grab: visual = fixture.kit_rotor
				if target == fixture.guard_handle: visual = fixture.guard.get_node("GuardHandle")
				for bound in Placement.collect_world_aabbs(visual).bounds: bounds = bounds.merge(bound)
				var result: Dictionary = Placement.find_placement(transform,head,physical.bounds,{"occluders":opaque.bounds,"target_bounds":bounds})
				if result.visible:
					available += 1
					_check(result.transform.origin.distance_to(transform.origin)<=.48,"Actual target callout remains near mechanism")
					var collisions: int = 0
					for obstacle in physical.bounds:
						if result.bounds.grow(Placement.CLEARANCE_M).intersects(obstacle): collisions += 1
					_check(collisions == 0,"Actual target full callout has no guard/bench/rotor intersection")
				else:
					print("CALLOUT_HIDDEN target=",target.name," mounted=",mounted," closed=",closed)
	_check(available == total, "All nominal fixture button/guard/rotor scenarios have safe nearby prompts (%d/%d)" % [available,total])
	print("ACTUAL_CALLOUT_AVAILABILITY ",available,"/",total)
	# Oblique/seated/standing/around-bench poses may hide a label when hardware
	# blocks its sightline. Every accepted result must still clear full bounds.
	fixture.update_state({"mounted":false,"guard_closed":false,"sensor_position_mm":6.0,"rpm":0.0,"time":0.0,"masses":[],"angles":[],"mode":"single"})
	var physical: Dictionary = Placement.collect_world_aabbs(fixture)
	var opaque: Dictionary = Placement.collect_world_aabbs(fixture,[],true)
	var accepted: int = 0
	var attempts: int = 0
	for position in [Vector3(0,1.2,-.65),Vector3(0,1.85,-.65),Vector3(-1.25,1.6,-1.4),Vector3(1.25,1.6,-1.4),Vector3(0,1.6,-2.2)]:
		for target in [fixture.physical_by_action.home,fixture.physical_by_action.baseline,fixture.physical_by_action.apply,fixture.guard_handle,fixture.rotor_grab]:
			attempts += 1
			var visual: Node3D = target
			if target == fixture.rotor_grab: visual = fixture.kit_rotor
			if target == fixture.guard_handle: visual = fixture.guard.get_node("GuardHandle")
			var bounds := AABB(target.global_position-Vector3.ONE*.01,Vector3.ONE*.02)
			for bound in Placement.collect_world_aabbs(visual).bounds: bounds = bounds.merge(bound)
			var result: Dictionary = Placement.find_placement(target.global_transform,_head(position),physical.bounds,{"occluders":opaque.bounds,"target_bounds":bounds})
			if not result.visible:
				_check(result.candidate_index == -1,"Blocked perimeter prompt hides instead of selecting an unchecked fallback")
				continue
			accepted += 1
			var safe: bool = true
			for obstacle in physical.bounds:
				if result.bounds.grow(Placement.CLEARANCE_M).intersects(obstacle): safe = false
			_check(safe,"Every visible seated/standing/perimeter prompt clears complete fixture bounds")
			_check(result.transform.origin.distance_to(target.global_position)<=.48,"Perimeter prompt remains target-adjacent")
			_check(result.transform.basis.z.dot((position-result.transform.origin).normalized())>.99,"Perimeter prompt facing uses actual tracked viewer")
	print("PERIMETER_CALLOUT_VISIBLE ",accepted,"/",attempts)
	fixture.free()

func _test_cached_capture() -> void:
	var fixture = Fixture.new()
	root.add_child(fixture)
	fixture.update_state({"mounted":false,"guard_closed":false,"sensor_position_mm":6.0,"rpm":0.0,"time":0.0,"masses":[],"angles":[],"mode":"single"})
	var capture: Dictionary = Placement.capture_geometry(fixture)
	_check(capture.complete and not capture.entries.is_empty(),"Static capture records all construction descriptors once")
	var count: int = capture.entries.size()
	for mounted in [false,true]:
		for closed in [false,true]:
			fixture.position = Vector3(0.12,0.18,0.65)
			fixture.rotation.y = 0.17
			fixture.update_state({"mounted":mounted,"guard_closed":closed,"sensor_position_mm":7.1,"rpm":500.0,"time":2.7,"masses":[.3,0],"angles":[45,0],"mode":"two_plane"})
			var live: Dictionary = Placement.world_aabbs_from_capture(capture)
			var oracle: Dictionary = Placement.collect_world_aabbs(fixture)
			var opaque: Dictionary = Placement.collect_world_aabbs(fixture,[],true)
			_check(live.complete and live.bounds == oracle.bounds,"Cached local descriptors track live station/guard/probe/rotor transforms exactly")
			_check(live.opaque_bounds == opaque.bounds,"One world pass matches independent opaque collection")
			_check(capture.entries.size() == count,"World updates never mutate static captured descriptors")
	# A carried rotor's arbitrary grip transform must propagate immediately;
	# hiding it later must remove all of its child bounds without recapturing.
	fixture.kit_rotor.visible = true
	fixture.kit_rotor.global_transform = Transform3D(Basis(Vector3.RIGHT,.47),Vector3(.4,1.5,-.3))
	var carried: Dictionary = Placement.world_aabbs_from_capture(capture)
	_check(carried.bounds == Placement.collect_world_aabbs(fixture).bounds,"Held rotor wrist rotation/translation uses current global transforms")
	fixture.kit_rotor.visible = false
	var hidden: Dictionary = Placement.world_aabbs_from_capture(capture)
	_check(hidden.bounds.size() < carried.bounds.size() and hidden.bounds == Placement.collect_world_aabbs(fixture).bounds,"Node visibility changes take effect without stale captured bounds")
	var batch: MultiMeshInstance3D = fixture.guard.get_node("GuardExtrusions")
	batch.multimesh.visible_instance_count = 2
	var few: Dictionary = Placement.world_aabbs_from_capture(capture)
	_check(few.bounds == Placement.collect_world_aabbs(fixture).bounds,"MultiMesh visible instance count remains live after capture")
	var original_count: int = batch.multimesh.instance_count
	batch.multimesh.instance_count = original_count+1
	_check(not Placement.world_aabbs_from_capture(capture).complete,"Changed MultiMesh construction fails closed and requests recapture")
	fixture.free()

func _test_application_views() -> void:
	var app = QuietApplication.new()
	app.tutorial_settings_path = ""
	app.narration_settings_path = ""
	app.narration_enabled = false
	root.add_child(app)
	app.set_process(false)
	app.set_process_unhandled_input(false)
	_check(app.guide_placement.visible,"Actual application desktop startup clears foreground guard and analyzer")
	var poses: Array[Vector3] = [Vector3(.3,1.7,.2)]
	for eye in [1.2,1.6,1.75]:
		for z in [0.0,0.2]: poses.append(Vector3(0,eye,z))
	for position in poses:
		app.camera.global_transform = Transform3D(Basis.IDENTITY,position)
		app._refresh_tutorial()
		_check(app.guide_placement.visible,"Actual app rotor silhouette stays clear for seated/standing/offset head %s" % position)
		if not app.guide_placement.visible: continue
		var safe: bool = true
		for bound in app._guide_obstacles().bounds:
			if app.guide_placement.bounds.grow(Placement.CLEARANCE_M).intersects(bound): safe = false
		_check(safe,"Actual app full prompt clears monitor/dials/guard/rotor geometry")
		_check(app.guide_placement.transform.origin.distance_to(app.geometry.rotor_grab.global_position)<=.48,"Actual app prompt remains adjacent despite changing head pose")
	app.free()
