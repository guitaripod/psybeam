#include <metal_stdlib>
using namespace metal;

struct WaveUniforms {
    float4 colorA;
    float4 colorB;
    float4 colorAccent;
    float2 resolution;
    float time;
    float amplitude;
    float mode;
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex VertexOut wave_vertex(uint vid [[vertex_id]]) {
    float2 pos[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
    VertexOut out;
    float2 p = pos[vid];
    out.position = float4(p, 0.0, 1.0);
    out.uv = p * 0.5 + 0.5;
    return out;
}

static float hash(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static float vnoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    float a = hash(i);
    float b = hash(i + float2(1.0, 0.0));
    float c = hash(i + float2(0.0, 1.0));
    float d = hash(i + float2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

static float fbm(float2 p) {
    float v = 0.0;
    float a = 0.5;
    float2x2 m = float2x2(1.6, 1.2, -1.2, 1.6);
    for (int i = 0; i < 4; i++) {
        v += a * vnoise(p);
        p = m * p;
        a *= 0.5;
    }
    return v;
}

fragment float4 wave_fragment(VertexOut in [[stage_in]], constant WaveUniforms& u [[buffer(0)]]) {
    float aspect = u.resolution.x / max(u.resolution.y, 1.0);
    float2 uv = in.uv;
    float2 p = float2(uv.x * aspect, uv.y) * 2.4;
    float t = u.time * 0.18;
    float amp = clamp(u.amplitude, 0.0, 1.0);
    float surge = amp * amp;
    p += surge * 0.42 * float2(sin(t * 1.9 + p.y * 3.1), cos(t * 1.7 + p.x * 2.7));

    float2 q = float2(fbm(p + float2(0.0, t)),
                      fbm(p + float2(5.2, 1.3 - t)));
    float2 r = float2(fbm(p + (1.0 + 0.9 * amp) * q + float2(1.7, 9.2) + 0.15 * t),
                      fbm(p + (1.0 + 0.9 * amp) * q + float2(8.3, 2.8) - 0.126 * t));
    float f = fbm(p + (1.4 + 1.3 * amp) * r);

    float bands = 0.5 + 0.5 * sin(uv.y * 6.0 - u.time * 0.6 + f * (5.0 + 2.5 * amp));
    float shade = clamp(f * 1.5 - 0.1, 0.0, 1.0);

    float3 col = mix(u.colorA.rgb, u.colorB.rgb, shade);
    col = mix(col, u.colorAccent.rgb, smoothstep(0.55, 1.0, bands) * (0.35 + 0.55 * amp));
    col += (0.05 + 0.30 * amp) * bands;

    float2 c = uv - 0.5;
    c.x *= aspect;
    float glow = exp(-dot(c, c) * (3.6 - 1.8 * amp)) * (0.12 + 0.72 * amp);
    col += glow * u.colorAccent.rgb;

    float vig = smoothstep(1.3, 0.32, length(c));
    col *= mix(0.78, 1.0, vig);
    col += (hash(uv * u.resolution + t) - 0.5) * 0.02;

    return float4(col, 1.0);
}
