extends "res://AKnight_Hcxmmx/Runtime/MotionCore.gd"

var plan=Plan.new()
var last_pose: Dictionary={}
var target_point:=Vector2(1520,660)
var group_target_point:=Vector2(1520,660)
var interrupted_at:=INF
var active_fx
var valid:=false
var back_fx_root: Node2D
var front_debris_root: Node2D
var native_fx_roots: Array=[]

func _players() -> Array:return [entry,ready_fx,skill1_fx,skill2_fx,unique_fx]

func _ready():
	world=self
	actor=Actor.new();add_child(actor)
	valid=actor.initialize("battle")
	if not valid:return
	actor.manual_sampling=true;actor.sample_modifier=modify_skeleton
	entry=common_effect("entry");ready_fx=common_effect("ready")
	ensure_skill(1);ensure_skill(2);ensure_skill(3)
	_attach_back_effects()
	_attach_native_fx()
	for player in _players():player.visible=false

func _attach_back_effects():
	var ancestor: Node=get_parent()
	var host: Node
	while ancestor!=null:
		var candidate=ancestor.get_node_or_null("BackCombatVfxContainer")
		if candidate is CanvasItem:host=candidate;break
		ancestor=ancestor.get_parent()

	if host==null:return # Standalone previews already have a clear backdrop.
	back_fx_root=Node2D.new();back_fx_root.name="AKnightSkill2Back_"+str(get_instance_id())
	host.add_child(back_fx_root);back_fx_root.visible=false
	var ids: Array=[]
	for i in skill2_fx.nodes.size():
		if skill2_fx.meta.groups[i].source_resource=="luolan_300701_skill2_1_hit" and skill2_fx.nodes[i].get_parent()==skill2_fx:ids.append(i)
	ids.sort_custom(func(a,b):
		var left: int=skill2_fx.meta.groups[a].renderer_order;var right: int=skill2_fx.meta.groups[b].renderer_order
		return left<right if left!=right else a<b)
	for id in ids:
		skill2_fx.nodes[id].reparent(back_fx_root,false)
		# Native background / back VFX / creatures ordering is by siblings.
		# Keeping preview negative Z here would still sink under the backdrop.
		skill2_fx.nodes[id].z_index=0
	ancestor=get_parent()
	while ancestor!=null:
		var candidate=ancestor.get_node_or_null("CombatVfxContainer")
		if candidate is CanvasItem:
			front_debris_root=Node2D.new();front_debris_root.name="AKnightSkill2FrontDebris_"+str(get_instance_id())
			candidate.add_child(front_debris_root);front_debris_root.visible=false
			ids.clear()
			for i in skill2_fx.nodes.size():
				if skill2_fx.meta.groups[i].source_resource=="luolan_300701_skill2_2_hit" and skill2_fx.nodes[i].get_parent()==skill2_fx:ids.append(i)
			ids.sort_custom(func(a,b):return int(skill2_fx.meta.groups[a].renderer_order)<int(skill2_fx.meta.groups[b].renderer_order) if skill2_fx.meta.groups[a].renderer_order!=skill2_fx.meta.groups[b].renderer_order else a<b)
			for id in ids:skill2_fx.nodes[id].reparent(front_debris_root,false);skill2_fx.nodes[id].z_index=0
			break
		ancestor=ancestor.get_parent()

func _attach_native_fx():
	var ancestor: Node=get_parent()
	var front: Node
	var back: Node
	while ancestor!=null:
		var candidate=ancestor.get_node_or_null("CombatVfxContainer")
		if candidate is CanvasItem:front=candidate
		candidate=ancestor.get_node_or_null("BackCombatVfxContainer")
		if candidate is CanvasItem:back=candidate
		ancestor=ancestor.get_parent()
	if front==null or back==null:return
	for player in _players():
		for behind in [true,false]:
			var ids: Array=[]
			for i in player.nodes.size():
				if player.nodes[i].get_parent()==player and (player.nodes[i].z_index<0)==behind:ids.append(i)
			if ids.is_empty():continue
			ids.sort_custom(func(a,b):return player.nodes[a].z_index<player.nodes[b].z_index if player.nodes[a].z_index!=player.nodes[b].z_index else a<b)
			var node:=Node2D.new();node.name="AKnightFx_"+str(get_instance_id())+"_"+str(native_fx_roots.size())
			(back if behind else front).add_child(node);node.visible=false
			for id in ids:player.nodes[id].reparent(node,false);player.nodes[id].z_index=0
			native_fx_roots.append({"root":node,"player":player})

func _exit_tree():
	for item in native_fx_roots:
		if is_instance_valid(item.root):item.root.queue_free()
	if is_instance_valid(back_fx_root):back_fx_root.queue_free()
	if is_instance_valid(front_debris_root):front_debris_root.queue_free()

func stop_effects():
	for item in native_fx_roots:item.root.visible=false
	if is_instance_valid(back_fx_root):back_fx_root.visible=false
	if is_instance_valid(front_debris_root):front_debris_root.visible=false
	for player in _players():
		player.visible=false
	active_fx=null

