shader_type canvas_item;
render_mode blend_disabled, unshaded;
uniform sampler2D light_map : repeat_disable, filter_linear;
uniform vec2 axis=vec2(1.0,0.0);
void fragment(){
    vec2 step_uv=axis*vec2(0.0041666667,0.0066666667);
    vec3 value=texture(light_map,UV).rgb*0.227027;
    value+=(texture(light_map,UV+step_uv*1.384615).rgb+texture(light_map,UV-step_uv*1.384615).rgb)*0.316216;
    value+=(texture(light_map,UV+step_uv*3.230769).rgb+texture(light_map,UV-step_uv*3.230769).rgb)*0.070270;
    COLOR=vec4(value,1.0);
}
