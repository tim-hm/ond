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

static float smokeTime(float elapsed, float seed) {
    // The derivative stays positive, so speed changes cannot reverse time.
    return elapsed * 1.55
        + 0.70 * (sin(elapsed * 0.79 + seed) - sin(seed))
        + 0.28 * (sin(elapsed * 1.83 + seed * 1.7) - sin(seed * 1.7));
}

static float2 smokeMaterial(float3 p, float time, float seed) {
    float variation = smokeHash(float3(seed, 2.7, 9.1));
    float angle = time * mix(0.24, 0.36, variation) + p.y * 1.7 + 0.45 * sin(time * 0.60 + seed);
    float sine = sin(angle);
    float cosine = cos(angle);
    p.xz = float2(cosine * p.x - sine * p.z, sine * p.x + cosine * p.z);
    p += 0.32 * float3(
        sin(p.y * 3.1 + time * 0.47 + seed),
        sin(p.z * 2.7 - time * 0.39 + seed * 1.3),
        cos(p.x * 2.9 + time * 0.41 + seed * 0.7)
    );
    p = p * mix(3.8, 4.7, variation) + float3(time * 0.08 + seed, -time * 0.22, seed * 0.3);
    float field = smokeNoise(p) * 0.63;
    field += smokeNoise(p * 2.03 + float3(5.2, 1.7, 8.3)) * 0.26;
    field += smokeNoise(p * 4.07 + float3(2.8, 9.1, 3.4)) * 0.11;
    float ribbons = 1.0 - smoothstep(0.025, 0.14, abs(field - 0.51));
    float pigment = smokeNoise(p * 0.83 + float3(7.3, 2.6, 4.1)) * 0.60
        + smokeNoise(p * 1.71 + float3(3.2, 8.4, 1.7)) * 0.40;
    float current = smoothstep(0.32, 0.68, pigment);
    return float2(ribbons * 0.78 + smoothstep(0.35, 0.70, field) * 0.12, current);
}

static float smokeWisp(float3 p, float4 strand, float time, float seed) {
    float2 direction = float2(cos(strand.x), sin(strand.x));
    float2 tangent = float2(-direction.y, direction.x);
    float along = dot(p.xy, direction);
    float travel = clamp((along - 0.40) / strand.y, 0.0, 1.0);
    float bend = travel * travel * (0.23 * sin(travel * 4.8 + strand.z + time * 0.29)
        + 0.15 * sin(travel * 8.1 - time * 0.17 + seed));
    float across = dot(p.xy, tangent) - bend;
    float depth = p.z - strand.w * travel - 0.12 * sin(travel * 4.0 + strand.z);
    float width = mix(0.16, 0.025, travel) * (0.88 + 0.12 * sin(time * 0.37 + strand.z));
    float distance = length(float2(across, depth * 0.55));
    float tube = 1.0 - smoothstep(width * 0.15, width, distance);
    float tip = 1.0 - smoothstep(0.64, 1.0, travel);
    float root = smoothstep(0.34, 0.60, along);
    return tube * tip * root * (0.48 + 0.14 * sin(time * 0.23 + strand.z));
}

[[stitchable]] half4 breathingSmoke(
    float2 position,
    half4 source,
    float2 size,
    float elapsed,
    float radius,
    float expansion,
    float dark,
    float seed
) {
    float time = smokeTime(elapsed, seed);
    float2 uv = (position - size * 0.5) / max(radius, 0.01);
    float radial = dot(uv, uv);
    if (radial >= 2.56) { return half4(0); }

    float depth = sqrt(2.56 - radial);
    float step = depth / 8.0;
    float3 accumulated = float3(0);
    float alpha = 0;
    float gathered = 1.0 - smoothstep(0.24, 0.60, expansion);
    int strandCount = 3 + int(smokeHash(float3(seed, 6.2, 1.9)) * 3.0);
    float4 strands[5];
    for (int strand = 0; strand < strandCount; ++strand) {
        float random = smokeHash(float3(seed, float(strand) * 3.7, 5.2));
        float phase = random * 6.2831853 + seed;
        float angle = float(strand) * 6.2831853 / float(strandCount) + seed
            + (random - 0.5) * 0.85 + time * 0.045 + 0.18 * sin(time * 0.21 + phase);
        float reach = mix(0.80, 1.12, random) + 0.06 * sin(time * 0.31 + phase);
        strands[strand] = float4(angle, reach, phase, (random - 0.5) * 0.7);
    }

    for (int slice = 0; slice < 16; ++slice) {
        float z = depth - (float(slice) + 0.5) * step;
        float3 p = float3(uv, z);
        float billow = smokeNoise(p * 1.6 + float3(seed, -time * 0.18, time * 0.12));
        float reach = mix(0.88 + (billow - 0.5) * 0.28, 0.90 + (billow - 0.5) * 0.12, gathered);
        float envelope = 1.0 - smoothstep(mix(0.38, 0.56, gathered), reach, length(p));
        float wisps = 0;
        for (int strand = 0; strand < strandCount; ++strand) {
            wisps = max(wisps, smokeWisp(p, strands[strand], time, seed));
        }
        float2 material = smokeMaterial(p, time, seed);
        float density = material.x * envelope
            + (0.20 + material.x * 0.80) * wisps * (1.0 - gathered) * (1.0 - envelope);
        float opacity = 1.0 - exp(-density * step * mix(1.35, 1.85, gathered));
        float light = clamp(0.48 - p.x * 0.22 - p.y * 0.30 + p.z * 0.42, 0.0, 1.0);
        float3 shadow = mix(float3(0.03, 0.18, 0.24), float3(0.07, 0.24, 0.32), dark);
        float3 highlight = mix(float3(0.23, 0.53, 0.59), float3(0.78, 0.94, 0.97), dark);
        float3 color = mix(shadow, highlight, light);
        float3 seaGlass = mix(float3(0.12, 0.48, 0.36), float3(0.30, 0.76, 0.56), dark);
        float3 lilac = mix(float3(0.42, 0.28, 0.57), float3(0.66, 0.43, 0.90), dark);
        color = mix(color, mix(seaGlass, lilac, material.y), 0.34 * smoothstep(0.1, 0.8, light));
        accumulated += (1.0 - alpha) * opacity * color;
        alpha += (1.0 - alpha) * opacity;
    }

    float2 edge = abs(position - size * 0.5) / (size * 0.5);
    float2 fade = 1.0 - smoothstep(float2(0.84), float2(1.0), edge);
    return half4(half3(accumulated), half(alpha)) * source.a * half(fade.x * fade.y);
}
