extends Node

const PORTRAIT="res://AKnight_Hcxmmx/Archive/Portrait.tscn"
var cover
var warm_view: SubViewport
var retained: Array=[]
var preparing:=false
var generation:=0
var start_delay:=.75
var watched: Dictionary={}

func _ready():
	add_to_group("aknight_archive_warmup")
	request()

func request():
	if not is_inside_tree() or preparing or is_instance_valid(cover):return
	preparing=true;generation+=1
	var ticket=generation
	# Owned timer disappears with this service; no suspended SceneTreeTimer
	# remains alive when the game exits during the initial menu delay.
	var timer=Timer.new();timer.one_shot=true;timer.wait_time=maxf(.001,start_delay);add_child(timer)
	timer.timeout.connect(func():timer.queue_free();_prepare(ticket),CONNECT_ONE_SHOT)
	timer.start()

func _valid(ticket: int) -> bool:
	return is_inside_tree() and preparing and ticket==generation

func _blocked() -> bool:
	if not get_tree().get_nodes_in_group("aknight_battles").is_empty():return true
	for view in get_tree().get_nodes_in_group("aknight_archive_portraits"):
		if view.get_viewport()!=warm_view and view.active:return true
	return false

func _idle(ticket: int) -> bool:
	while _valid(ticket) and _blocked():
		if is_instance_valid(warm_view):warm_view.render_target_update_mode=SubViewport.UPDATE_DISABLED
		if is_instance_valid(cover):cover.process_mode=Node.PROCESS_MODE_DISABLED
		await get_tree().process_frame
	if not _valid(ticket):return false
	if is_instance_valid(warm_view):warm_view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	if is_instance_valid(cover):cover.process_mode=Node.PROCESS_MODE_INHERIT
	return true

func _draw(ticket: int) -> bool:
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	return _valid(ticket)

func _prepare(ticket: int):
	if not await _idle(ticket):return
	# Most cover images/fonts are referenced dynamically rather than by PackedScene.
	var paths: Array[String]=[]
	_collect("res://AKnight_Hcxmmx/Archive",paths)
	paths.append("res://AKnight_Hcxmmx/Assets/portrait/300702_weixiukai_p.png")
	paths.append(PORTRAIT)
	for path in paths:
		if not await _idle(ticket):return
		var error=ResourceLoader.load_threaded_request(path)
		if error!=OK:continue
		while ResourceLoader.load_threaded_get_status(path)==ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			await get_tree().process_frame
			if not _valid(ticket):return
		if ResourceLoader.load_threaded_get_status(path)==ResourceLoader.THREAD_LOAD_LOADED:
			retained.append(ResourceLoader.load_threaded_get(path))
		await get_tree().process_frame
		if not _valid(ticket):return
	if not await _idle(ticket):return
	warm_view=SubViewport.new();warm_view.size=Vector2i(1920,1080)
	warm_view.disable_3d=true;warm_view.transparent_bg=true
	warm_view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(warm_view)
	cover=load(PORTRAIT).instantiate();warm_view.add_child(cover)
	if not cover.is_ready():_discard();preparing=false;return
	cover.prepare_pages();cover._layout()
	# Do not activate the cover: automatic greeting and native UI stay untouched.
	for page in 5:
		if not await _idle(ticket):return
		cover._select_page(page)
		if not await _draw(ticket):return
	for row in cover.voice.catalog.values():
		if not await _idle(ticket):return
		var path: String=row.audio.file
		if not cover.voice.streams.has(path):cover.voice.streams[path]=AudioStreamWAV.load_from_file(path, {})
		await get_tree().process_frame
		if not _valid(ticket):return
	if not await _idle(ticket):return
	cover._select_page(1);cover._select_voice_scope("combat")
	if not await _draw(ticket):return
	cover._select_voice_scope("home")
	cover.subtitle.warming=true;var english_only: bool=cover.subtitle.english_only
	cover.subtitle.english_only=false
	for row in cover.voice.catalog.values():
		if not await _idle(ticket):return
		cover.subtitle._show_subtitles(str(row.text),str(row.text_zh))
		if not await _draw(ticket):return
	cover.subtitle.english_only=english_only;cover.subtitle.warming=false;cover.subtitle.visible=false
	cover._select_page(0);cover.actor.portrait_idle(0);cover.set_active(false)
	warm_view.render_target_update_mode=SubViewport.UPDATE_DISABLED
	retained.clear();preparing=false
	print("[AKnightSkin] Archive warmup ready (five pages, portrait, voices, subtitle glyphs).")

func acquire():
	# An early click takes the existing synchronous path without waiting on us.
	if preparing:
		generation+=1;preparing=false;_discard();return null
	if not is_instance_valid(cover):return null
	var result=cover;cover=null
	# Voice normally clears decoded audio on exit; preserve it for this one transfer.
	result.voice.retain_on_exit=true;warm_view.remove_child(result)
	result.voice.retain_on_exit=false;result.exiting_tree=false
	result.process_mode=Node.PROCESS_MODE_INHERIT;result.reload_settings()
	warm_view.queue_free();warm_view=null
	return result

func watch(view: Node):
	var id=view.get_instance_id()
	if watched.has(id):return
	watched[id]=true
	view.tree_exited.connect(func():watched.erase(id);request.call_deferred(),CONNECT_ONE_SHOT)

func _discard():
	if is_instance_valid(warm_view):
		warm_view.render_target_update_mode=SubViewport.UPDATE_DISABLED;warm_view.queue_free()
	warm_view=null;cover=null;retained.clear()

func _exit_tree():
	generation+=1;preparing=false
	if is_instance_valid(warm_view):warm_view.render_target_update_mode=SubViewport.UPDATE_DISABLED
	retained.clear()

func _collect(directory: String,paths: Array[String]):
	for child in DirAccess.get_directories_at(directory):_collect(directory.path_join(child),paths)
	for file in DirAccess.get_files_at(directory):
		if file.get_extension() in ["png","ttf","otf"]:paths.append(directory.path_join(file))
