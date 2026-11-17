// The following shader is used in order to simulate a simple ocean using Gerstner waves.
// This shader can be added in a plane mesh. For a more detailed ocean, increase the width and depth subdivision.
// Note 1: On larger planes ex. 500x500, increasing the subdivision above 1000 comes at great performance cost
// Note 2: Special thanks to @ninetailsrabbit for fixing a caustics projection issue!

shader_type spatial;

// Set render modes: always draw depth and disable backface culling
render_mode depth_draw_always, cull_disabled;

// Uniforms for screen and depth textures
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, filter_linear_mipmap;

// The sea, driven by SeaModel (scripts/view/sea_model.gd; sea-state spec B). Per frame: sea_time, chop_time,
// swell_phase, zoom_intensity, grid_opacity. The rest is pushed when the wind, sea state or
// tuning changes.
group_uniforms Sea;
uniform float sea_time = 0.0;                     // the one sea clock (ship motion samples it too)
uniform float zoom_intensity = 0.0;               // 0 = flat board (zoomed out), 1 = full swell
uniform vec2 wind_dir = vec2(1.0, 0.0);           // world XZ the wind blows toward
// Swell: three Gerstner components running downwind (SeaModel samples the same sum).
uniform vec4 swell_1 = vec4(1.0, 0.0, 0.0, 8.75); // dir.x, dir.y, full amplitude, wavelength (world units)
uniform vec4 swell_2 = vec4(1.0, 0.0, 0.0, 8.75);
uniform vec4 swell_3 = vec4(1.0, 0.0, 0.0, 8.75);
uniform vec3 swell_phase = vec3(0.0);             // ∫ k * c dt + offset, per component (SeaModel)
uniform float swell_q = 0.8;                      // crest sharpening
uniform float swell_shading = 0.4;                // normal tilt from the swell when zoomed out (none of its height)
// Chop: short waves set relative to the wind, surface detail at every zoom (height only zoomed in).
uniform float chop_strength = 1.0;                // chop steepness and normal-map detail
uniform float chop_amplitude = 0.16;              // base steepness, from wind speed and sea state
uniform float chop_wavelength = 0.85;             // base wavelength
uniform float chop_time = 0.0;                    // the chop's clock (SeaModel: ∫ dt / chop time scale)
uniform float chop_noise = 0.08;                  // fBm height added to the chop
uniform float noise_zoom = 2.0;
// Whitecaps: foam on swell crests and breaking chop, streaked downwind.
uniform float whitecap_threshold = 0.8;           // crest height (fraction of swell_amp_total) where foam starts
uniform float whitecap_strength = 0.0;            // preset strength
uniform float whitecap_sea_factor = 0.0;          // WHITECAP_BY_SEA[sea]; 0 below whitecap_min_sea
uniform float swell_amp_total = 0.1;              // sum of the full swell amplitudes (crest height)

// Group uniforms for water colors
group_uniforms Water_colours;
uniform vec3 base_water_color:source_color = vec3(0.4, 0.6, 0.8);
uniform vec3 fresnel_water_color:source_color = vec3(0.5, 0.7, 0.9);
uniform vec4 deep_water_color : source_color = vec4(0.2, 0.4, 0.6, 1.0);
uniform vec4 shallow_water_color : source_color = vec4(0.4, 0.6, 0.8, 1.0);

// Group uniforms for depth-related parameters
group_uniforms Depth;
uniform float beers_law = 0.5;
uniform float depth_offset = -1.2;
uniform float near = 7.0;
uniform float far = 10000.0;

// Group uniforms for edge detection and foam effects
group_uniforms Edge_Detection;
uniform float edge_texture_scale = 3.5;
uniform float edge_texture_offset = 1.0;
uniform float edge_texture_speed = 0.1;

// Group uniforms for hex grid lines
group_uniforms Hex_Grid;
uniform bool show_hex_grid = true;
uniform float grid_opacity = 1.0;  // the plain grid fades as the swell comes in (HexOverlay layers do not)
uniform vec3 hex_grid_color : source_color = vec3(1.0, 1.0, 1.0);
uniform float hex_grid_width = 0.02;
uniform float hex_size = 1.0;
uniform float edge_foam_intensity = 2.0;
uniform float edge_fade_start = -3.0;
uniform float edge_fade_end = 6.6;
uniform sampler2D edge_foam_texture;

