extends "res://AKnight_Hcxmmx/Archive/Subtitle.gd"
var lift:=0.0
func _process(delta:float)->void:
	super._process(delta)
	position=(logical_size*.5-Vector2(0,lift))*scale.x

	# The source texture is a top-to-bottom gradient. Its opaque bottom must
	# reach the viewport edge, regardless of the reference content's fixed rect.
	# Retain source overscan: the texture has atlas padding on its right/bottom.
	if backdrop!=null:
		backdrop.size=Vector2(maxf(float(specs["#simage_voicebg"].layout.m_SizeDelta.x),logical_size.x+400.0),float(specs["#simage_voicebg"].layout.m_SizeDelta.y))
		backdrop.position=Vector2(-backdrop.size.x*.5,logical_size.y*.5+4.0-backdrop.size.y+lift)
