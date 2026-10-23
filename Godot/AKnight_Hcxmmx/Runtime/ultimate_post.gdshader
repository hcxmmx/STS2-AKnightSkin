shader_type canvas_item;
render_mode blend_disabled, unshaded;
// DXBC: rgbsplitradialblur VS step .006; PS19 radial sum and PS97 split.
// _SplitPercent runtime packing is unknown: the standard RGB channel selection
// below is an explicit adaptation. Curve timing and strengths are source values.
uniform sampler2D screen_map : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform vec4 stage_rect=vec4(0.0194444444,0.2155555556,0.9805555556,0.8244444444);
uniform float radial_level=1.0;
uniform float rgb_strength=0.0;
uniform bool bloom_enabled=true;
uniform float bloom_strength=0.35;
uniform float effect_opacity=1.0;
uniform sampler2D highlights : repeat_disable, filter_linear;

vec2 source_uv(vec2 uv){return stage_rect.xy+clamp(uv,vec2(0.001),vec2(0.999))*(stage_rect.zw-stage_rect.xy);}
vec3 scene(vec2 uv){return textureLod(screen_map,source_uv(uv),0.0).rgb;}
float gaussian_weight(int n){
    return n==0?6.0:(abs(n)==1?4.0:1.0);
}
vec3 glow_kernel(vec2 uv,float radius){
    vec3 sum=vec3(0.0);
    vec2 center=source_uv(uv);
    vec2 pixel=vec2(radius/1440.0,radius/900.0);
    for(int y=-2;y<=2;y++){
        for(int x=-2;x<=2;x++){
            sum+=texture(highlights,center+vec2(float(x),float(y))*pixel).rgb*gaussian_weight(x)*gaussian_weight(y);
        }
    }
    return sum*(64.0/256.0);
}
void fragment(){
    vec2 uv=(SCREEN_UV-stage_rect.xy)/(stage_rect.zw-stage_rect.xy);
    vec2 ray=uv-vec2(0.5);
    int count=clamp(int(ceil(radial_level)),1,32);
    vec3 original=scene(uv);
    vec3 blurred=vec3(0.0);
    for(int n=0;n<32;n++){
        if(n>=count){break;}
        blurred+=scene(uv-float(n)*0.006*ray);
    }
    blurred/=float(count);
    // Source PS93 / PS97: center-weighted radial pass with an outer clear region.
    vec3 combined=mix(blurred,original,min(length(ray)*4.0+0.3,1.0));
    vec3 minus=scene(uv-ray*rgb_strength);
    vec3 plus=scene(uv+ray*rgb_strength);
    vec3 result=vec3(minus.r,combined.g,plus.b);
    // The highlight viewport preserves HDR excess over 1.3 by scaling /64 before
    // LDR storage. This avoids losing all radiance after normal canvas clipping.
    // Its two Gaussian kernels and LDR calibration are preview adaptations.
    if(bloom_enabled){
        vec3 glow=glow_kernel(uv,1.5)*0.65+glow_kernel(uv,4.5)*0.35;
        result+=glow*5.0*0.2*bloom_strength;
    }
    COLOR=vec4(mix(original,result,effect_opacity),1.0);
}
