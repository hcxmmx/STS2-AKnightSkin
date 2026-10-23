shader_type canvas_item;
render_mode blend_disabled, unshaded;
uniform sampler2D screen_map : hint_screen_texture, repeat_disable, filter_linear;
uniform sampler2D glass_field : repeat_disable, filter_linear;
uniform vec4 stage_rect=vec4(0.0,0.0,1.0,1.0);
uniform float animation_time=0.0;
uniform float displacement_pixels=40.0;
uniform float glass_strength=0.1;
uniform bool show_regions=false;

void fragment(){
    vec2 p=(SCREEN_UV-stage_rect.xy)/(stage_rect.zw-stage_rect.xy);
    // Deliberate screen-space approximation: five cuts distributed across the
    // stage, based on the reference composition, not recovered Unity positions.
    float cuts[5];
    cuts[0]=p.x+0.20*p.y-0.26;
    cuts[1]=p.x-0.30*p.y-0.24;
    cuts[2]=p.x+0.27*p.y-0.75;
    cuts[3]=p.x-0.24*p.y-0.73;
    cuts[4]=p.y+0.15*p.x-0.79;
    vec2 directions[5];
    directions[0]=vec2(0.85,-0.15);
    directions[1]=vec2(-0.60,0.30);
    directions[2]=vec2(0.75,0.10);
    directions[3]=vec2(-0.70,-0.20);
    directions[4]=vec2(0.25,0.55);
    vec2 displacement=vec2(0.0);
    float region=0.0;
    float edge=1000.0;
    float bit=1.0;
    for(int i=0;i<5;i++){
        float birth=9.10+float(i)*0.14;
        float formation=smoothstep(birth,birth+0.12,animation_time);
        float side=step(0.0,cuts[i]);
        displacement+=(side*2.0-1.0)*directions[i]*formation;
        region+=side*bit*step(0.01,formation);bit*=2.0;
        if(formation>0.01){edge=min(edge,abs(cuts[i])/max(fwidth(cuts[i]),0.000001));}
    }
    float phase=smoothstep(9.05,9.30,animation_time)*(1.0-step(12.70,animation_time));
    vec2 sample_uv=clamp(SCREEN_UV+displacement*displacement_pixels*0.55*SCREEN_PIXEL_SIZE*phase,
                         stage_rect.xy+SCREEN_PIXEL_SIZE,stage_rect.zw-SCREEN_PIXEL_SIZE);
    // Keep the original burst/afterburst glass masks, sampled in the displaced
    // region, while the old large-plane masks are excluded by the player.
    vec2 field=vec2(0.5)+texture(glass_field,sample_uv).rg;
    vec2 active=step(vec2(0.501),field)+step(field,vec2(0.498));
    vec2 glass_offset=(field*2.0-vec2(1.0))*active*glass_strength;
    sample_uv=clamp(sample_uv+glass_offset,stage_rect.xy+SCREEN_PIXEL_SIZE,stage_rect.zw-SCREEN_PIXEL_SIZE);
    vec4 scene=texture(screen_map,sample_uv);
    if(show_regions){
        vec3 tint=0.55+0.45*cos(6.2831853*(region*0.618034+vec3(0.0,0.333333,0.666667)));
        scene.rgb=mix(scene.rgb,tint,phase*0.60);
        scene.rgb*=1.0-(1.0-smoothstep(0.5,1.3,edge))*phase*0.8;
    }
    COLOR=scene;
}
