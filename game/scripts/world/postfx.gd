class_name PostFX
extends CanvasLayer
## Pós-processamento de tela cheia (raios de sol, gradação, vinheta, grão...).
## Fica acima do 3D e abaixo do HUD (layer 1; o HUD usa layer >= 5).

const SHADER := preload("res://game/shaders/postfx.gdshader")

var rect: ColorRect
var material: ShaderMaterial
var sun_direction := Vector3(-0.42, 0.27, -0.87)
var shafts_enabled := true
var _fade := 0.0


func _ready() -> void:
	layer = 1
	rect = ColorRect.new()
	rect.name = "PostFX"
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	material = ShaderMaterial.new()
	material.shader = SHADER
	rect.material = material
	add_child(rect)


func set_quality(level: int) -> void:
	# 0 = low, 1 = medium, 2 = high
	visible = level > 0
	shafts_enabled = level >= 2
	material.set_shader_parameter("shaft_samples", 10 if level == 1 else 14)
	material.set_shader_parameter("grain", 0.0 if level < 2 else 0.025)
	material.set_shader_parameter("aberration", 0.0 if level < 2 else 0.0018)


func set_fade(v: float) -> void:
	_fade = v
	material.set_shader_parameter("fade", v)


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or material == null:
		return
	var vp := get_viewport().get_visible_rect().size
	var far_point := cam.global_position + sun_direction.normalized() * 1000.0
	var facing := -cam.global_transform.basis.z.dot(sun_direction.normalized())
	var vis := 0.0
	if shafts_enabled and not cam.is_position_behind(far_point):
		var sp := cam.unproject_position(far_point)
		material.set_shader_parameter("sun_screen", sp / vp)
		vis = smoothstep(0.05, 0.6, facing)
	material.set_shader_parameter("sun_visible", vis)
	material.set_shader_parameter("shaft_strength", 0.45 if shafts_enabled else 0.0)
