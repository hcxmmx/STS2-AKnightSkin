extends Node2D

static var shared_metadata: Dictionary={}
static var shared_programs: Dictionary={}
static var animated_names: Dictionary={}
static var material_templates: Dictionary={}
# Only explicitly prepared start frames are shared, with the existing per-skill budget.
static var shared_starts: Dictionary={}
var source_key: String=""
const PlaneClip = preload("res://AKnight_Hcxmmx/Runtime/NearClip.gd")

# Separate runtime for the new v4 caches. The accepted skill1 runtime is untouched.
var meta: Dictionary
var stream: FileAccess
var nodes: Array[MeshInstance2D] = []
var states: Array = []
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
	# v4 GPU data textures pad each group to 1024 columns, in addition to mesh data.
	return int(meta.frames[frame].bytes)*2+int(meta.frames[frame].get("groups",nodes.size()))*65536

func _cache_frame(frame: Variant, data: Array, cost: int) -> void:
	while not frame_cache.is_empty() and (cache_bytes+cost>CACHE_BYTES or frame_cache.size()>=48):
		var oldest=frame_cache.keys()[0];cache_bytes-=int(cache_costs[oldest])
		frame_cache.erase(oldest);cache_costs.erase(oldest)
	if cost>CACHE_BYTES:return
	frame_cache[frame]=data;cache_costs[frame]=cost;cache_bytes+=cost

var last_frame := -1
var visible_kinds := {"cast":false}
var distortion_enabled := true
var dedicated_enabled := true
var field_viewport: SubViewport
var field_root: Node2D
var unsupported_groups: Array = []
var peak_visible := 0
var fallback: Texture2D
var perspective_view := false
var camera_position := Vector3(0,2.13,-12.06)
var highlight_viewport: SubViewport
var highlight_root: Node2D
var highlight_nodes: Array=[]
var highlight_materials: Array=[]
var layout_mode := 0
var layout_nodes: Dictionary = {}
var layout_materials: Dictionary = {}
var approximate_tail := false
var tail_nodes: Dictionary = {}
var tail_materials: Dictionary = {}
var tail_ready := false
var particle_details=preload("res://AKnight_Hcxmmx/Runtime/ParticleDetails.gd").new()

func set_particle_approximation(value: bool,t: float):
	if particle_details.approximate==value:return
	particle_details.approximate=value;frame_cache.clear();start_frames.clear();cache_costs.clear();cache_bytes=0;start_bytes=0;show_time(t,true)

