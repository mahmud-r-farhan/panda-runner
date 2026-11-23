#version 460 core
#include <flutter/runtime_effect.glsl>

// Port of the demo's "Single-Pass Fused Subtle Peripheral Overcharge
// Filaments" (I_/L_): radial streaks in the outer ring of the viewport,
// opacity <= 0.14, composited additively over the frame.
uniform vec2 uSize;
uniform float uTime;
uniform float uOvercharge;

out vec4 fragColor;

void main() {
  vec2 vUv = FlutterFragCoord().xy / uSize;
  vUv.y = 1.0 - vUv.y;
  vec2 p = (vUv - 0.5) * vec2(1.777, 1.0);
  float rad = length(p);
  float edgeMask = smoothstep(0.74, 1.08, rad);
  float ang = atan(p.y, p.x);
  float rayA = pow(max(0.5 + 0.5 * sin(ang * 48.0 + uTime * 22.0), 1e-4), 22.0);
  float rayB = pow(max(0.5 + 0.5 * sin(ang * 78.0 - uTime * 31.0), 1e-4), 26.0);
  float streaks = (rayA * 0.58 + rayB * 0.42) * edgeMask * clamp(uOvercharge, 0.0, 1.0);
  vec3 col = mix(vec3(1.0, 0.36, 0.08), vec3(0.22, 0.74, 0.98), clamp(rayB * 1.4, 0.0, 1.0));
  fragColor = vec4(col * streaks * 0.14, 0.0);
}
