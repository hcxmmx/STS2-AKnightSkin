extends Node

const Tempo=preload("res://AKnight_Hcxmmx/FullTempo.gd")
const Sfx=preload("res://AKnight_Hcxmmx/Runtime/CombatSfx.gd")
var sfx
var voice: AudioStreamPlayer
var records: Dictionary
static var streams: Dictionary={}
var gain:=1.0
var voice_gain:=.8
var sfx_gain:=.8
var voice_enabled:=true
var mute_in_background:=true
var voice_cooldown:=0.0
var voice_interval:=4.0
var selection_voice:=false
var counter:=0
var effect_time:=0.0
var unique_clips: Array=[]

func _ready():
	records=JSON.parse_string(FileAccess.get_file_as_string("res://AKnight_Hcxmmx/Runtime/combat_voice.json")).records
	voice=AudioStreamPlayer.new();add_child(voice)
	sfx=Sfx.new();add_child(sfx)
	unique_clips=JSON.parse_string(FileAccess.get_file_as_string("res://AKnight_Hcxmmx/Runtime/unique_sentences.json")).clips
	var full_clips: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://AKnight_Hcxmmx/Runtime/full_tempo_sfx.json")).clips
	for id in full_clips:sfx.catalog.clips[id]=full_clips[id]

func prepare(progressive:=false):
	for record in records.values():
		var clips: Array=[record.audio]+record.combat_audio
		for clip in clips:
			if not streams.has(clip.file):
				streams[clip.file]=AudioStreamWAV.load_from_file(clip.file, {})
				if progressive:await get_tree().process_frame
	for clip in unique_clips:
		if not streams.has(clip.file):
			streams[clip.file]=AudioStreamWAV.load_from_file(clip.file, {})
			if progressive:await get_tree().process_frame
	for id in sfx.catalog.clips:
		if not sfx.streams.has(id):
			sfx.streams[id]=AudioStreamWAV.load_from_file(sfx.catalog.clips[id].file, {})
			if progressive:await get_tree().process_frame

func speak(ids: Array, priority:=false, hit:=false, selection:=false):
	if not voice_enabled or (voice_cooldown>0 and not priority):return
	var id: String=str(ids[counter%ids.size()]);counter+=1
	var record: Dictionary=records[id]
	var clip: Dictionary=record.combat_audio[counter%record.combat_audio.size()] if hit and not record.combat_audio.is_empty() else record.audio
	_play_clip(clip)
	selection_voice=selection
	if not selection:voice_cooldown=voice_interval

func _play_clip(clip: Dictionary):
	if not streams.has(clip.file):streams[clip.file]=AudioStreamWAV.load_from_file(clip.file, {})
	voice.stop();voice.stream=streams[clip.file];voice.play()

func speak_ultimate_line(index: int):
	if not voice_enabled:return
	_play_clip(unique_clips[index]);selection_voice=false;voice_cooldown=voice_interval

func release_selection_voice():
	if selection_voice:voice.stop();selection_voice=false

func start_sfx(kind: String):
	effect_time=0
	sfx.stop();sfx.cues.clear();sfx.fired.clear();sfx.duration=0
	if kind in ["skill1","skill2","unique"]:
		sfx.configure({"skill1":2,"skill2":3,"unique":4}[kind],"",counter)
	elif sfx.catalog.actions.has(kind):sfx._add(str(sfx.catalog.actions[kind]),0)
	sfx.sync(0,true)

func start_full_sfx(kind: String):
	effect_time=0;sfx.stop();sfx.cues.clear();sfx.fired.clear();sfx.duration=0
	sfx._add("full_"+kind,0)
	if kind in ["skill1","skill2","unique"]:
		var skill: Dictionary=sfx.catalog.skills[kind]
		for i in skill.hits.size():
			var choices: Array=skill.hit_variants
			sfx._add(str(choices[(counter+i)%choices.size()]),Tempo.inverse(kind,float(skill.hits[i])))
	sfx.sync(0,true)

func start_rhythm_sfx(kind: String,index:=0):
	effect_time=0;sfx.stop();sfx.cues.clear();sfx.fired.clear();sfx.duration=0
	var key={"rhythm_one":"rhythm_one_"+str(index+1),"rhythm_two":"rhythm_two","ultimate_first":"rhythm_unique_first","ultimate_second":"rhythm_unique_second"}[kind]
	sfx._add(key,0)
	if kind=="rhythm_one":sfx._add("sword_hit_"+str(index+1),[.1166667,.1133333,.1][index])
	elif kind=="rhythm_two":sfx._add("sword_hit_1",.0833333)
	elif kind=="ultimate_first":sfx._add("sword_hit_1",.1)
	else:
		for i in 4:
			var source: float=[8.5,8.7,8.9,9.8666667][i]
			sfx._add("sword_hit_"+str(i%3+1),source-8.17 if source<=9.15 else .98+(source-9.15)/2.2)
	sfx.sync(0,true)

func tick(previous: float,at: float,delta: float):
	voice_cooldown=maxf(0,voice_cooldown-delta)
	var old=effect_time;effect_time+=delta
	sfx.advance(old,effect_time,true)

func stop():
	voice.stop();sfx.stop();selection_voice=false

func _process(_delta):
	var audible=not mute_in_background or DisplayServer.window_is_focused()
	voice.volume_db=linear_to_db(maxf(.0001,gain*voice_gain)) if audible else -80
	sfx.gain=gain*sfx_gain;sfx.update_volume(audible)
