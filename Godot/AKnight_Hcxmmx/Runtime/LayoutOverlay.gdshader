shader_type canvas_item;
render_mode blend_mix, unshaded;
uniform sampler2D vertex_data : filter_nearest, repeat_disable;
uniform sampler2D mask_map : repeat_enable, filter_linear;
uniform bool line_mode = false;
uniform vec4 main_st = vec4(1.0,1.0,0.0,0.0);
uniform float factor = 1.0;
uniform bool shape_mode = false;
uniform int piece_vertex_count = 4;
uniform float palette_offset = 0.0;
uniform bool world_piece_ids = false;
#include "res://AKnight_Hcxmmx/Runtime/perspective_canvas.gdshaderinc"
varying vec2 source_uv;
varying float particle_alpha;
varying flat float piece_id;
void vertex() {
    piece_id=floor(float(VERTEX_ID)/float(piece_vertex_count));
    source_uv=UV;
    particle_alpha=COLOR.a;
    preview_reciprocal=1.0;preview_depth=1.0;
    if(perspective_view){
        vec4 packed_world=texelFetch(vertex_data,ivec2(VERTEX_ID%1024,VERTEX_ID/1024),0);
        vec3 world=packed_world.xyz;
        if(world_piece_ids){piece_id=packed_world.w-1.0;}
        VERTEX=project_source(world);
        preview_depth=world.z-camera_position.z;
        if(line_mode){
            preview_reciprocal=1.0/max(preview_depth,0.05);
            preview_depth*=preview_reciprocal;
            source_uv*=preview_reciprocal;
            particle_alpha*=preview_reciprocal;
        }
    }
}
void fragment() {
    if(perspective_view && preview_depth/preview_reciprocal<0.05){discard;}
    if(line_mode){
        vec2 uv=source_uv/preview_reciprocal;
        // This group's geometry is long along local X; mark its long centerline.
        float distance_pixels=abs(uv.y-0.5)/max(fwidth(uv.y),0.000001);
        float alpha=(1.0-smoothstep(2.3,3.7,distance_pixels))*clamp(particle_alpha/preview_reciprocal*20.0,0.0,1.0);
        COLOR=vec4(1.0,0.74,0.04,alpha);
    }else{
        // Match the current mask renderer's UVs and contribution, merely tinted.
        vec2 uv=vec2(source_uv.x,1.0-source_uv.y)*main_st.xy+main_st.zw;
        vec4 tex=texture(mask_map,uv);
        float contribution=tex.r*tex.a*factor*factor*particle_alpha*particle_alpha;
        float coverage=clamp(contribution*8.0,0.0,1.0);
        if(shape_mode){
            // Diagnostic colors show the existing pieces, not reconstructed cuts.
            vec3 tint=0.55+0.45*cos(6.2831853*(piece_id*0.618034+palette_offset+vec3(0.0,0.333333,0.666667)));
            float alpha=smoothstep(0.0005,0.015,contribution)*0.58;
            if(piece_vertex_count==4){
                vec2 edge=min(source_uv,vec2(1.0)-source_uv)/max(fwidth(source_uv),vec2(0.000001));
                float outline=1.0-smoothstep(0.7,1.8,min(edge.x,edge.y));
                alpha=max(alpha,outline*step(0.0005,contribution)*0.9);
            }
            COLOR=vec4(tint,alpha);
        }else{COLOR=vec4(0.06,0.72,1.0,coverage*0.55);}
    }
}
