extends Node2D
const FrameSource=preload("res://AKnight_Hcxmmx/Runtime/FrameStore.gd")

# Immutable source data and material templates survive room instances.
static var shared_metadata: Dictionary={}
static var material_templates: Dictionary={}
# Only explicitly prepared start frames are shared, with the existing per-skill budget.
static var shared_starts: Dictionary={}
static var shared_clips: Dictionary={}
const CLIP_BYTES=24*1024*1024
var source_key: String=""

var meta: Dictionary
var stream:FrameSource
var nodes: Array[MeshInstance2D] = []
var shaders: Array[ShaderMaterial] = []
var frame_cache: Dictionary = {}
# Separate bounded start-pose cache from the streaming window.
var start_frames: Dictionary = {}
var start_bytes:=0
var cache_bytes:=0
var cache_costs: Dictionary={}
const CACHE_BYTES=24*1024*1024
const START_BYTES=8*1024*1024
var start_budget:=START_BYTES

func prepare_frames(times: Array) -> void:
	for t in times:
		var frame:=clampi(roundi(float(t)*float(meta.fps)),0,meta.frames.size()-1)
		if start_frames.has(frame):continue
		var cost:=_frame_cost(frame)
		if start_bytes+cost>start_budget:continue
		var key:=source_key+":"+str(particle_details.approximate)
		if not shared_starts.has(key):shared_starts[key]={"frames":{},"bytes":0}
		var shared: Dictionary=shared_starts[key]
		if shared.frames.has(frame):start_frames[frame]=shared.frames[frame]
		else:
			start_frames[frame]=read_frame(frame)
			if int(shared.bytes)+cost<=start_budget:
				shared.frames[frame]=start_frames[frame];shared.bytes+=cost
		start_bytes+=cost

func _frame_cost(frame: int) -> int:
	# v2/v3 has mesh attributes only; the v4 data-texture padding does not apply.
	return int(meta.frames[frame].bytes)*2+int(meta.frames[frame].get("groups",nodes.size()))*1024

func prepare_clip() -> void:
	# Only the small skill1 clip is requested by menu warmup. Meshes are immutable
	# and shared by all three slash players; other skills keep streaming normally.
	var key:=source_key+":"+str(particle_details.approximate)
	if not shared_clips.has(key):shared_clips[key]={"frames":{},"bytes":0}
	var clip: Dictionary=shared_clips[key]
	for frame in meta.frames.size():
		if clip.frames.has(frame):continue
		if int(clip.bytes)+_frame_cost(frame)>CLIP_BYTES:break
		while not get_tree().get_nodes_in_group("aknight_battles").is_empty():await get_tree().create_timer(.2).timeout
		clip.frames[frame]=read_frame(frame);clip.bytes+=_frame_cost(frame)
		await get_tree().process_frame

func _cache_frame(frame: int, data: Array) -> void:
	var cost:=_frame_cost(frame)
	while not frame_cache.is_empty() and (cache_bytes+cost>CACHE_BYTES or frame_cache.size()>=48):
		var oldest=frame_cache.keys()[0];cache_bytes-=int(cache_costs[oldest])
		frame_cache.erase(oldest);cache_costs.erase(oldest)
	if cost>CACHE_BYTES:return
	frame_cache[frame]=data;cache_costs[frame]=cost;cache_bytes+=cost

var last_frame := -1
var visible_kinds := {"cast": true, "flight": true, "target": true}
var gain := 0.8
var peak_visible := 0
var legacy_mode := false
var caster_ratio := 1.0
var caster_shift := Vector2.ZERO
var advanced_enabled := true
var distortion_enabled := true
var refined_materials: Array[ShaderMaterial] = []
var field_viewport: SubViewport
var field_root: Node2D
var distortion_group_count := 0
var unsupported_groups: Array = []
var dedicated_group_ids: Array[int] = []
var dedicated_enabled := true
var particle_details=preload("res://AKnight_Hcxmmx/Runtime/ParticleDetails.gd").new()