func render(kind: String,t: float):
	stop_effects()
	var p: Dictionary=plan.pose("idle",t)
	match kind:
		"entry":p=plan.action("born",t-.8,2.0)
		"ready":p=plan.ready(t)
		"skill1":
			p=plan.skill1(t);p.position+=Plan.CENTER-Plan.BATTLE
			if t>=.1 and t<2.6666667:
				var sign_value: float=-1.0 if mirrored else 1.0
				p.position=Plan.CENTER+Vector2(sign_value*maxf(0,sign_value*(target_point.x-Plan.CENTER.x)-375),target_point.y-660)
		"skill2":p=plan.action("skill2",t,3.0)
		"cast_b","power_a","power_b":
			plan.mode={"cast_b":10,"power_a":11,"power_b":12}[kind];p=plan.sample(t)
		"hit":p=plan.action("hit",t,.6666667)
		"die":p=plan.action("die",t,2.3333335,Plan.CENTER,true)
		"victory":p=plan.action("victory",t,3.4,Plan.CENTER,true)
		"relaxed":p=plan.action("idle_special1",t,4.033333)
	apply_pose(p);last_pose=p
	if kind=="entry":
		actor.modulate.a=clampf((t-.7)/.1,0,1);show_common(entry,t,"entry");active_fx=entry
	elif kind=="ready":
		show_common(ready_fx,t,"ready");active_fx=ready_fx
		if t<.5:actor.modulate=Color.WHITE.lerp(Color(2.119,1.353,.821,1),maxf(0,1-absf(t*4-1)))
	elif kind=="skill1" and t<=4.1:
		var player=skill1_fx;player.visible=true;player.position=Plan.CENTER+Vector2(-450 if mirrored else 450,0);player.scale=Vector2(-75 if mirrored else 75,75)
		player.show_time(t)
		# Reposition target-side geometry as a rigid piece. Never stretch the
		# actual sword/particle dimensions to bridge the distance to an enemy.
		var default_target=Plan.CENTER+Vector2(-900 if mirrored else 900,0)
		var correction=(target_point-default_target)/player.scale
		for i in player.nodes.size():
			player.nodes[i].position=correction if player.meta.groups[i].prefab=="target" else Vector2.ZERO
			if float(player.meta.groups[i].instance_start)>interrupted_at:player.nodes[i].visible=false
		if t<.3833333:actor.modulate.a=clampf(1-t/.05,0,1) if t<.05 else (0.0 if t<.3333333 else clampf((t-.3333333)/.05,0,1))
		active_fx=player
	elif kind=="skill2" and t<=4.0:
		show_followup(skill2_fx,t,range(skill2_fx.nodes.size()))
		# These are source Timeline type-7 scene effects, not one impact prefab
		# per enemy. Map the shared scene from caster (-6) to the far enemy (+6),
		# retaining caster/weapon emitters at their original body-relative size.
		var span=(group_target_point-Plan.CENTER)/skill2_fx.scale
		var axis=Vector2(span.x/12.0,span.y/12.0)
		var scene_map=Transform2D(axis,Vector2(0,1),axis*6.0-Vector2(6,0))
		for i in skill2_fx.nodes.size():
			if skill2_fx.meta.groups[i].kind=="world":skill2_fx.nodes[i].transform=scene_map
			if float(skill2_fx.meta.groups[i].instance_start)>interrupted_at:skill2_fx.nodes[i].visible=false
		active_fx=skill2_fx
	elif kind in ["cast_b","power_a","power_b"]:
		var fade=smoothstep(.25,.45,t)*(1-smoothstep(1.85,2.35,t))
		if kind=="power_a":
			show_common(ready_fx,t-.3,"ready")
			show_followup(unique_fx,2.65+clampf(t-.3,0,1.4),range(16) if t<1.65 else [7,14,15],fade,true)
			active_fx=unique_fx
		else:
			show_common(ready_fx if kind=="cast_b" else entry,t-.2,"ready" if kind=="cast_b" else "entry")
			show_followup(skill2_fx,1.25+clampf(t-.3,0,.55),[62,63,64],fade,true)
			active_fx=skill2_fx
	_sync_fields()

func _sync_fields():
	# Each mask viewport has its own canvas; synchronize to the exact world
	# transform and current game canvas (including the native camera shake).
	for player in _players():
		var field_active: bool=player.visible and player.distortion_enabled
		if field_active:field_active=player.field_root.get_children().any(func(node):return node.visible)
		player.field_viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS if field_active else SubViewport.UPDATE_DISABLED
		player.field_viewport.size=Vector2i(get_viewport_rect().size)
		player.field_viewport.canvas_transform=get_viewport().get_canvas_transform()
		player.field_root.transform=player.global_transform
		player.field_root.modulate=player.modulate
	if is_instance_valid(back_fx_root):
		back_fx_root.global_transform=skill2_fx.global_transform
		back_fx_root.visible=skill2_fx.visible and is_visible_in_tree()
	if is_instance_valid(front_debris_root):
		front_debris_root.global_transform=skill2_fx.global_transform
		front_debris_root.visible=skill2_fx.visible and is_visible_in_tree()
	for item in native_fx_roots:
		item.root.global_transform=item.player.global_transform
		item.root.modulate=item.player.modulate
		item.root.visible=item.player.visible and is_visible_in_tree()

func render_tail(tail_kind: String,t: float,cutoff: float):
	var saved: Dictionary=last_pose.duplicate()
	interrupted_at=cutoff;render(tail_kind,t)
	if active_fx!=null:
		for i in active_fx.nodes.size():
			var group: Dictionary=active_fx.meta.groups[i]
			if group.get("prefab",group.get("kind",""))=="cast":active_fx.nodes[i].visible=false
	apply_pose(saved);last_pose=saved