// Group uniforms for wave peak effects
group_uniforms WavePeakEffect;
uniform float peak_height_threshold = 1.0;
uniform vec3 peak_color = vec3(1.0, 1.0, 1.0);
uniform float peak_intensity = 1.0;
uniform sampler2D foam_texture;
uniform float foam_intensity = 1.0;
uniform float foam_scale = 1.0;

// Group uniforms for surface details
group_uniforms Surface_details;
uniform float metallic = 0.6;
uniform float roughness = 0.045;
uniform float uv_scale_text_a = 0.1;
uniform vec2 uv_speed_text_a = vec2(0.42, 0.3);
uniform float uv_scale_text_b = 0.6;
uniform vec2 uv_speed_text_b = vec2(0.15, 0.1);
uniform float normal_strength = 1.0;
uniform float uv_sampler_scale = 0.3;
uniform float blend_factor = 0.28;
uniform float perturbation_strength = 1.0;
uniform float perturbation_time = 0.3;
uniform sampler2D normalmap_a;
uniform sampler2D normalmap_b;
uniform sampler2D uv_sampler;
uniform sampler2DArray caustic_sampler : hint_default_black;
uniform float caustics_intensity = 15.0;

uniform float num_caustic_layers = 16.0;
uniform float caustic_distortion_strength = 0.001;

// Fresnel function to calculate the reflection/refraction effect
float fresnel(float amount, vec3 normal, vec3 view) {
    return pow((1.0 - clamp(dot(normalize(normal), normalize(view)), 0.0, 1.0)), amount);
}

// Function to calculate edge depth
float edge(float depth) {
    depth = 2.0 * depth - 1.0;
    return near * far / (far - depth * (near - far));
}

// Function to calculate dynamic amplitude based on position and time
float dynamic_amplitude(vec2 pos, float time) {
    return 1.0 + 0.5 * sin(time + length(pos) * 0.1);
}

// Hash function for noise generation
float hash(vec2 p) {
    return fract(sin(dot(p * 17.17, vec2(14.91, 67.31))) * 4791.9511);
}

// 2D noise function
float noise(vec2 x) {
    vec2 p = floor(x);
    vec2 f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    vec2 a = vec2(1.0, 0.0);
    return mix(mix(hash(p + a.yy), hash(p + a.xy), f.x),
               mix(hash(p + a.yx), hash(p + a.xx), f.x), f.y);
}

// Fractional Brownian Motion (fBM) function for generating complex noise
float fbm(vec2 x) {
    float height = 0.0;
    float amplitude = 0.5;
    float frequency = 3.0;
    for (int i = 0; i < 6; i++) {
        height += noise(x * frequency) * amplitude;
        amplitude *= 0.5;
        frequency *= 2.0;
    }
    return height;
}

// Structure to hold wave results: displacement, tangent, binormal, and normal
struct WaveResult {
    vec3 displacement;
    vec3 tangent;
    vec3 binormal;
    vec3 normal;
};

// Gerstner wave function to calculate wave displacement and normals
WaveResult gerstner_wave(vec4 params, vec2 pos, float time) {
    float steepness = params.z * chop_strength * dynamic_amplitude(pos, time);
    float wavelength = params.w;
    float k = 2.0 * PI / wavelength;
    float c = sqrt(9.81 / k);
    vec2 d = normalize(params.xy);
    float f = k * (dot(d, pos.xy) - c * time);
    float a = steepness / k;

    vec3 displacement = vec3(d.x * (a * cos(f)), a * sin(f), d.y * (a * cos(f)));

    vec3 tangent = vec3(1.0 - d.x * d.x * steepness * sin(f), steepness * cos(f), -d.x * d.y * steepness * sin(f));
    vec3 binormal = vec3(-d.x * d.y * steepness * sin(f), steepness * cos(f), 1.0 - d.y * d.y * steepness * sin(f));
    vec3 normal = normalize(cross(tangent, binormal));

    return WaveResult(displacement, tangent, binormal, normal);
}

