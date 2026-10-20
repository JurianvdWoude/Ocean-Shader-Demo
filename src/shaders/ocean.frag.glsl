precision highp float;

// ---------------------------------------------------------------------------
// LOOK
// ---------------------------------------------------------------------------
uniform vec3 water_color_deep;
uniform vec3 water_color_shallow;
uniform vec3 reflection_tint;
uniform vec3 foam_color;
uniform vec3 sss_color;
uniform float sss_strength;
uniform float fresnel_power;
// Light direction is pushed in each frame from GDScript (see notes below);
// there is no built-in "sun direction" uniform available in fragment().
uniform vec3 light_dir_world;
uniform sampler2D uSeabedDepth;
uniform vec2 uScreenSize;
uniform float uCameraNear;
uniform float uCameraFar;
uniform float shallow_depth_distance;
uniform float uReflectionStrength;
uniform float uSunGlintStrength;
uniform float uFoamVisibility;
uniform float uFoamCrestBoost;

varying vec3 vWorldPos;
varying vec3 vWorldNormal;
varying float vFoamMask;
varying vec2 vDispDir; // horizontal Gerstner displacement direction, for SSS
varying float vWaveHeight;

void main() {
  // N is the normal of the water vector
  // V points from the surface towards the camera
  // L is the direction towards the light
  vec3 N = normalize(vWorldNormal);
  vec3 V = normalize(cameraPosition - vWorldPos);
  vec3 L = normalize(-light_dir_world);
  float NdotL = max(dot(N, L), 0.0);

  // --- Fresnel reflection term ---
  float fresnel = pow(1.0 - clamp(dot(N, V), 0.0, 1.0), fresnel_power);

  // --- Depth-based shoreline transparency ---
  vec2 screenUV = gl_FragCoord.xy / uScreenSize;
  float seabedRawDepth = texture2D(uSeabedDepth, screenUV).r;
  float seabedViewDepth = (uCameraNear * uCameraFar) /
      (uCameraFar - seabedRawDepth * (uCameraFar - uCameraNear));
  // camera looks down the negative z-axis
  // negate to get positive distance from camera
  float waterViewDepth = -(viewMatrix * vec4(vWorldPos, 1.0)).z;
  // water between camera and seabed calculated per pixel
  float depthDiff = max(seabedViewDepth - waterViewDepth, 0.0);
  float depthMix = clamp(depthDiff / max(shallow_depth_distance, 0.001), 0.0, 1.0);
  vec3 baseColor = mix(water_color_shallow, water_color_deep, depthMix);

  vec3 R = reflect(-V, N);
  float skyHeight = clamp(R.y * 0.5 + 0.5, 0.0, 1.0);
  vec3 skyHorizon = reflection_tint * 0.58 + vec3(0.04, 0.10, 0.14);
  vec3 skyZenith = mix(reflection_tint, vec3(0.10, 0.28, 0.46), 0.45);
  vec3 skyReflection = mix(skyHorizon, skyZenith, smoothstep(0.18, 0.95, skyHeight));

  vec3 color = baseColor * (0.82 + 0.18 * NdotL);
  color = mix(color, skyReflection, clamp(fresnel * uReflectionStrength, 0.0, 1.0));

  vec3 H = normalize(L + V);
  float broadGlint = pow(max(dot(N, H), 0.0), 84.0) * NdotL;
  float sharpGlint = pow(max(dot(R, L), 0.0), 240.0) * NdotL;
  float glint = (0.22 * broadGlint + 0.55 * sharpGlint) * uSunGlintStrength;
  vec3 sunTint = mix(reflection_tint, vec3(0.98, 0.92, 0.80), 0.30);
  color += sunTint * glint * (0.35 + 0.65 * fresnel);

  // --- Subsurface-scattering-style glow on the sunlit/backlit slope ---
  // disp_dir is the sum of horizontal displacements from Gerstner waves
  vec2 dispN = length(vDispDir) > 0.0001 ? normalize(vDispDir) : vec2(0.0);
  vec3 dispDir3 = vec3(dispN.x, 0.0, dispN.y);
  // check if slope of wave is leaning away from camera
  float waveFacing = smoothstep(-0.15, 0.75, dot(dispDir3, -V));
  // check if camera is looking towards the light along the waves
  float backlit = pow(clamp(dot(L, -V), 0.0, 1.0), 1.35);
  float sss = backlit * (0.35 + 0.65 * waveFacing) * sss_strength;
  sss *= (0.35 + 0.65 * fresnel);
  color += sss_color * sss;

  float crestMask = smoothstep(0.10, 0.55, vWaveHeight);
  float upwardMask = smoothstep(0.15, 0.75, N.y);
  float foam = vFoamMask * (1.0 + crestMask * uFoamCrestBoost);
  foam *= mix(0.7, 1.0, upwardMask);
  foam = clamp(foam * uFoamVisibility, 0.0, 1.0);
  color = mix(color, foam_color, foam);

  float alpha = mix(0.76, 0.98, depthMix);
  gl_FragColor = vec4(color, alpha);
  #include <tonemapping_fragment>
  #include <colorspace_fragment>
}
