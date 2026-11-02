shader_type canvas_item;
render_mode unshaded;
uniform sampler2D screen : hint_screen_texture, repeat_disable, filter_linear;
uniform vec2 center_px;
uniform vec2 viewport_px = vec2(1280.0, 720.0);
uniform float age = 0.0;
uniform float amplitude = 22.0;
uniform float travel_px = 1000.0;
uniform float ring_seconds = 1.3;
void fragment() {
	vec2 p = SCREEN_UV*viewport_px-center_px;
	float radius = length(p);
	vec2 direction = p/max(radius, 1.0);
	float displacement = 0.0;
	float edge = 0.0;
	for (int i=0; i<3; i++) {
		float t = age-float(i)*0.11;
		float r = max(t, 0.0)*travel_px/(ring_seconds-0.22);
		float band = exp(-pow((radius-r)/30.0, 2.0))*step(0.0, t);
		float decay = max(0.0, 1.0-r/travel_px);
		displacement += sin((radius-r)/18.0)*band*amplitude*decay;
		edge += band*decay*0.12;
	}
	vec2 uv = SCREEN_UV+direction*displacement/viewport_px;
	vec2 aberration = direction*abs(displacement)*0.07/viewport_px;
	vec3 color = vec3(texture(screen, uv+aberration).r, texture(screen, uv).g, texture(screen, uv-aberration).b);
	float flash = 0.12*max(0.0, 1.0-age/0.12);
	COLOR = vec4(mix(color+vec3(edge), vec3(1.0), flash), 1.0);
}