// Add one wave's displacement, tangent, binormal and normal to the sum.
void add_wave(inout WaveResult sum, vec4 params, vec2 pos, float time) {
    WaveResult wr = gerstner_wave(params, pos, time);
    sum.displacement += wr.displacement;
    sum.tangent += wr.tangent;
    sum.binormal += wr.binormal;
    sum.normal += wr.normal;
}

// The chop: four waves running with the wind (downwind, +30, -45 degrees) and four fixed cross
// waves, sized from chop_amplitude and chop_wavelength (vec4: direction, steepness, wavelength).
WaveResult wave(vec2 pos, float time) {
    WaveResult waveResult;
    waveResult.displacement = vec3(0.0);
    waveResult.tangent = vec3(1.0, 0.0, 0.0);
    waveResult.binormal = vec3(0.0, 0.0, 1.0);
    waveResult.normal = vec3(0.0, 1.0, 0.0);

    vec2 w = normalize(wind_dir);
    float c30 = cos(radians(30.0));
    float s30 = sin(radians(30.0));
    float c45 = cos(radians(-45.0));
    float s45 = sin(radians(-45.0));
    vec2 w30 = vec2(w.x * c30 - w.y * s30, w.x * s30 + w.y * c30);
    vec2 w45 = vec2(w.x * c45 - w.y * s45, w.x * s45 + w.y * c45);
    float a = chop_amplitude;
    float l = chop_wavelength;
    add_wave(waveResult, vec4(w, a * 0.2, l * 0.8), pos, time);
    add_wave(waveResult, vec4(-0.3, -0.2, a * 0.02, 0.5), pos, time);
    add_wave(waveResult, vec4(w30, a * 0.15, l * 0.6), pos, time);
    add_wave(waveResult, vec4(0.2, -0.4, a * 0.08, 0.4), pos, time);
    add_wave(waveResult, vec4(w45, a * 0.1, l * 1.2), pos, time);
    add_wave(waveResult, vec4(0.8, 0.3, a * 0.03, 0.4), pos, time);
    add_wave(waveResult, vec4(w, a * 0.18, l * 1.5), pos, time);
    add_wave(waveResult, vec4(-0.3, 0.5, a * 0.12, 0.6), pos, time);

    // Add noise to the wave displacement for more natural look
    waveResult.displacement.y += fbm(pos.xy * (noise_zoom / 50.0)) * chop_noise;

    return waveResult;
}

// One swell component (Gerstner): adds its displacement and its height slope.
void swell_component(vec4 s, float phase, vec2 p, inout vec3 disp, inout vec2 slope) {
    if (s.z <= 0.0 || s.w < 0.01) {
        return;
    }
    float k = 2.0 * PI / s.w;
    vec2 d = normalize(s.xy);
    float f = k * dot(d, p) - phase;
    float a = s.z;
    disp += vec3(d.x * swell_q * a * cos(f), a * sin(f), d.y * swell_q * a * cos(f));
    slope += d * (a * k * cos(f));
}

// Varying variables to pass data from vertex to fragment shader
varying float height;
varying float swell_height_raw;  // swell height before the zoom scale (for whitecaps)
varying vec3 world_position;
varying vec3 original_world_position;  // Position before wave displacement
varying mat3 tbn_matrix;
varying mat4 inv_mvp;