func set_particle_approximation(value: bool,t: float):
	if particle_details.approximate==value:return
	particle_details.approximate=value;frame_cache.clear();start_frames.clear();cache_costs.clear();cache_bytes=0;start_bytes=0;show_time(t,true)

const DEDICATED_SHADERS := {
	"shenlan/effects/default/dd":"res://AKnight_Hcxmmx/Runtime/material_dd.gdshader",
	"shenlan/effects/fx_01":"res://AKnight_Hcxmmx/Runtime/material_fx01.gdshader",
	"shenlan/effects/default/mask":"res://AKnight_Hcxmmx/Runtime/material_mask.gdshader"
}

func set_dedicated(value: bool, t: float) -> void:
	dedicated_enabled=value
	show_time(t,true)

func _dedicated_material(mat: Dictionary, additive: bool) -> ShaderMaterial:
	var sm:=ShaderMaterial.new()
	var sh:=Shader.new()
	sh.code=FileAccess.get_file_as_string(str(DEDICATED_SHADERS[mat.shader])).replace("render_mode blend_mix", "render_mode blend_add" if additive else "render_mode blend_mix")
	if str(mat.name)=="glow_093_xz":
		sh.code=sh.code.replace("blend_add","blend_premul_alpha").replace("blend_mix","blend_premul_alpha").replace("COLOR = vec4(result.rgb*gain,clamp(result.a,0.0,1.0));","COLOR = vec4(result.rgb*gain*clamp(result.a,0.0,1.0),"+("0.0" if additive else "clamp(result.a,0.0,1.0)")+");")
	sm.shader=sh
	var main:Dictionary=mat.colors.get("_MainColor",{"r":1,"g":1,"b":1,"a":1})
	sm.set_shader_parameter("main_color",Vector4(main.r,main.g,main.b,main.a))
	var pairs:Array=[]
	if mat.shader=="shenlan/effects/default/dd":
		pairs=[["_MainTex","main"],["_NoiseMap1","noise1"],["_NoiseMap2","noise2"],["_NoiseMap3","noise3"],["_SecondMaskMap","second"]]
		var outside:Dictionary=mat.colors.get("_OutSideColor",{"r":0,"g":0,"b":0,"a":1})
		sm.set_shader_parameter("outside_color",Vector4(outside.r,outside.g,outside.b,outside.a))
		sm.set_shader_parameter("strength",Vector2(mat.floats.get("_StrengthX",.5),mat.floats.get("_StrengthY",.5)))
		sm.set_shader_parameter("direction",Vector2(mat.floats.get("_Direction",1),mat.floats.get("_Direction2",1)))
		for p in [["heat_time","_HeatTime",0.0],["dissolve_power","_Pow",.1],["subtract_value","_Sub",.1]]:
			sm.set_shader_parameter(p[0],float(mat.floats.get(p[1],p[2])))
		for p in [["use_custom_scroll","_PARTCUSTOM_ON"],["use_second_custom","_PARTCUSTOM2_ON"],["use_dissolve_map","_USEDISSOLVEMAP_ON"],["use_dissolve","_HAVEMASK_ON"],["remap_color","_TEXTUREORCOLOR_ON"]]:
			sm.set_shader_parameter(p[0],p[1] in mat.raw.m_ValidKeywords)
	elif mat.shader=="shenlan/effects/fx_01":
		pairs=[["_MainTex","main"],["_SubTex","sub"],["_DissolveTex","dissolve"]]
		for p in [["edge_color","_EdgeColor"],["panner_speed","_PannerSpeed"],["dissolve_control","_DissolveControl"],["dissolve_control2","_DissolveControl2"]]:
			var c:Dictionary=mat.colors.get(p[1],{"r":0,"g":0,"b":0,"a":0})
			sm.set_shader_parameter(p[0],Vector4(c.r,c.g,c.b,c.a))
		for p in [["soft_dissolve","_SOFTDISSOLVE_ON"],["use_custom","_USEVTS_ON"],["panner","_PANNER_ON"]]:
			sm.set_shader_parameter(p[0],p[1] in mat.raw.m_ValidKeywords)
	else:
		pairs=[["_MainTex","main"],["_Mask","mask"]]
	for p in pairs:
		if not mat.textures.has(p[0]):continue
		var info:Dictionary=mat.textures[p[0]]
		sm.set_shader_parameter(p[1]+"_map",load("res://AKnight_Hcxmmx/Runtime/"+str(meta.textures[info.texture].path)))
		sm.set_shader_parameter(p[1]+"_st",_st(info))
		if p[1]!="main":sm.set_shader_parameter("has_"+p[1],true)
	return sm

