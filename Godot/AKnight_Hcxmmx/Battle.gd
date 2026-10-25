extends Node2D

const Stage=preload("res://AKnight_Hcxmmx/BattleRhythmStage.gd")
const Cuts=preload("res://AKnight_Hcxmmx/RhythmOnePlan.gd")
const Audio=preload("res://AKnight_Hcxmmx/CombatAudio.gd")
const Glow=preload("res://AKnight_Hcxmmx/Runtime/EffectGlow.gd")
const Tempo=preload("res://AKnight_Hcxmmx/FullTempo.gd")
const Settings=preload("res://AKnight_Hcxmmx/Settings.gd")
var preferences: Dictionary
var glow_amount:=.35
var ultimate
var bound_card_active:=false
var pending_victory:=false
var selection_ultimate:=false
var stage
var sound
var glow
var overlay_host: Control
var overlay_anchor: Node2D
var refraction_copy: BackBufferCopy
var refraction: ColorRect
var original_body: Node2D
var original_visible:=true
var original_color:=Color.WHITE
var ready_ok:=false
var configured:=false
var local_voice:=true
var dead:=false
var victorious:=false
var entry_started:=false
var kind:="idle"
var time:=0.0
var clock:=0.0
var base_position:=Vector2.ZERO
var factor:=.75
var selection_ticket:=-1
var selection_since:=0.0
var selection_upgraded:=false
var selection_spoken:=false
var selection_cooldown:=0.0
var selection_counter:=0
var last_card:=""
var last_card_time:=-100.0
var targets: Array=[]
var target_anchor:=Vector2.ZERO
var attack_group:=false
var attack_random:=false
var held_card_kind:=""
var suppress_trigger_until:=0.0
var presentation_mode:="rhythm"
var slash_cursor:=0
var slash_index:=0
var ultimate_cursor:=0
var ultimate_style:="full"
var cast_cursor:=0
var power_cursor:=0
var rhythm_glows: Array=[]
var attack_voice_cycle:=0
var old_pose: Dictionary={}
var blend_clock:=0.0
var tail: Dictionary={}
var feather_serial:=0
var feather_ticket:=0
var feather_records: Dictionary={}
var feather_bursts: Array=[]

func _ready():
	add_to_group("aknight_battles")
	stage=Stage.new();add_child(stage);ready_ok=stage.valid
	if not ready_ok:return
	sound=Audio.new();add_child(sound)
	preferences=Settings.read();presentation_mode=preferences.mode
	# Native VFX layers protect the HUD; there is no artificial combat-band crop.
	var canvas:=CanvasLayer.new();canvas.layer=1;add_child(canvas)
	overlay_anchor=Node2D.new();canvas.add_child(overlay_anchor)
	overlay_host=Control.new();overlay_host.mouse_filter=Control.MOUSE_FILTER_IGNORE;overlay_anchor.add_child(overlay_host)
	glow=Glow.new();add_child(glow);glow.initialize(overlay_host)
	for i in 3:
		var extra=Glow.new();add_child(extra);extra.initialize(overlay_host);extra.overlay.z_index=1;extra.sync(null,false);rhythm_glows.append(extra)
	# Waterfall and other native screen-reading scenery can fill the shared
	# screen texture before creatures are drawn. Snapshot this pass's actual
	# input immediately before refraction, and only while it is active.
	refraction_copy=BackBufferCopy.new();refraction_copy.copy_mode=BackBufferCopy.COPY_MODE_VIEWPORT
	refraction_copy.z_index=-1;overlay_host.add_child(refraction_copy);refraction_copy.visible=false
	refraction=ColorRect.new();refraction.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var sm:=ShaderMaterial.new();sm.shader=load("res://AKnight_Hcxmmx/Runtime/combat_refraction.gdshader");refraction.material=sm
	refraction.z_index=-1;overlay_host.add_child(refraction);refraction.visible=false
	_refresh_overlay();reload_settings()

func _ultimate_settings():
	if not is_instance_valid(ultimate):return
	ultimate.glow_strength=glow_amount;ultimate.glow.brightness=float(preferences.brightness)

