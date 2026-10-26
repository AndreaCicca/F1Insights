#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// Dark vertical "speed line" backdrop for the replay canvas. Faint scanlines
// drift left to suggest motion; a top-to-bottom slate gradient anchors it.
[[ stitchable ]] half4 speedGrid(float2 pos, half4 color, float2 size, float time) {
    float2 uv = pos / max(size, float2(1.0));
    float lines = sin(uv.x * 44.0 - time * 5.0);
    float g = smoothstep(0.92, 1.0, lines) * 0.05;
    half3 base = mix(half3(0.02, 0.02, 0.045), half3(0.06, 0.07, 0.13), half(uv.y));
    base += half3(g);
    float d = distance(uv, float2(0.5, 0.45));
    base *= half(1.0 - d * 0.35);
    return half4(base, 1.0);
}

