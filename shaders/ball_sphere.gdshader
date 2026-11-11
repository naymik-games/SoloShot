shader_type canvas_item;
// Renders a lit, rotating sphere inside a flat quad. The quad is drawn by BallView with UV 0..1.
//
// View space: x right, y UP, z toward the viewer. The ball's orientation arrives as `to_local`
// (view -> ball-local). Texture layout (2:1 equirectangular):
//   u = 0.5 + longitude / 360, longitude = atan(x, z)   (u = 0.5 faces the viewer at rest)
//   v = 0.5 - latitude / 180                            (top of the image = local +Y)
// Local +X is u = 0.75 and local -X is u = 0.25 (where the number spots go).

uniform sampler2D ball_tex : source_color, filter_linear, repeat_enable;
uniform bool use_texture = true;

// Fallback look when a ball has no texture yet: flat color, optional stripe, two white spots.
uniform vec4 fallback_color : source_color = vec4(1.0);
uniform bool fallback_stripe = false;

uniform mat3 to_local = mat3(1.0);

// The quad is drawn this many times larger than the ball, leaving room for the antialiased edge
// and the drop shadow (shadow reach = shadow_distance + shadow_radius must stay below this).
uniform float pad = 1.7;
// Outline thickness in ball-radius units (BallView sets this to ~1 screen pixel).
uniform float outline_width = 0.05;
uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 0.45);

// Lighting is fixed in view space, so highlights stay put while the texture rolls.
uniform vec3 light_dir = vec3(-0.35, 0.55, 0.75);
uniform float ambient : hint_range(0.0, 1.0) = 0.50;
uniform float diffuse : hint_range(0.0, 1.0) = 0.60;
uniform float spec_strength : hint_range(0.0, 2.0) = 0.50;
uniform float spec_power : hint_range(1.0, 200.0) = 45.0;

// Soft drop shadow, cast away from the light. All sizes are in ball-radius units.
uniform float shadow_opacity : hint_range(0.0, 1.0) = 0.35;
uniform float shadow_distance = 0.19; // How far the shadow is shifted from the ball center.
uniform float shadow_inner = 0.60;    // Shadow is at full strength inside this radius...
uniform float shadow_radius = 1.35;   // ...and fades to nothing at this one.
uniform vec4 shadow_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);

vec3 fallback_albedo(vec3 l) {
	vec3 base = fallback_color.rgb;
	if (fallback_stripe) {
		// White caps above and below a colored band (same proportions as the old drawn balls).
		base = mix(vec3(0.97, 0.97, 0.94), base, 1.0 - smoothstep(0.55, 0.58, abs(l.y)));
	}
	// White number spots at local +X / -X.
	float spot = smoothstep(0.86, 0.89, abs(l.x));
	return mix(base, vec3(0.97, 0.97, 0.94), spot);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0 * pad;
	p.y = -p.y; // Screen y is down; view space y is up.

	float d = length(p);
	float aa = max(fwidth(d), 0.0001);
	float ball_a = clamp((1.0 - d) / aa + 0.5, 0.0, 1.0);

	// Shadow: a soft disc offset away from the light.
	vec2 away = -light_dir.xy / max(length(light_dir.xy), 0.0001);
	float sh = shadow_opacity * (1.0 - smoothstep(shadow_inner, shadow_radius,
			length(p - away * shadow_distance)));

	vec3 ball_rgb = vec3(0.0);
	if (ball_a > 0.0) {
		float z = sqrt(max(1.0 - d * d, 0.0));
		vec3 n = normalize(vec3(p, z));
		vec3 l = to_local * n;

		vec3 albedo;
		if (use_texture) {
			float u = 0.5 + atan(l.x, l.z) / TAU;
			float v = 0.5 - asin(clamp(l.y, -1.0, 1.0)) / PI;
			albedo = texture(ball_tex, vec2(u, v)).rgb;
		} else {
			albedo = fallback_albedo(l);
		}

		vec3 L = normalize(light_dir);
		float diff = max(dot(n, L), 0.0);
		ball_rgb = albedo * (ambient + diffuse * diff);

		vec3 H = normalize(L + vec3(0.0, 0.0, 1.0));
		ball_rgb += vec3(pow(max(dot(n, H), 0.0), spec_power) * spec_strength);

		float ring = smoothstep(1.0 - outline_width - aa, 1.0 - outline_width, d);
		ball_rgb = mix(ball_rgb, outline_color.rgb, ring * outline_color.a);
	}

	// Ball over shadow.
	float shadow_a = sh * (1.0 - ball_a);
	float out_a = ball_a + shadow_a;
	vec3 out_rgb = out_a > 0.0 ? (ball_rgb * ball_a + shadow_color.rgb * shadow_a) / out_a : vec3(0.0);
	COLOR = vec4(out_rgb, out_a);
}
