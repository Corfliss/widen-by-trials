shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec4 face_color : source_color = vec4(0.2, 0.0, 0.0, 1.0);
uniform vec4 wire_color : source_color = vec4(1.0, 0.0, 0.0, 1.0);
uniform float wire_width : hint_range(0.1, 10.0, 0.1) = 1.0;

varying vec3 v_bary;

void vertex() {
	// derive barycentric coord from vertex index within its triangle
	int local = VERTEX_ID % 3;
	if (local == 0) {
		v_bary = vec3(1.0, 0.0, 0.0);
	} else if (local == 1) {
		v_bary = vec3(0.0, 1.0, 0.0);
	} else {
		v_bary = vec3(0.0, 0.0, 1.0);
	}
}

void fragment() {
	vec3 d = fwidth(v_bary);
	vec3 a3 = smoothstep(vec3(0.0), d * wire_width, v_bary);
	float edge_factor = min(min(a3.x, a3.y), a3.z);

	ALBEDO = mix(wire_color.rgb, face_color.rgb, edge_factor);
	ALPHA  = mix(wire_color.a, face_color.a, edge_factor);
}