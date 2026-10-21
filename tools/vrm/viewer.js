import * as THREE from "three";
import { GLTFLoader } from "three/addons/loaders/GLTFLoader.js";
import { VRMLoaderPlugin, VRMUtils } from "@pixiv/three-vrm";
import { MotionController } from "./motions.js";
const report = (type, message = "") => window.webkit?.messageHandlers.vrm.postMessage({ type, message });
let avatar, motion, elapsed = 0, state = "idle", loadGeneration = 0;
const scene = new THREE.Scene(), camera = new THREE.PerspectiveCamera(30, 1, 0.01, 100);
const renderer = new THREE.WebGLRenderer({ alpha: true, antialias: true, preserveDrawingBuffer: true });
renderer.setClearColor(0, 0);
renderer.setPixelRatio(Math.min(devicePixelRatio, 2));
document.body.appendChild(renderer.domElement);
scene.add(new THREE.HemisphereLight(16777215, 9143961, 2));
const light = new THREE.DirectionalLight(16777215, 2);
light.position.set(1, 2, 3);
scene.add(light);
function resize() {
  renderer.setSize(innerWidth, innerHeight);
  camera.aspect = innerWidth / Math.max(innerHeight, 1);
  camera.updateProjectionMatrix();
}
addEventListener("resize", resize);
resize();
const loader = new GLTFLoader();
loader.register((parser) => new VRMLoaderPlugin(parser));
window.pet3D = { async load(url) {
  const generation = ++loadGeneration;
  try {
    const gltf = await loader.loadAsync(url), next = gltf.userData.vrm;
    if (generation !== loadGeneration) { VRMUtils.deepDispose(gltf.scene); return; }
    if (!next) {
      VRMUtils.deepDispose(gltf.scene);
      throw new Error("File bukan model humanoid VRM.");
    }
    if (avatar) {
      scene.remove(avatar.scene);
      VRMUtils.deepDispose(avatar.scene);
    }
    avatar = next;
    VRMUtils.rotateVRM0(avatar);
    avatar.scene.traverse((o) => {
      o.frustumCulled = false;
    });
    scene.add(avatar.scene);
    motion = new MotionController(avatar);
    motion.setState(state);
    motion.update(0, 0);
    avatar.update(0);
    const box = new THREE.Box3().setFromObject(avatar.scene), center = box.getCenter(new THREE.Vector3()), height = box.getSize(new THREE.Vector3()).y;
    avatar.scene.position.x -= center.x;
    avatar.scene.position.y -= box.min.y;

    camera.position.set(0, height / 2, height / (2 * Math.tan(Math.PI / 12)) * 1.38);
    camera.lookAt(0, height / 2, 0);
    report("loaded");
  } catch (e) {
    if (generation === loadGeneration) report("error", String(e.message || e));
  }
}, setState(value) {
  state = value; motion?.setState(value);
}, play(name, seconds = 6) {
  return motion?.play(name, seconds) ?? false;
}, motionState() {
  const joints = {};
  for (const name of ["hips", "leftUpperLeg", "leftLowerLeg", "leftFoot", "rightFoot"]) {
    joints[name] = avatar?.humanoid.getRawBoneNode(name)?.getWorldPosition(new THREE.Vector3()).toArray();
  }
  return { active: motion?.active, time: elapsed, joints };
} };
const clock = new THREE.Clock();
renderer.setAnimationLoop(() => {
  const dt = Math.min(clock.getDelta(), 0.1);
  elapsed += dt;
  if (avatar) {
    motion.update(elapsed, dt);
    avatar.update(dt);
  }
  renderer.render(scene, camera);
});
report("ready");
