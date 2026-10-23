extends Node2D

const Tempo=preload("res://AKnight_Hcxmmx/FullTempo.gd")
const Actor=preload("res://AKnight_Hcxmmx/Actor.gd")
const Effects=preload("res://AKnight_Hcxmmx/Runtime/followup_player.gd")
const Camera=preload("res://AKnight_Hcxmmx/Runtime/UltimateCamera.gd")
const Glow=preload("res://AKnight_Hcxmmx/Runtime/EffectGlow.gd")
const SOURCE_STAGE=Rect2(28,194,1384,548)
const DURATION=13.794
var active:=false
var elapsed:=0.0
var live_actor
var actor
var fx
var mapping: Node2D
var world: Node2D
var clip: Control
var screen_root: Control
var glow
var slices: ColorRect
var post: ColorRect
var flicker: ColorRect
var back_root: Node2D
var rig=Camera.new()
var stage_rect:=Rect2()
var start_transform:=Transform2D.IDENTITY
var mirrored:=false
var prepared:=false
var progressive_loading:=false
var background_orders: Dictionary={}
var presentation:="full"
var glow_strength:=.35

func _ready():
	screen_root=Control.new();screen_root.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(screen_root)
	clip=Control.new();clip.clip_contents=false;clip.mouse_filter=Control.MOUSE_FILTER_IGNORE;screen_root.add_child(clip)
	mapping=Node2D.new();clip.add_child(mapping);world=Node2D.new();mapping.add_child(world)
	# Back-facing FX use local z=-1. Keep their effective z at zero, after
	# the native background host; otherwise its opaque scenery covers them.
	# Actor/front FX and glow remain at z=1, before the screen-copy passes.
	world.z_index=1
	actor=Actor.new();world.add_child(actor)
	var initialized=actor.initialize("battle")
	if not initialized:return
	actor.manual_sampling=true
	fx=Effects.new();world.add_child(fx)
	await fx.initialize("unique",progressive_loading)
	fx.visible_kinds.cast=false
	fx.position=Vector2(720,660);fx.scale=Vector2.ONE*75
	fx.set_approximate_tail(true)
	for i in fx.nodes.size():background_orders[i]=fx.nodes[i].z_index
	_attach_background()
	for node in fx.nodes:
		if node.get_parent()==fx:node.z_index=-1 if node.z_index<0 else 0
	for node in fx.tail_nodes.values():node.z_index=0
	glow=Glow.new();add_child(glow);glow.initialize(clip);glow.screen_space_capture=true;glow.overlay.z_index=1;glow.prepare(fx)
	# Each screen-reading pass owns its snapshot; native hit FX also copy the screen.
	var input_copy:=BackBufferCopy.new();input_copy.copy_mode=BackBufferCopy.COPY_MODE_VIEWPORT;input_copy.z_index=2;clip.add_child(input_copy)
	slices=_post_rect("res://AKnight_Hcxmmx/Runtime/FullScreenSlices.gdshader",2)
	slices.material.set_shader_parameter("glass_field",fx.field_viewport.get_texture())
	slices.material.set_shader_parameter("displacement_pixels",40.0)
	var copy:=BackBufferCopy.new();copy.copy_mode=BackBufferCopy.COPY_MODE_VIEWPORT;copy.z_index=3;clip.add_child(copy)
	post=_post_rect("res://AKnight_Hcxmmx/Runtime/ultimate_post.gdshader",4)
	post.material.set_shader_parameter("bloom_enabled",false)
	copy=BackBufferCopy.new();copy.copy_mode=BackBufferCopy.COPY_MODE_VIEWPORT;copy.z_index=5;clip.add_child(copy)
	flicker=_post_rect("res://AKnight_Hcxmmx/Runtime/ultimate_flicker.gdshader",6)
	fx.start_budget=12*1024*1024
	fx.prepare_frames([0.0,6.1,8.17])
	prepared=true;visible=false;fx.visible=false
	fx.highlight_viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	fx.field_viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED

func _post_rect(path: String,z: int) -> ColorRect:
	var rect:=ColorRect.new();rect.mouse_filter=Control.MOUSE_FILTER_IGNORE;rect.z_index=z
	var material:=ShaderMaterial.new();material.shader=load(path);rect.material=material;clip.add_child(rect);return rect

func _attach_background():
	var ancestor: Node=get_parent()
	while ancestor!=null:
		var host=ancestor.get_node_or_null("BackCombatVfxContainer")
		if host==null:host=ancestor.get_node_or_null("CombatSceneContainer/BackCombatVfxContainer")
		if host is CanvasItem:
			back_root=Node2D.new();back_root.name="AKnightUltimateBackground_"+str(get_instance_id());host.add_child(back_root)
			var ids: Array=[]
			for i in fx.nodes.size():
				if str(fx.meta.groups[i].source_resource).ends_with("_bg") and fx.nodes[i].get_parent()==fx:ids.append(i)
			ids.sort_custom(func(a,b):return background_orders[a]<background_orders[b] if background_orders[a]!=background_orders[b] else a<b)
			for id in ids:fx.nodes[id].reparent(back_root,false);fx.nodes[id].z_index=0
			back_root.visible=false;return
		ancestor=ancestor.get_parent()