func initialize(skill: String, progressive:=false) -> void:
	source_key=skill
	var folder := "res://AKnight_Hcxmmx/Runtime/assets/fx/"+skill+"/"
	particle_details.initialize(folder)
	if not shared_metadata.has(skill):
		shared_metadata[skill]=JSON.parse_string(FileAccess.get_file_as_string(folder+"frames.json"))
		shared_programs[skill]=JSON.parse_string(FileAccess.get_file_as_string(folder+"shader_materials.json"))
	meta=shared_metadata[skill]
	var programs: Dictionary=shared_programs[skill]
	if not animated_names.has(skill):
		var names: Dictionary={}
		for frame_props in meta.properties:
			for id in frame_props:
				if not names.has(str(id)):names[str(id)]={}
				for property in frame_props[id]:names[str(id)][str(property).get_slice(".",0)]=true
		animated_names[skill]=names
	stream=FileAccess.open(folder+"frames.bin",FileAccess.READ)
	assert(stream!=null and int(meta.binary_version)==4)
	var im:=Image.create(1,1,false,Image.FORMAT_RGBA8);im.fill(Color.WHITE);fallback=ImageTexture.create_from_image(im)
	field_viewport=SubViewport.new();field_viewport.size=Vector2i(get_viewport_rect().size);field_viewport.transparent_bg=true;field_viewport.disable_3d=true
	field_viewport.render_target_update_mode=SubViewport.UPDATE_WHEN_VISIBLE;add_child(field_viewport)
	field_root=Node2D.new();field_root.position=position;field_root.scale=scale;field_viewport.add_child(field_root)
	if skill=="unique":
		highlight_viewport=SubViewport.new();highlight_viewport.size=Vector2i(get_viewport_rect().size);highlight_viewport.transparent_bg=true;highlight_viewport.disable_3d=true
		highlight_viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED;add_child(highlight_viewport)
		visibility_changed.connect(_update_highlight_activity)
		highlight_root=Node2D.new();highlight_root.position=position;highlight_root.scale=scale;highlight_viewport.add_child(highlight_root)
	for group in meta.groups:
		if progressive and nodes.size()%4==0:
			await get_tree().process_frame
			while not get_tree().get_nodes_in_group("aknight_battles").is_empty():await get_tree().create_timer(.2).timeout
		var mat: Dictionary=group.material
		var node:=MeshInstance2D.new();node.texture_repeat=CanvasItem.TEXTURE_REPEAT_ENABLED
		var tex: Dictionary=mat.textures._MainTex
		node.texture=load("res://AKnight_Hcxmmx/Runtime/"+str(meta.textures[tex.texture].path))
		var template_key:=skill+":"+str(nodes.size())
		var sm: ShaderMaterial
		var state: Dictionary
		if material_templates.has(template_key):
			sm=material_templates[template_key].material.duplicate()
			state=material_templates[template_key].state.duplicate(true)
		else:
			sm=ShaderMaterial.new();state={"buffers":{},"fields":[],"distortion":false}
			if mat.shader=="shenlan/effects/postprocess/mask":
				var sh:=Shader.new();sh.code=FileAccess.get_file_as_string("res://AKnight_Hcxmmx/Runtime/distortion_mask.gdshader").replace("UV - baked_scroll","vec2(UV.x,1.0-UV.y) * main_st.xy + main_st.zw - baked_scroll")
				if skill=="unique":
					sh.code=sh.code.replace("varying float particle_alpha;","varying float particle_alpha;\nuniform sampler2D vertex_data : filter_nearest;\nuniform int vertex_rows=1;\n#include \"res://AKnight_Hcxmmx/Runtime/perspective_canvas.gdshaderinc\"")
					sh.code=sh.code.replace("particle_alpha = COLOR.a;","particle_alpha=COLOR.a;preview_reciprocal=1.0;preview_depth=1.0;if(perspective_view){vec3 world=texelFetch(vertex_data,ivec2(VERTEX_ID%1024,VERTEX_ID/1024),0).xyz;VERTEX=project_source(world);preview_depth=world.z-camera_position.z;}")
				sm.shader=sh;sm.set_shader_parameter("mask_map",node.texture)
				sm.set_shader_parameter("main_st",Vector4(tex.scale.x,tex.scale.y,tex.offset.x,tex.offset.y))
				sm.set_shader_parameter("factor",float(mat.floats.get("_Factor",1)))
				state.distortion=true
			else:
				assert(programs.has(group.material_id),"Missing material variant "+str(mat.name))
				var program: Dictionary=programs[group.material_id]
				sm.shader=load("res://AKnight_Hcxmmx/Runtime/"+str(program.shader_path))
				var code:=FileAccess.get_file_as_string("res://AKnight_Hcxmmx/Runtime/"+str(program.shader_path))
				if skill=="unique" and str(mat.name) in ["glow_029_wjy_ab07","glow_029_wjy"]:
					# Preserve source RGB*alpha before the LDR canvas clamps HDR RGB.
					var beam_shader:=Shader.new()
					beam_shader.code=code.replace("blend_mix","blend_premul_alpha").replace("COLOR=vec4(light,clamp(o0.a,0.0,1.0));","COLOR=vec4(light,clamp(o0.a,0.0,1.0));COLOR.rgb*=COLOR.a;")
					sm.shader=beam_shader
				if skill=="unique" and nodes.size() in [185,186,187]:
					# The source uses SrcAlpha/One with HDR colors up to 767. Preserve
					# RGB*alpha before the compatibility canvas clamps the source RGB.
					var ring_code:=code.replace("blend_add","blend_premul_alpha").replace("COLOR=vec4(light,clamp(o0.a,0.0,1.0));","COLOR=vec4(light*clamp(o0.a,0.0,1.0),0.0);")
					if nodes.size()==187:
						# Verified in source Texture2D settings: mask_015_hl uses Clamp.
						# Repeating this moving mask turns one circular reveal into repeats.
						ring_code=ring_code.replace("uniform sampler2D ps_t1 : repeat_enable","uniform sampler2D ps_t1 : repeat_disable")
					# Match the visible stroke, not mesh/quad bounds. The dissolve ring
					# is the reference (alpha-weighted radius 5.76035); draw mesh radius
					# is 4.06246, soft halo radius 5.98431. Keep the source overlap/fade.
					var ring_scale: float=1.417944 if nodes.size()==187 else (.962575 if nodes.size()==186 else 1.0)
					ring_code=ring_code.replace("uniform int vertex_rows=1;","uniform int vertex_rows=1;\nuniform float ring_reference_scale=%.6f;"%ring_scale)
					ring_code=ring_code.replace("vec4 preview_world=texelFetch(vertex_data,data_coord,0);","vec4 preview_world=texelFetch(vertex_data,data_coord,0);\npreview_world.xyz=vec3(3.5,0.0,-2.98)+(preview_world.xyz-vec3(3.5,0.0,-2.98))*ring_reference_scale;\nif(!perspective_view){VERTEX=vec2(-3.5,0.9536)+(VERTEX-vec2(-3.5,0.9536))*ring_reference_scale;}")
					var ring_shader:=Shader.new();ring_shader.code=ring_code;sm.shader=ring_shader
				if skill=="skill2" and str(mat.name) in ["glow_002_wx_ab","glow_014_hl_add_08"]:
					var particle_shader:=Shader.new()
					var additive: bool=code.contains("blend_add")
					particle_shader.code=code.replace("blend_add","blend_premul_alpha").replace("blend_mix","blend_premul_alpha").replace("COLOR=vec4(light,clamp(o0.a,0.0,1.0));","COLOR=vec4(light*clamp(o0.a,0.0,1.0),"+("0.0" if additive else "clamp(o0.a,0.0,1.0)")+");")
					particle_shader.code=particle_shader.code.replace("COLOR=vec4(o0.rgb*preview_gain,clamp(o0.a,0.0,1.0));","COLOR=vec4(o0.rgb*preview_gain*clamp(o0.a,0.0,1.0),"+("0.0" if additive else "clamp(o0.a,0.0,1.0)")+");")
					sm.shader=particle_shader
				var rx:=RegEx.new();rx.compile("uniform vec4 ([a-z]+_cb[0-9]+)\\[([0-9]+)\\]")
				for match in rx.search_all(code):
					var values:=PackedVector4Array();values.resize(int(match.get_string(2)));state.buffers[match.get_string(1)]=values
				for stage in ["vs","ps"]:
					for slot in program[stage].textures:
						var name: String=program[stage].textures[slot]
						var texture: Texture2D=fallback
						if mat.textures.has(name):texture=load("res://AKnight_Hcxmmx/Runtime/"+str(meta.textures[mat.textures[name].texture].path))
						sm.set_shader_parameter(stage+"_t"+str(slot),texture)
					for entry in program[stage].fields:
						var field: Dictionary={"buffer":stage+"_cb"+str(int(entry[0])),"name":entry[1],"byte":int(entry[2]),"dim":int(entry[3]),"rows":int(entry[4])}
						state.fields.append(field)
						var val: Array=program.defaults.get(field.name,[0,0,0,0]).duplicate()
						if mat.colors.has(field.name):
							var c: Dictionary=mat.colors[field.name];val=[c.r,c.g,c.b,c.a]
						elif mat.floats.has(field.name):val=[mat.floats[field.name],0,0,0]
						elif str(field.name).ends_with("_ST"):
							var tn:=str(field.name).trim_suffix("_ST")
							if mat.textures.has(tn):
								var st: Dictionary=mat.textures[tn];val=[st.scale.x,st.scale.y,st.offset.x,st.offset.y]
							else:val=[1,1,0,0]
						elif field.name=="_WorldSpaceCameraPos":val=[0,5,-20,1]
						elif field.name=="_MainLightColor":val=[1,1,1,1]
						if int(field.rows)>1:
							for row in int(field.rows):
								var unit: Array=[0,0,0,0];unit[row]=1.0
								_put(state,field,unit,row)
						else:_put(state,field,val)
				for key in state.buffers:sm.set_shader_parameter(key,state.buffers[key])
			var animated: Dictionary=animated_names[skill].get(str(nodes.size()),{})
			state.fields=state.fields.filter(func(field):return field.name=="_Time" or animated.has(field.name))
			var dynamic_buffers: Dictionary={}
			for field in state.fields:dynamic_buffers[field.buffer]=true
			state.dynamic_buffers=dynamic_buffers.keys()
			material_templates[template_key]={"material":sm.duplicate(),"state":state.duplicate(true)}
		if state.distortion:field_root.add_child(node)
		else:add_child(node)
		node.material=sm
		# Timeline sort 0 is behind the character, 140 is in front. Scene meshes
		# stay behind both characters; retain original relative renderer orders.
		if str(group.source_resource).ends_with("_bg"):node.z_index=-100+clampi(int(group.renderer_order),-50,50)
		elif int(group.order)==-1:node.z_index=clampi(int(group.renderer_order),-45,99)
		elif int(group.order)==0:node.z_index=-20+clampi(int(group.renderer_order),-5,5)
		else:node.z_index=10+clampi(int(group.renderer_order),-5,60)
		nodes.append(node);states.append(state);shaders.append(sm)
		var group_id:=nodes.size()-1
		if skill=="unique" and (group_id==270 or group_id in [271,272,273,281,282,291,292]):
			var overlay:=MeshInstance2D.new();overlay.z_index=90;overlay.texture=node.texture
			var overlay_mat:=ShaderMaterial.new();overlay_mat.shader=load("res://AKnight_Hcxmmx/Runtime/LayoutOverlay.gdshader")
			overlay_mat.set_shader_parameter("line_mode",group_id==270)
			overlay_mat.set_shader_parameter("mask_map",node.texture)
			overlay_mat.set_shader_parameter("main_st",Vector4(tex.scale.x,tex.scale.y,tex.offset.x,tex.offset.y))
			overlay_mat.set_shader_parameter("factor",float(mat.floats.get("_Factor",1)))
			overlay_mat.set_shader_parameter("palette_offset",float(group_id)*0.271)
			# Source glass mesh has 36 vertices per particle; the planes use quads.
			overlay_mat.set_shader_parameter("piece_vertex_count",36 if group_id in [282,292] else 4)
			overlay.material=overlay_mat;overlay.visible=false;add_child(overlay)
			layout_nodes[group_id]=overlay;layout_materials[group_id]=overlay_mat
		var highlight_node: MeshInstance2D=null;var highlight_material: ShaderMaterial=null
		var tint: Dictionary=mat.colors.get("_MainColor",{"r":1,"g":1,"b":1})
		if skill=="unique" and not state.distortion and (str(mat.name).begins_with("daoguang_") or str(mat.name).begins_with("noise_171_ld")):
			highlight_node=MeshInstance2D.new();highlight_node.texture=node.texture;highlight_node.texture_repeat=node.texture_repeat;highlight_node.z_index=node.z_index
			highlight_material=sm.duplicate();highlight_material.set_shader_parameter("highlight_capture",true);highlight_node.material=highlight_material
			highlight_root.add_child(highlight_node)
		highlight_nodes.append(highlight_node);highlight_materials.append(highlight_material)
		if skill=="unique" and group_id in [268,269,270]:
			var tail:=MeshInstance2D.new();tail.texture=node.texture;tail.texture_repeat=node.texture_repeat;tail.z_index=node.z_index
			var tail_mat: ShaderMaterial=sm.duplicate();tail.material=tail_mat;tail.visible=false;add_child(tail)
			tail_nodes[group_id]=tail;tail_materials[group_id]=tail_mat
	show_time(0)

