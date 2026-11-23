#version 460 core
#include <flutter/runtime_effect.glsl>

// The demo's display-space vignette from its grade pass:
// graded *= clamp(1 - dot(uv - .5, uv - .5) * uVignette, 0.76, 1.0)
uniform vec2 uSize;
uniform float uVignette;

out vec4 fragColor;

void main() {
  vec2 c = FlutterFragCoord().xy / uSize - 0.5;
  float v = clamp(1.0 - dot(c, c) * uVignette, 0.76, 1.0);
  fragColor = vec4(v, v, v, 1.0);
}