func set_advanced(value: bool, t: float) -> void:
	advanced_enabled=value
	show_time(t,true)

func _st(info: Dictionary) -> Vector4:
	return Vector4(info.scale.x,info.scale.y,info.offset.x,info.offset.y)

func _refined_material(mat: Dictionary, additive: bool) -> ShaderMaterial:
	var sm:=ShaderMaterial.new()
	var sh:=Shader.new()
	sh.code=FileAccess.get_file_as_string("res://AKnight_Hcxmmx/Runtime/advanced_dissolve.gdshader").replace("render_mode blend_add", "render_mode blend_add" if additive else "render_mode blend_mix")
	sm.shader=sh
	var main: Dictionary=mat.colors.get("_MainColor",{"r":1,"g":1,"b":1,"a":1})
	sm.set_shader_parameter("material_tint",Vector4(main.r,main.g,main.b,main.a))
	sm.set_shader_parameter("smoothness",float(mat.floats.get("_Smooth",1)))
	sm.set_shader_parameter("alpha_from_luminance","_BLENDALPHA_ON" in mat.raw.m_ValidKeywords)
	var speed: Dictionary=mat.colors.get("_Speed",{"r":0,"g":0,"b":0,"a":0})
	sm.set_shader_parameter("uv_speed",Vector4(speed.r,speed.g,speed.b,speed.a))
	for pair in [["_MainTex","main"],["_Distortion","noise"],["_Mask","mask"]]:
		if not mat.textures.has(pair[0]):continue
		var info: Dictionary=mat.textures[pair[0]]
		sm.set_shader_parameter(str(pair[1])+"_st",_st(info))
		sm.set_shader_parameter(str(pair[1])+"_map",load("res://AKnight_Hcxmmx/Runtime/"+str(meta.textures[info.texture].path)))
		if pair[1]!="main":sm.set_shader_parameter("has_"+str(pair[1]),true)
	return sm

func set_caster_mapping(pixel_scale: float, root_offset: Vector2, pixels_per_unit: float) -> void:
	# Original Unity SkeletonDataAsset uses 0.01 world units per Spine unit.
	caster_ratio = pixel_scale / (0.01 * pixels_per_unit)
	caster_shift = root_offset / pixels_per_unit
	_apply_caster_mapping()

func _apply_caster_mapping() -> void:
	for i in nodes.size():
		if meta.groups[i].prefab != "cast": continue
		var ratio := 1.0 if legacy_mode else caster_ratio
		nodes[i].scale = Vector2.ONE * ratio
		nodes[i].position = Vector2(-6, 0) * (1.0-ratio) + (Vector2.ZERO if legacy_mode else caster_shift)

func set_legacy(value: bool, t: float) -> void:
	legacy_mode = value
	_apply_caster_mapping()
	show_time(t, true)

