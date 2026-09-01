shader_type canvas_item;
render_mode unshaded;

// Ground-only luminance remap; the source PNG and actor materials are unchanged.
uniform vec4 base_color : source_color = vec4(0.48, 0.52, 0.48, 1.0);
uniform float detail_amplitude = 0.10;

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	float luminance = dot(source.rgb, vec3(0.2126, 0.7152, 0.0722));
	COLOR = vec4(base_color.rgb + vec3((luminance - 0.5) * detail_amplitude), source.a * base_color.a);
}
