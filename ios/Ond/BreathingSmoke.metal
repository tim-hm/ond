#include <metal_stdlib>
using namespace metal;

static float smokeHash(float3 p) {
    p = fract(p * 0.3183099 + float3(0.17, 0.31, 0.53));
    p *= 17.0;
    return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

static float smokeNoise(float3 p) {
    float3 cell = floor(p);
    float3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = mix(smokeHash(cell), smokeHash(cell + float3(1, 0, 0)), f.x);
    float b = mix(smokeHash(cell + float3(0, 1, 0)), smokeHash(cell + float3(1, 1, 0)), f.x);
    float c = mix(smokeHash(cell + float3(0, 0, 1)), smokeHash(cell + float3(1, 0, 1)), f.x);
    float d = mix(smokeHash(cell + float3(0, 1, 1)), smokeHash(cell + float3(1, 1, 1)), f.x);
    return mix(mix(a, b, f.y), mix(c, d, f.y), f.z);
}

static float smokeDensity(float3 p, float time) {
    float angle = time * 0.23 + p.y * 1.7;
    float sine = sin(angle);
    float cosine = cos(angle);
    p.xz = float2(cosine * p.x - sine * p.z, sine * p.x + cosine * p.z);
    p += 0.24 * float3(
        sin(p.y * 3.1 + time * 0.37),
        sin(p.z * 2.7 - time * 0.29),
        cos(p.x * 2.9 + time * 0.31)
    );
    p = p * 4.2 + float3(time * 0.08, -time * 0.22, 0);
    float field = smokeNoise(p) * 0.63;
    field += smokeNoise(p * 2.03 + float3(5.2, 1.7, 8.3)) * 0.26;
    field += smokeNoise(p * 4.07 + float3(2.8, 9.1, 3.4)) * 0.11;
    float ribbons = 1.0 - smoothstep(0.025, 0.14, abs(field - 0.51));
    return ribbons * 0.78 + smoothstep(0.35, 0.70, field) * 0.12;
}

[[stitchable]] half4 breathingSmoke(
    float2 position,
    half4 source,
    float2 size,
    float time,
    float scale,
    float dark
) {
    float radius = min(size.x, size.y) * 0.5 * max(scale, 0.01);
    float2 uv = (position - size * 0.5) / radius;
    float radial = dot(uv, uv);
    if (radial >= 1.0) { return half4(0); }

    float depth = sqrt(1.0 - radial);
    float step = depth / 6.0;
    float3 accumulated = float3(0);
    float alpha = 0;

    for (int slice = 0; slice < 12; ++slice) {
        float z = depth - (float(slice) + 0.5) * step;
        float3 p = float3(uv, z);
        float envelope = 1.0 - smoothstep(0.65, 1.0, length(p));
        float density = smokeDensity(p, time) * envelope;
        float opacity = 1.0 - exp(-density * step * 1.35);
        float light = clamp(0.48 - p.x * 0.22 - p.y * 0.30 + p.z * 0.42, 0.0, 1.0);
        float3 shadow = mix(float3(0.03, 0.18, 0.24), float3(0.07, 0.24, 0.32), dark);
        float3 highlight = mix(float3(0.23, 0.53, 0.59), float3(0.78, 0.94, 0.97), dark);
        float3 color = mix(shadow, highlight, light);
        accumulated += (1.0 - alpha) * opacity * color;
        alpha += (1.0 - alpha) * opacity;
    }

    float3 normal = float3(uv, depth);
    float surfaceLight = max(dot(normal, normalize(float3(-0.5, -0.65, 1.0))), 0.0);
    float edge = pow(1.0 - depth, 3.0) * (1.0 - smoothstep(0.93, 1.0, radial));
    float skin = edge * (0.025 + surfaceLight * 0.12) + pow(surfaceLight, 20.0) * 0.12;
    float3 sheen = mix(float3(0.12, 0.44, 0.51), float3(0.78, 0.95, 1.0), dark);
    accumulated += (1.0 - alpha) * skin * sheen;
    alpha += (1.0 - alpha) * skin;

    return half4(half3(accumulated), half(alpha)) * source.a;
}
