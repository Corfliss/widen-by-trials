shader_type sky;

uniform vec2 grid_count = vec2(10.0, 6.0); // Grid divisions in longitude (X) and latitude (Y)
uniform float line_width: hint_range(0.001, 0.1) = 0.02;
uniform float scroll_speed = 0.4;
uniform vec3 grid_color: source_color = vec3(1.0);
uniform vec3 background_color: source_color = vec3(0.0);

void sky() {
    // Convert SKY_COORDS (equirectangular) into scrolling UV space
    float u = SKY_COORDS.x;
    float v = SKY_COORDS.y;

    // Apply vertical scroll
    v -= TIME * scroll_speed;

    // Scale UVs to grid frequency
    vec2 uv = vec2(u, v) * grid_count;

    // Create anti-aliased grid lines
    vec2 grid = abs(fract(uv - 0.5) - 0.5) / fwidth(uv);
    float line = min(grid.x, grid.y);
    float alpha = 1.0 - smoothstep(0.0, line_width * 100.0, line);

    // Mix grid and background color
    vec3 color = mix(background_color, grid_color, alpha);
    COLOR = color;
}