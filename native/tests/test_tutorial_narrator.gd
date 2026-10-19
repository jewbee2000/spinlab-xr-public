extends SceneTree
const Narrator = preload("res://scripts/tutorial_narrator.gd")
var checks := 0
var failures := 0
var app

func _initialize() -> void:call_deferred("_run")
func _check(value: bool, description: String) -> void:
	checks+=1
	if not value:failures+=1;push_error("NARRATOR: "+description)

func _run() -> void:
	var narrator=Narrator.new();root.add_child(narrator);narrator.configure()
	var manifest:Dictionary=narrator.manifest
	var lesson=load("res://scripts/lab_tutorial.gd").new("")
	_check(manifest.get("clips",{}).size()==lesson.steps.size(),"Every work instruction has bundled narration")
	for step in lesson.steps:
		var clip:Dictionary=manifest.get("clips",{}).get(step.id,{})
		_check(not clip.is_empty(),"Clip exists: "+step.id)
		if clip.is_empty():continue
		var stream=load(clip.path) as AudioStreamOggVorbis
		_check(stream!=null and stream.get_length()>3,"Bundled Ogg decodes and has nonzero duration: "+step.id)
		_check(absf(stream.get_length()-float(clip.duration_s))<0.05,"Decoded duration matches manifest: "+step.id)
		_check(FileAccess.get_sha256(clip.path)==clip.sha256,"Exact audio hash matches manifest: "+step.id)
		_check(not str(clip.text).is_empty() and not str(clip.instruction).is_empty() and not str(clip.science).is_empty(),"Instruction and scientific purpose are transcribed: "+step.id)
	var view={"active":true,"id":"load"}
	narrator.sync(view,true)
	_check(narrator.current_id=="load" and narrator.has_unfinished_clip() and narrator.player.playing,"Step entry begins exactly its spoken instruction")
	var stream=narrator.player.stream
	narrator.sync(view,false)
	_check(narrator.player.stream_paused and narrator.has_unfinished_clip(),"Menu/focus interruption pauses narration without marking it complete")
	narrator.sync(view,true)
	_check(not narrator.player.stream_paused and narrator.player.stream==stream,"Resume continues the same clip")
	narrator.sync({"active":true,"id":"home"},true)
	_check(narrator.current_id=="home" and narrator.player.stream!=stream,"New target replaces previous speech instead of queuing it")
	narrator.player.stop();narrator.player.finished.emit()
	_check(not narrator.has_unfinished_clip(),"Finished signal marks the current clip complete")
	narrator.replay()
	_check(narrator.has_unfinished_clip() and narrator.player.playing,"Replay restarts current step")
	narrator.set_enabled(false)
	_check(not narrator.has_unfinished_clip() and not narrator.player.playing,"Mute stops voice")
	narrator.set_enabled(true)
	_check(narrator.has_unfinished_clip(),"Enabling voice restarts current instruction deliberately")
	narrator.sync({"active":false,"id":"home"},false)
	_check(narrator.current_id.is_empty() and not narrator.player.playing and not narrator.has_unfinished_clip(),"Skipping/pausing tutorial clears speech state")
	var prefs="user://narrator-test-"+str(Time.get_ticks_usec())+".cfg"
	narrator.settings_path=prefs;narrator.set_enabled(false)
	var restored=Narrator.new();root.add_child(restored);restored.configure("res://audio/tutorial/manifest.json",prefs)
	_check(not restored.enabled,"Mute persists independently from guide startup preference")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(prefs))
	narrator.queue_free();restored.queue_free()
	# Task completion cuts off narration immediately; listeners may wait before acting.
	app=load("res://main.tscn").instantiate();app.tutorial_settings_path="";app.narration_settings_path=""
	root.add_child(app);app.set_process(false);app.model.async_processing=false
	_check(app.narrator.current_id=="load" and app.narrator.has_unfinished_clip(),"Production startup begins the conceptual introduction")
	var initial_stream=app.narrator.player.stream
	for frame in range(3):app._process(0.05)
	_check(app.tutorial.index==0,"Speech and elapsed time alone cannot satisfy rotor seating")
	app._action("mount")
	app._set_menu_open(true)
	_check(app.narrator.player.stream_paused,"B/Y menu pauses spoken instruction immediately")
	app._process(0.05)
	_check(app.tutorial.index==0,"Open menu still pauses the instruction observer")
	app._set_menu_open(false)
	_check(not app.narrator.player.stream_paused,"Closing menu resumes the current clip")
	app._process(0.05)
	_check(app.tutorial.index==1 and app.narrator.current_id=="home" and app.narrator.player.stream!=initial_stream,"Confirmed task immediately replaces speech and advances to HOME without a timer")
	_check(not app.model.homed,"Narration itself does not operate equipment")
	app._set_xr_focus(false)
	_check(app.narrator.player.stream_paused,"Focus loss pauses voice immediately")
	app._set_xr_focus(true)
	_check(not app.narrator.player.stream_paused,"Focus recovery resumes voice")
	app._tutorial_action("tutorial:skip")
	_check(not app.narrator.player.playing and not app.narrator.has_unfinished_clip(),"Production tutorial pause cancels voice")
	app._tutorial_action("tutorial:toggle")
	_check(app.narrator.current_id=="home" and app.narrator.has_unfinished_clip(),"Resuming the guide restarts its current instruction")
	app._set_menu_open(true);app._tutorial_action("tutorial:voice")
	_check(not app.narrator.enabled and not app.narrator.has_unfinished_clip(),"Real Session mute stops voice without changing work")
	app._tutorial_action("tutorial:voice");app._tutorial_action("tutorial:replay")
	_check(app.narrator.enabled and app.narrator.player.stream_paused,"Voice enable/replay in Session remains paused until menu closes")
	app._set_menu_open(false);app._tutorial_action("tutorial:skip_step")
	_check(app.tutorial.view(app._tutorial_context()).id=="probe_adjust" and app.narrator.current_id=="rehome" and app.narrator.has_unfinished_clip(),"Skipping HOME preserves the next work task while narrating its missing prerequisite")
	_check(not app.model.homed and app.geometry.physical_by_action.home.guide_highlight,"Prerequisite speech highlights real HOME without inventing a reference")
	app._tutorial_action("tutorial:restart")
	_check(app.narrator.current_id=="load" and app.narrator.has_unfinished_clip(),"Restart replaces even the same procedure's prior speech")
	app.queue_free();await process_frame;app=null
	stream=null;lesson=null
	await create_timer(0.6).timeout
	print("NARRATOR TESTS: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)

