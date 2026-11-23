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

float hash21(vec2 p) {
  p = fract(p * vec2(123.34, 456.21));
  p += dot(p, p + 45.32);
  return fract(p.x * p.y);
}
vec4 sampleAt(vec2 uv) {
  return texture(u_texture, clamp(uv, vec2(0.001), vec2(0.999)));
}
vec3 colorAt(vec2 uv) {
  vec4 s = sampleAt(uv);
  return s.a > 0.00001 ? s.rgb / s.a : s.rgb;
}
float luminance(vec3 c) {
  return dot(c, vec3(0.2126, 0.7152, 0.0722));
}
vec3 saturation(vec3 c, float amount) {
  return mix(vec3(luminance(c)), c, amount);
}
vec3 hueRotate(vec3 c, float degrees) {
  float a = degrees * 0.01745329252;
  float cs = cos(a);
  float sn = sin(a);
  mat3 m = mat3(
    0.213 + cs * 0.787 - sn * 0.213,
    0.715 - cs * 0.715 - sn * 0.715,
    0.072 - cs * 0.072 + sn * 0.928,
    0.213 - cs * 0.213 + sn * 0.143,
    0.715 + cs * 0.285 + sn * 0.140,
    0.072 - cs * 0.072 - sn * 0.283,
    0.213 - cs * 0.213 - sn * 0.787,
    0.715 - cs * 0.715 + sn * 0.715,
    0.072 + cs * 0.928 + sn * 0.072
  );
  return clamp(m * c, 0.0, 1.0);
}
vec3 hsvToRgb(vec3 c) {
  vec3 p = abs(fract(c.xxx + vec3(0.0, 0.6666667, 0.3333333)) * 6.0 - 3.0);
  return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}
float curve5(float x, float a, float b, float c, float d, float e) {
  if (x < 0.25) return mix(a,b,x*4.0);
  if (x < 0.50) return mix(b,c,(x-0.25)*4.0);
  if (x < 0.75) return mix(c,d,(x-0.50)*4.0);
  return mix(d,e,(x-0.75)*4.0);
}
vec3 softBlur(vec2 uv, vec2 direction, float radius, vec2 px) {
  vec3 result = colorAt(uv) * 0.28;
  result += colorAt(uv + direction * radius * px) * 0.18;
  result += colorAt(uv - direction * radius * px) * 0.18;
  result += colorAt(uv + vec2(direction.y, -direction.x) * radius * px) * 0.12;
  result += colorAt(uv - vec2(direction.y, -direction.x) * radius * px) * 0.12;
  result += colorAt(uv + direction * radius * px * 2.0) * 0.06;
  result += colorAt(uv - direction * radius * px * 2.0) * 0.06;
  return result;
}

