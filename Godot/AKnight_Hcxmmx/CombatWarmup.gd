extends Node

# Menu preparation stays outside the encounter attachment call.
var preparing:=false
var basics_ready:=false
var controller
var warm_view: SubViewport

func _ready():
	add_to_group("aknight_combat_warmup")
	request()

func _process(_delta):
	if is_instance_valid(warm_view):
		warm_view.render_target_update_mode=SubViewport.UPDATE_ALWAYS if get_tree().get_nodes_in_group("aknight_battles").is_empty() else SubViewport.UPDATE_DISABLED

func _idle():
	while not get_tree().get_nodes_in_group("aknight_battles").is_empty() or _archive_preparing():
		await get_tree().create_timer(.2).timeout

func _archive_preparing() -> bool:
	var warmer=get_tree().get_first_node_in_group("aknight_archive_warmup")
	return warmer!=null and warmer.preparing

func _script(path: String):
	var error:=ResourceLoader.load_threaded_request(path)
	if error!=OK:return load(path)
	while ResourceLoader.load_threaded_get_status(path)==ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await get_tree().process_frame
	if ResourceLoader.load_threaded_get_status(path)!=ResourceLoader.THREAD_LOAD_LOADED:return null
	return ResourceLoader.load_threaded_get(path)

func request():
	if preparing or is_instance_valid(controller):return
	preparing=true
	get_tree().create_timer(1.0).timeout.connect(_begin)

func _begin():
	if not get_tree().get_nodes_in_group("aknight_battles").is_empty() or _archive_preparing():
		get_tree().create_timer(.2).timeout.connect(_begin)
		return
	var ultimate_script=await _script("res://AKnight_Hcxmmx/Ultimate.gd")
	if ultimate_script==null:preparing=false;return
	warm_view=SubViewport.new();warm_view.size=Vector2i(get_viewport().get_visible_rect().size)
	warm_view.transparent_bg=true;warm_view.disable_3d=true
	warm_view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(warm_view)
	if not basics_ready:
		await _basics()
		basics_ready=true
	await _idle()
	controller=ultimate_script.new();controller.progressive_loading=true;warm_view.add_child(controller)
	while not controller.prepared:await get_tree().process_frame
	# Exercise the same materials and render targets before entering a room.
	controller.active=true;controller.visible=true;controller.fx.visible=true
	for at in [.8,6.17,8.3]:
		await _idle()
		controller.seek(at)
		await RenderingServer.frame_post_draw
		await get_tree().process_frame
	controller.cancel();controller.live_actor=null
	controller.reparent(self,false)
	warm_view.queue_free();warm_view=null;preparing=false
	print("[AKnightSkin] Combat warmup ready (offscreen, start frames and standby ultimate).")

func _basics():
	var actor_script=load("res://AKnight_Hcxmmx/Actor.gd")
	var texture_path="res://AKnight_Hcxmmx/Assets/battle/300702_weixiukai.png"
	ResourceLoader.load_threaded_request(texture_path)
	while ResourceLoader.load_threaded_get_status(texture_path)==ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await get_tree().process_frame
	var warmed_texture: Texture2D
	if ResourceLoader.load_threaded_get_status(texture_path)==ResourceLoader.THREAD_LOAD_LOADED:
		warmed_texture=ResourceLoader.load_threaded_get(texture_path)
	var actor=actor_script.new();warm_view.add_child(actor);actor.initialize("battle");actor.visible=false
	var effects=load("res://AKnight_Hcxmmx/Runtime/effect_player.gd")
	var followup=load("res://AKnight_Hcxmmx/Runtime/followup_player.gd")
	var glow_script=load("res://AKnight_Hcxmmx/Runtime/EffectGlow.gd")
	var panel=Control.new();warm_view.add_child(panel)
	for kind in ["entry","ready","skill1","skill2","ability"]:
		await _idle()
		var player=(followup if kind in ["skill2","ability"] else effects).new()
		warm_view.add_child(player)
		if kind in ["skill2","ability"]:await player.initialize(kind,true)
		else:await player.initialize("res://AKnight_Hcxmmx/Runtime/assets/fx/"+("common/"+kind+"/" if kind!="skill1" else ""),true)
		if kind in ["entry","ready","skill1"]:await player.prepare_clip()
		player.position=Vector2(720,660);player.scale=Vector2.ONE*75
		var light=glow_script.new();warm_view.add_child(light);light.initialize(panel);light.prepare(player)
		var times: Array={"entry":[0.0],"ready":[0.0],"skill1":[0.0,1.05,1.1666667,1.37,1.4833333,2.0,2.1,2.5],"skill2":[0.0,.2,1.05,1.25,1.85],"ability":[2.65]}[kind]
		for at in times:
			await _idle()
			player.prepare_frames([at]);player.show_time(at,true);light.sync(player,true)
			await RenderingServer.frame_post_draw
			await get_tree().process_frame
		light.sync(player,false);player.free();light.overlay.free();light.free()
	panel.free();actor.free()
	var audio=load("res://AKnight_Hcxmmx/CombatAudio.gd").new();add_child(audio)
	await audio.prepare(true)
	audio.free()

func take(host: Node):
	if preparing or not is_instance_valid(controller) or not controller.prepared:return null
	var value=controller;controller=null
	value.reparent(host,false);value._attach_background()
	# Next standby is prepared between encounters; the active room owns this one.
	request()
	return value
