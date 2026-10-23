extends Node2D
const Common=preload("res://AKnight_Hcxmmx/Runtime/effect_player.gd")
const Followup=preload("res://AKnight_Hcxmmx/Runtime/followup_player.gd")
const Glow=preload("res://AKnight_Hcxmmx/Runtime/EffectGlow.gd")
var fx
var glow
var panel: Control
var variant:=""
var active:=false
var elapsed:=0.0
func initialize(kind: String):
	variant=kind;z_index=1
	fx=(Common if kind=="normal" else Followup).new();add_child(fx)
	if kind=="normal":await fx.initialize("res://AKnight_Hcxmmx/Runtime/assets/fx/feather_normal/")
	else:await fx.initialize("feather_unique");fx.visible_kinds.cast=true
	for node in fx.nodes:node.z_index=0
	fx.field_viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	panel=Control.new();panel.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(panel)
	glow=Glow.new();add_child(glow);glow.initialize(panel);glow.screen_space_capture=true;glow.overlay.z_index=0;glow.prepare(fx)
	fx.prepare_frames([0.0,.6,1.3]);stop()
func play_at(source: Transform2D,brightness: float,strength: float):
	global_transform=get_viewport().get_canvas_transform().affine_inverse()
	fx.position=source.origin
	var pixel_scale=source.y.length()*100.
	fx.scale=Vector2(-pixel_scale if source.x.x>0 else pixel_scale,pixel_scale)
	glow.brightness=brightness;glow.strength=strength
	elapsed=0;active=true;visible=true;set_process(true);sample(0)
func sample(at: float):
	elapsed=at
	if at>=float(fx.meta.duration):stop();return
	fx.show_time(at,true)
	var extent=get_viewport_rect().size;panel.size=extent;glow.overlay.position=Vector2.ZERO;glow.overlay.size=extent
	for vp in [glow.capture,glow.blur_h,glow.blur_v]:vp.size=Vector2i(extent*.5)
	glow.capture.canvas_transform=Transform2D.IDENTITY.scaled(Vector2(.5,.5))
	for vp in [glow.blur_h,glow.blur_v]:vp.get_child(0).size=extent*.5
	glow.sync(fx,true)
func _process(delta: float):
	if active:sample(elapsed+delta)
func stop():
	active=false;visible=false;set_process(false)
	if glow!=null:glow.sync(fx,false)
