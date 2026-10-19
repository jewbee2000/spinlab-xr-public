class_name AnalyzerView
extends RefCounted
## Read-only projection of acquired samples; empty acquisitions stay empty.

static func build(kind: String, waveform: Array, spectrum: Array, sweep: Array, records: Array, acquisition: Dictionary = {}) -> Dictionary:
	var record: Dictionary = {}
	for candidate in records:
		if candidate is Dictionary and candidate.get("accepted",false):record = candidate
	var view := {"kind":kind,"points":[],"second":[],"x_min":0.0,"x_max":1.0,"y_min":0.0,"y_max":1.0,
		"x_ticks":[],"y_ticks":[],"markers":[],"title":"","footer":"","empty_text":"","source_id":record.get("id",0)}
	var busy: bool = acquisition.get("running",false) or acquisition.get("processing",false)
	var record_rpm: float = float(record.get("rpm",0.0))
	var capture_name: String = str(record.get("kind","capture")).replace("_"," ").to_upper()
	var source: String = "%s #%d · %.0f RPM" % [capture_name,int(record.get("id",0)),record_rpm]
	var two_channel: bool = record.get("mode","single") == "two_plane"
	if kind == "time":
		view.title = "TIME / SENSOR A" + (" + B" if two_channel else "") + " [µm]"
		for index in waveform.size():
			var sample = waveform[index]
			if sample is Dictionary:
				var t: float = float(sample.get("t",float(index)/1024.0))
				var a: float = float(sample.get("a",sample.get("y",0.0)))
				if is_finite(t) and is_finite(a):view.points.append(Vector2(t,a))
				if two_channel and sample.has("b") and is_finite(float(sample.b)):view.second.append(Vector2(t,float(sample.b)))
		if not view.points.is_empty():
			# Last 256 samples of the one-second record retain actual timestamps.
			view.x_min = float(view.points[0].x)
			view.x_max = float(view.points[-1].x) + 1.0/1024.0
			view.y_max = _nice_ceiling(maxf(_peak_absolute(view.points,view.second)*1.08,0.1));view.y_min = -view.y_max
		view.x_unit = "TIME [s]"
		view.empty_text = "No captured waveform\nClose guard; press BASELINE"
	elif kind == "order":
		view.title = "ORDER / SENSOR A PEAK [µm]"
		var shaft_hz: float = record_rpm/60.0
		if shaft_hz > 0.0:
			for sample in spectrum:
				if not sample is Dictionary:continue
				var hz: float = float(sample.get("frequency_hz",sample.get("hz",0.0)))
				var amplitude: float = float(sample.get("amplitude_um",sample.get("amplitude",0.0)))
				if is_finite(hz) and is_finite(amplitude) and hz >= 0.0 and hz/shaft_hz <= 5.0:view.points.append(Vector2(hz/shaft_hz,maxf(amplitude,0.0)))
		view.x_max = 5.0
		view.y_max = _nice_ceiling(maxf(_peak_absolute(view.points,[])*1.08,0.1))
		view.x_ticks = _ticks(0.0,5.0,5,"%.0f×")
		view.markers = [{"x":1.0,"label":"1×"},{"x":2.0,"label":"2×"}]
		view.x_unit = "ORDER = FREQUENCY / SHAFT Hz"
		view.empty_text = "No captured spectrum\nAcquire BASELINE first"
	else:
		view.kind = "sweep"
		view.title = "SWEEP / SENSOR A 1× PEAK [µm]"
		for sample in sweep:
			if not sample is Dictionary:continue
			var speed: float = float(sample.get("rpm",0.0))
			var amplitude: float = float(sample.get("amplitude_um",0.0))
			if is_finite(speed) and is_finite(amplitude):view.points.append(Vector2(speed,maxf(amplitude,0.0)))
		view.x_max = 1800.0
		view.y_max = _nice_ceiling(maxf(_peak_absolute(view.points,[])*1.08,0.1))
		view.x_ticks = _ticks(0.0,1800.0,3,"%.0f")
		view.x_unit = "SHAFT SPEED [RPM]"
		view.empty_text = "No speed sweep yet\nPress SWEEP to scan speed"
		if not sweep.is_empty():
			source = "SWEEP · %d ACQUIRED POINTS" % sweep.size()
			if record.get("kind","") == "sweep":source = "SWEEP #%d · %d POINTS" % [int(record.id),sweep.size()]
	if view.x_ticks.is_empty():view.x_ticks = _ticks(view.x_min,view.x_max,4,"%.3f")
	view.y_ticks = _ticks(view.y_min,view.y_max,4,"%.1f")
	if view.points.is_empty():
		view.footer = "AWAITING ACQUISITION"
		if busy:
			view.empty_text = "Analyzing captured samples…" if acquisition.get("processing",false) else "Measuring %s…\nTrace appears after analysis" % str(acquisition.get("run_kind","rotor")).replace("_"," ")
			view.footer = "ACQUISITION IN PROGRESS"
	else:
		view.empty_text = "" if view.points.size() >= 2 else "First point acquired…"
		view.footer = source + (" · NEW RUN…" if busy else " · CAPTURED")
	if acquisition.get("estop",false) or not str(acquisition.get("fault","")).is_empty():view.footer += " · STOPPED"
	return view

static func _peak_absolute(first: Array, second: Array) -> float:
	var result := 0.0
	for points in [first,second]:
		for point in points:result = maxf(result,absf(point.y))
	return result

static func _nice_ceiling(value: float) -> float:
	var exponent: float = pow(10.0,floor(log(maxf(value,0.0001))/log(10.0)))
	for scale in [1.0,2.0,5.0,10.0]:
		if value <= scale*exponent:return scale*exponent
	return value

static func _ticks(low: float, high: float, count: int, pattern: String) -> Array:
	var result: Array = []
	for index in range(count+1):
		var value: float = lerpf(low,high,float(index)/count)
		result.append({"value":value,"label":pattern % value})
	return result
