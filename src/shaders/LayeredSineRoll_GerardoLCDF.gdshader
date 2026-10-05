shader_type canvas_item;

uniform int lineas = 255;             
uniform float velocidad = 2.0;      
uniform float ondulacion = 0.19;     
uniform float frecuencia = 5.0;   
uniform vec4 color_a : source_color = vec4(0.1, 0.5, 0.8, 1.0);
uniform vec4 color_b : source_color = vec4(0.1, 0.1, 0.2, 1.0);

void fragment() {
    vec2 uv = UV;
    
    float id_linea = floor(uv.y * float(lineas));
    
    float sentido = (mod(id_linea, 2.0) == 0.0) ? 1.0 : -1.0;
    
    float desfase_gusano = sin(uv.y * frecuencia + TIME * velocidad) * ondulacion;
    
    float movimiento_h = (TIME * velocidad * 0.2) * sentido;
    uv.x += movimiento_h + (desfase_gusano * sentido);
    
    float patron = step(0.5, fract(uv.x * 2.0));
    
    vec3 color_final = mix(color_a.rgb, color_b.rgb, patron);
    
    float borde = sin(fract(uv.y * float(lineas)) * PI);
    color_final *= smoothstep(0.0, 0.1, borde); 
    
    COLOR = vec4(color_final, 1.0);
}