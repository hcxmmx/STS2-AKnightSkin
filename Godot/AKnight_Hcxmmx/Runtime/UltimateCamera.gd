extends RefCounted

const FOCAL := 474.5819
var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://AKnight_Hcxmmx/Runtime/assets/fx/unique/camera.json"))

func sample(t: float) -> Dictionary:
	var records: Array=data.frames
	var f:=clampf(t*float(data.fps),0,records.size()-1)
	var a: Dictionary=records[int(f)];var b: Dictionary=records[mini(int(f)+1,records.size()-1)]
	var weight:=f-floorf(f)
	var offset:=Vector3(float(a.position[0]),float(a.position[1]),float(a.position[2])).lerp(Vector3(float(b.position[0]),float(b.position[1]),float(b.position[2])),weight)
	# Flicker is stepped in the source clip. Do not interpolate the enable/type
	# or the alternating black/white colors across a sample boundary.
	return {"eye":Vector3(0,2.13,-12.06)+offset,"radial":lerpf(float(a.radialBlurLevel),float(b.radialBlurLevel),weight),"rgb":lerpf(float(a.rgbSplitStrength),float(b.rgbSplitStrength),weight),
		"flicker":int(a.flickerType)==3,"flicker_threshold":float(a.flickerLumiance),
		"flicker_inside":Vector3(float(a["flickerInsideCol.r"]),float(a["flickerInsideCol.g"]),float(a["flickerInsideCol.b"])),
		"flicker_outside":Vector3(float(a["flickerOutsideCol.r"]),float(a["flickerOutsideCol.g"]),float(a["flickerOutsideCol.b"]))}

func project(world: Vector3,eye: Vector3) -> Vector2:
	var delta:=world-eye
	return Vector2(720,468)+Vector2(-delta.x,-delta.y)*FOCAL/maxf(delta.z,.05)

func pixels_per_unit(world: Vector3,eye: Vector3) -> float:
	return FOCAL/maxf(world.z-eye.z,.05)