func reload_settings():
	preferences=Settings.read()
	if configured and presentation_mode!=preferences.mode:set_presentation_mode(preferences.mode,false)
	else:presentation_mode=preferences.mode
	glow_amount=float(preferences.glow_strength)
	for light in [glow]+rhythm_glows:
		light.brightness=float(preferences.brightness);light.strength=glow_amount
	sound.voice_enabled=bool(preferences.combat_voice);sound.voice_interval=float(preferences.combat_voice_interval)
	sound.voice_cooldown=minf(sound.voice_cooldown,sound.voice_interval)
	sound.voice_gain=float(preferences.voice_volume);sound.sfx_gain=float(preferences.sfx_volume)
	sound.sfx.enabled=bool(preferences.original_sfx)
	if not sound.voice_enabled:sound.voice.stop();sound.selection_voice=false
	if not sound.sfx.enabled:sound.sfx.stop()
	_ultimate_settings()
	if configured and not preferences.ultimate_enabled and bound_card_active:
		if is_instance_valid(ultimate):ultimate.cancel()
		sound.stop();_start("idle")
		if pending_victory:pending_victory=false;request_victory()

func is_ready() -> bool:return ready_ok

func configure(body: Node2D,bounds_position: Vector2,bounds_size: Vector2,audible: bool) -> bool:
	if not ready_ok or bounds_size.x<=0 or bounds_size.y<=0:return false
	original_body=body;original_visible=body.visible;original_color=body.modulate;local_voice=audible
	var bounds: Rect2=stage.actor.bounds();var desired:=Rect2(bounds_position,bounds_size)
	factor=minf(desired.size.x*.95/bounds.size.x,desired.size.y/bounds.size.y)
	base_position=Vector2(desired.get_center().x+bounds.get_center().x*factor,desired.end.y-bounds.end.y*factor)
	configured=true;RenderingServer.frame_pre_draw.connect(_hide_original);_hide_original()
	var native_front=_native_front()
	if native_front!=null:
		overlay_anchor.reparent(native_front,false);glow.overlay.z_index=1;refraction.z_index=0;refraction_copy.z_index=0
	# Prepare once at encounter setup, rather than synchronously on the first card.
	var warmup=get_tree().get_first_node_in_group("aknight_combat_warmup")
	var ultimate_host=native_front if native_front!=null else self
	if warmup!=null:ultimate=warmup.take(ultimate_host)
	if ultimate==null:
		ultimate=load("res://AKnight_Hcxmmx/Ultimate.gd").new()
		ultimate_host.add_child(ultimate)
	_ultimate_settings()
	for variant in ["normal","unique"]:_new_feather(variant)
	for player in [stage.entry,stage.ready_fx,stage.skill1_fx,stage.skill2_fx,stage.unique_fx]:glow.prepare(player)
	for i in 3:
		rhythm_glows[i].prepare(stage.rhythm_players[i])
		stage.rhythm_players[i].prepare_frames([Cuts.FROM[i],Cuts.FROM[i]+1.0/30.0])
	stage.skill1_fx.prepare_frames([0.0])
	stage.skill2_fx.prepare_frames([0.0,.2,1.05,1.25,1.85])
	stage.unique_fx.prepare_frames([2.65])
	stage.entry.prepare_frames([0.0]);stage.ready_fx.prepare_frames([0.0])
	sound.prepare()
	_update_mapping();_start("entry");entry_started=true
	if local_voice:sound.speak(["1300720"],true)
	return true

func _refresh_overlay():
	var size_value=get_viewport_rect().size
	if overlay_anchor.get_parent() is CanvasItem:overlay_anchor.global_transform=get_viewport().get_canvas_transform().affine_inverse()
	overlay_host.position=Vector2.ZERO;overlay_host.size=size_value
	overlay_host.clip_contents=false
	refraction.position=Vector2.ZERO;refraction.size=overlay_host.size
	refraction.material.set_shader_parameter("stage_rect",Vector4(0,0,1,1))
	var half:=Vector2i(size_value*.5)
	for light in [glow]+rhythm_glows:
		light.overlay.size=overlay_host.size
		for vp in [light.capture,light.blur_h,light.blur_v]:vp.size=half
		light.capture.canvas_transform=get_viewport().get_canvas_transform().scaled(Vector2(.5,.5))
		for vp in [light.blur_h,light.blur_v]:vp.get_child(0).size=size_value*.5

