extends Node

# Preview compensation, separate from the accepted material calculations/caches.
# Capture source radiance before the compatibility framebuffer clamps it.
var capture: SubViewport
var blur_h: SubViewport
var blur_v: SubViewport
var canvas: Node2D
var overlay: ColorRect
var player
var entries: Array = []
var bindings: Dictionary = {}
static var shader_cache: Dictionary = {}
var screen_space_capture := false
var enabled := true
var strength := .35
var brightness := 1.0

static func is_emitter(group: Dictionary) -> bool:
	var name:=str(group.material.name).to_lower()
	if group.material.shader=="shenlan/effects/postprocess/mask":return false
	if name.begins_with("m_s05_") or name.begins_with("object_") or name.begins_with("debris_") or name.begins_with("smoke_"):return false
	if name.begins_with("trail_035") or name.begins_with("trail_503") or name.begins_with("trail_062"):return false
	return true

func _apply_brightness(next_player) -> void:
	# Both existing runtimes already separate RGB gain from alpha/dissolve.
	# Keep their baseline (.8), changing only the selected effect materials.
	var followup: bool=int(next_player.meta.binary_version)==4
	var base: float=.8 if followup else float(next_player.gain)
	var parameter: String="preview_gain" if followup else "gain"
	for i in next_player.nodes.size():
		if not next_player.nodes[i].visible or not is_emitter(next_player.meta.groups[i]):continue
		var sm: ShaderMaterial=next_player.nodes[i].material
		sm.set_shader_parameter(parameter,base*brightness)
		if followup and next_player.highlight_materials[i]!=null:
			next_player.highlight_materials[i].set_shader_parameter(parameter,base*brightness)

func _viewport() -> SubViewport:
	var vp:=SubViewport.new();vp.size=Vector2i(get_viewport().get_visible_rect().size*.5)
	vp.transparent_bg=true;vp.disable_3d=true
	vp.render_target_update_mode=SubViewport.UPDATE_DISABLED
	add_child(vp);return vp

func initialize(stage: Control) -> void:
	capture=_viewport();capture.canvas_transform=Transform2D(0,Vector2.ZERO).scaled(Vector2(.5,.5))
	canvas=Node2D.new();capture.add_child(canvas)
	blur_h=_blur(capture.get_texture(),Vector2(1,0))
	blur_v=_blur(blur_h.get_texture(),Vector2(0,1))
	overlay=ColorRect.new();overlay.position=Vector2.ZERO;overlay.size=stage.size;overlay.z_index=84
	overlay.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var sm:=ShaderMaterial.new();sm.shader=load("res://AKnight_Hcxmmx/Runtime/effect_glow_composite.gdshader")
	sm.set_shader_parameter("soft_light",blur_v.get_texture())
	sm.set_shader_parameter("core_light",capture.get_texture())
	overlay.material=sm;stage.add_child(overlay)

func _blur(input: Texture2D, axis: Vector2) -> SubViewport:
	var vp:=_viewport();var rect:=ColorRect.new();rect.size=get_viewport().get_visible_rect().size*.5
	var sm:=ShaderMaterial.new();sm.shader=load("res://AKnight_Hcxmmx/Runtime/effect_glow_blur.gdshader")
	sm.set_shader_parameter("light_map",input);sm.set_shader_parameter("axis",axis)
	rect.material=sm;vp.add_child(rect);return vp