func _layout():
	var size_value=get_viewport().get_visible_rect().size
	global_transform=get_viewport().get_canvas_transform().affine_inverse()
	stage_rect=Rect2(size_value*Vector2(.02,.10),size_value*Vector2(.96,.66))
	clip.position=stage_rect.position;clip.size=stage_rect.size
	mapping.scale=stage_rect.size/SOURCE_STAGE.size;mapping.position=-SOURCE_STAGE.position*mapping.scale
	for rect in [slices,post,flicker,glow.overlay]:rect.position=-stage_rect.position;rect.size=size_value
	var normalized=Vector4(0,0,1,1)
	for rect in [slices,post]:rect.material.set_shader_parameter("stage_rect",normalized)
	fx.field_viewport.size=Vector2i(size_value);fx.field_viewport.canvas_transform=Transform2D.IDENTITY
	glow.capture.canvas_transform=Transform2D.IDENTITY.scaled(Vector2(.5,.5))
	for vp in [glow.capture,glow.blur_h,glow.blur_v]:vp.size=Vector2i(size_value*.5)
	for vp in [glow.blur_h,glow.blur_v]:vp.get_child(0).size=size_value*.5

func _return_transform(source: Vector3,eye: Vector3) -> Transform2D:
	var desired: Vector2=live_actor.get_global_transform_with_canvas().origin
	var source_position: Vector2=rig.project(source,eye)
	var ratio: float=live_actor.get_global_transform_with_canvas().y.length()/(.01*rig.pixels_per_unit(source,eye)*mapping.scale.y)
	var origin=(desired-stage_rect.position-mapping.position)/mapping.scale-source_position*ratio
	return Transform2D(0,Vector2.ONE*ratio,0,origin)

func start(value,style:="full"):
	if not prepared:return
	presentation=style
	live_actor=value;elapsed=0;active=true;visible=true;fx.visible=true
	mirrored=live_actor.get_global_transform_with_canvas().x.x>0
	_layout()
	var camera: Dictionary=rig.sample(0)
	start_transform=_return_transform(Vector3(3.5,0,-2.98),camera.eye)
	live_actor.visible=false;seek(source_time(0))

func source_time(wall: float) -> float:
	if presentation=="first":return 6.1+wall
	if presentation=="second":return 8.17+minf(wall,.98)+maxf(0,wall-.98)*2.2
	return Tempo.sample("unique",wall)

func duration() -> float:
	if presentation=="first":return .85
	if presentation=="second":return .98+(12.7-9.15)/2.2
	return Tempo.duration("unique")

func tick(delta: float):
	if not active:return
	elapsed+=delta;seek(source_time(elapsed))
	if elapsed>=duration():cancel()

func seek(t: float):
	if not prepared:return
	var opacity=1.0
	if presentation=="first":opacity=smoothstep(6.1,6.18,t)*(1-smoothstep(6.83,6.95,t))
	fx.modulate.a=opacity
	_layout()
	var camera: Dictionary=rig.sample(t)
	var source:=Vector3(3.5,0,-2.98) if t<10.2 else Vector3(6,0,0)
	world.transform=start_transform.interpolate_with(Transform2D.IDENTITY,smoothstep(.15,1.2,t))
	if t>=10.2:world.transform=Transform2D.IDENTITY.interpolate_with(_return_transform(source,camera.eye),smoothstep(10.2,11.4,t))
	actor.visible=t<11.4
	actor.sample("unique",t) if t<11.4 else actor.sample("idle",t-11.4)
	# A reflected global transform may decompose into PI rotation + negative Y.
	# Replace the full basis so a return pose cannot turn the next X flip into Y.
	var pixel_scale: float=.01*rig.pixels_per_unit(source,camera.eye)
	actor.transform=Transform2D(Vector2((1 if mirrored else -1)*pixel_scale,0),Vector2(0,pixel_scale),rig.project(source,camera.eye))
	actor.modulate.a=(clampf((t-.3)/.2,0,1) if t<.5 else 1.0)*opacity
	if is_instance_valid(live_actor):live_actor.visible=t>=11.4
	fx.set_projection(true,camera.eye);fx.show_time(t,true)
	fx.field_root.transform=fx.get_global_transform_with_canvas()
	fx.field_viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	fx.highlight_viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	if is_instance_valid(back_root):
		back_root.global_transform=get_viewport().get_canvas_transform().affine_inverse()*fx.get_global_transform_with_canvas()
		back_root.visible=active
		back_root.modulate=fx.modulate
	glow.strength=glow_strength*opacity
	glow.sync(fx,active)
	slices.material.set_shader_parameter("animation_time",t)
	post.material.set_shader_parameter("radial_level",camera.radial);post.material.set_shader_parameter("rgb_strength",camera.rgb)
	post.material.set_shader_parameter("effect_opacity",opacity)
	flicker.visible=bool(camera.flicker)
	flicker.material.set_shader_parameter("threshold",camera.flicker_threshold)
	flicker.material.set_shader_parameter("inside_color",camera.flicker_inside)
	flicker.material.set_shader_parameter("outside_color",camera.flicker_outside)

func cancel():
	active=false;visible=false
	if is_instance_valid(live_actor):live_actor.visible=true
	if is_instance_valid(back_root):back_root.visible=false
	if not prepared:return
	fx.visible=false;glow.sync(fx,false)
	fx.field_viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	fx.highlight_viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED

func _exit_tree():
	cancel()
	if is_instance_valid(back_root):back_root.queue_free()