func initialize(folder := "res://AKnight_Hcxmmx/Runtime/assets/fx/", progressive:=false) -> void:
	source_key=folder
	particle_details.initialize(folder)
	if not shared_metadata.has(folder):shared_metadata[folder]=JSON.parse_string(FileAccess.get_file_as_string(folder+"frames.json"))
	meta=shared_metadata[folder]
	stream = preload("res://AKnight_Hcxmmx/Runtime/FrameStore.gd").open(folder,meta)
	assert(stream != null)
	assert(int(meta.get("binary_version",0)) in [2,3])
	field_viewport=SubViewport.new();field_viewport.size=Vector2i(get_viewport_rect().size)
	field_viewport.transparent_bg=true;field_viewport.disable_3d=true
	field_viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	add_child(field_viewport)
	field_root=Node2D.new();field_root.position=position;field_root.scale=scale;field_viewport.add_child(field_root)
	for g in meta.groups:
		if progressive and nodes.size()%4==0:
			await get_tree().process_frame
			while not get_tree().get_nodes_in_group("aknight_battles").is_empty():await get_tree().create_timer(.2).timeout
		if str(g.material.shader) not in ["shenlan/effects/default/simple", "shenlan/effects/default/dissolve_particle", "shenlan/effects/postprocess/mask"] and not DEDICATED_SHADERS.has(str(g.material.shader)):
			unsupported_groups.append({"hierarchy":g.source_hierarchy,"material":g.material.name,"shader":g.material.shader})
		var node := MeshInstance2D.new()
		var mat: Dictionary = g.material
		var info: Dictionary = mat.textures._MainTex
		node.texture = load("res://AKnight_Hcxmmx/Runtime/" + str(meta.textures[info.texture].path))
		var key:=folder+":"+str(nodes.size())
		var sm: ShaderMaterial
		var refined: ShaderMaterial
		var is_distortion: bool=mat.shader=="shenlan/effects/postprocess/mask"
		if material_templates.has(key):
			sm=material_templates[key].base.duplicate()
			if material_templates[key].refined!=null:refined=material_templates[key].refined.duplicate()
		else:
			var additive := float(mat.floats.get("_DstBlend", mat.floats.get("_BlendDst",10))) == 1.0
			var shader := Shader.new()
			shader.code = """shader_type canvas_item;
render_mode BLEND;
uniform float gain = 0.8;
uniform float dissolve = 0.0;
uniform vec4 main_tint = vec4(1.0);
uniform bool legacy = false;
uniform vec2 main_scale = vec2(1.0);
uniform vec2 main_offset = vec2(0.0);
uniform vec2 scroll_offset = vec2(0.0);
uniform vec2 mask_scale = vec2(1.0);
uniform vec2 mask_offset = vec2(0.0);
uniform vec2 noise_scale = vec2(1.0);
uniform vec2 noise_offset = vec2(0.0);
uniform bool has_mask = false;
uniform bool has_noise = false;
uniform bool mask_uses_alpha = true;
uniform sampler2D mask_tex : repeat_enable, filter_linear;
uniform sampler2D noise_tex : repeat_enable, filter_linear;
varying vec4 vertex_tint;
void vertex() { vertex_tint = COLOR; }
void fragment() {
    vec4 tex = texture(TEXTURE, UV);
    vec2 base_uv = (UV - main_offset - scroll_offset) / main_scale;
    vec2 mask_uv = legacy ? UV : base_uv * mask_scale + mask_offset;
    vec2 noise_uv = legacy ? UV : base_uv * noise_scale + noise_offset + scroll_offset;
    vec4 tint = vertex_tint * main_tint;
    if (legacy) { tint = clamp(tint,vec4(0.0),vec4(1.0)); }
    float alpha = tex.a * tint.a;
    if (has_mask) {
        vec4 mask_value = texture(mask_tex, mask_uv);
        alpha *= mask_uses_alpha ? mask_value.a : mask_value.r;
    }
    // Approximation: original custom shader stream bindings are not yet recovered.
    if (has_noise) {
        float n = texture(noise_tex, noise_uv).r;
        alpha *= smoothstep(dissolve - 0.18, dissolve + 0.18, n);
    } else {
        alpha *= 1.0 - smoothstep(0.45, 1.45, dissolve);
    }
    vec3 light = tex.rgb * tint.rgb * gain;
    if (legacy) {
        light = light / (vec3(1.0) + light) * 0.65;
    }
    COLOR = vec4(light, clamp(alpha, 0.0, 1.0));
}
""".replace("BLEND", "blend_add" if additive else "blend_mix")
			sm=ShaderMaterial.new()
			sm.shader = shader
			var main: Dictionary=mat.colors.get("_MainColor",{"r":1,"g":1,"b":1,"a":1})
			sm.set_shader_parameter("main_tint",Vector4(main.r,main.g,main.b,main.a))
			sm.set_shader_parameter("main_scale", Vector2(info.scale.x,info.scale.y))
			sm.set_shader_parameter("main_offset", Vector2(info.offset.x,info.offset.y))
			if mat.textures.has("_Mask"):
				var mask_info: Dictionary = mat.textures._Mask
				sm.set_shader_parameter("has_mask", true)
				sm.set_shader_parameter("mask_tex", load("res://AKnight_Hcxmmx/Runtime/" + str(meta.textures[mask_info.texture].path)))
				sm.set_shader_parameter("mask_uses_alpha", bool(meta.textures[mask_info.texture].get("has_alpha_mask",true)))
				sm.set_shader_parameter("mask_scale", Vector2(mask_info.scale.x,mask_info.scale.y))
				sm.set_shader_parameter("mask_offset", Vector2(mask_info.offset.x,mask_info.offset.y))
			if "dissolve" in str(mat.shader) and mat.textures.has("_Distortion"):
				var noise_info: Dictionary = mat.textures._Distortion
				sm.set_shader_parameter("has_noise", true)
				sm.set_shader_parameter("noise_tex", load("res://AKnight_Hcxmmx/Runtime/" + str(meta.textures[noise_info.texture].path)))
				sm.set_shader_parameter("noise_scale", Vector2(noise_info.scale.x,noise_info.scale.y))
				sm.set_shader_parameter("noise_offset", Vector2(noise_info.offset.x,noise_info.offset.y))
			if str(mat.name) in ["glow_006_wx","glow_014_hl_add_08","glow_205_ch","glow_002_wx_ab","glow_007_xz","glow_025_ch_sj"]:
				# Apply alpha while RGB is still HDR, before the LDR canvas clamps it.
				shader.code=shader.code.replace("blend_add","blend_premul_alpha").replace("blend_mix","blend_premul_alpha").replace("COLOR = vec4(light, clamp(alpha, 0.0, 1.0));","COLOR = vec4(light*clamp(alpha,0.0,1.0),"+("0.0" if additive else "clamp(alpha,0.0,1.0)")+");")
			if is_distortion:
				sm=ShaderMaterial.new();sm.shader=load("res://AKnight_Hcxmmx/Runtime/distortion_mask.gdshader")
				sm.set_shader_parameter("mask_map",node.texture)
				sm.set_shader_parameter("main_st",_st(info))
				sm.set_shader_parameter("factor",float(mat.floats.get("_Factor",1)))
			elif mat.shader=="shenlan/effects/default/dissolve_particle":
				refined=_refined_material(mat,additive)
			elif DEDICATED_SHADERS.has(str(mat.shader)):
				refined=_dedicated_material(mat,additive)
			material_templates[key]={"base":sm.duplicate(),"refined":refined.duplicate() if refined!=null else null}
		if is_distortion:distortion_group_count+=1
		elif DEDICATED_SHADERS.has(str(mat.shader)):dedicated_group_ids.append(nodes.size())
		node.material = refined if refined!=null else sm
		node.z_index = 10 + clampi(int(g.order), -5, 20)
		node.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		if is_distortion:field_root.add_child(node)
		else:add_child(node)
		nodes.append(node)
		shaders.append(sm)
		refined_materials.append(refined)
	show_time(0.0)