func _capture_shader(original: Shader) -> Dictionary:
	var key:=original.get_instance_id()
	if shader_cache.has(key):return shader_cache[key]
	var code:=original.code
	# Insert at the end of the fragment entry point, retaining texture sampling,
	# dissolve, Custom streams, animated alpha, projection and source tint.
	var start:=code.find("void fragment()")
	assert(start>=0,"Missing fragment entry for glow capture")
	var brace:=code.find("{",start);var end:=brace+1;var depth:=1
	while depth>0:
		if code[end]=="{":depth+=1
		elif code[end]=="}":depth-=1
		end+=1
	var tail:="""
    float glow_peak=max(COLOR.r,max(COLOR.g,COLOR.b));
    vec3 glow_energy=max(COLOR.rgb,vec3(0.0))*smoothstep(0.7,1.5,glow_peak);
    // Bounded HDR encoding prevents extreme source colors (up to 767) from
    // turning a whole translucent sheet into an opaque white bloom field.
    glow_energy/=1.0+max(glow_peak,0.0)/6.0;
    COLOR=vec4(glow_energy/16.0,clamp(COLOR.a,0.0,1.0));
"""
	code=code.insert(end-1,tail)
	code=code.replace("blend_mix","blend_add").replace("blend_disabled","blend_add")
	var shader:=Shader.new();shader.code=code
	var params: Array=[]
	for item in original.get_shader_uniform_list():params.append(str(item.name))
	var result: Dictionary={"shader":shader,"params":params}
	shader_cache[key]=result;return result

func _bind(next_player) -> void:
	for entry in entries:entry.node.visible=false
	player=next_player
	var key: int=player.get_instance_id()
	if bindings.has(key):
		entries=bindings[key];return
	entries=[]
	var sources: Array=[]
	for i in player.nodes.size():
		sources.append({"node":player.nodes[i],"group":player.meta.groups[i]})
	if int(player.meta.binary_version)==4:
		for id in player.tail_nodes:sources.append({"node":player.tail_nodes[id],"group":player.meta.groups[id]})
	for item in sources:
		var source: MeshInstance2D=item.node
		var group: Dictionary=item.group
		# Scene surfaces, opaque debris and the already identified grey airflow
		# are not emitters. All remaining pixels still need to pass the bright gate.
		if not is_emitter(group):continue
		var original: ShaderMaterial=source.material
		var program:=_capture_shader(original.shader)
		var sm:=ShaderMaterial.new();sm.shader=program.shader
		var node:=MeshInstance2D.new();node.material=sm;node.texture=source.texture
		node.texture_repeat=source.texture_repeat;node.z_index=source.z_index
		canvas.add_child(node)
		entries.append({"source":source,"node":node,"material":sm,"params":program.params,"uniform_token":[],"source_material":null})

	bindings[key]=entries

func prepare(next_player) -> void:
	_bind(next_player)
	for entry in entries:entry.node.visible=false

func sync(next_player, active: bool) -> void:
	# Source brightness remains active when the extra bloom layer is switched off.
	if active:_apply_brightness(next_player)
	if active and player!=next_player:_bind(next_player)
	var show:=active and enabled and strength>0.0
	if show:show=entries.any(func(entry):return entry.source.is_visible_in_tree())
	overlay.visible=show
	for vp in [capture,blur_h,blur_v]:
		vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS if show else SubViewport.UPDATE_DISABLED
	if not show:return
	if player!=next_player:_bind(next_player)
	overlay.material.set_shader_parameter("strength",strength)
	var common: bool=int(next_player.meta.binary_version)<4
	var token: Array=[next_player.last_frame,next_player.gain,next_player.legacy_mode,next_player.advanced_enabled,next_player.dedicated_enabled,brightness] if common else []
	for entry in entries:
		var source: MeshInstance2D=entry.source
		entry.node.visible=source.is_visible_in_tree()
		if not entry.node.visible:continue
		entry.node.transform=source.get_global_transform_with_canvas() if screen_space_capture else source.get_global_transform()
		if entry.node.mesh!=source.mesh:entry.node.mesh=source.mesh
		entry.node.modulate=source.modulate
		# v2/v3 uniforms are sampled at the baked 30 fps. Transforms still follow
		# every game frame, while the unchanged material block can be reused.
		if not common or entry.uniform_token!=token or entry.source_material!=source.material:
			for param in entry.params:
				var value=source.material.get_shader_parameter(param)
				if value!=null:entry.material.set_shader_parameter(param,value)
			entry.uniform_token=token;entry.source_material=source.material
