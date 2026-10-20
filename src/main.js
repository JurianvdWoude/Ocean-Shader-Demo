import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import vertexShader from './shaders/ocean.vert.glsl?raw';
import fragmentShader from './shaders/ocean.frag.glsl?raw';
import './style.css';

const scene = new THREE.Scene();
scene.background = new THREE.Color('#071725');

const camera = new THREE.PerspectiveCamera(55, window.innerWidth / window.innerHeight, 0.1, 150);
camera.position.set(10, 8, 12);

const renderer = new THREE.WebGLRenderer({ antialias: true });
renderer.setSize(window.innerWidth, window.innerHeight);
renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
renderer.outputColorSpace = THREE.SRGBColorSpace;
document.querySelector('#app').appendChild(renderer.domElement);

const controls = new OrbitControls(camera, renderer.domElement);
controls.enableDamping = true;
controls.target.set(0, 0, 0);
controls.minDistance = 3;
controls.maxDistance = 55;
controls.update();

// 64 x 64 subdivisions, 65 x 65 = 4,225 vertices.
const geometry = new THREE.PlaneGeometry(16, 16, 64, 64);
geometry.rotateX(-Math.PI / 2);

// Seabed beneath the water: shallow on the left, deep on the right.
const seabedGeometry = new THREE.PlaneGeometry(20, 20, 80, 80);
seabedGeometry.rotateX(-Math.PI / 2);
const positions = seabedGeometry.attributes.position;
const seabedColors = [];
const sand = new THREE.Color('#b9b58c');
const deepSand = new THREE.Color('#336d72');
for (let i = 0; i < positions.count; i++) {
  const x = positions.getX(i);
  const z = positions.getZ(i);
  const t = THREE.MathUtils.clamp((x + 10) / 20, 0, 1);
  const y = -2.9 - 4.4 * t + 0.12 * Math.sin(z * 0.55) * (1.0 - t * 0.35);
  positions.setY(i, y);
  const col = sand.clone().lerp(deepSand, t);
  seabedColors.push(col.r, col.g, col.b);
}
seabedGeometry.setAttribute('color', new THREE.Float32BufferAttribute(seabedColors, 3));
seabedGeometry.computeVertexNormals();
const seabedMaterial = new THREE.MeshBasicMaterial({ vertexColors: true, side: THREE.DoubleSide });
const seabed = new THREE.Mesh(seabedGeometry, seabedMaterial);
scene.add(seabed);

// Offscreen seabed-only depth pass.
const depthScene = new THREE.Scene();
const depthSeabed = new THREE.Mesh(seabedGeometry, new THREE.MeshDepthMaterial({
  depthPacking: THREE.BasicDepthPacking,
  side: THREE.DoubleSide,
}));
depthScene.add(depthSeabed);
const depthTarget = new THREE.WebGLRenderTarget(1, 1, { depthBuffer: true });
depthTarget.depthTexture = new THREE.DepthTexture(1, 1, THREE.UnsignedIntType);
depthTarget.depthTexture.minFilter = THREE.NearestFilter;
depthTarget.depthTexture.magFilter = THREE.NearestFilter;
const drawingBufferSize = new THREE.Vector2();
function resizeDepthTarget() {
  renderer.getDrawingBufferSize(drawingBufferSize);
  depthTarget.setSize(drawingBufferSize.x, drawingBufferSize.y);
}
resizeDepthTarget();

// WaveProfile values ported from Godot.
const uniforms = {
  uTime: { value: 0 },
  amplitudes: { value: [0.6, 0.5, 0.45, 0.4, 0.15, 0.1] },
  wavelengths: { value: [18, 14, 10, 8, 6, 4] },
  directions: { value: [[1, 0], [0.8, 0.6], [-0.5, 0.8], [0.3, -0.9], [-0.9, -0.2], [0.6, 0.7]].map(([x, y]) => new THREE.Vector2(x, y)) },
  speeds: { value: [1.2, 1.0, 0.9, 1.4, 0.7, 1.1] },
  steepness: { value: 0.6 },
  detail_amplitudes: { value: [0.03, 0.02, 0.015] },
  detail_wavelengths: { value: [2.0, 1.8, 1.5] },
  detail_directions: { value: [[1, 0.3], [-0.4, 0.9], [-0.7, -0.6]].map(([x, y]) => new THREE.Vector2(x, y)) },
  detail_speeds: { value: [2.0, 2.4, 1.8] },
  foam_threshold: { value: 0.5 },
  water_color_deep: { value: new THREE.Vector3(0.05, 0.28, 0.42) },
  water_color_shallow: { value: new THREE.Vector3(0.25, 0.65, 0.65) },
  reflection_tint: { value: new THREE.Vector3(0.06, 0.67, 0.96) },
  foam_color: { value: new THREE.Vector3(0.84, 0.91, 0.95) },
  sss_color: { value: new THREE.Vector3(0.36, 0.85, 0.60) },
  sss_strength: { value: 1.1 },
  fresnel_power: { value: 2.14 },
  light_dir_world: { value: new THREE.Vector3(0.3, -0.7, 0.4) },
  uSeabedDepth: { value: depthTarget.depthTexture },
  uScreenSize: { value: drawingBufferSize },
  uCameraNear: { value: camera.near },
  uCameraFar: { value: camera.far },
  shallow_depth_distance: { value: 5.19 },
  uReflectionStrength: { value: 0.48 },
  uSunGlintStrength: { value: 0.38 },
  uFoamVisibility: { value: 1.35 },
  uFoamCrestBoost: { value: 0.9 },
};

const material = new THREE.ShaderMaterial({
  uniforms,
  vertexShader,
  fragmentShader,
  side: THREE.DoubleSide,
  transparent: true,
  depthWrite: false,
});

const ocean = new THREE.Mesh(geometry, material);
ocean.frustumCulled = false;
scene.add(ocean);

const clock = new THREE.Clock();
function animate() {
  requestAnimationFrame(animate);
  uniforms.uTime.value = clock.getElapsedTime();
  controls.update();

  renderer.setRenderTarget(depthTarget);
  renderer.clear();
  renderer.render(depthScene, camera);
  renderer.setRenderTarget(null);

  renderer.render(scene, camera);
}
animate();

window.addEventListener('resize', () => {
  camera.aspect = window.innerWidth / window.innerHeight;
  camera.updateProjectionMatrix();
  renderer.setSize(window.innerWidth, window.innerHeight);
  resizeDepthTarget();
});