func _vec2_array(raw: PackedByteArray) -> PackedVector2Array:
	var floats := raw.to_float32_array()
	var result := PackedVector2Array()
	result.resize(floats.size() / 2)
	for i in result.size(): result[i] = Vector2(floats[i*2], floats[i*2+1])
	return result

func _color_array(raw: PackedByteArray) -> PackedColorArray:
	var floats := raw.to_float32_array()
	var result := PackedColorArray()
	result.resize(floats.size() / 4)
	for i in result.size(): result[i] = Color(floats[i*4],floats[i*4+1],floats[i*4+2],floats[i*4+3])
	return result

func read_frame(frame: int) -> Array:
	if start_frames.has(frame):return start_frames[frame]
	var shared_key:=source_key+":"+str(particle_details.approximate)
	if shared_clips.has(shared_key) and shared_clips[shared_key].frames.has(frame):return shared_clips[shared_key].frames[frame]
	if shared_starts.has(shared_key) and shared_starts[shared_key].frames.has(frame):return shared_starts[shared_key].frames[frame]
	if frame_cache.has(frame): return frame_cache[frame]
	var info: Dictionary = meta.frames[frame]
	stream.seek(int(info.offset))
	var count := stream.get_32()
	var groups: Array = []
	for n in count:
		var id := stream.get_32()
		var nv := stream.get_32()
		var ni := stream.get_32()
		var dissolve := stream.get_float()
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = _vec2_array(stream.get_buffer(nv*8))
		arrays[Mesh.ARRAY_TEX_UV] = _vec2_array(stream.get_buffer(nv*8))
		arrays[Mesh.ARRAY_COLOR] = _color_array(stream.get_buffer(nv*16))
		arrays[Mesh.ARRAY_CUSTOM0] = stream.get_buffer(nv*16).to_float32_array()
		if int(meta.binary_version)>=3:
			arrays[Mesh.ARRAY_CUSTOM1] = stream.get_buffer(nv*16).to_float32_array()
		arrays[Mesh.ARRAY_INDEX] = stream.get_buffer(ni*4).to_int32_array()
		particle_details.apply(frame,id,arrays)
		var mesh := ArrayMesh.new()
		var flags:=Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
		if int(meta.binary_version)>=3:flags |= Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays,[],{},flags)
		groups.append({"id": id,"mesh":mesh,"dissolve":dissolve})
	assert(stream.get_position() == int(info.offset) + int(info.bytes))
	_cache_frame(frame,groups)
	return groups

