shader_type sky;

// ---------- SKY COLORS ----------
group_uniforms sky_colors;
uniform vec3 sky_top : source_color = vec3(0.16, 0.42, 0.86);
uniform vec3 sky_mid : source_color = vec3(0.42, 0.68, 0.95);
uniform vec3 sky_horizon : source_color = vec3(0.86, 0.93, 0.98);
uniform vec3 golden_horizon : source_color = vec3(1.0, 0.72, 0.45);
uniform vec3 ground_color : source_color = vec3(0.58, 0.66, 0.72);
uniform float horizon_haze : hint_range(0.0, 1.0) = 0.5;

// ---------- SUN ----------
group_uniforms sun;
uniform vec3 sun_direction = vec3(0.45, 0.38, -0.8);
uniform vec3 sun_color : source_color = vec3(1.0, 0.93, 0.78);
uniform float sun_size : hint_range(0.005, 0.1) = 0.03;
uniform float sun_glow : hint_range(0.0, 2.0) = 0.8;

// ---------- CLOUDS ----------
group_uniforms clouds;
uniform vec3 cloud_lit_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 cloud_shadow_color : source_color = vec3(0.62, 0.70, 0.84);
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.5;
uniform float cloud_softness : hint_range(0.05, 0.8) = 0.35;
uniform float cloud_scale : hint_range(0.2, 4.0) = 1.1;
uniform float cloud_speed : hint_range(0.0, 0.2) = 0.012;
uniform vec2 wind_direction = vec2(1.0, 0.3);

// ---------- NOISE ----------
float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	mat2 rot = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p = rot * p * 2.03 + 11.7;
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	vec3 sun_dir = normalize(sun_direction);
	float h = dir.y;
	float sun_dot = max(dot(dir, sun_dir), 0.0);

	// How low the sun is: 1 = golden hour, 0 = high noon
	float golden = 1.0 - smoothstep(0.05, 0.55, sun_dir.y);

	// ----- Gradient sky -----
	float up = clamp(h, 0.0, 1.0);
	vec3 horizon_col = mix(sky_horizon, golden_horizon, golden * 0.8);
	vec3 col = mix(horizon_col, sky_mid, smoothstep(0.0, 0.25, up));
	col = mix(col, sky_top, smoothstep(0.2, 0.9, up));

	// Very slow "breathing" so the sky feels alive
	col *= 1.0 + 0.025 * sin(TIME * 0.2);

	// ----- Warm light scattering near the sun -----
	float scatter = pow(sun_dot, 3.0) * (1.0 - up * 0.6);
	col += mix(sun_color, golden_horizon, golden) * scatter * 0.22;

	// ----- Sun disc + glow -----
	float disc = smoothstep(cos(sun_size), cos(sun_size * 0.7), dot(dir, sun_dir));
	float glow = pow(sun_dot, 180.0) * 0.9 + pow(sun_dot, 24.0) * 0.25 + pow(sun_dot, 6.0) * 0.08;
	col += sun_color * (disc * 2.5 + glow * sun_glow);

	// ----- Clouds (skipped in the reflection cubemap for performance) -----
	if (h > 0.0 && !AT_CUBEMAP_PASS) {
		vec2 uv = dir.xz / (h + 0.18);
		vec2 wind = normalize(wind_direction) * TIME * cloud_speed;

		// Main puffy layer
		vec2 p = uv * cloud_scale + wind;
		float n = fbm(p);
		float density = smoothstep(1.0 - cloud_coverage - 0.1, 1.0 - cloud_coverage - 0.1 + cloud_softness, n);

		// Fake lighting: sample towards the sun, brighter where cloud thins
		float n_sun = fbm(p + normalize(sun_dir.xz + 0.0001) * 0.12);
		float light = clamp(0.55 + (n - n_sun) * 4.0, 0.0, 1.0);

		vec3 lit = mix(cloud_lit_color, golden_horizon + 0.4, golden * 0.6);
		vec3 cloud_col = mix(cloud_shadow_color, lit, light);

		// Silver lining when looking toward the sun
		float lining = pow(sun_dot, 8.0) * (1.0 - density * 0.6);
		cloud_col += sun_color * lining * 0.5;

		// Fade into the horizon haze
		float fade = smoothstep(0.0, 0.22, h);
		col = mix(col, cloud_col, density * fade * 0.95);

		// High, thin wispy layer moving the other way
		vec2 p2 = uv * cloud_scale * 0.5 - wind * 0.6 + vec2(4.2, 1.3);
		float wisp = fbm(p2 * vec2(1.0, 2.5));
		wisp = smoothstep(0.5, 0.9, wisp) * 0.3 * fade;
		col = mix(col, cloud_lit_color, wisp);
	}

	// ----- Horizon haze -----
	float haze = exp(-abs(h) * 9.0) * horizon_haze;
	col = mix(col, horizon_col, haze * 0.6);

	// ----- Ground (below horizon) -----
	vec3 ground = mix(ground_color, horizon_col, exp(-abs(h) * 4.0));
	col = mix(col, ground, smoothstep(0.01, -0.06, h));

	COLOR = col;
}