// Vertex shader function
void vertex() {
    // Store original world position BEFORE wave displacement (for static hex grid)
    original_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

    // Chop: the short waves (surface detail; height only when zoomed in)
    WaveResult waveResult = wave(VERTEX.xz, chop_time);
    // Swell: the long waves the ships ride, in world XZ as SeaModel samples them
    vec3 swell = vec3(0.0);
    vec2 swell_slope = vec2(0.0);
    swell_component(swell_1, swell_phase.x, original_world_position.xz, swell, swell_slope);
    swell_component(swell_2, swell_phase.y, original_world_position.xz, swell, swell_slope);
    swell_component(swell_3, swell_phase.z, original_world_position.xz, swell, swell_slope);
    VERTEX += (waveResult.displacement + swell) * zoom_intensity;
    // Store the height of the wave displacement
    height = (waveResult.displacement.y + swell.y) * zoom_intensity;
    swell_height_raw = swell.y;

    // Chop normal tilted by the swell slope: the swell shades the water even when it is flat
    vec3 chop_n = normalize(waveResult.normal);
    vec2 tilt = swell_slope * mix(swell_shading, 1.0, zoom_intensity);
    vec3 wn = normalize(vec3(chop_n.x - tilt.x, chop_n.y, chop_n.z - tilt.y));
    vec3 wt = normalize(waveResult.tangent.xyz);
    // Transform normals, tangents, and binormals to view space
    vec3 n = normalize((MODELVIEW_MATRIX * vec4(wn, 0.0)).xyz);
    vec3 t = normalize((MODELVIEW_MATRIX * vec4(wt, 0.0)).xyz);
    vec3 b = normalize((MODELVIEW_MATRIX * vec4(cross(wn, wt), 0.0)).xyz);
    // Calculate world position of the vertex AFTER displacement (for water effects)
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    // Create TBN matrix for normal mapping
    tbn_matrix = mat3(t, b, n);
    // Calculate inverse MVP matrix for screen space transformations
    inv_mvp = inverse(PROJECTION_MATRIX * MODELVIEW_MATRIX);
}


// 2D Random hash function
float random(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

// Smooth noise function
float smooth_noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(random(i + vec2(0.0, 0.0)), random(i + vec2(1.0, 0.0)), u.x),
        mix(random(i + vec2(0.0, 1.0)), random(i + vec2(1.0, 1.0)), u.x),
        u.y
    );
}

// Layered noise for detiling
float layered_noise(vec2 p, float scale) {
    float n = 0.0;
    n += smooth_noise(p * scale) * 0.5;
    n += smooth_noise(p * scale * 2.0) * 0.25;
    n += smooth_noise(p * scale * 4.0) * 0.125;
    return n;
}

// Calculate distance to nearest hex edge (for grid lines)
float hex_edge_distance(vec2 pos, float size) {
    const float SQRT3 = 1.7320508075688772;

    // Convert world position to axial hex coordinates
    float q = (SQRT3/3.0 * pos.x - 1.0/3.0 * pos.y) / size;
    float r = (2.0/3.0 * pos.y) / size;

    // Convert to cube coordinates
    float x = q;
    float z = r;
    float y = -x - z;

    // Round to nearest hex
    float rx = round(x);
    float ry = round(y);
    float rz = round(z);

    float x_diff = abs(rx - x);
    float y_diff = abs(ry - y);
    float z_diff = abs(rz - z);

    if (x_diff > y_diff && x_diff > z_diff) {
        rx = -ry - rz;
    } else if (y_diff > z_diff) {
        ry = -rx - rz;
    } else {
        rz = -rx - ry;
    }

    // Convert back to axial
    float hex_q = rx;
    float hex_r = rz;

    // Convert to world position of hex center
    float hex_x = size * (SQRT3 * hex_q + SQRT3/2.0 * hex_r);
    float hex_y = size * (3.0/2.0 * hex_r);

    // Calculate distance from hex center
    vec2 center_offset = pos - vec2(hex_x, hex_y);

    // Calculate minimum distance to any of the 6 hex edges
    float min_dist = size;
    for (int i = 0; i < 6; i++) {
        float angle = radians(60.0 * float(i) - 30.0);
        vec2 edge_dir = vec2(cos(angle), sin(angle));
        vec2 edge_pos = edge_dir * size;

        float angle_next = radians(60.0 * float(i + 1) - 30.0);
        vec2 edge_next = vec2(cos(angle_next), sin(angle_next)) * size;

        vec2 edge_line = edge_next - edge_pos;
        float t = clamp(dot(center_offset - edge_pos, edge_line) / dot(edge_line, edge_line), 0.0, 1.0);
        vec2 closest = edge_pos + edge_line * t;
        float dist = length(center_offset - closest);
        min_dist = min(min_dist, dist);
    }

    return min_dist;
}