func show_time(t: float, force: bool = false, group_ids: Array = []) -> void:
	var frame := clampi(int(round(t * float(meta.fps))),0,meta.frames.size()-1)
	if frame == last_frame and not force: return
	last_frame = frame
	for node in nodes: node.visible = false
	var shown := 0
	for entry in read_frame(frame):
		var id := int(entry.id)
		if not group_ids.is_empty() and id not in group_ids:continue
		if not visible_kinds.get(meta.groups[id].prefab, true): continue
		var group: Dictionary=meta.groups[id]
		if id in dedicated_group_ids and not dedicated_enabled:continue
		if not DEDICATED_SHADERS.has(str(group.material.shader)) and str(group.material.shader) not in ["shenlan/effects/default/simple","shenlan/effects/default/dissolve_particle","shenlan/effects/postprocess/mask"]:continue
		var is_distortion: bool=group.material.shader=="shenlan/effects/postprocess/mask"
		if is_distortion and (not distortion_enabled or legacy_mode):continue
		nodes[id].mesh = entry.mesh
		nodes[id].visible = true
		nodes[id].material=refined_materials[id] if id in dedicated_group_ids or (advanced_enabled and not legacy_mode and refined_materials[id]!=null) else shaders[id]
		shaders[id].set_shader_parameter("gain",gain)
		shaders[id].set_shader_parameter("dissolve",entry.dissolve)
		shaders[id].set_shader_parameter("legacy",legacy_mode)
		var scroll: Dictionary=group.material.colors.get("_Speed",{})
		var effect_time: float=(float(frame)/float(meta.fps)-float(group.instance_start))*float(group.simulation_speed)
		shaders[id].set_shader_parameter("scroll_offset",Vector2(float(scroll.get("r",0)),-float(scroll.get("g",0)))*effect_time)
		if refined_materials[id]!=null:
			refined_materials[id].set_shader_parameter("gain",gain)
			refined_materials[id].set_shader_parameter("effect_time",effect_time)
			refined_materials[id].set_shader_parameter("baked_scroll",Vector2(float(scroll.get("r",0)),-float(scroll.get("g",0)))*effect_time)
		if is_distortion:
			shaders[id].set_shader_parameter("baked_scroll",Vector2(float(scroll.get("r",0)),-float(scroll.get("g",0)))*effect_time)
		shown += 1
	peak_visible = maxi(peak_visible, shown)
