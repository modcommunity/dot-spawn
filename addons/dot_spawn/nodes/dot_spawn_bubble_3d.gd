class_name DotSpawnBubble3D
extends Node3D

## A translucent bubble drawn around a spawn-protected body.
##
## Presentation only: it reads nothing from the ledger. A game calls [method sync] each
## frame with "is this body protected", and the bubble shows, hides and follows. Attach
## it as a child of the body (it then follows for free) or give it a [member target].
## Gated by [code]DotSpawnRules.protection_bubble[/code] on the caller's side.

const SHADER_CODE := """
shader_type spatial;
render_mode blend_mix, unshaded, cull_back, depth_draw_never;
uniform vec4 tint : source_color = vec4(0.35, 0.75, 1.0, 1.0);
uniform float pulse = 0.0;
void fragment() {
	float f = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.0);
	ALBEDO = tint.rgb;
	ALPHA = clamp(0.18 + f * 0.6 + 0.08 * sin(pulse), 0.0, 0.85);
}
"""

## Metres. Wide enough for a standing capsule of 1.8 m with a margin.
@export var radius: float = 1.1
@export var tint: Color = Color(0.35, 0.75, 1.0)
## Local offset of the bubble's centre from this node's origin (body centre height).
@export var center_offset: Vector3 = Vector3(0, 0.9, 0)

var target: Node3D = null

var _mesh: MeshInstance3D = null
var _mat: ShaderMaterial = null
var _time: float = 0.0


func _init() -> void:
	visible = false
	_mesh = MeshInstance3D.new()
	_mesh.name = "Bubble"
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 32
	sphere.rings = 16
	_mesh.mesh = sphere
	var sh := Shader.new()
	sh.code = SHADER_CODE
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_mat.set_shader_parameter("tint", tint)
	_mesh.material_override = _mat
	add_child(_mesh)


func _ready() -> void:
	_mesh.position = center_offset


## Shows or hides the bubble. When [member target] is set the bubble also moves to it.
func sync(is_protected: bool) -> void:
	visible = is_protected

	if is_protected and target != null and is_inside_tree() and target.is_inside_tree():
		global_position = target.global_position


func _process(delta: float) -> void:
	if not visible:
		return

	_time += delta
	_mat.set_shader_parameter("pulse", _time * 6.0)