// Perturb UV coordinates for detiling
vec2 perturb_uv(vec2 uv, vec2 world_pos, float time, float strength) {
    // Use world position to generate unique noise patterns
    vec2 noise_offset = vec2(
        layered_noise(world_pos * 0.3 + time * 0.06, 1.0),
        layered_noise(world_pos * 0.3 + time * 0.06 + vec2(10.0), 1.0)
    );
    // Apply subtle distortion to UVs
    return uv + noise_offset * strength;
}


// Fragment shader function
void fragment() {
    // Calculate UV coordinates based on world position
    vec2 uv = world_position.xz;

    // Sample UV offset texture
    vec2 uv_offset = texture(uv_sampler, uv * uv_sampler_scale).rg;

    // Calculate base UV coordinates for normal maps
    vec2 base_uv_a = (uv + uv_speed_text_a * sea_time + uv_offset) * uv_scale_text_a;
    vec2 base_uv_b = (uv + uv_speed_text_b * sea_time + uv_offset) * uv_scale_text_b;

    // Apply noise-based perturbation to UVs
    vec2 animated_uv_a = perturb_uv(base_uv_a, world_position.xz, sea_time, perturbation_strength);
    vec2 animated_uv_b = perturb_uv(base_uv_b, world_position.xz, sea_time + 0.0, perturbation_time);

    // Sample normal maps
    vec3 normal_sample_a = texture(normalmap_a, animated_uv_a).rgb;
    vec3 normal_sample_b = texture(normalmap_b, animated_uv_b).rgb;

    // Normalize normal samples and combine them
    normal_sample_a = normalize(normal_sample_a * 2.0 - 1.0);
    normal_sample_b = normalize(normal_sample_b * 2.0 - 1.0);
    vec3 combined_normal = normalize(mix(normal_sample_a, normal_sample_b, blend_factor));
    // Chop strength scales the normal-map detail (tangent-space xy)
    combined_normal = normalize(vec3(combined_normal.xy * chop_strength, combined_normal.z));

    // Perturb the normal using the TBN matrix
    vec3 perturbed_normal = normalize(tbn_matrix * (combined_normal * normal_strength));

    // Sample depth texture
    float depth_raw = texture(DEPTH_TEXTURE, SCREEN_UV).r;
    float depth = PROJECTION_MATRIX[3][2] / (depth_raw + PROJECTION_MATRIX[2][2]);

    // Calculate the distance from the camera to the water surface
    float camera_depth = INV_VIEW_MATRIX[3].y - world_position.y;
    if (camera_depth < 0.0) { // Camera is underwater
        // Map the depth to a range where deeper = positive beers_law, closer = negative beers_law
        float depth_factor = smoothstep(-10.0, 0.0, camera_depth); // Adjust -10.0 for the depth range
        ALPHA -= depth_factor * 0.3;
        }
    // Calculate depth blend factor using Beer's law
    float depth_blend = exp((depth + VERTEX.z + depth_offset) * -beers_law);
    depth_blend = clamp(1.0 - depth_blend, 0.0, 1.0);
    float depth_blend_power = clamp(pow(depth_blend, 2.5), 0.0, 1.0);

    // Sample screen color and blend it with depth color
    vec3 screen_color = textureLod(SCREEN_TEXTURE, SCREEN_UV, depth_blend_power * 2.5).rgb;
    vec3 depth_color = mix(shallow_water_color.rgb, deep_water_color.rgb, depth_blend_power);
    vec3 color = mix(screen_color * depth_color, depth_color * 0.25, depth_blend_power * 0.5);

    // Calculate depth difference for edge detection
    float z_depth = edge(texture(DEPTH_TEXTURE, SCREEN_UV).x);
    float z_pos = edge(FRAGCOORD.z);
    float z_dif = z_depth - z_pos;

    // Calculate caustic effect
    vec4 caustic_screenPos = vec4(SCREEN_UV * 2.0 - 1.0, depth_raw, 1.0);
    vec4 caustic_localPos = inv_mvp * caustic_screenPos;
    caustic_localPos = vec4(caustic_localPos.xyz / caustic_localPos.w, caustic_localPos.w);

    vec2 caustic_Uv = caustic_localPos.xz / vec2(1024.0) + 0.5;
    caustic_Uv += perturbed_normal.xz * caustic_distortion_strength;

    float caustic_layer_index = floor(mod(sea_time * 26.0, num_caustic_layers)); // Use floor for integer index

    vec4 caustic_color = texture(caustic_sampler, vec3(caustic_Uv * 660.0, caustic_layer_index));
    float caustic_intensity_multiplier = (1.0 - depth_blend_power) * caustics_intensity;

    color *= 1.0 + pow(caustic_color.r, 1.50) * caustic_intensity_multiplier;

    // Calculate fresnel effect
    float fresnel = fresnel(5.0, NORMAL, VIEW);
    vec3 surface_color = mix(base_water_color, fresnel_water_color, fresnel);

    // Calculate edge foam effect
    vec2 edge_uv = world_position.xz * edge_texture_scale + edge_texture_offset + sea_time * edge_texture_speed;
    float edge_fade = smoothstep(edge_fade_start, edge_fade_end, z_dif);
    vec3 depth_color_adj = mix(texture(edge_foam_texture, edge_uv).rgb * edge_foam_intensity, color, edge_fade);

    // Apply peak color effect based on height with noise
    float peak_factor = smoothstep(peak_height_threshold, peak_height_threshold + 0.2, height);
    float noise_factor = fbm(world_position.xz * 0.1 + sea_time * 0.1);
    peak_factor = peak_factor * noise_factor;

    vec3 final_color = mix(surface_color, peak_color * peak_intensity, peak_factor);

    // Sample the foam texture and blend it with the final color
    vec2 foam_uv = world_position.xz * foam_scale + sea_time * 0.1;
    float foam_sample = texture(foam_texture, foam_uv).r;
    float foam_blend_factor = smoothstep(0.0, 1.0, peak_factor) * foam_sample * foam_intensity;

    final_color = mix(final_color, vec3(1.0), foam_blend_factor);

    // Whitecaps: foam on the swell crests and breaking chop, streaked downwind; they keep 15 %
    // zoomed out as faint texture
    float cap = 0.0;
    float whitecap_amount = whitecap_strength * whitecap_sea_factor * (0.15 + 0.85 * zoom_intensity);
    // Uniform-only test: the whole draw skips the streak texture and fbm when there are no caps
    if (whitecap_amount > 0.001) {
        vec2 wd = normalize(wind_dir);
        vec2 wp = vec2(dot(world_position.xz, wd), dot(world_position.xz, vec2(-wd.y, wd.x)));
        float streak = texture(foam_texture, vec2(wp.x * 0.25, wp.y * 0.9) - vec2(sea_time * 0.04, 0.0)).r;
        float crest = smoothstep(whitecap_threshold, 1.0, swell_height_raw / max(swell_amp_total, 0.0001));
        float n = fbm(wp * vec2(0.35, 1.1) - vec2(sea_time * 0.25, 0.0));
        float breaking = smoothstep(0.62, 0.85, n);
        float breakup = smoothstep(0.42, 0.7, n);  // crest foam in patches, not solid stripes
        cap = clamp((crest * breakup * 1.1 + breaking * 0.5) * (0.3 + 0.7 * streak) * whitecap_amount, 0.0, 1.0);
        final_color = mix(final_color, vec3(0.93, 0.96, 0.98), cap);
    }

    // Add hex grid lines (using original position so grid stays static)
    vec3 color_with_grid = final_color + depth_color_adj * (1.0 - cap);
    if (show_hex_grid && grid_opacity > 0.0) {
        float edge_dist = hex_edge_distance(original_world_position.xz, hex_size);
        float grid_line = smoothstep(hex_grid_width, hex_grid_width * 0.5, edge_dist);
        color_with_grid = mix(color_with_grid, hex_grid_color, grid_line * 0.8 * grid_opacity);
    }

    // Set the final color, metallic, roughness, and normal
    ALBEDO = clamp(color_with_grid, vec3(0.0), vec3(1.0));
    METALLIC = metallic;
    ROUGHNESS = mix(roughness, 0.8, cap);
    NORMAL = perturbed_normal;
}
