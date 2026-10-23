shader_type canvas_item;
render_mode blend_add, unshaded;
uniform sampler2D soft_light : repeat_disable, filter_linear;
uniform sampler2D core_light : repeat_disable, filter_linear;
uniform float strength=1.0;
void fragment(){
    vec3 halo=texture(soft_light,SCREEN_UV).rgb*16.0;
    vec3 core=texture(core_light,SCREEN_UV).rgb*16.0;
    vec3 light=halo*0.85+core*0.08;
    // Preserve color ratios and leave visible detail in the bright core.
    light/=1.0+max(light.r,max(light.g,light.b))*0.65;
    COLOR=vec4(light*strength,1.0);
}
