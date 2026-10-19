extends SceneTree
## Real application acquisitions plus independent chart geometry/data contracts.
const Data = preload("res://scripts/analyzer_view.gd")
const Chart = preload("res://scripts/panel_chart.gd")

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
	if not condition:failures+=1;push_error("ANALYZER: "+caption)

func _view(kind: String, acquisition: Dictionary = {}) -> Dictionary:
	return Data.build(kind,app.model.waveform,app.model.spectrum,app.model.sweep_points,app.model.records,acquisition)

func _settle() -> void:
	for index in range(2000):
		app._process(0.05)
		if not app.model.running and not app.model.processing and app.model.rpm<0.1:break
	_check(not app.model.running and not app.model.processing and app.model.rpm<0.1,"Acquisition and coast-down complete")
	app._update_ui()

func _run() -> void:
	app=SilentApp.new();root.add_child(app);app.set_process(false);app.set_process_unhandled_input(false);app.model.async_processing=false
	_check(app.chart_kind=="time","New user sees waveform, not empty sweep")
	_check(app.chart.view.points.is_empty(),"Fresh station has no invented samples")
	_check(app.chart._empty_label.visible and "BASELINE" in app.chart._empty_label.text,"Empty analyzer explains acquisition action")
	_check(app.chart.trace_vertices.is_empty(),"Empty analyzer supplies no fake geometry")
	app._action("mount");app._action("home");app._action("guard");app._action("baseline")
	_check(app.chart_kind=="time","Baseline automatically selects waveform")
	_check("Measuring" in app.chart._empty_label.text,"Acquisition wait is explicit before samples exist")
	_settle()
	_check("captured" in app.status,"Actual application clock replaces stale acquisition-start status after capture")
	var time_view: Dictionary = _view("time")
	_check(time_view.points.size()==256,"Actual baseline supplies retained 256 sensor samples")
	_check(is_equal_approx(time_view.x_min,0.75) and is_equal_approx(time_view.x_max,1.0),"Waveform preserves real captured time interval .750–1.000 s")
	_check(is_equal_approx(time_view.points[0].y,app.model.waveform[0].a),"Waveform uses actual sensor sample amplitude")
	_check(time_view.y_min<0 and time_view.y_max>0,"Raw waveform signed displacement domain")
	_check("BASELINE #1" in time_view.footer and "1200 RPM" in time_view.footer,"Trace identifies real capture and speed")
	_check(not app.chart.trace_vertices.is_empty(),"Baseline reaches rendered application trace geometry")
	_check(app.chart.line_mesh.mesh is ArrayMesh and app.chart.line_mesh.mesh.surface_get_primitive_type(0)==Mesh.PRIMITIVE_TRIANGLES,"Application renders thick triangles, not fragile one-pixel lines")
	await _capture("analyzer-time.png")
	app._action("chart")
	_check(app.chart_kind=="order" and app.chart.view.kind=="order","Physical chart action reaches order view")
	var order_view: Dictionary = _view("order")
	var at_one: Array = order_view.points.filter(func(point):return is_equal_approx(point.x,1.0))
	_check(at_one.size()==1,"20Hz captured at1200RPM maps to exactly1×")
	_check(at_one.size()==1 and absf(at_one[0].y-app.model.baseline.amplitude_um)<0.01,"Integer-bin order amplitude agrees with least-squares baseline within noise")
	_check(order_view.x_min==0 and order_view.x_max==5 and order_view.x_ticks[1].label=="1×","Order domain and tick labels are shaft multiples")
	_check(order_view.title.contains("PEAK [µm]") and "ORDER" in order_view.x_unit,"Order units distinguish peak displacement from frequency")
	var before: float = at_one[0].x if not at_one.is_empty() else -1.0
	app._action("speed")
	_check(app.model.test_rpm!=1200,"Test changes current set speed independently of saved capture")
	_check(is_equal_approx(_view("order").points[20].x,before),"Saved spectrum normalization uses capture RPM, not current changed setpoint")
	await _capture("analyzer-order.png")
	app._action("chart")
	_check(app.chart_kind=="sweep" and app.chart.view.points.is_empty(),"Sweep remains honestly empty without sweep acquisition")
	_check("SWEEP" in app.chart._empty_label.text,"Unmeasured sweep tells user how to acquire it")
	app._action("sweep")
	var saw_partial := false
	for index in range(1000):
		app._process(0.05)
		if app.model.sweep_points.size()>=2:
			app._update_ui();saw_partial=app.chart.view.points.size()>=2 and not app.chart.trace_vertices.is_empty();break
	_check(saw_partial,"Sweep plots measured quasi-steady points during acquisition")
	_settle()
	var sweep_view: Dictionary = _view("sweep")
	_check(sweep_view.points.size()>=15,"Finished sweep graph contains actual acquired speed points")
	_check(sweep_view.x_max==1800 and sweep_view.x_unit=="SHAFT SPEED [RPM]","Sweep x-axis explicitly spans0–1800RPM")
	_check(sweep_view.points[0].x==app.model.sweep_points[0].rpm and sweep_view.points[0].y==app.model.sweep_points[0].amplitude_um,"Sweep preserves real measured rpm and peak displacement")
	_check("SWEEP #2" in sweep_view.footer,"Finished sweep labels its own accepted record")
	await _capture("analyzer-sweep.png")
	await _test_actual_two_plane()
	_test_ribbons()
	_test_two_channels()
	app.queue_free();await process_frame
	print("ANALYZER TESTS: %d checks, %d failures" % [checks,failures]);quit(0 if failures==0 else 1)

