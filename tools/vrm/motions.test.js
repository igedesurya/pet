import assert from 'node:assert/strict';
import fs from 'node:fs';
import * as THREE from 'three';
import { VRMHumanoid } from '@pixiv/three-vrm';
import { MotionController, motionNames, solveLimb } from './motions.js';
const point=(x=0,y=0,z=0)=>new THREE.Vector3(x,y,z);
const root=new THREE.Object3D(),a=new THREE.Object3D(),b=new THREE.Object3D(),c=new THREE.Object3D();
root.add(a);a.add(b);b.add(c);b.position.x=.4;c.position.x=.35;
for(const [target,pole] of [[point(.3,.4,.1),point(0,0,1)],[point(2,0,0),point(3,0,0)]]){
 a.quaternion.identity();b.quaternion.identity();root.updateMatrixWorld(true);
 solveLimb(a,b,c,target,pole);root.updateMatrixWorld(true);
 assert.ok(c.getWorldPosition(point()).toArray().every(Number.isFinite));
 if(target.length()<.75)assert.ok(c.getWorldPosition(point()).distanceTo(target)<1e-5);
 assert.ok(Math.abs(a.getWorldPosition(point()).distanceTo(b.getWorldPosition(point()))-.4)<1e-6);
}
// Test against the real exported skeleton, without loading image textures.
const data=fs.readFileSync(new URL('../../Resources/vrm/3D.vrm',import.meta.url));
const gltf=JSON.parse(data.subarray(20,20+data.readUInt32LE(12)).toString());
const scene=new THREE.Object3D();
const nodes=gltf.nodes.map(n=>{const o=new THREE.Object3D();if(n.translation)o.position.fromArray(n.translation);if(n.rotation)o.quaternion.fromArray(n.rotation);if(n.scale)o.scale.fromArray(n.scale);if(n.matrix)new THREE.Matrix4().fromArray(n.matrix).decompose(o.position,o.quaternion,o.scale);return o;});
gltf.nodes.forEach((n,i)=>(n.children??[]).forEach(c=>nodes[i].add(nodes[c])));
gltf.scenes[gltf.scene??0].nodes.forEach(i=>scene.add(nodes[i]));scene.updateMatrixWorld(true);
const bones=Object.fromEntries(Object.entries(gltf.extensions.VRMC_vrm.humanoid.humanBones).map(([k,b])=>[k,{node:nodes[b.node]}]));
const humanoid=new VRMHumanoid(bones);scene.add(humanoid.normalizedHumanBonesRoot);scene.updateMatrixWorld(true);
const motion=new MotionController({humanoid,expressionManager:{setValue(){}}});let t=0;
for(const name of motionNames){
 assert.equal(motion.play(name,6),true);
 for(let i=0;i<360;i++){
  t+=1/60;motion.update(t,1/60);
  for(const [name,node] of Object.entries(motion.nodes)){
   assert.ok(node.quaternion.toArray().every(Number.isFinite),`${name} finite`);
   assert.ok(Math.abs(node.quaternion.length()-1)<1e-5,`${name} unit`);
   assert.ok(node.position.toArray().every(Number.isFinite),`${name} finite position`);
  }
  assert.ok(motion.nodes.hips.position.y>-.1,'hip above floor');
  assert.ok(motion.nodes.hips.position.y<1.6,'bounded jumping');
 }
}
assert.equal(motion.play('unsupported'),false);
motion.play('sitting-cross-legged',10);for(let i=0;i<120;i++){t+=1/60;motion.update(t,1/60);}
assert.ok(motion.nodes.hips.position.y<motion.hipRest.y*.5);
motion.play('idle',10);for(let i=0;i<180;i++){t+=1/60;motion.update(t,1/60);}
assert.ok(Math.abs(motion.nodes.hips.position.y-motion.hipRest.y)<.002);
console.log(`PASS: IK contact, ${motionNames.length} real-skeleton motions, seated-to-standing recovery`);