func set_presentation_mode(value: String,persist:=true):
	if value not in ["full","rhythm"]:return
	presentation_mode=value;slash_cursor=0;ultimate_cursor=0;cast_cursor=0;power_cursor=0
	selection_ticket=-1;tail.clear();stage.clear_rhythm();sound.stop();sound.voice_cooldown=0
	if ultimate!=null:ultimate.cancel()
	if not dead and not victorious:_start("idle")
	if pending_victory:pending_victory=false;request_victory()
	if persist:
		Settings.write("mode",value)
		preferences.mode=value
	_sync_overlay()

func _unhandled_key_input(event: InputEvent):
	if configured and local_voice and event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_F8:
		set_presentation_mode("full" if presentation_mode=="rhythm" else "rhythm")
		get_viewport().set_input_as_handled()

func _sync_overlay():
	var primary=stage.active_fx
	glow.strength=glow_amount*stage.primary_fade;glow.sync(primary,primary!=null and primary.visible)
	var weights=Vector4.ZERO
	refraction.material.set_shader_parameter("field_0",(primary if primary!=null else stage.skill1_fx).field_viewport.get_texture())
	weights.x=1.0 if primary!=null and primary.visible and primary.field_viewport.render_target_update_mode!=SubViewport.UPDATE_DISABLED else 0.0
	for i in 3:
		var player=stage.rhythm_players[i] if i<stage.rhythm_players.size() else stage.skill1_fx
		var active=stage.rhythm_active(i) and player.visible
		rhythm_glows[i].sync(player,active)
		refraction.material.set_shader_parameter("field_"+str(i+1),player.field_viewport.get_texture())
		weights[i+1]=1.0 if active and player.field_viewport.render_target_update_mode!=SubViewport.UPDATE_DISABLED else 0.0
	refraction.material.set_shader_parameter("active_fields",weights)
	refraction.visible=weights!=Vector4.ZERO
	refraction_copy.visible=refraction.visible

func _native_front() -> Node:
	var ancestor: Node=get_parent()
	while ancestor!=null:
		var candidate=ancestor.get_node_or_null("CombatVfxContainer")
		if candidate is CanvasItem:return candidate
		ancestor=ancestor.get_parent()
	return null

func _update_mapping():
	stage.scale=Vector2.ONE*(factor/.75)
	stage.mirrored=is_instance_valid(original_body) and original_body.scale.x<0
	stage.position=base_position-stage.scale*Vector2(620,660)
	var aim=base_position+Vector2(900*factor/.75,0)
	if stage.mirrored:aim=base_position-Vector2(900*factor/.75,0)
	var far_aim=aim
	if not targets.is_empty():
		var far_distance:=-1.0
		for i in targets.size():
			var row: Dictionary=targets[i]
			var point=Vector2(row.ground)
			if row.has("ref") and is_instance_valid(row.ref.get_ref()):point+=row.ref.get_ref().global_position-Vector2(row.anchor)
			point=to_local(point)
			if i==0:aim=point
			var distance=absf(point.x-base_position.x)
			if distance>far_distance:far_distance=distance;far_aim=point
	stage.target_point=(aim-stage.position)/stage.scale
	stage.group_target_point=(far_aim-stage.position)/stage.scale

func _snapshot(rows: Array):
	targets.clear()
	for row in rows:
		var item: Dictionary=row.duplicate()
		if item.has("node"):
			var node=item.node
			if is_instance_valid(node):item.ref=weakref(node);item.anchor=node.global_position
			item.erase("node")
		targets.append(item)

func full_action(action: String) -> bool:
	return presentation_mode=="full" and Tempo.has(action)

func source_time(action: String,wall: float) -> float:
	return Tempo.sample(action,wall) if full_action(action) else wall

func action_duration(action: String) -> float:
	if full_action(action):return Tempo.duration(action)
	if action in ["cast_touch","power_raise"]:return stage.plan.short_duration(action)
	if action=="rhythm_one":return Cuts.TO[slash_index]-Cuts.FROM[slash_index]+.20
	return float({"entry":2.8,"skill1":4.1,"skill2":4.0,"rhythm_two":.98,"cast_b":2.5,"power_a":2.5,"power_b":2.65,"hit":.85,"relaxed":4.2}.get(action,INF))

