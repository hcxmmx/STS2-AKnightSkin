shader_type canvas_item;
render_mode blend_disabled, unshaded;

// Client urpcustom/uberpost USE_FLICKER, PS382: decode sRGB to linear,
// threshold Rec.709 luminance, select _FlickerInsideCol/_FlickerOutsideCol.
// Scene capture/layer ordering adapts the Unity post pass to this 2D preview.
uniform sampler2D screen_map : hint_screen_texture, repeat_disable, filter_nearest;
uniform float threshold=0.45;
uniform vec3 inside_color=vec3(0.0);
uniform vec3 outside_color=vec3(1.0);

vec3 to_linear(vec3 c){
    return mix(pow((c+0.055)/1.055,vec3(2.4)),c/12.92,lessThanEqual(c,vec3(0.04045)));
}
vec3 to_srgb(vec3 c){
    return mix(1.055*pow(max(c,vec3(0.0)),vec3(1.0/2.4))-0.055,c*12.92,lessThanEqual(c,vec3(0.0031308)));
}
void fragment(){
    vec3 source=texture(screen_map,SCREEN_UV).rgb;
    float luminance=dot(to_linear(source),vec3(0.212673,0.715152,0.072175));
    COLOR=vec4(to_srgb(mix(inside_color,outside_color,step(threshold,luminance))),1.0);
}