func _test_actual_two_plane() -> void:
	app._action("new")
	_check(app.chart_kind=="time" and app.chart.view.points.is_empty() and "BASELINE" in app.chart._empty_label.text,"NewSession resets previous sweep selection to useful empty waveform")
	app._action("mode");app._action("mount");app._action("home");app._action("guard");app._action("baseline");_settle()
	_check(app.model.mode=="two_plane" and app.chart.view.second.size()==256,"Real two-plane baseline supplies both acquired sensor traces")
	_check(app.chart._legend_a.visible and app.chart._legend_b.visible,"Two-plane legend identifies tealA and amberB")
	await _capture("analyzer-two-plane.png")
	for plane in range(2):
		app._action("guard")
		if plane==1:app._action("plane")
		app._action("fit_trial");app._action("guard");app._action("trial_a" if plane==0 else "trial_b");_settle()
		_check(app.chart_kind=="time" and app.chart.view.source_id==app.model.latest.id,"Trial measurement refreshes displayed capture identity")
	app._action("solve");app._action("guard");app._action("apply");app._action("guard");app._action("verify");_settle()
	_check(app.model.latest.get("verified",false),"Actual two-plane trial/solve/apply workflow produces verified result")
	_check("VERIFY" in app.chart.view.footer and app.chart.view.points.size()==256 and app.chart.view.second.size()==256,"Verification refreshes both displayed measured channels")
	app._action("repeat");_settle()
	_check("REPEAT" in app.chart.view.footer and app.chart.view.source_id==app.model.latest.id,"Repeatability final window updates chart and source identity")

func _test_ribbons() -> void:
	var chart=Chart.new();root.add_child(chart)
	chart.set_points([Vector2(0,0.5),Vector2(1,0.5)],0,1,0,1)
	_check(chart.trace_vertices.size()==6,"Two acquired points produce two visible triangles")
	var thickness: float = absf(chart.trace_vertices[0].y-chart.trace_vertices[1].y)
	_check(is_equal_approx(thickness,chart.trace_width_m) and thickness>=0.002,"Trace has measurable millimetre-scale thickness")
	var valid := true
	for point in chart.trace_vertices:valid=valid and point.is_finite() and point.x>=0 and point.x<=chart.width_m and point.y>=0 and point.y<=chart.height_m
	_check(valid,"CPU trace vertices stay finite inside chart viewport")
	chart.set_points([Vector2(-1,2),Vector2(2,2)],0,1,0,1)
	_check(chart.trace_vertices.is_empty(),"Entirely out-of-range data do not manufacture boundary traces")
	chart.set_points([Vector2(-1,0.5),Vector2(2,0.5)],0,1,0,1)
	_check(chart.trace_vertices.size()==6 and is_equal_approx(chart.trace_vertices[0].x,0.0) and is_equal_approx(chart.trace_vertices[2].x,chart.width_m),"Crossing data are clipped as line segments")
	chart.set_points([Vector2(NAN,0),Vector2(1,1)],0,1,0,1)
	_check(chart.trace_vertices.is_empty(),"Invalid sample coordinates cannot enter rendered mesh")
	chart.queue_free()

func _test_two_channels() -> void:
	var samples := [{"t":0.75,"a":1.0,"b":-0.5},{"t":0.751,"a":1.5,"b":-1.0}]
	var view := Data.build("time",samples,[],[],[{"id":1,"kind":"baseline","rpm":900,"accepted":true,"mode":"two_plane"}])
	_check(view.second.size()==2 and view.second[1].y==-1.0,"Two-plane waveform contains real channelB samples")
	_check("A + B" in view.title,"Two-channel plot identifies both sensors")
	var chart=Chart.new();root.add_child(chart);chart.set_view(view)
	_check(chart.line_mesh.mesh.get_surface_count()==2 and chart.trace_vertices.size()==12,"Both sensor traces reach independent colored mesh surfaces")
	_check(chart.line_mesh.mesh.surface_get_material(0).albedo_color!=chart.line_mesh.mesh.surface_get_material(1).albedo_color,"SensorA/B have distinct trace colors")
	chart.queue_free()

func _capture(filename: String) -> void:
	if capture_directory.is_empty():return
	app.tutorial_panel.visible=false
	app.camera.global_position=app.monitor.to_global(Vector3(0,0,1.8))
	app.camera.look_at(app.monitor.global_position,Vector3.UP)
	app.camera.fov=40.0
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var result: Error = image.save_png(capture_directory.path_join(filename))
	_check(result==OK,"Rendered analyzer image saves: "+filename)
