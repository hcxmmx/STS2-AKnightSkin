extends "res://AKnight_Hcxmmx/BattleStage.gd"

const Cuts=preload("res://AKnight_Hcxmmx/RhythmOnePlan.gd")
var rhythm_index:=0
var rhythm_players: Array=[]
var rhythm_records: Array=[{},{},{}]
var primary_fade:=1.0

func _players() -> Array:
	var result=super._players()
	for player in rhythm_players:
		if player not in result:result.append(player)
	return result

var cuts=Cuts.new()
var slash_groups: Array=[]

func _ready():
	super._ready()
	if not valid:return
	rhythm_players.append(skill1_fx)
	for i in 2:
		var player=Effects.new();add_child(player);player.initialize();player.visible_kinds.cast=false;player.visible=false;rhythm_players.append(player)
	_attach_native_fx()
	for i in 3:slash_groups.append(cuts.groups(i))

func start_slash(index: int):
	rhythm_index=index
	rhythm_records[index]={"at":0.0,"target":target_point}

func clear_rhythm():
	rhythm_records=[{},{},{}];stop_effects()

func tick_rhythm(delta: float):
	for i in rhythm_records.size():
		if rhythm_records[i].is_empty():continue
		rhythm_records[i].at+=delta
		if Cuts.FROM[i]+float(rhythm_records[i].at)>=3.4333334:rhythm_records[i]={}

func rhythm_active(index: int) -> bool:return index<rhythm_players.size() and not rhythm_records[index].is_empty()

func update_slash_target():
	if rhythm_active(rhythm_index):rhythm_records[rhythm_index].target=target_point

func render(kind: String,t: float):
	primary_fade=1.0
	var special=kind in ["rhythm_one","rhythm_two","cast_touch","power_raise"]
	if special:stop_effects()
	else:super.render(kind,t)
	if kind=="rhythm_one":
		var index=rhythm_index;var source: float=Cuts.FROM[index]+t;var end: float=Cuts.TO[index]
		var sign_value=-1.0 if mirrored else 1.0
		var dest=Plan.CENTER+Vector2(sign_value*maxf(0,sign_value*(target_point.x-Plan.CENTER.x)-375),target_point.y-660)
		var p=plan.pose("skill1_3",minf(source,end),dest)
		if source>=end:p=plan.blend(plan.pose("idle",source-end),p,source-end,.20)
		apply_pose(p);last_pose=p
	elif kind=="rhythm_two":
		var source=1.85+t;var p=plan.pose("skill2",minf(source,2.65))
		if source>=2.65:p=plan.blend(plan.pose("idle",source-2.65),p,source-2.65,.18)
		apply_pose(p);last_pose=p
		if source<4.0:
			show_followup(skill2_fx,source,range(23,61)+range(65,87))
			var span=(group_target_point-Plan.CENTER)/skill2_fx.scale
			var axis=Vector2(span.x/12.0,span.y/12.0)
			var scene_map=Transform2D(axis,Vector2(0,1),axis*6.0-Vector2(6,0))
			for i in skill2_fx.nodes.size():
				if skill2_fx.meta.groups[i].kind=="world":skill2_fx.nodes[i].transform=scene_map
			active_fx=skill2_fx
	elif kind in ["cast_touch","power_raise"]:
		var clip=plan.short_clip(kind)
		var source: float=float(clip.start)+t;var end: float=clip.end
		var fade=1.0-smoothstep(end,end+.10,source)
		var p=plan.short_pose(kind,t)
		apply_pose(p);last_pose=p
		if source<end+.10:
			show_followup(skill2_fx,minf(source,end),range(0,23)+range(61,65),fade)
			active_fx=skill2_fx;primary_fade=fade
	_render_slashes()
	if special or not rhythm_records.all(func(record):return record.is_empty()):_sync_fields()

func _render_slashes():
	for i in rhythm_players.size():
		if rhythm_records[i].is_empty():continue
		var player=rhythm_players[i];var record: Dictionary=rhythm_records[i]
		player.visible=true;player.modulate=Color.WHITE
		player.transform=Transform2D(Vector2(-75 if mirrored else 75,0),Vector2(0,75),Plan.CENTER+Vector2(-450 if mirrored else 450,0))
		player.show_time(Cuts.FROM[i]+float(record.at),true,slash_groups[i])
		var default_target=Plan.CENTER+Vector2(-900 if mirrored else 900,0)
		var correction=(Vector2(record.target)-default_target)/Vector2(-75 if mirrored else 75,75)
		var ids=slash_groups[i]
		for j in ids:
			player.nodes[j].position=correction if player.meta.groups[j].prefab=="target" else Vector2.ZERO
