shader_type spatial;
// The owner ring on the water round each ship (ShipView). Drawn in the transparent pass without the
// hardware depth test, so wave crests of the (transparent) ocean never cut it, but it reads the
// opaque depth texture and hides itself wherever solid geometry (hull, masts, sails) stands between
// it and the camera: the ring passes behind the ship like a physical object on the water.
render_mode unshaded, blend_mix, depth_test_disabled, depth_draw_never, cull_back, fog_disabled;

uniform vec4 ring_color : source_color = vec4(0.24, 0.86, 0.43, 0.75);
// View-space distance (world units) the opaque surface must be in front of the ring to hide it.
uniform float occlusion_bias = 0.02;

uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;

void fragment() {
	float depth = textureLod(depth_texture, SCREEN_UV, 0.0).r;
	vec4 scene = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float scene_dist = -scene.z / scene.w;
	float ring_dist = -VERTEX.z;
	if (scene_dist < ring_dist - occlusion_bias) {
		discard;
	}
	ALBEDO = ring_color.rgb;
	ALPHA = ring_color.a;
}