func _put(state: Dictionary, field: Dictionary, values: Array, row: int=0) -> void:
	if not state.buffers.has(field.buffer):return
	var data: PackedVector4Array=state.buffers[field.buffer]
	var index:=int(field.byte)/16+row
	if index>=data.size():return
	var v: Vector4=data[index]
	for k in int(field.dim):v[(int(field.byte)%16)/4+k]=float(values[k])
	data[index]=v;state.buffers[field.buffer]=data

func set_dedicated(value: bool,t: float) -> void:
	dedicated_enabled=value;show_time(t,true)

func set_layout_mode(value: int) -> void:
	if layout_mode==value:return
	layout_mode=value;last_frame=-1
	for sm in layout_materials.values():sm.set_shader_parameter("shape_mode",value>=4)

func set_approximate_tail(value: bool) -> void:
	if approximate_tail==value:return
	approximate_tail=value;last_frame=-1

func _show_approximate_tail(t: float) -> void:
	for node in tail_nodes.values():node.visible=false
	if not approximate_tail or t<10.2 or t>=12.7:return
	if not tail_ready:
		for entry in read_frame(305):
			if not tail_nodes.has(int(entry.id)):continue
			var id:=int(entry.id);tail_nodes[id].mesh=entry.mesh
			tail_materials[id].set_shader_parameter("vertex_data",entry.vertex_data)
			tail_materials[id].set_shader_parameter("vertex_rows",entry.vertex_rows)
		tail_ready=true
	for id in tail_nodes:
		if id==270:continue
		tail_nodes[id].visible=true;tail_nodes[id].modulate=Color.WHITE
		tail_materials[id].set_shader_parameter("perspective_view",perspective_view)
		tail_materials[id].set_shader_parameter("camera_position",camera_position)
		tail_materials[id].set_shader_parameter("preview_gain",shaders[id].get_shader_parameter("preview_gain"))

