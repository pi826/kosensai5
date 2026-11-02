shader_type canvas_item;
render_mode unshaded;
uniform sampler2D water : filter_nearest, repeat_enable;
uniform sampler2D crystal : filter_nearest, repeat_enable;
uniform sampler2D ash : filter_nearest, repeat_enable;
uniform vec2 camera_offset;
uniform sampler2D mid_water : filter_nearest, repeat_enable;
uniform sampler2D mid_crystal : filter_nearest, repeat_enable;
uniform sampler2D mid_ash : filter_nearest, repeat_enable;
uniform vec2 mid_offset;
uniform vec3 far_enabled;
uniform vec3 mid_enabled;
void fragment() {
	vec3 weights = COLOR.rgb;
	vec2 uv = UV - camera_offset;
	vec4 far_layer = vec4(0.0);
	if (weights.r > 0.0) far_layer += mix(vec4(0.063,0.118,0.133,1.0),textureLod(water,uv,0.0),far_enabled.r)*weights.r;
	if (weights.g > 0.0) far_layer += mix(vec4(0.11,0.098,0.165,1.0),textureLod(crystal,uv,0.0),far_enabled.g)*weights.g;
	if (weights.b > 0.0) far_layer += mix(vec4(0.141,0.11,0.133,1.0),textureLod(ash,uv,0.0),far_enabled.b)*weights.b;
	vec2 mid_uv = UV - mid_offset;
	vec4 mid_layer = vec4(0.0);
	if (weights.r > 0.0) mid_layer += textureLod(mid_water,mid_uv,0.0)*weights.r*mid_enabled.r;
	if (weights.g > 0.0) mid_layer += textureLod(mid_crystal,mid_uv,0.0)*weights.g*mid_enabled.g;
	if (weights.b > 0.0) mid_layer += textureLod(mid_ash,mid_uv,0.0)*weights.b*mid_enabled.b;
	COLOR = vec4(mix(far_layer.rgb,mid_layer.rgb,mid_layer.a),1.0);
}
