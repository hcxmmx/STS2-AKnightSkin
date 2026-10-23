// Original camera lens is perspective, FOV 60; its animated rig remains frontal.
// Native 2D viewport projection and perspective-correct varyings are explicit
// preview adaptations. This include is used only by the new optional camera view.
uniform bool perspective_view=false;
uniform vec3 camera_position=vec3(0.0,2.13,-12.06);
uniform float camera_focal=474.5819;
uniform vec2 camera_center=vec2(720.0,468.0);
varying float preview_reciprocal;
varying float preview_depth;

vec2 project_source(vec3 world) {
    vec3 delta=world-camera_position;
    vec2 screen=camera_center+vec2(-delta.x,-delta.y)*camera_focal/max(delta.z,0.05);
    return (screen-vec2(720.0,660.0))/75.0;
}