func set_projection(enabled: bool,eye: Vector3) -> void:
	if perspective_view==enabled and camera_position==eye:return
	if perspective_view!=enabled:last_frame=-1
	perspective_view=enabled;camera_position=eye
	_update_highlight_activity()
	for sm in shaders:
		sm.set_shader_parameter("perspective_view",enabled)
		sm.set_shader_parameter("camera_position",eye)
	for sm in layout_materials.values():
		sm.set_shader_parameter("perspective_view",enabled)
		sm.set_shader_parameter("camera_position",eye)
	for sm in highlight_materials:
		if sm!=null:
			sm.set_shader_parameter("perspective_view",enabled);sm.set_shader_parameter("camera_position",eye)

func _update_highlight_activity() -> void:
	if highlight_viewport!=null:
		highlight_viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS if perspective_view and is_visible_in_tree() else SubViewport.UPDATE_DISABLED

func _vec2(raw: PackedByteArray) -> PackedVector2Array:
	var floats:=raw.to_float32_array();var values:=PackedVector2Array();values.resize(floats.size()/2)
	for i in values.size():values[i]=Vector2(floats[i*2],floats[i*2+1])
	return values

func _colors(raw: PackedByteArray) -> PackedColorArray:
	var floats:=raw.to_float32_array();var values:=PackedColorArray();values.resize(floats.size()/4)
	for i in values.size():values[i]=Color(floats[i*4],floats[i*4+1],floats[i*4+2],floats[i*4+3])
	return values

