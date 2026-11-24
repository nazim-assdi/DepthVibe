#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 u_size;
uniform float u_lut_size;
uniform vec3 u_domain_min;
uniform vec3 u_domain_max;
uniform sampler2D u_texture;
uniform sampler2D u_lut;

out vec4 fragColor;

vec3 sourceAt(vec2 uv) {
  vec4 sampleColor = texture(u_texture, clamp(uv, vec2(0.001), vec2(0.999)));
  return sampleColor.a > 0.00001 ? sampleColor.rgb / sampleColor.a : sampleColor.rgb;
}
vec3 lutCell(float red, float green, float blue, float size) {
  float x = (blue * size + red + 0.5) / (size * size);
  float y = (green + 0.5) / size;
  return texture(u_lut, vec2(x, y)).rgb;
}
vec3 lookupLut(vec3 value) {
  float n = max(2.0, u_lut_size);
  vec3 domain = max(u_domain_max - u_domain_min, vec3(0.000001));
  vec3 coords = clamp((value - u_domain_min) / domain, 0.0, 1.0) * (n - 1.0);
  vec3 lo = floor(coords);
  vec3 hi = min(vec3(n - 1.0), lo + 1.0);
  vec3 f = fract(coords);

  vec3 c000 = lutCell(lo.r, lo.g, lo.b, n);
  vec3 c100 = lutCell(hi.r, lo.g, lo.b, n);
  vec3 c010 = lutCell(lo.r, hi.g, lo.b, n);
  vec3 c110 = lutCell(hi.r, hi.g, lo.b, n);
  vec3 c001 = lutCell(lo.r, lo.g, hi.b, n);
  vec3 c101 = lutCell(hi.r, lo.g, hi.b, n);
  vec3 c011 = lutCell(lo.r, hi.g, hi.b, n);
  vec3 c111 = lutCell(hi.r, hi.g, hi.b, n);

  vec3 lowBlue = mix(
    mix(c000, c100, f.r),
    mix(c010, c110, f.r),
    f.g
  );
  vec3 highBlue = mix(
    mix(c001, c101, f.r),
    mix(c011, c111, f.r),
    f.g
  );
  return mix(lowBlue, highBlue, f.b);
}

void main() {
  vec2 uv = FlutterFragCoord().xy / u_size;
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif
  vec4 inputColor = texture(u_texture, clamp(uv, vec2(0.001), vec2(0.999)));
  vec3 source = inputColor.a > 0.00001
      ? inputColor.rgb / inputColor.a
      : inputColor.rgb;
  vec3 corrected = clamp(lookupLut(source), 0.0, 1.0);
  fragColor = vec4(corrected * inputColor.a, inputColor.a);
}
