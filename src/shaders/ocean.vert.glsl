// ---------------------------------------------------------------------------
// WAVE PARAMETERS
// Fill these from a WaveProfile resource at course-load time via
// ShaderMaterial.set_shader_parameter().
// ---------------------------------------------------------------------------
const int WAVE_COUNT = 6;
const int DETAIL_WAVE_COUNT = 3;
const float TAU = 6.28318530718;

uniform float uTime;
uniform float amplitudes[WAVE_COUNT];
uniform float wavelengths[WAVE_COUNT];
uniform vec2 directions[WAVE_COUNT];
uniform float speeds[WAVE_COUNT];
uniform float steepness;
uniform float detail_amplitudes[DETAIL_WAVE_COUNT];
uniform float detail_wavelengths[DETAIL_WAVE_COUNT];
uniform vec2 detail_directions[DETAIL_WAVE_COUNT];
uniform float detail_speeds[DETAIL_WAVE_COUNT];
uniform float foam_threshold;

varying vec3 vWorldPos;
varying vec3 vWorldNormal;
varying float vFoamMask;
varying vec2 vDispDir; // horizontal Gerstner displacement direction, for SSS
varying float vWaveHeight;

// ---------------------------------------------------------------------------
// VERTEX SHADER
// Wave addition to generate ocean waves
// See: Tessendorf 2001 or "The Technical Art of Sea of Thieves"
// ---------------------------------------------------------------------------
void main() {
  vec3 displaced = position;
  vec2 pos = position.xz;
  float h = 0.0;
  vec2 total_disp = vec2(0.0);
  // Set 1: height gradient (∂h/∂x, ∂h/∂z), used ONLY for the normal
  float dhdx = 0.0;
  float dhdz = 0.0;
  // Set 2: Jacobian of the horizontal displacement map, used ONLY for foam
  // Checking the determinant to see a flip in horizontal displacement
  // In Calculus ET 6thEd p1015, Multiple Integrals (req. Partial Derivatives)
  float dDxdx = 0.0;
  float dDxdz = 0.0;
  float dDzdx = 0.0;
  float dDzdz = 0.0;

  // Gerstner waves used for waves is calculated as
  // x(ξ,t)=ξ−asin(θ), with θ=kξ−ωt
  // z(ξ,t)=acos(θ)
  for (int i = 0; i < WAVE_COUNT; i++) {
    vec2 ndir = normalize(directions[i]);
    float k = TAU / max(wavelengths[i], 0.001);
    float phase = k * (dot(ndir, pos) + speeds[i] * uTime);
    float A = amplitudes[i];
    float Q = steepness;

    h += A * sin(phase);
    // horizontal displacement
    vec2 horiz = Q * A * ndir * cos(phase);
    total_disp += horiz;
    displaced.xz += horiz;

    // dD/dx = d(Sn)/dx = (dS/dx)n, with n=(nx,nz), whereby n is constant
    // dS/dx = -Q A sin(phase)(k nx), because dphase/dx = k nx
    // dDx/dx = -Q A k sin(phase) nx nx
    float jacobianFactor = -Q * A * k * sin(phase);
    dDxdx += jacobianFactor * ndir.x * ndir.x;
    dDxdz += jacobianFactor * ndir.x * ndir.y;
    dDzdx += jacobianFactor * ndir.y * ndir.x;
    dDzdz += jacobianFactor * ndir.y * ndir.y;

    // Derivative of the height per wave
    // h = A * sin(phase)
    // dh/dx = A cos(phase) dphase/dx
    dhdx += A * k * ndir.x * cos(phase);
    dhdz += A * k * ndir.y * cos(phase);
  }

  // Small high-frequency detail waves: contribute a little height/foam
  // sensitivity but are not fed into the physics-facing height sample
  for (int i = 0; i < DETAIL_WAVE_COUNT; i++) {
    vec2 ndir = normalize(detail_directions[i]);
    float k = TAU / max(detail_wavelengths[i], 0.001);
    float phase = k * (dot(ndir, pos) + detail_speeds[i] * uTime);
    float A = detail_amplitudes[i];

    h += A * sin(phase);
    float jacobianFactor = -steepness * A * k * sin(phase);
    dDxdx += jacobianFactor * ndir.x * ndir.x;
    dDxdz += jacobianFactor * ndir.x * ndir.y;
    dDzdx += jacobianFactor * ndir.y * ndir.x;
    dDzdz += jacobianFactor * ndir.y * ndir.y;

    dhdx += A * k * ndir.x * cos(phase);
    dhdz += A * k * ndir.y * cos(phase);
  }

  displaced.y += h;
  // Normal, uses height-gradient accumulators
  vec3 approx_normal = normalize(vec3(-dhdx, 1.0, -dhdz));
  // Foam, uses determinant of Jacobian accumulators
  float jacobian = (1.0 + dDxdx) * (1.0 + dDzdz) - dDxdz * dDzdx;
  vFoamMask = clamp((foam_threshold - jacobian) * 2.0, 0.0, 1.0);
  vDispDir = total_disp;
  vWaveHeight = h;
  vWorldNormal = normalize(mat3(modelMatrix) * approx_normal);
  vec4 world = modelMatrix * vec4(displaced, 1.0);
  vWorldPos = world.xyz;
  gl_Position = projectionMatrix * viewMatrix * world;
}
