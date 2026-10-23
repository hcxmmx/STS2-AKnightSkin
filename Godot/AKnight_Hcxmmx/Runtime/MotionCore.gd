extends Node2D
const Actor=preload("res://AKnight_Hcxmmx/Actor.gd")
const Plan=preload("res://AKnight_Hcxmmx/MotionPlan.gd")
const Effects=preload("res://AKnight_Hcxmmx/Runtime/effect_player.gd")
const Followup=preload("res://AKnight_Hcxmmx/Runtime/followup_player.gd")
const UNIT=75.0
var actor
var entry
var ready_fx
var skill1_fx
var skill2_fx
var unique_fx
var world: Node2D
var effects_on := true
var mirrored := false
var pending_pose: Dictionary = {}
var anchors: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://AKnight_Hcxmmx/Runtime/followup_anchors.json")).animations

func common_effect(kind: String):
	var player=Effects.new();world.add_child(player);player.initialize("res://AKnight_Hcxmmx/Runtime/assets/fx/common/"+kind+"/")
	player.gain=1.15
	for i in player.nodes.size():
		var group: Dictionary=player.meta.groups[i]
		player.nodes[i].z_index=-5 if group.name in ["lizi_quan_01","fazhen","glow03"] else int(group.order)
	player.visible=false;return player


func ensure_skill(which: int):
	if which==1 and skill1_fx==null:
		skill1_fx=Effects.new();world.add_child(skill1_fx);skill1_fx.initialize();skill1_fx.gain=.8
		skill1_fx.visible_kinds.cast=false
	if which==2 and skill2_fx==null:
		skill2_fx=Followup.new();world.add_child(skill2_fx);skill2_fx.initialize("skill2");skill2_fx.visible_kinds.cast=true
	if which==3 and unique_fx==null:
		unique_fx=Followup.new();world.add_child(unique_fx);unique_fx.initialize("ability");unique_fx.visible_kinds.cast=true


func apply_pose(p: Dictionary):
	actor.position=p.position;actor.scale=Vector2(.75 if mirrored else -.75,.75);actor.modulate=Color.WHITE
	pending_pose=p
	if not str(p.procedural).is_empty():actor.position.y-=float(p.pulse)*(10 if p.procedural=="power" else 3)
	actor.sample(p.animation,p.at,float(p.from_at) if not str(p["from"]).is_empty() else -1.0,float(p.mix),p["from"],float(p.get("mix_duration",.18)))


func modify_skeleton(skeleton):
	var p=pending_pose
	if p.is_empty():return
	if not str(p.procedural).is_empty():
		var amount=float(p.pulse);var power=p.procedural=="power"
		skeleton.update_world_transform(0)
		# The sword is a separate root child, not a child of the arm. Preserve
		# the original grip offset while editing the hand/arm pose.
		var hand=skeleton.find_bone("ll_z_youshou1");var weapon=skeleton.find_bone("wuqi")
		var original_grip=Vector2(hand.get_world_x()-weapon.get_world_x(),hand.get_world_y()-weapon.get_world_y())
		var original_angle=atan2(weapon.get_c(),weapon.get_a())
		for item in [["youshou_1",-12.0 if power else 22.0],["zuoshou_1",12.0 if power else -16.0],["shenti_1",-2.0],["pifu_z_pf1",4.0],["pifu_z_pf6",-3.0]]:
			var bone=skeleton.find_bone(item[0])
			if bone!=null:bone.set_rotation(bone.get_rotation()+float(item[1])*amount)
		weapon.set_rotation(weapon.get_rotation()+(-12.0 if power else 22.0)*amount)
		skeleton.update_world_transform(0)
		var turn=atan2(weapon.get_c(),weapon.get_a())-original_angle
		var target=Vector2(hand.get_world_x(),hand.get_world_y())-original_grip.rotated(turn)
		var local=weapon.world_to_parent(target);weapon.set_x(local.x);weapon.set_y(local.y)
		skeleton.update_world_transform(0)


func show_common(player,at: float,kind: String):
	if not effects_on or at<0 or at>=float(player.meta.duration):return
	player.visible=true;player.position=actor.position;player.scale=Vector2(-UNIT if mirrored else UNIT,UNIT)
	if kind=="ready":
		var bone=actor.sprite.get_skeleton().find_bone("mountbottom")
		if bone!=null:player.position=player.get_parent().to_local(actor.to_global(Vector2(bone.get_world_x(),bone.get_world_y())))
	player.show_time(at,true)


func follow_weapon(player,source_time: float,skill: String):
	var frames: Array=anchors[skill].frames
	var a: Array=frames[clampi(roundi(source_time*30),0,frames.size()-1)].mountweapon
	var source_basis:=Transform2D(Vector2(-float(a[2]),float(a[4])).normalized(),Vector2(-float(a[3]),float(a[5])).normalized(),Vector2(-6.0-float(a[0])*.01,float(a[1])*.01))
	if skill=="unique":source_basis.origin+=Vector2(2.5,.9536)
	var bone=actor.sprite.get_skeleton().find_bone("mountweapon")
	var target_basis:=Transform2D((actor.transform.basis_xform(Vector2(bone.get_a(),bone.get_c()))).normalized()*UNIT,(actor.transform.basis_xform(Vector2(bone.get_b(),bone.get_d()))).normalized()*UNIT,actor.transform*Vector2(bone.get_world_x(),bone.get_world_y()))
	# World lives in the clipped stage, while native bone globals include its
	# parent translation. Convert the final remap back to the player's parent.
	player.transform=target_basis*source_basis.affine_inverse()


func show_followup(player,source_time: float,ids: Array,alpha := 1.0,remap := false):
	if not effects_on or alpha<=0:return
	player.visible=true;player.position=actor.position+Vector2(-450 if mirrored else 450,0);player.scale=Vector2(-UNIT if mirrored else UNIT,UNIT);player.rotation=0
	player.modulate=Color(1,1,1,alpha);player.show_time(source_time,true,ids)
	if remap:follow_weapon(player,source_time,"unique" if player.meta.skill=="ability" else str(player.meta.skill))
	for i in player.nodes.size():
		player.nodes[i].transform=Transform2D.IDENTITY
		if not i in ids:player.nodes[i].visible=false
		else:player.shaders[i].set_shader_parameter("preview_gain",.8)
