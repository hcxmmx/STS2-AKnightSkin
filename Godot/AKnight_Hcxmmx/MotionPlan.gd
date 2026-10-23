extends RefCounted

# Review-only visual edits, with source clip times kept explicit. None of these
# choices selects STS2 card behavior or changes the accepted full skill previews.
const MODES = ["战前入场", "普通选咒 → 取消", "高阶选咒 → 取消", "至终选咒 → 取消", "选咒 → 一技能 → 待机", "一技能 → 受击 → 待机", "二技能 → 受击 → 待机", "受击 → 死亡", "胜利 → 保持", "", "技能B · 姿态与手势重组", "能力A · 大招立剑剪辑", "能力B · 姿态与披风重组"]
const CENTER=Vector2(620,660)
const BATTLE=Vector2(300,660)
var mode := 0
var cycle := 0

func duration() -> float:
	return [5.5,3.8,4.5,4.5,7.0,5.5,5.0,4.8,6.3,4.0,3.6,4.3,4.0][mode]

func ordinary_voice() -> String:return "1300721" if cycle%2==0 else "1300722"

func voices() -> Array:
	match mode:
		0:return [[0.0,"1300720",false]]
		1,2,3:return [[.52,[ordinary_voice(),"1300723","1300724"][mode-1],false]]
		4:return [[.52,ordinary_voice(),false],[2.1,"1300725" if cycle%2==0 else "1300726",false]]
		5:return [[.4,"1300725",false],[2.0,"1300730",true]]
		6:return [[.4,"1300727",false],[1.85,"1300731",true]]
		7:return [[.5,"1300730",true]]
		8:return [[.35,"1300732",false]]
		10:return [[.3,"1300721",false]]
		11:return [[.3,"1300724",false]]
		12:return [[.3,"1300726",false]]
	return []

func sfx() -> Array:
	match mode:
		0:return [[.8,"born"]]
		1,2,3:return [[.4,"posture"]]
		4:return [[.4,"posture"],[2.1,"skill1"],[3.266667,"sword_hit_1"],[3.583333,"sword_hit_2"],[4.2,"sword_hit_3"]]
		5:return [[.4,"skill1",2.0],[1.566667,"sword_hit_1"],[1.883333,"sword_hit_2"]]
		6:return [[.4,"skill2",1.85]]
		7:return [[1.2,"die"]]
		10,11:return [[.2,"posture"]]
		12:return [[.2,"born"]]
	return []

func info() -> String:
	match mode:
		0:return "公共入场光效 → 0.7秒显现 → born → 待机；战前原声。"
		1,2,3:return "公共选咒光圈与暖金短闪；posture持续等待，取消后回待机。"
		4:return "选咒在2.1秒交给出手；剪辑接续不等待原选咒动作播完。"
		5,6:return "攻击中受击：动作交给hit，已飞出的旧特效继续收尾。"
		7:return "hit被die接管；死亡姿态保持，旧光效和语音清理。"
		8:return "胜利原动作播完后保持；不强制回待机。"
		10:return "候选重组：待机＋双手骨骼小幅手势；剑光实时跟随新姿态。"
		11:return "候选剪辑：unique的2.65～4.05秒，立剑蓄势后回待机，不带场景斩击。"
		12:return "候选重组：posture＋披风/手臂小幅运动，配公共升光与跟随剑光。"
	return ""

func pose(name_value: String, at: float, pos := CENTER) -> Dictionary:
	return {"animation":name_value,"at":maxf(0,at),"position":pos,"from":"","from_at":0.0,"mix":1.0,"procedural":"","pulse":0.0}

func blend(to: Dictionary, previous: Dictionary, elapsed: float, length := .18) -> Dictionary:
	if elapsed<length:
		to["from"]=previous.animation;to.from_at=previous.at;to.mix=maxf(0,elapsed);to.mix_duration=length
		to.position=previous.position.lerp(to.position,smoothstep(0,length,elapsed))
	return to

# Short visual excerpts: finish with a held source pose mixed into live idle.
# The blend changes only presentation time, never the card's native wait.
func short_clip(kind: String) -> Dictionary:
	return {"start":.2,"end":.85,"return":.24} if kind=="cast_touch" else {"start":1.05,"end":1.65,"return":.30}

func short_duration(kind: String) -> float:
	var clip=short_clip(kind)
	return float(clip.end)-float(clip.start)+float(clip["return"])

func short_pose(kind: String,at: float) -> Dictionary:
	var clip=short_clip(kind)
	var source: float=float(clip.start)+maxf(0,at)
	var ending: float=clip.end
	if source<ending:return pose("skill2",source)
	return blend(pose("idle",source-ending),pose("skill2",ending),source-ending,float(clip["return"]))

func action(name_value: String, at: float, length: float, pos := CENTER, hold := false) -> Dictionary:
	if at<0:return pose("idle",at,pos)
	if at<length:return blend(pose(name_value,at,pos),pose("idle",0,pos),at)
	if hold:return pose(name_value,length-.0001,pos)
	return blend(pose("idle",at-length,pos),pose(name_value,length,pos),at-length)

func ready(at: float) -> Dictionary:
	if at<0:return pose("idle",at)
	return blend(pose("posture",fposmod(at,1.0666667)),pose("idle",0),at,.16)

func skill1(at: float) -> Dictionary:
	var pos=BATTLE+Vector2(525,0) if at>=.1 and at<2.6666667 else BATTLE
	return action("skill1_3",at,3.4333334,pos)

func sample(t: float) -> Dictionary:
	match mode:
		0:return action("born",t-.8,2.0)
		1,2,3:
			if t<2.6:return ready(t-.4)
			return blend(pose("idle",t-2.6),ready(2.2),t-2.6)
		4:
			if t<2.1:
				var p=ready(t-.4);p.position=BATTLE;return p
			return blend(skill1(t-2.1),pose("posture",.8,BATTLE),t-2.1,.12)
		5:
			if t<.4:return pose("idle",t,BATTLE)
			if t<2:return skill1(t-.4)
			var previous=skill1(1.6)
			if t<2.666667:return blend(pose("hit",t-2,previous.position),previous,t-2,.08)
			return blend(pose("idle",t-2.666667,BATTLE),pose("hit",.6666667,previous.position),t-2.666667,.25)
		6:
			if t<1.85:return action("skill2",t-.4,3.0)
			if t<2.516667:return blend(pose("hit",t-1.85),pose("skill2",1.45),t-1.85,.08)
			return blend(pose("idle",t-2.516667),pose("hit",.6666667),t-2.516667)
		7:
			if t<1.2:return action("hit",t-.5,.6666667)
			return blend(action("die",t-1.2,2.3333335,CENTER,true),pose("hit",.6666667),t-1.2,.10)
		8:return action("victory",t-.35,3.4,CENTER,true)
		11:
			if t<.3:return pose("idle",t)
			if t<1.7:return blend(pose("unique",2.65+t-.3),pose("idle",0),t-.3,.25)
			return blend(pose("idle",t-1.7),pose("unique",4.05),t-1.7,.35)
		10,12:
			if mode==12 and t>=2.3:return blend(pose("idle",t-2.3),pose("posture",fposmod(2.3,1.0666667)),t-2.3,.25)
			var p=pose("idle" if mode==10 else "posture",t if mode==10 else fposmod(t,1.0666667))
			if mode==12:p=blend(p,pose("idle",0),t,.18)
			p.procedural="cast" if mode==10 else "power"
			p.pulse=smoothstep(.2,.65,t)*(1-smoothstep(1.65,2.3,t))
			return p
	return pose("idle",t)