func _start(next: String):
	if next!="ultimate" and ultimate!=null and ultimate.active:ultimate.cancel()
	if next!="ultimate":bound_card_active=false
	if next in ["entry","die","victory","ultimate"]:stage.clear_rhythm()
	if next=="hit" and kind in ["skill1","skill2","rhythm_two"]:tail={"kind":kind,"at":time,"cutoff":source_time(kind,time),"full":full_action(kind)}
	elif next not in ["hit","idle"]:tail.clear()
	old_pose=stage.last_pose.duplicate();blend_clock=0;kind=next;time=0
	stage.interrupted_at=INF;stage.stop_effects();sound.release_selection_voice()
	if next!="idle":sound.sfx.stop()
	if next=="rhythm_one":stage.start_slash(slash_index)
	stage.render(kind,0)
	if next=="idle" and not tail.is_empty():stage.render_tail(tail.kind,Tempo.sample(tail.kind,tail.at) if bool(tail.get("full",false)) else float(tail.at),tail.cutoff)
	if full_action(next):sound.start_full_sfx(next)
	elif next in ["skill1","skill2"]:sound.start_sfx(next)
	elif next in ["rhythm_one","rhythm_two"]:sound.start_rhythm_sfx(next,slash_index)
	elif next=="ultimate":
		if ultimate_style=="full":sound.start_full_sfx("unique")
		else:sound.start_rhythm_sfx("ultimate_"+ultimate_style)
	elif next=="ready":sound.start_sfx("posture")
	elif next=="die":sound.start_sfx("die")
	elif next in ["cast_touch","power_raise","cast_b","power_a"]:sound.start_sfx("posture")
	elif next=="power_b":sound.start_sfx("born")

func _card_action(card_type: String,target_type: String) -> String:
	if card_type=="Attack":
		if presentation_mode=="full":return "skill2" if target_type in ["AllEnemies","RandomEnemy"] else "skill1"
		if target_type in ["AllEnemies","RandomEnemy"]:return "rhythm_two"
		slash_index=slash_cursor%3;slash_cursor+=1;return "rhythm_one"
	if card_type=="Power":
		var action=["power_raise","power_a","power_b"][power_cursor%3];power_cursor+=1;return action
	var action=["cast_touch","cast_b"][cast_cursor%2];cast_cursor+=1;return action

func card_played(card_id: String,card_type: String,target_type: String,rows: Array=[],visual_ticket: int=0):
	if not configured or dead or victorious:return
	selection_ticket=-1;_snapshot(rows);last_card=card_id;last_card_time=clock
	attack_random=target_type=="RandomEnemy";attack_group=target_type=="AllEnemies" or attack_random
	_update_mapping()
	bound_card_active=bool(preferences.ultimate_enabled) and card_id==str(preferences.ultimate_card)
	if bound_card_active:
		var mode_value: String=presentation_mode if preferences.ultimate_mode=="follow" else str(preferences.ultimate_mode)
		ultimate_style="full" if mode_value=="full" else ("first" if ultimate_cursor%2==0 else "second")
		ultimate_cursor+=1
	held_card_kind="ultimate" if bound_card_active else _card_action(card_type,target_type)
	_start(held_card_kind);suppress_trigger_until=clock+.45
	if bound_card_active:
		if ultimate==null:
			ultimate=load("res://AKnight_Hcxmmx/Ultimate.gd").new()
			var host=_native_front()
			(host if host!=null else self).add_child(ultimate)
		_ultimate_settings();ultimate.start(stage.actor,ultimate_style)
	_speak_action()
	bind_feather(visual_ticket)

func attack_targets(rows: Array,multi: bool,random: bool=false):
	if not configured or dead or victorious:return
	if not rows.is_empty():_snapshot(rows)
	attack_random=random;attack_group=multi or random
	if kind=="skill1" and time<.15 and attack_group:held_card_kind="skill2";_start("skill2")
	if kind=="rhythm_one" and time<.15 and attack_group:
		stage.rhythm_records[slash_index]={};held_card_kind="rhythm_two";_start("rhythm_two")
	if held_card_kind in ["skill2","rhythm_two"]:feather_records.erase(feather_ticket)

func actual_targets(card_id: String,rows: Array):
	# Keep the existing broad scene placement for random attacks. No extra
	# candidate fitting, and no snapping onto each individual random hit.
	if attack_random:return
	if not dead and not victorious and (card_id==last_card or card_id.is_empty()) and kind in ["skill1","skill2","rhythm_one","rhythm_two"] and not rows.is_empty():
		_snapshot(rows);_update_mapping()
		if kind=="rhythm_one":stage.update_slash_target()

