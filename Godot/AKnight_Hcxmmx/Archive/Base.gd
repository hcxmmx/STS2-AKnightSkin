extends Control
const CoverScript=preload("res://AKnight_Hcxmmx/Archive/Scene.gd")
const VoiceScript=preload("res://AKnight_Hcxmmx/Archive/Voice.gd")
const SubtitleScript=preload("res://AKnight_Hcxmmx/Archive/Subtitle.gd")
const Settings=preload("res://AKnight_Hcxmmx/Archive/Settings.gd")
var cover
var actor
var voice
var subtitle
var touch: Control
var rng=RandomNumberGenerator.new()
var ready_ok:=false
var active:=false
var since_touch:=0.0
var idle_cooldown:=300.0
var interaction_cooldown:=0.0
var last_id:=""
var native_screen: Control
var native_states: Dictionary={}
var custom_ui: Control
var ui_font: Font
var gameplay: Dictionary={}
var bilingual: CheckBox
var home_settings: Dictionary
var exiting_tree:=false
var popup: Control

func _ready():
	add_to_group("aknight_archive_portraits")
	mouse_filter=Control.MOUSE_FILTER_IGNORE;clip_contents=true;rng.randomize();home_settings=Settings.read()
	cover=CoverScript.new();add_child(cover);cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	actor=cover.actor;ready_ok=actor!=null and actor.valid
	if not ready_ok:return
	voice=VoiceScript.new();add_child(voice);voice.actor=actor
	subtitle=SubtitleScript.new();subtitle.voice=voice;cover.canvas.add_child(subtitle)
	touch=Control.new();touch.mouse_filter=Control.MOUSE_FILTER_STOP;touch.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	touch.gui_input.connect(_on_touch);add_child(touch)
	ui_font=load("res://AKnight_Hcxmmx/Archive/fonts/hwzs.ttf")
	resized.connect(_layout)
func _layout():pass
func _style_button(button: Button):
	for state in ["normal","hover","pressed","focus"]:
		var style=StyleBoxFlat.new();style.bg_color=Color("282a25") if state=="normal" else Color("484034")
		style.border_color=Color("7e715d");style.set_border_width_all(1);style.content_margin_left=18;style.content_margin_right=18
		button.add_theme_stylebox_override(state,style)
	button.add_theme_color_override("font_color",Color("e7e4d9"))
func _remember(path: String) -> Control:
	if not is_instance_valid(native_screen):return null
	var node=native_screen.get_node_or_null(path) as Control
	if node!=null and not native_states.has(path):native_states[path]={"node":node,"position":node.position,"scale":node.scale,"visible":node.visible,"modulate":node.modulate}
	return node
func set_active(value: bool):
	active=value;visible=value
	if not exiting_tree and is_inside_tree():process_mode=Node.PROCESS_MODE_INHERIT if value else Node.PROCESS_MODE_DISABLED
	if value:
		actor.portrait_idle(0);_layout();_greet.call_deferred()
	else:
		if voice!=null:voice.stop_voice()
		for saved in native_states.values():
			if is_instance_valid(saved.node):saved.node.visible=saved.visible
		native_states.clear()
func _exit_tree():
	exiting_tree=true
	set_active(false)
func _greet():
	if active and ready_ok and is_visible_in_tree() and bool(home_settings.auto_greeting):play_line("1300705")
func _on_touch(event: InputEvent):
	if not event is InputEventMouseButton or not event.pressed:return
	if event.button_index not in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]:return
	touch.accept_event();since_touch=0
	if interaction_cooldown>0:return
	# Hotspots follow portrait-local coordinates; skin 300702 source rectangles.
	var point=actor.to_local(touch.get_global_mouse_position())*Vector2(1,-1)*.1
	var areas=[Rect2(-129.7,195.5,220.5,240.9),Rect2(-102,-233.4,169.9,237.9),Rect2(-210.4,-596.2,367,842.2)]
	var special=""
	for i in areas.size():
		if areas[i].has_point(point):special=["1300710","1300711","1300712"][i];break
	if event.button_index==MOUSE_BUTTON_LEFT and not special.is_empty() and last_id!=special and rng.randf()>.5:play_line(special)
	else:play_line(_normal_line())
	interaction_cooldown=float(home_settings.home_touch_interval)
func _normal_line() -> String:
	var choices: Array=[];var total:=0.0
	for id in voice.catalog:
		var r: Dictionary=voice.catalog[id]
		if int(r.type_id)==13 and id!=last_id:total+=float(r.weight);choices.append([id,total])
	var value=rng.randf()*total
	for item in choices:
		if value<=float(item[1]):return item[0]
	return "1300713"
func play_line(id: String) -> bool:
	if not active or not ready_ok:return false
	last_id=id;since_touch=0
	return voice.play_voice(id)
func reload_settings():
	home_settings=Settings.read();voice.reload_settings()
	interaction_cooldown=minf(interaction_cooldown,float(home_settings.home_touch_interval))
	subtitle.english_only=not bool(home_settings.bilingual_subtitles)
	if bilingual!=null:bilingual.set_pressed_no_signal(bool(home_settings.bilingual_subtitles))
func _process(delta: float):
	if not ready_ok or not active:return
	interaction_cooldown=maxf(0,interaction_cooldown-delta);since_touch+=delta;idle_cooldown+=delta
	if since_touch>=60 and idle_cooldown>=300 and not voice.playing:play_line("1300704");since_touch=0;idle_cooldown=0

func is_ready() -> bool:return ready_ok
func prepare_selection():set_active(false)
func set_audio_policy(gain_value: float,background_mute: bool):
	if voice!=null:voice.set_gain(gain_value);voice.mute_in_background=background_mute
