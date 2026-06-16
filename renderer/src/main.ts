import * as THREE from 'three';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
import { FBXLoader } from 'three/examples/jsm/loaders/FBXLoader.js';
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js';
import { VRMLoaderPlugin, VRMUtils, type VRM } from '@pixiv/three-vrm';

// When launched from the WKWebView (Quick Look extension), forward the console to
// the Swift side's os_log. In a plain browser there is no messageHandlers, so this is a no-op.
const nativeLog = (window as any).webkit?.messageHandlers?.log;
if (nativeLog) {
  const forward = (level: string, args: unknown[]) => {
    try {
      nativeLog.postMessage(
        `[${level}] ` +
          args
            .map((a) => (typeof a === 'string' ? a : JSON.stringify(a)))
            .join(' '),
      );
    } catch {
      /* noop */
    }
  };
  for (const level of ['log', 'warn', 'error'] as const) {
    const orig = console[level].bind(console);
    console[level] = (...args: unknown[]) => {
      forward(level, args);
      orig(...args);
    };
  }
  window.addEventListener('error', (e) =>
    forward('error', [e.message, e.filename, e.lineno]),
  );
  window.addEventListener('unhandledrejection', (e) =>
    forward('error', ['unhandledrejection', String(e.reason)]),
  );
}

// ---------------------------------------------------------------------------
// Setup
// ---------------------------------------------------------------------------
const app = document.getElementById('app')!;
const overlay = document.getElementById('overlay')!;
const overlayText = document.getElementById('overlay-text')!;

const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true });
renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
renderer.setSize(window.innerWidth, window.innerHeight);
renderer.outputColorSpace = THREE.SRGBColorSpace;
app.appendChild(renderer.domElement);

const scene = new THREE.Scene();

const camera = new THREE.PerspectiveCamera(
  30,
  window.innerWidth / window.innerHeight,
  0.1,
  100,
);
camera.position.set(0, 1.3, 3);

const controls = new OrbitControls(camera, renderer.domElement);
controls.target.set(0, 1.0, 0);
controls.enableDamping = true;
controls.dampingFactor = 0.1;
controls.update();

// Lighting (key + fill + ambient)
const keyLight = new THREE.DirectionalLight(0xffffff, 2.0);
keyLight.position.set(1, 2, 1.5);
scene.add(keyLight);

const fillLight = new THREE.DirectionalLight(0xffffff, 0.6);
fillLight.position.set(-1.5, 1, -1);
scene.add(fillLight);

scene.add(new THREE.AmbientLight(0xffffff, 0.6));
scene.add(new THREE.HemisphereLight(0xffffff, 0x444455, 0.6));

// Floor grid
const grid = new THREE.GridHelper(10, 20, 0x444444, 0x2a2a2a);
(grid.material as THREE.Material).transparent = true;
(grid.material as THREE.Material).opacity = 0.4;
scene.add(grid);

// ---------------------------------------------------------------------------
// Loaders
// ---------------------------------------------------------------------------
const gltfLoader = new GLTFLoader();
gltfLoader.register((parser) => new VRMLoaderPlugin(parser));
const fbxLoader = new FBXLoader();

// Remember the root added to the scene (VRM or plain glTF/GLB) so we can swap it out
let currentRoot: THREE.Object3D | null = null;
let currentVrm: VRM | null = null;
let currentMixer: THREE.AnimationMixer | null = null;
let currentSkeletonHelper: THREE.SkeletonHelper | null = null;
const clock = new THREE.Clock();

/** Whether it has a renderable mesh. false for VRMA / skin-less FBX. */
function hasRenderableMesh(root: THREE.Object3D): boolean {
  let found = false;
  root.traverse((o) => {
    if ((o as THREE.Mesh).isMesh) found = true;
  });
  return found;
}

function showOverlay(text: string, isError = false) {
  overlayText.textContent = text;
  overlay.classList.toggle('error', isError);
  overlay.classList.remove('hidden');
}

function hideOverlay() {
  overlay.classList.add('hidden');
}

/** Fit the camera and target to the model's bounding box. */
function frameModel(root: THREE.Object3D) {
  const box = new THREE.Box3().setFromObject(root);
  // With no mesh (bones only) the box is empty, so derive it from each node's position.
  if (box.isEmpty()) {
    const p = new THREE.Vector3();
    root.updateWorldMatrix(true, true);
    root.traverse((o) => box.expandByPoint(o.getWorldPosition(p)));
  }
  const size = box.getSize(new THREE.Vector3());
  const center = box.getCenter(new THREE.Vector3());

  // Derive the distance that fits the whole model from the field of view.
  const maxDim = Math.max(size.x, size.y, size.z);
  const fov = (camera.fov * Math.PI) / 180;
  const distance = (maxDim / 2 / Math.tan(fov / 2)) * 1.4;

  controls.target.copy(center);
  camera.position.set(center.x, center.y + size.y * 0.05, center.z + distance);
  camera.near = distance / 100;
  camera.far = distance * 100;
  camera.updateProjectionMatrix();
  controls.update();
}

/** Dispose the currently shown model (VRM / glTF / FBX / VRMA alike). */
function disposeCurrent() {
  if (currentMixer) {
    currentMixer.stopAllAction();
    currentMixer = null;
  }
  if (currentSkeletonHelper) {
    scene.remove(currentSkeletonHelper);
    currentSkeletonHelper.dispose();
    currentSkeletonHelper = null;
  }
  if (currentRoot) {
    scene.remove(currentRoot);
    VRMUtils.deepDispose(currentRoot);
    currentRoot = null;
  }
  currentVrm = null;
}

