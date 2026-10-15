shader_type spatial;
render_mode cull_disabled;

// Eversion surface material. Colours each patch by the map's own face
// orientation so the inside-out flip reads at a glance: right-side-out sphere
// shows one colour, inside-out shows the other, and the mid-eversion fold shows
// the gradient between them.
//
// The mesh vertices are the analytic map f(theta, phi, s), centred on the object
// origin, so the outward radial direction at a vertex is the vertex position
// itself. In the vertex stage NORMAL is the raw per-vertex normal we uploaded
// (outward at s=0, inward at s=1), so dot with radial gives +1 outside-out and
// -1 inside-out regardless of which way the patch faces the camera. Cull is
// disabled so the inside is visible; the renderer flips the interpolated normal
// for lighting, but this orientation is computed before that, so the colour
// tracks the eversion state, not the camera.
//
// Lighting is left to the default (directional sun + ambient), so the 3D form
// still reads on top of the orientation colour.

uniform vec3 outside_color : source_color = vec3(0.33, 0.55, 0.87);
uniform vec3 inside_color : source_color = vec3(0.93, 0.45, 0.26);

varying float orientation;

void vertex() {
	orientation = dot(NORMAL, normalize(VERTEX));
}

void fragment() {
	float t = clamp(orientation * 0.5 + 0.5, 0.0, 1.0);
	ALBEDO = mix(inside_color, outside_color, t);
	ROUGHNESS = 0.85;
	METALLIC = 0.0;
}
