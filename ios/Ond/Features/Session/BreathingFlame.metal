#include <metal_stdlib>
using namespace metal;

static float gardenHash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

static float gardenNoise(float2 p) {
    float2 cell = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(gardenHash(cell), gardenHash(cell + float2(1, 0)), f.x),
        mix(gardenHash(cell + float2(0, 1)), gardenHash(cell + float2(1, 1)), f.x), f.y
    );
}

[[stitchable]] half4 gardenFlame(
    float2 position,
    half4 source,
    float2 size,
    float time,
    float strength,
    float breeze,
    float seed
) {
    float2 uv = float2(position.x - size.x * 0.5, size.y * 0.9 - position.y) / size.y;
    float living = smoothstep(0.0, 0.08, strength);
    float height = 0.76 * sqrt(max(strength, 0.0));
    height *= 1.0 + 0.035 * sin(time * 3.7 + seed) + 0.025 * sin(time * 5.1 + seed * 1.7);
    float y = uv.y / max(height, 0.01);
    float bend = breeze * y * y * 0.30 + sin(time * 2.1 + seed + y * 3.0) * 0.022 * y;
    float x = uv.x - bend * height;
    float width = sin(pow(clamp(y, 0.0, 1.0), 0.68) * M_PI_F) * 0.19 * sqrt(max(strength, 0.0));
    float noise = gardenNoise(float2(x * 13 + seed, y * 5 - time * 1.1));
    width *= 0.90 + noise * 0.20;
    float flame = (1.0 - smoothstep(width * 0.68, width + 0.012, abs(x)))
        * smoothstep(0.0, 0.07, y) * (1.0 - smoothstep(0.85, 1.0, y)) * living;
    float core = exp(-pow(x / max(width * 0.55, 0.008), 2.0)) * (1.0 - smoothstep(0.2, 0.8, y));
    float3 fireColor = mix(float3(1.0, 0.32, 0.07), float3(1.0, 0.78, 0.27), noise * 0.5 + 0.4);
    fireColor = mix(fireColor, float3(1.0, 0.97, 0.75), core);

    float2 lightCenter = uv - float2(breeze * height * 0.12, height * 0.36);
    float glow = exp(-dot(lightCenter, lightCenter) / 0.085) * living * strength * 0.16;
    float3 color = float3(1.0, 0.55, 0.16) * glow;
    float alpha = glow;
    color += (1.0 - alpha) * flame * fireColor;
    alpha += (1.0 - alpha) * flame;

    float smokeOn = (1.0 - smoothstep(0.01, 0.22, strength)) * smoothstep(0.0, 2.0, time);
    float smokeY = max(0.0, uv.y);
    float smokeX = uv.x - sin(smokeY * 10 - time * 1.3 + seed) * 0.055 * smokeY;
    float plume = exp(-pow(smokeX / (0.012 + smokeY * 0.055), 2.0));
    float smoke = plume * smoothstep(0.0, 0.08, smokeY) * (1.0 - smoothstep(0.35, 0.88, smokeY));
    smoke *= gardenNoise(float2(uv.x * 18 + seed, smokeY * 8 - time * 0.8)) * smokeOn * 0.35;
    color += (1.0 - alpha) * smoke * float3(0.70, 0.77, 0.84);
    alpha += (1.0 - alpha) * smoke;

    float2 edge = abs(position - size * 0.5) / (size * 0.5);
    float2 fade = 1.0 - smoothstep(float2(0.82), float2(1.0), edge);
    return half4(half3(color), half(alpha)) * source.a * half(fade.x * fade.y);
}