func _speak_action():
	if not local_voice:return
	if kind in ["skill1","rhythm_one"]:sound.speak(["1300725","1300726"])
	elif kind=="ultimate":
		if ultimate_style=="full":sound.speak(["1300729"],true)
		else:sound.speak_ultimate_line(0 if ultimate_style=="first" else 1)
	elif kind in ["skill2","rhythm_two"]:sound.speak(["1300727","1300728"])
	elif kind=="cast_touch":sound.speak(["1300721"])
	elif kind=="power_raise":sound.speak(["1300724"])
	elif kind=="cast_b":sound.speak(["1300721"])
	elif kind=="power_a":sound.speak(["1300724"])
	elif kind=="power_b":sound.speak(["1300726"])

func heavy_attack():
	# Native card animation arrives shortly after the card-start notification.
	# Promote that same action even during the duplicate-trigger suppression window.
	if bound_card_active:return
	if clock<suppress_trigger_until:
		if held_card_kind in ["rhythm_two","skill2"]:return
		if held_card_kind=="rhythm_one":
			stage.rhythm_records[slash_index]={};slash_cursor=maxi(0,slash_cursor-1)
	feather_records.erase(feather_ticket)
	held_card_kind="skill2" if presentation_mode=="full" else "rhythm_two"
	_start(held_card_kind);suppress_trigger_until=clock+.45
	sound.voice_cooldown=0;_speak_action()

func handle_trigger(trigger: String):
	if not configured or dead or victorious:return
	if bound_card_active and trigger in ["Attack","AttackSingle","AttackTriple","heavyAttack","Cast","PowerUp","Idle"]:return
	match trigger:
		"heavyAttack":heavy_attack()
		"Dead","Die","Death":
			dead=true;selection_ticket=-1;sound.stop();_start("die")
		"Attack","AttackSingle","AttackTriple","Cast","PowerUp":
			if clock<suppress_trigger_until:return
			selection_ticket=-1
			var next=_card_action("Attack","AllEnemies" if attack_group else "AnyEnemy") if trigger not in ["Cast","PowerUp"] else _card_action("Power" if trigger=="PowerUp" else "Skill","")
			_start(next);_speak_action()
		"Hit":
			selection_ticket=-1;_start("hit")
			if local_voice:sound.speak(["1300730","1300731"],false,true)
		"Intro":
			if not entry_started:entry_started=true;_start("entry")
		"Relaxed":
			if kind=="idle":_start("relaxed")

func card_selection_begin(ticket: int,_id: String,upgraded: bool):
	if not configured or not local_voice or dead or victorious:return
	selection_ticket=ticket;selection_since=clock;selection_upgraded=upgraded;selection_spoken=false
	selection_ultimate=bool(preferences.ultimate_enabled) and _id==str(preferences.ultimate_card)

func card_selection_end(ticket: int,_committed: bool):
	if ticket!=selection_ticket:return
	selection_ticket=-1;sound.release_selection_voice()
	if kind=="ready":_start("idle")

func request_victory():
	if not configured or dead or victorious:return
	if ultimate!=null and ultimate.active:pending_victory=true;selection_ticket=-1;return
	victorious=true;selection_ticket=-1;sound.stop();_start("victory")
	if local_voice:sound.speak(["1300732"],true)

func set_audio_policy(gain_value: float,background_mute: bool):
	if sound!=null:sound.gain=gain_value;sound.mute_in_background=background_mute

func stop_voice():
	sound.voice.stop();sound.selection_voice=false

func uses_original_sfx() -> bool:return sound!=null and sound.sfx.enabled