/** Detect FBX from the leading bytes (VRM/GLB start with the "glTF" magic). */
function isFBX(u8: Uint8Array): boolean {
  // Binary FBX: "Kaydara FBX Binary  \x00"
  const sig = 'Kaydara FBX Binary';
  let binMatch = u8.length > sig.length;
  for (let i = 0; binMatch && i < sig.length; i++) {
    if (u8[i] !== sig.charCodeAt(i)) binMatch = false;
  }
  if (binMatch) return true;
  // ASCII FBX: contains "FBX" near the start (GLB is 'glTF', so it won't match).
  const head = new TextDecoder().decode(u8.subarray(0, 64));
  return head.includes('FBX');
}

/** Add the loaded root to the scene (shared post-processing for VRM / glTF / FBX / VRMA). */
function applyModel(
  root: THREE.Object3D,
  vrm: VRM | null,
  clips: THREE.AnimationClip[],
) {
  // Play the first clip if any (GLB/FBX animation, VRMA, etc.).
  if (clips.length > 0) {
    currentMixer = new THREE.AnimationMixer(root);
    currentMixer.clipAction(clips[0]).play();
  }
  // Disable frustum culling so meshes don't disappear unexpectedly.
  root.traverse((obj) => {
    obj.frustumCulled = false;
  });
  scene.add(root);

  // No mesh, animation only (VRMA / skin-less FBX):
  // visualize the bone hierarchy with a skeleton helper.
  if (!vrm && clips.length > 0 && !hasRenderableMesh(root)) {
    root.traverse((o) => {
      // SkeletonHelper only links bones, so mark each node as a bone.
      if (o !== root) (o as unknown as { isBone: boolean }).isBone = true;
    });
    currentSkeletonHelper = new THREE.SkeletonHelper(root);
    scene.add(currentSkeletonHelper);
  }

  currentRoot = root;
  currentVrm = vrm;
  frameModel(root);
  hideOverlay();
}

async function loadModelFromArrayBuffer(buffer: ArrayBuffer) {
  showOverlay('Loading…');
  try {
    disposeCurrent();

    if (isFBX(new Uint8Array(buffer))) {
      // --- FBX ---
      const root = fbxLoader.parse(buffer, '');
      applyModel(root, null, root.animations);
      console.log('FBX loaded & added to scene');
      return;
    }

    // --- VRM / VRMA / glTF / GLB ---
    const blob = new Blob([buffer], { type: 'model/gltf-binary' });
    const url = URL.createObjectURL(blob);
    const gltf = await gltfLoader.loadAsync(url);
    URL.revokeObjectURL(url);

    // The VRM plugin sets userData.vrm when it can parse it; otherwise plain glTF/GLB.
    // A VRMA (no mesh, animation only) ends up vrm=null + animations present, and
    // applyModel routes it to the skeleton view.
    const vrm = (gltf.userData.vrm as VRM | undefined) ?? null;
    if (vrm) {
      VRMUtils.removeUnnecessaryVertices(gltf.scene);
      VRMUtils.combineSkeletons(gltf.scene);
      VRMUtils.rotateVRM0(vrm); // fix VRM 0.x coordinate system (faces +Z)
    }
    applyModel(vrm ? vrm.scene : gltf.scene, vrm, vrm ? [] : gltf.animations);
    console.log(
      vrm
        ? 'VRM loaded & added to scene'
        : hasRenderableMesh(gltf.scene)
          ? 'glTF/GLB loaded & added to scene'
          : 'skeleton (mesh-less) loaded & added to scene',
    );
  } catch (e) {
    console.error('[model] load failed', e);
    showOverlay('Failed to load', true);
  }
}

function base64ToArrayBuffer(base64: string): ArrayBuffer {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}

// ---------------------------------------------------------------------------
// Entry point from the Swift side (WKWebView)
//   received via window.postMessage({ type: 'loadVRM', base64 })
// ---------------------------------------------------------------------------
window.addEventListener('message', (event) => {
  if (event.data?.type !== 'loadVRM') return;
  console.log('received loadVRM message, base64 length =', event.data.base64?.length);
  void loadModelFromArrayBuffer(base64ToArrayBuffer(event.data.base64));
});

console.log('renderer booted, WebGL context =', !!renderer.getContext());

// Browser dev fallbacks ---------------------------------------------------
// 1) load ?url=... if present
// 2) load a file dropped onto the window
(function devFallbacks() {
  const params = new URLSearchParams(location.search);
  const url = params.get('url');
  if (url) {
    showOverlay('Loading…');
    fetch(url)
      .then((r) => r.arrayBuffer())
      .then((buf) => loadModelFromArrayBuffer(buf))
      .catch(() => showOverlay('Failed to load', true));
  } else if (location.protocol.startsWith('http')) {
    showOverlay('Drag & drop a .vrm / .vrma / .glb / .fbx');
  }

  window.addEventListener('dragover', (e) => e.preventDefault());
  window.addEventListener('drop', (e) => {
    e.preventDefault();
    const file = e.dataTransfer?.files?.[0];
    if (!file) return;
    file.arrayBuffer().then((buf) => loadModelFromArrayBuffer(buf));
  });
})();

// ---------------------------------------------------------------------------
// Render loop
// ---------------------------------------------------------------------------
function animate() {
  requestAnimationFrame(animate);
  const delta = clock.getDelta();
  controls.update();
  if (currentVrm) currentVrm.update(delta); // update spring bones, expressions, etc.
  if (currentMixer) currentMixer.update(delta); // glTF/GLB animation
  renderer.render(scene, camera);
}
animate();

window.addEventListener('resize', () => {
  camera.aspect = window.innerWidth / window.innerHeight;
  camera.updateProjectionMatrix();
  renderer.setSize(window.innerWidth, window.innerHeight);
});