func read_frame(frame: int,group_ids: Array=[]) -> Array:
	if start_frames.has(frame):return start_frames[frame]
	var shared_key:=source_key+":"+str(particle_details.approximate)
	if shared_starts.has(shared_key) and shared_starts[shared_key].frames.has(frame):return shared_starts[shared_key].frames[frame]
	if frame_cache.has(frame):return frame_cache[frame]
	var selected: bool=not group_ids.is_empty() and group_ids.size()<nodes.size()
	var cache_key: Variant=str(frame)+":"+str(group_ids) if selected else frame
	if selected and frame_cache.has(cache_key):return frame_cache[cache_key]
	var selected_cost:=0
	var record: Dictionary=meta.frames[frame];stream.seek(int(record.offset));var count:=stream.get_32();var live: Array=[]
	for n in count:
		var id:=stream.get_32();var nv:=stream.get_32();var ni:=stream.get_32()
		if selected and id not in group_ids:
			stream.seek(stream.get_position()+nv*96+ni*4);continue
		var arrays: Array=[];arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=_vec2(stream.get_buffer(nv*8))
		arrays[Mesh.ARRAY_TEX_UV]=_vec2(stream.get_buffer(nv*8))
		arrays[Mesh.ARRAY_COLOR]=_colors(stream.get_buffer(nv*16))
		var flags:=0
		for k in 2:
			arrays[Mesh.ARRAY_CUSTOM0+k]=stream.get_buffer(nv*16).to_float32_array()
			flags|=Mesh.ARRAY_CUSTOM_RGBA_FLOAT << (Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT+k*Mesh.ARRAY_FORMAT_CUSTOM_BITS)
		var world:=stream.get_buffer(nv*16);var normals:=stream.get_buffer(nv*16)
		world=particle_details.apply(frame,id,arrays,world)
		var rows:=ceili(float(nv)/1024.0);world.resize(rows*1024*16);normals.resize(rows*1024*16);world.append_array(normals)
		selected_cost+=(nv*64+ni*4)*2+rows*65536+1024
		var image:=Image.create_from_data(1024,rows*2,false,Image.FORMAT_RGBAF,world)
		var data_tex:=ImageTexture.create_from_image(image)
		arrays[Mesh.ARRAY_INDEX]=stream.get_buffer(ni*4).to_int32_array()
		var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},flags)
		var entry: Dictionary={"id":id,"mesh":mesh,"vertex_data":data_tex,"vertex_rows":rows}
		if meta.skill=="unique" and id in [271,272,273]:
			entry.clip_arrays=arrays;entry.clip_world=world.slice(0,nv*16).to_float32_array()
		live.append(entry)
	assert(stream.get_position()==int(record.offset)+int(record.bytes))
	_cache_frame(cache_key,live,selected_cost if selected else _frame_cost(frame));return live

