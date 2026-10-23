shader_type canvas_item;
render_mode blend_disabled, unshaded;
uniform sampler2D screen_map : hint_screen_texture, repeat_disable, filter_linear;
uniform sampler2D field_0 : repeat_disable, filter_linear;
uniform sampler2D field_1 : repeat_disable, filter_linear;
uniform sampler2D field_2 : repeat_disable, filter_linear;
uniform sampler2D field_3 : repeat_disable, filter_linear;
uniform vec4 active_fields = vec4(0.0);
uniform float strength_pixels = 7.0;
void fragment() {
    vec2 field = texture(field_0,SCREEN_UV).rg*active_fields.x + texture(field_1,SCREEN_UV).rg*active_fields.y + texture(field_2,SCREEN_UV).rg*active_fields.z + texture(field_3,SCREEN_UV).rg*active_fields.w;
    vec2 offset=field*2.0*step(vec2(0.001),field);
    vec2 uv=clamp(SCREEN_UV+offset*strength_pixels*SCREEN_PIXEL_SIZE,SCREEN_PIXEL_SIZE,vec2(1.0)-SCREEN_PIXEL_SIZE);
    COLOR=texture(screen_map,uv);
}