func _process(delta: float):
	if not configured:return
	clock+=delta;blend_clock+=delta;var previous=time;time+=delta
	stage.tick_rhythm(delta)
	_hide_original();_update_mapping();_refresh_overlay()
	if ultimate!=null and ultimate.active:
		glow.sync(null,false);refraction.visible=false;refraction_copy.visible=false
		for extra in rhythm_glows:extra.sync(null,false)
		ultimate.tick(delta);sound.tick(previous,time,delta)
		_tick_feathers()
		if not ultimate.active:
			_start("idle")
			if pending_victory:pending_victory=false;request_victory()
		return
	if kind=="entry" and previous<.8 and time>=.8:sound.start_sfx("born")
	if selection_ticket>=0 and kind=="idle":_start("ready")
	if selection_ticket>=0 and kind=="ready" and not selection_spoken and clock-selection_since>=.12 and clock>=selection_cooldown and not sound.voice.playing:
		selection_counter+=1;selection_spoken=true;selection_cooldown=clock+.8
		sound.speak(["1300724"] if selection_ultimate else (["1300723"] if selection_upgraded else ["1300721" if selection_counter%2 else "1300722"]),true,false,true)
	stage.render(kind,source_time(kind,time))
	if not tail.is_empty():
		tail.at+=delta
		var full_tail: bool=bool(tail.get("full",false))
		var end: float=Tempo.duration(tail.kind) if full_tail else (4.1 if tail.kind=="skill1" else (2.15 if tail.kind=="rhythm_two" else 4.0))
		var source: float=Tempo.sample(tail.kind,tail.at) if full_tail else float(tail.at)
		if float(tail.at)<end:stage.render_tail(tail.kind,source,tail.cutoff)
		else:tail.clear()
	if blend_clock<.12 and not old_pose.is_empty() and kind not in ["entry","die"]:
		var p: Dictionary=stage.last_pose.duplicate();p["from"]=old_pose.animation;p.from_at=old_pose.at;p.mix=blend_clock;p.mix_duration=.12
		p.position=old_pose.position.lerp(p.position,smoothstep(0,.12,blend_clock));stage.apply_pose(p)
	_sync_overlay()
	_tick_feathers()
	sound.tick(previous,time,delta)
	var duration_value: float=action_duration(kind)
	if time>=duration_value:
		if kind=="rhythm_two":tail={"kind":kind,"at":time,"cutoff":INF}
		_start("idle")

func _hide_original():
	if is_instance_valid(original_body):original_body.show();original_body.modulate=Color(original_body.modulate,0)

func _exit_tree():
	for burst in feather_bursts:
		if is_instance_valid(burst):burst.queue_free()
	if is_instance_valid(ultimate):ultimate.cancel();ultimate.queue_free()
	if is_instance_valid(overlay_anchor):overlay_anchor.queue_free()
	if RenderingServer.frame_pre_draw.is_connected(_hide_original):RenderingServer.frame_pre_draw.disconnect(_hide_original)
	if sound!=null:sound.stop()
	if configured and is_instance_valid(original_body):original_body.visible=original_visible;original_body.modulate=original_color

func _new_feather(variant: String):
	var burst=load("res://AKnight_Hcxmmx/FeatherBurst.gd").new()
	var host=_native_front();(host if host!=null else self).add_child(burst)
	burst.initialize(variant);feather_bursts.append(burst)
	return burst

func bind_feather(ticket: int=0):
	feather_serial=maxi(feather_serial+1,ticket);feather_ticket=ticket if ticket>0 else feather_serial
	if kind not in ["skill1","rhythm_one","ultimate"]:return
	var due=action_duration(kind)
	var variant="normal"
	if kind=="skill1":due=Tempo.inverse("skill1",2.9966667) if presentation_mode=="full" else 2.9966667
	elif kind=="ultimate":
		variant="unique"
		due=Tempo.inverse("unique",11.3333333) if ultimate_style=="full" else ultimate.duration()
	feather_records[feather_ticket]={"variant":variant,"due":clock+due,"killed":false}

func feather_kill(ticket: int):
	if dead or not feather_records.has(ticket):return
	feather_records[ticket].killed=true
	_tick_feathers()

func feather_finished(ticket: int):
	if feather_records.has(ticket) and not feather_records[ticket].killed:feather_records.erase(ticket)

func _tick_feathers():
	if dead:
		feather_records.clear()
		for burst in feather_bursts:burst.stop()
		return
	for ticket in feather_records.keys():
		var record: Dictionary=feather_records[ticket]
		if not record.killed or clock<record.due:continue
		var source=stage.actor
		if is_instance_valid(ultimate) and ultimate.active and ultimate.actor.visible:source=ultimate.actor
		var available=null
		for burst in feather_bursts:
			if burst.variant==record.variant and not burst.active:available=burst;break
		if available==null:available=_new_feather(record.variant)
		available.play_at(source.get_global_transform_with_canvas(),float(preferences.brightness),glow_amount)
		feather_records.erase(ticket)