func show_time(t: float,force: bool=false,group_ids: Array=[]) -> void:
	_show_approximate_tail(t)
	var frame:=clampi(roundi(t*float(meta.fps)),0,meta.frames.size()-1)
	if frame==last_frame and not force:return
	last_frame=frame
	for node in nodes:node.visible=false
	for node in layout_nodes.values():node.visible=false
	for node in highlight_nodes:
		if node!=null:node.visible=false
	var props: Dictionary=meta.properties[frame];var shown:=0
	for entry in read_frame(frame,group_ids):
		if not group_ids.is_empty() and int(entry.id) not in group_ids:continue
		var id:=int(entry.id);var g: Dictionary=meta.groups[id];var state: Dictionary=states[id];var sm:=shaders[id]
		if approximate_tail and id==270:continue
		if approximate_tail and state.distortion and id not in [281,282,291,292]:continue
		if perspective_view and entry.has("clip_arrays"):
			var clipped: Dictionary=PlaneClip.clipped(entry.clip_arrays,entry.clip_world,camera_position)
			if clipped.is_empty():continue
			entry=entry.duplicate();entry.mesh=clipped.mesh;entry.vertex_data=clipped.vertex_data
		if layout_mode>0:
			var show_layout: bool=((id==270 and layout_mode in [1,3]) or (id!=270 and layout_mode in [2,3])
				or (id in [271,272,273] and layout_mode in [4,6]) or (id in [282,292] and layout_mode in [5,6]))
			if layout_nodes.has(id) and show_layout:
				var overlay: MeshInstance2D=layout_nodes[id]
				overlay.mesh=entry.mesh;overlay.visible=true
				layout_materials[id].set_shader_parameter("vertex_data",entry.vertex_data)
				layout_materials[id].set_shader_parameter("world_piece_ids",perspective_view and entry.has("clip_arrays"))
			if not str(g.source_resource).ends_with("_bg"):continue
		if g.conditional and not visible_kinds.cast:continue
		if state.distortion and not distortion_enabled:continue
		if not dedicated_enabled and g.material.shader not in ["shenlan/effects/default/simple","shenlan/effects/default/dissolve_particle","shenlan/effects/postprocess/mask"]:continue
		var over: Dictionary=props.get(str(id),{})
		for field in state.fields:
			var name:=str(field.name);var val: Array=[]
			if name=="_Time":val=[t/20,t,t*2,t*3]
			elif over.has(name):val=[over[name],0,0,0]
			else:
				var arr: PackedVector4Array=state.buffers.get(field.buffer,PackedVector4Array())
				if arr.is_empty():continue
				var v: Vector4=arr[int(field.byte)/16];val=[v.x,v.y,v.z,v.w]
				var changed:=false
				for axis in 4:
					var suffix: String="xyzw"[axis];var suffix2: String="rgba"[axis]
					if over.has(name+"."+suffix):val[axis]=over[name+"."+suffix];changed=true
					if over.has(name+"."+suffix2):val[axis]=over[name+"."+suffix2];changed=true
				if not changed:continue
			_put(state,field,val)
		for key in state.dynamic_buffers:sm.set_shader_parameter(key,state.buffers[key])
		if not state.distortion or meta.skill=="unique":
			sm.set_shader_parameter("vertex_data",entry.vertex_data);sm.set_shader_parameter("vertex_rows",entry.vertex_rows)
		nodes[id].mesh=entry.mesh;nodes[id].visible=true;shown+=1
		if highlight_nodes[id]!=null:
			var hm: ShaderMaterial=highlight_materials[id]
			for key in state.dynamic_buffers:hm.set_shader_parameter(key,state.buffers[key])
			hm.set_shader_parameter("vertex_data",entry.vertex_data);hm.set_shader_parameter("vertex_rows",entry.vertex_rows)
			highlight_nodes[id].mesh=entry.mesh;highlight_nodes[id].visible=true
	peak_visible=maxi(peak_visible,shown)