void main() {
  vec2 uv = FlutterFragCoord().xy / u_size;
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif
  vec2 px = 1.0 / max(u_size, vec2(1.0));
  float type = floor(u_effect + 0.5);
  float t = u_time;

  // Geometry and source-space effects.
  if (type == 16.0) uv.x = 1.0 - uv.x;                         // Mirror
  if (type == 17.0) uv.y = 1.0 - uv.y;                         // Flip
  if (type == 10.0) {                                          // Pixelate
    float block = max(2.0, u_p0);
    uv = (floor(uv * u_size / block) + 0.5) * block / u_size;
  }
  if (type == 23.0 || type == 46.0) {                           // Lens / fisheye
    vec2 q = (uv - 0.5) * 2.0;
    float r2 = dot(q,q);
    float strength = type == 23.0 ? u_p0 : u_p0;
    uv = 0.5 + q * (0.5 + strength * r2 * 0.22);
  }
  if (type == 20.0) {                                          // Displacement
    float a = u_p0;
    float wave = max(20.0, u_p1);
    uv += vec2(sin(uv.y*u_size.y/wave+t*u_p2),
               cos(uv.x*u_size.x/wave+t*u_p2)) * a * px;
  }
  if (type == 58.0 || type == 59.0) {                           // Wave / heat haze
    float scale = max(8.0, u_p1);
    float amount = u_p0;
    float speed = u_p2;
    float vertical = type == 59.0 ? 0.35 : 0.0;
    uv += vec2(sin(uv.y*u_size.y/scale+t*speed),
               cos(uv.x*u_size.x/scale+t*speed*0.73)*vertical) * amount * px;
  }
  if (type == 60.0) {                                          // Film gate weave
    vec2 q = uv - 0.5;
    float a = sin(t*u_p1*6.2831853) * u_p0 * 0.0174532925;
    uv = 0.5 + mat2(cos(a),-sin(a),sin(a),cos(a))*q;
  }
  if (type == 24.0) {                                          // Transform
    vec2 q = (uv - 0.5) / max(0.01, u_p0 / 100.0);
    float a = u_p1 * 0.0174532925;
    uv = 0.5 + mat2(cos(a),-sin(a),sin(a),cos(a))*q;
  }
  if (type == 27.0) {                                          // Stabilize preview crop
    float strength = clamp(u_p0/64.0,0.0,1.0);
    uv = 0.5 + (uv-0.5)*(1.0-strength*0.10);
  }

  vec4 raw = sampleAt(uv);
  vec4 c = vec4(raw.a > 0.00001 ? raw.rgb / raw.a : vec3(0.0), raw.a);
  float radial = length(uv - 0.5);

  // Primary color / tonal effects.
  if (type == 1.0) c.rgb += vec3(u_p0);                         // Brightness
  else if (type == 2.0) c.rgb = (c.rgb-0.5)*u_p0+0.5;          // Contrast
  else if (type == 3.0) c.rgb = saturation(c.rgb,u_p0);        // Saturation
  else if (type == 4.0) c.rgb = pow(max(c.rgb,vec3(0.0)),vec3(1.0/max(0.2,u_p0))); // Gamma
  else if (type == 8.0) c.rgb *= 1.0-clamp(radial*u_p0*0.9,0.0,0.9); // Vignette
  else if (type == 11.0) { float l=luminance(c.rgb); c.rgb=vec3(step(u_p0/255.0,l)); } // Threshold
  else if (type == 12.0) c.rgb=1.0-c.rgb;                       // Invert
  else if (type == 13.0) c.rgb=vec3(luminance(c.rgb));          // Grayscale
  else if (type == 28.0) c.rgb=floor(c.rgb*max(2.0,u_p0))/max(2.0,u_p0); // Posterize
  else if (type == 29.0) c.rgb += vec3(u_p0,u_p1,u_p2);        // Color balance
  else if (type == 30.0) {                                    // Primary curves
    float master=curve5(luminance(c.rgb),u_p0,u_p1,u_p2,u_p3,u_p4);
    c.r=curve5(c.r,u_p5,u_p6,u_p7,u_p8,u_p9);
    c.g=curve5(c.g,u_p10,u_p11,u_p12,u_p13,u_p14);
    c.b=curve5(c.b,u_p15,u_p16,u_p17,u_p18,u_p19);
    c.rgb=clamp(c.rgb+(master-luminance(c.rgb)),0.0,1.0);
  }
  else if (type == 31.0) {                                    // .cube LUT slot; neutral until a LUT texture is bound
    c.rgb = c.rgb;
  }
  else if (type == 32.0) {                                    // Primary Color Grade
    vec3 lift=vec3(u_p0,u_p1,u_p2);
    vec3 gamma=vec3(u_p3,u_p4,u_p5);
    vec3 gain=vec3(u_p6,u_p7,u_p8);
    vec3 offset=vec3(u_p9,u_p10,u_p11);
    float temp=u_p12, tint=u_p13, contrast=u_p14, brightness=u_p15, mg=max(0.1,u_p16), sat=u_p17;
    vec3 wb=vec3(temp*0.055-tint*0.02,tint*0.055,-temp*0.055-tint*0.02);
    c.rgb=clamp((c.rgb+lift*0.14+offset*0.16+wb)*((1.0+gain*0.5+gamma*0.28)/mg),0.0,1.0);
    c.rgb=clamp((saturation(c.rgb,sat)-0.5)*contrast+0.5+brightness,0.0,1.0);
  }
  else if (type == 33.0) c.rgb=clamp(c.rgb*exp2(u_p0),0.0,1.0); // Exposure
  else if (type == 34.0) c.rgb=hueRotate(c.rgb,u_p0);          // Hue rotate
  else if (type == 35.0) {                                    // Colorize
    vec3 tint=hsvToRgb(vec3(mod(u_p0/360.0,1.0),u_p1,clamp(0.7+u_p2,0.0,1.0)));
    c.rgb=mix(c.rgb,tint,clamp(u_p3,0.0,1.0));
  }
  else if (type == 49.0) {                                    // Vibrance
    float l=luminance(c.rgb);
    float sat=max(max(c.r,c.g),c.b)-min(min(c.r,c.g),c.b);
    c.rgb=clamp(mix(vec3(l),c.rgb,1.0+u_p0*(1.0-sat)),0.0,1.0);
  }
  else if (type == 50.0) {                                    // Color contrast
    c.rgb=clamp((c.rgb-0.5)*(1.0+vec3(u_p0,u_p1,u_p2))+0.5,0.0,1.0);
  }
  else if (type == 51.0) {                                    // Auto white balance approximation
    float gray=(c.r+c.g+c.b)/3.0;
    c.rgb=clamp(c.rgb*(vec3(gray)/max(c.rgb,vec3(0.025))),0.0,1.0);
  }
  else if (type == 52.0) {                                    // RGB channel mixer
    vec3 source=c.rgb;
    c.rgb=clamp(vec3(
      source.r*u_p0+source.g*u_p1+source.b*u_p2,
      source.r*u_p3+source.g*u_p4+source.b*u_p5,
      source.r*u_p6+source.g*u_p7+source.b*u_p8),0.0,1.0);
  }
  else if (type == 66.0) c.rgb=clamp((saturation(c.rgb,u_p1)-0.5)*u_p0+0.5,0.0,1.0); // Bleach bypass
  else if (type == 67.0) {                                    // Sepia
    c.rgb=clamp(vec3(dot(c.rgb,vec3(0.393,0.769,0.189)),
      dot(c.rgb,vec3(0.349,0.686,0.168)),
      dot(c.rgb,vec3(0.272,0.534,0.131))),0.0,1.0);
  }

  // Blur, sharpen and denoise effects use bounded GPU taps.
  if (type == 5.0 || type == 6.0 || type == 22.0 || type == 36.0 ||
      type == 37.0 || type == 38.0 || type == 44.0 || type == 47.0 ||
      type == 48.0 || type == 54.0 || type == 55.0 || type == 56.0 ||
      type == 57.0) {
    float amount = type == 38.0 ? u_p1 : type == 48.0 ? u_p2 :
        (type == 36.0 || type == 47.0) ? u_p1 : u_p0;
    float rad=max(0.5,amount)*max(px.x,px.y);
    float angle=type==36.0?u_p0*0.0174532925:0.0;
    vec2 dir=type==36.0?vec2(cos(angle),sin(angle)):
        type==47.0?normalize(uv-0.5+vec2(0.0001)):vec2(1.0,0.0);
    vec3 blurred=softBlur(uv,dir,rad,px);
    float mixAmount=type==38.0?0.2:type==54.0?0.45:type==55.0?0.35:
        type==56.0?0.28:type==57.0?0.32:type==48.0?0.6:0.72;
    c.rgb=mix(c.rgb,blurred,mixAmount);
  }
  if (type == 7.0 || type == 53.0) {                          // Sharpen
    vec3 blur=(colorAt(uv+px*vec2(1,0))+colorAt(uv-px*vec2(1,0))+
               colorAt(uv+px*vec2(0,1))+colorAt(uv-px*vec2(0,1)))*0.25;
    c.rgb=clamp(c.rgb+(c.rgb-blur)*u_p0,0.0,1.0);
  }
  if (type == 15.0 || type == 68.0) {                         // Edge detect / edge glow
    float gx=luminance(colorAt(uv+px*vec2(1,0)))-luminance(colorAt(uv-px*vec2(1,0)));
    float gy=luminance(colorAt(uv+px*vec2(0,1)))-luminance(colorAt(uv-px*vec2(0,1)));
    float edge=clamp(length(vec2(gx,gy))*4.0,0.0,1.0);
    c.rgb=type==68.0?clamp(c.rgb+vec3(edge*u_p1),0.0,1.0):vec3(edge);
  }

  // Keying / compositing effects.
  if (type == 18.0) {                                        // Drop shadow
    float alpha=sampleAt(uv-vec2(u_p2*px.x,u_p2*px.y)).a;
    c.rgb=mix(vec3(0.0),c.rgb,clamp(c.a+alpha*u_p0,0.0,1.0));
  }
  if (type == 19.0) {                                        // Glow
    vec3 glow=max(colorAt(uv+px*2.0)-vec3(u_p0),vec3(0.0));
    glow+=max(colorAt(uv-px*2.0)-vec3(u_p0),vec3(0.0));
    c.rgb=clamp(c.rgb+glow*u_p2*0.35,0.0,1.0);
  }
  if (type == 25.0) {                                        // Chroma key
    float chroma=c.g-max(c.r,c.b);
    float mask=1.0-smoothstep(u_p0*0.15,u_p0*0.15+u_p1*0.45,chroma);
    c.a*=mask;
  }
  if (type == 26.0) {                                        // Luma key
    float l=luminance(c.rgb);
    c.a*=smoothstep(u_p0-u_p1,u_p0+u_p1,l);
  }

  // Time-dependent texture and compositing effects.
  if (type == 9.0 || type == 64.0 || type == 65.0) {           // Grain
    float amount=type==64.0?u_p0:type==65.0?u_p1:u_p0;
    float n=(hash21(gl_FragCoord.xy+floor(t*24.0))-0.5)*amount/255.0;
    c.rgb=clamp(c.rgb+n,0.0,1.0);
  }
  if (type == 21.0) {                                        // Particle dust
    float spacing=max(16.0,u_p0);
    vec2 cell=floor((uv*u_size+vec2(t*u_p3*17.0,t*u_p3*11.0))/spacing);
    float dotMask=step(0.965,hash21(cell));
    c.rgb=clamp(c.rgb+dotMask*u_p2,0.0,1.0);
  }
  if (type == 14.0 || type == 42.0 || type == 45.0 || type == 65.0) { // RGB split / VHS
    float shift=max(0.0,type==14.0?u_p0:type==42.0?u_p0:type==45.0?u_p0:u_p0)*px.x;
    c.r=colorAt(uv+vec2(shift,0)).r;
    c.b=colorAt(uv-vec2(shift,0)).b;
  }
  if (type == 39.0) {                                        // Deband dither
    float levels=max(8.0,1.0/max(0.00003,u_p0));
    float d=(hash21(gl_FragCoord.xy+floor(t*30.0))-0.5)/255.0;
    c.rgb=clamp(floor((c.rgb+d)*levels+0.5)/levels,0.0,1.0);
  }
  if (type == 40.0) {                                        // Deflicker visual response
    c.rgb=clamp(c.rgb- sin(t*6.2831853*max(1.0,u_p0))*0.008,0.0,1.0);
  }
  if (type == 41.0) {                                        // Scanlines
    float line=mod(gl_FragCoord.y,max(2.0,u_p0));
    if (line<u_p1) c.rgb*=1.0-clamp(u_p2,0.0,1.0);
  }
  if (type == 43.0) {                                        // Posterize time cadence
    float cadence=max(2.0,u_p0);
    float pulse=step(0.92,fract(t*cadence));
    c.rgb=clamp(c.rgb*(1.0-pulse*0.025),0.0,1.0);
  }
  if (type == 45.0 || type == 65.0) {                        // Tape noise / glitch bands
    float n=hash21(gl_FragCoord.xy+floor(t*18.0));
    float band=step(0.93,fract(uv.y*38.0+t*4.0));
    c.rgb=clamp(c.rgb+vec3((n-0.5)*u_p1/255.0+band*0.12,(n-0.5)*u_p1/255.0,band*0.06),0.0,1.0);
  }
  if (type == 61.0) c.rgb=clamp(c.rgb+u_p0*0.45,0.0,1.0);     // Camera flash
  if (type == 62.0) {                                        // Letterbox
    float h=u_p0;
    if (uv.y<h || uv.y>1.0-h) c.rgb=vec3(0.0);
  }
  if (type == 63.0) {                                        // Frame border
    float d=min(min(uv.x,uv.y),min(1.0-uv.x,1.0-uv.y))*min(u_size.x,u_size.y);
    if (d<u_p0) c.rgb=mix(c.rgb,vec3(1.0),clamp(u_p1,0.0,1.0));
  }
  if (type == 64.0) {                                        // Old film warmth / vignette
    c.rgb=clamp(hueRotate(c.rgb,8.0*u_p2)+vec3(u_p2*0.06,0.0,-u_p2*0.04),0.0,1.0);
    c.rgb*=1.0-radial*u_p1*0.45;
  }
  if (type == 66.0) {                                        // Bleach bypass
    c.rgb=clamp((saturation(c.rgb,u_p1)-0.5)*u_p0+0.5,0.0,1.0);
  }

  fragColor = vec4(clamp(c.rgb,0.0,1.0)*c.a,c.a);
}
