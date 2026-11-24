#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 u_size;
uniform sampler2D u_texture;
uniform float u_effect;
uniform float u_time;
uniform float u_p0;
uniform float u_p1;
uniform float u_p2;
uniform float u_p3;
uniform float u_p4;
uniform float u_p5;
uniform float u_p6;
uniform float u_p7;
uniform float u_p8;
uniform float u_p9;
uniform float u_p10;
uniform float u_p11;
uniform float u_p12;
uniform float u_p13;
uniform float u_p14;
uniform float u_p15;
uniform float u_p16;
uniform float u_p17;
uniform float u_p18;
uniform float u_p19;
uniform float u_p20;
uniform float u_p21;
uniform float u_p22;
uniform float u_p23;

out vec4 fragColor;

float luminance(vec3 c) {
  return dot(c, vec3(0.2126, 0.7152, 0.0722));
}
float noiseValue(vec2 p) {
  return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
vec4 sampleAt(vec2 uv) {
  return texture(u_texture, clamp(uv, vec2(0.001), vec2(0.999)));
}
vec3 rgbAt(vec2 uv) {
  vec4 value = sampleAt(uv);
  if (value.a > 0.0001) return value.rgb / value.a;
  return value.rgb;
}
vec3 blurAt(vec2 uv, vec2 stepSize) {
  vec3 a = rgbAt(uv);
  vec3 b = rgbAt(uv + vec2(stepSize.x, 0.0));
  vec3 c = rgbAt(uv - vec2(stepSize.x, 0.0));
  vec3 d = rgbAt(uv + vec2(0.0, stepSize.y));
  vec3 e = rgbAt(uv - vec2(0.0, stepSize.y));
  return (a * 0.36 + b * 0.16 + c * 0.16 + d * 0.16 + e * 0.16);
}

void main() {
  vec2 uv = FlutterFragCoord().xy / u_size;
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif
  vec2 px = vec2(1.0) / max(u_size, vec2(1.0));
  float id = floor(u_effect + 0.5);
  float time = u_time;

  // Spatial mapping: all geometry is sampled before tonal processing.
  if (id == 16.0) uv.x = 1.0 - uv.x;
  if (id == 17.0) uv.y = 1.0 - uv.y;
  if (id == 10.0) {
    float blockSize = max(2.0, u_p0);
    uv = (floor(uv * u_size / blockSize) + 0.5) * blockSize / u_size;
  }
  if (id == 20.0) {
    uv.x += sin(uv.y * max(16.0, u_p1) + time * u_p2) * u_p0 * px.x;
    uv.y += cos(uv.x * max(16.0, u_p1) + time * u_p2) * u_p0 * px.y;
  }
  if (id == 23.0 || id == 46.0) {
    vec2 q = uv - 0.5;
    float strength = u_p0;
    uv = 0.5 + q * (1.0 + strength * dot(q, q) * 2.0);
  }
  if (id == 24.0) {
    vec2 q = (uv - 0.5) / max(0.01, u_p0 / 100.0);
    float angle = u_p1 * 0.0174532925;
    float cs = cos(angle);
    float sn = sin(angle);
    uv = 0.5 + vec2(q.x * cs - q.y * sn, q.x * sn + q.y * cs);
  }
  if (id == 27.0) {
    uv = 0.5 + (uv - 0.5) * (1.0 - clamp(u_p0 / 700.0, 0.0, 0.12));
  }
  if (id == 45.0 || id == 58.0 || id == 59.0) {
    float scale = max(12.0, u_p1);
    float speed = u_p2;
    uv.x += sin(uv.y * u_size.y / scale + time * speed) * u_p0 * px.x;
    if (id != 45.0) {
      uv.y += cos(uv.x * u_size.x / scale + time * speed) * u_p0 * px.y * 0.3;
    }
  }
  if (id == 60.0) {
    float angle = sin(time * max(0.1, u_p1) * 6.28318) * u_p0 * 0.0009;
    vec2 q = uv - 0.5;
    uv = 0.5 + vec2(q.x * cos(angle) - q.y * sin(angle),
                    q.x * sin(angle) + q.y * cos(angle));
  }

  vec4 inputColor = sampleAt(uv);
  float alpha = inputColor.a;
  vec3 color = alpha > 0.0001 ? inputColor.rgb / alpha : inputColor.rgb;
  float radial = length(uv - 0.5);

  // Exposure, contrast, saturation and channel effects.
  if (id == 1.0) color += vec3(u_p0);
  if (id == 2.0) color = (color - 0.5) * u_p0 + 0.5;
  if (id == 3.0) color = mix(vec3(luminance(color)), color, u_p0);
  if (id == 4.0) color = pow(max(color, vec3(0.0)), vec3(1.0 / max(0.2, u_p0)));
  if (id == 8.0) color *= 1.0 - clamp(radial * u_p0 * 0.9, 0.0, 0.9);
  if (id == 11.0) color = vec3(step(u_p0 / 255.0, luminance(color)));
  if (id == 12.0) color = 1.0 - color;
  if (id == 13.0) color = vec3(luminance(color));
  if (id == 28.0) {
    float levels = max(2.0, u_p0);
    color = floor(color * levels) / levels;
  }
  if (id == 29.0) color += vec3(u_p0, u_p1, u_p2);
  if (id == 32.0) {
    color += vec3(u_p0, u_p1, u_p2) * 0.15;
    color *= vec3(1.0) + vec3(u_p6, u_p7, u_p8) * 0.35;
    color = (color - 0.5) * u_p14 + 0.5 + u_p15;
    color = mix(vec3(luminance(color)), color, u_p17);
  }
  if (id == 33.0) color *= exp2(u_p0);
  if (id == 34.0) {
    float angle = u_p0 * 0.0174532925;
    vec3 axis = vec3(0.57735);
    color = color * cos(angle) + cross(axis, color) * sin(angle) +
            axis * dot(axis, color) * (1.0 - cos(angle));
  }
  if (id == 35.0) {
    vec3 tint = vec3(0.5 + 0.5 * cos(6.28318 * (u_p0 / 360.0 + vec3(0.0, 0.33, 0.67))));
    color = mix(color, tint, clamp(u_p3, 0.0, 1.0));
  }
  if (id == 49.0) {
    float l = luminance(color);
    float chroma = max(max(color.r, color.g), color.b) - min(min(color.r, color.g), color.b);
    color = mix(vec3(l), color, 1.0 + u_p0 * (1.0 - chroma));
  }
  if (id == 50.0) color = (color - 0.5) * (1.0 + vec3(u_p0, u_p1, u_p2)) + 0.5;
  if (id == 51.0) {
    float gray = (color.r + color.g + color.b) / 3.0;
    color = color * gray / max(color, vec3(0.025));
  }
  if (id == 52.0) {
    vec3 source = color;
    color = vec3(
      source.r * u_p0 + source.g * u_p1 + source.b * u_p2,
      source.r * u_p3 + source.g * u_p4 + source.b * u_p5,
      source.r * u_p6 + source.g * u_p7 + source.b * u_p8);
  }
  if (id == 66.0) {
    color = (mix(vec3(luminance(color)), color, u_p1) - 0.5) * u_p0 + 0.5;
  }
  if (id == 67.0) {
    color = vec3(dot(color, vec3(0.393, 0.769, 0.189)),
                 dot(color, vec3(0.349, 0.686, 0.168)),
                 dot(color, vec3(0.272, 0.534, 0.131)));
  }

  // Spatial blur, sharpen and detail effects.
  if (id == 5.0 || id == 6.0 || id == 22.0 || id == 36.0 ||
      id == 37.0 || id == 38.0 || id == 44.0 || id == 47.0 ||
      id == 48.0 || id == 54.0 || id == 55.0 || id == 56.0 || id == 57.0) {
    float radius = max(0.4, u_p0) * 0.7;
    vec2 direction = vec2(1.0, 0.0);
    if (id == 36.0) {
      float angle = u_p0 * 0.0174532925;
      direction = vec2(cos(angle), sin(angle));
    }
    if (id == 47.0) direction = normalize(uv - 0.5 + vec2(0.0001));
    vec3 blurred = blurAt(uv, px * radius * direction);
    float amount = 0.72;
    if (id == 38.0) amount = 0.22;
    if (id == 48.0) amount = 0.65;
    if (id == 54.0 || id == 55.0) amount = 0.38;
    if (id == 56.0 || id == 57.0) amount = 0.3;
    color = mix(color, blurred, amount);
  }
  if (id == 7.0 || id == 53.0) {
    vec3 blurred = blurAt(uv, px);
    color += (color - blurred) * u_p0;
  }
  if (id == 15.0 || id == 68.0) {
    float dx = luminance(rgbAt(uv + vec2(px.x, 0.0))) -
               luminance(rgbAt(uv - vec2(px.x, 0.0)));
    float dy = luminance(rgbAt(uv + vec2(0.0, px.y))) -
               luminance(rgbAt(uv - vec2(0.0, px.y)));
    float edge = clamp(length(vec2(dx, dy)) * 4.0, 0.0, 1.0);
    if (id == 15.0) color = vec3(edge);
    if (id == 68.0) color += vec3(edge * u_p1);
  }
  if (id == 19.0) {
    vec3 soft = blurAt(uv, px * 2.0);
    color += max(soft - vec3(u_p0), vec3(0.0)) * u_p2;
  }
  if (id == 18.0) {
    float shadow = sampleAt(uv - vec2(u_p2 * px.x, u_p2 * px.y)).a;
    color = mix(vec3(0.0), color, clamp(alpha + shadow * u_p0, 0.0, 1.0));
  }

  // Noise, keying, stylised overlays and animated looks.
  if (id == 9.0 || id == 64.0 || id == 65.0) {
    float n = noiseValue(gl_FragCoord.xy + floor(time * 24.0)) - 0.5;
    float amount = u_p0;
    if (id == 65.0) amount = u_p1;
    color += vec3(n * amount / 255.0);
  }
  if (id == 21.0) {
    vec2 cell = floor((uv * u_size + time * u_p3 * 18.0) / max(16.0, u_p0));
    color += step(0.985, noiseValue(cell)) * u_p2;
  }
  if (id == 14.0 || id == 42.0 || id == 45.0 || id == 65.0) {
    float shift = max(0.0, u_p0) * px.x;
    color.r = rgbAt(uv + vec2(shift, 0.0)).r;
    color.b = rgbAt(uv - vec2(shift, 0.0)).b;
  }
  if (id == 25.0) {
    float greenExcess = color.g - max(color.r, color.b);
    alpha *= 1.0 - smoothstep(u_p0 * 0.15, u_p0 * 0.15 + u_p1 * 0.45, greenExcess);
  }
  if (id == 26.0) alpha *= smoothstep(u_p0 - u_p1, u_p0 + u_p1, luminance(color));
  if (id == 39.0) {
    float dither = (noiseValue(gl_FragCoord.xy) - 0.5) / 255.0;
    color += vec3(dither);
  }
  if (id == 40.0) color *= 1.0 - sin(time * 6.28318 * max(1.0, u_p0)) * 0.008;
  if (id == 41.0) {
    float line = mod(gl_FragCoord.y, max(2.0, u_p0));
    if (line < u_p1) color *= 1.0 - clamp(u_p2, 0.0, 1.0);
  }
  if (id == 43.0) {
    float cadence = max(2.0, u_p0);
    float pulse = step(0.92, fract(time * cadence));
    color *= 1.0 - pulse * 0.025;
  }
  if (id == 61.0) color += vec3(u_p0 * 0.45);
  if (id == 62.0) {
    if (uv.y < u_p0 || uv.y > 1.0 - u_p0) color = vec3(0.0);
  }
  if (id == 63.0) {
    float edge = min(min(uv.x, uv.y), min(1.0 - uv.x, 1.0 - uv.y));
    if (edge * min(u_size.x, u_size.y) < u_p0) color = mix(color, vec3(1.0), u_p1);
  }
  if (id == 64.0) {
    color.r += u_p2 * 0.06;
    color.b -= u_p2 * 0.04;
    color *= 1.0 - radial * u_p1 * 0.45;
  }
  if (id == 65.0) {
    float line = step(0.94, fract(uv.y * 38.0 + time * 4.0));
    color += vec3(line * 0.12, 0.0, line * 0.06);
  }

  fragColor = vec4(clamp(color, 0.0, 1.0) * alpha, alpha);
}
