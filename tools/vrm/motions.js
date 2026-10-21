import * as THREE from "three";
export const motionNames = ["idle","waving","talking","waiting","okay-smile","failed","walking","walk-talk","sad","happy","jumping","laughing","thinking","pondering","sitting-cross-legged","kneeling","clapping","nodding","shaking-head","bowing","stretching"];
const seated=new Set(["pondering","sitting-cross-legged","kneeling"]);
const v=(x=0,y=0,z=0)=>new THREE.Vector3(x,y,z);
const smooth=(a,b,x)=>THREE.MathUtils.smoothstep(x,a,b);
// Analytic two-bone IK with an explicit elbow/knee pole.
export function solveLimb(upper,lower,end,target,pole) {
 if(!upper||!lower||!end)return;
 upper.updateWorldMatrix(true,true);
 const a=upper.getWorldPosition(v()),b=lower.getWorldPosition(v()),c=end.getWorldPosition(v());
 const l1=a.distanceTo(b),l2=b.distanceTo(c);if(l1<1e-5||l2<1e-5)return;
 const direction=target.clone().sub(a),distance=direction.length();if(distance<1e-5)return;
 direction.divideScalar(distance);
 const d=THREE.MathUtils.clamp(distance,Math.abs(l1-l2)+0.0001,l1+l2-0.0001);
 const along=(l1*l1-l2*l2+d*d)/(2*d),bend=pole.clone().sub(a);
 bend.addScaledVector(direction,-bend.dot(direction));
 if(bend.lengthSq()<1e-8)bend.set(0,0,1).addScaledVector(direction,-direction.z);
 if(bend.lengthSq()<1e-8)bend.set(1,0,0);bend.normalize();
 const joint=a.clone().addScaledVector(direction,along).addScaledVector(bend,Math.sqrt(Math.max(0,l1*l1-along*along)));
 const rotateWorld=(node,from,to)=>{
  if(from.lengthSq()<1e-10||to.lengthSq()<1e-10)return;
  const delta=new THREE.Quaternion().setFromUnitVectors(from.normalize(),to.normalize());
  const world=node.getWorldQuaternion(new THREE.Quaternion()).premultiply(delta);
  node.quaternion.copy(node.parent.getWorldQuaternion(new THREE.Quaternion()).invert().multiply(world));node.updateWorldMatrix(false,true);
 };
 rotateWorld(upper,b.clone().sub(a),joint.clone().sub(a));
 const actual=lower.getWorldPosition(v());
 rotateWorld(lower,end.getWorldPosition(v()).sub(actual),a.clone().addScaledVector(direction,d).sub(actual));
}
export class MotionController {
 constructor(avatar){
  this.avatar=avatar;this.root=avatar.humanoid.normalizedHumanBonesRoot;
  this.nodes={};this.previous={};this.expressions={};
  for(const [name,bone] of Object.entries(avatar.humanoid.normalizedHumanBones))this.nodes[name]=bone.node;
  avatar.humanoid.resetNormalizedPose();this.root.updateWorldMatrix(true,true);
  const local=name=>this.root.worldToLocal(this.nodes[name].getWorldPosition(v()));
  this.hipRest=this.nodes.hips.position.clone();this.feet={left:local("leftFoot"),right:local("rightFoot")};
  this.unit=(local("head").y-Math.min(this.feet.left.y,this.feet.right.y))/1.45;
  this.ground=Math.min(this.feet.left.y,this.feet.right.y)-0.065*this.unit;
  this.legLengths={};for(const side of ["left","right"]){this.legLengths[side]=[local(side+"UpperLeg").distanceTo(local(side+"LowerLeg")),local(side+"LowerLeg").distanceTo(local(side+"Foot"))];}
  this.baseHip=local("hips").y;this.hipPosition=this.hipRest.clone();
  this.time=0;this.start=0;this.until=0;this.gesture="";this.state="idle";this.active="idle";
 }
 play(name,duration=6){if(!motionNames.includes(name))return false;this.gesture=name;this.start=this.time;this.until=this.time+Math.max(0.2,duration);return true;}
 setState(state){this.state=state;}
 rotate(name,x=0,y=0,z=0){this.nodes[name]?.rotation.set(x,y,z);}
 point(x,y,z){return this.root.localToWorld(v(x*this.unit,this.ground+y*this.unit,z*this.unit));}
 limb(side,kind,target,pole){solveLimb(this.nodes[side+"Upper"+kind],this.nodes[side+"Lower"+kind],this.nodes[side+(kind==="Arm"?"Hand":"Foot")],target,pole);}
 hand(side,target,pole){this.limb(side,"Arm",target,pole);}
 foot(side,target,pole){this.limb(side,"Leg",target,pole);}
 orient(name,x,y,z){
  const n=this.nodes[name];if(!n)return;
  const world=this.root.getWorldQuaternion(new THREE.Quaternion()).multiply(new THREE.Quaternion().setFromEuler(new THREE.Euler(x,y,z)));
  n.quaternion.copy(n.parent.getWorldQuaternion(new THREE.Quaternion()).invert().multiply(world));
 }
 fingers(side,curl=0.18){
  const sign=side==="left"?-1:1;
  for(const finger of ["Index","Middle","Ring","Little"]){
   this.rotate(side+finger+"Proximal",0,0,sign*curl);this.rotate(side+finger+"Intermediate",0,0,sign*curl*0.75);this.rotate(side+finger+"Distal",0,0,sign*curl*0.4);
  }
 }
 update(t,dt){
  this.time=t;let clip=t<this.until?this.gesture:this.state;const age=t-this.start;
  if(clip==="walk-talk")clip=age<4?"walking":"talking";
  clip=({failed:"sad",error:"sad","okay-smile":"happy",speaking:"talking",waiting:"thinking"})[clip]||clip;
  if(!motionNames.includes(clip))clip="idle";
  if(clip==="idle"&&t>=this.until&&t%12>3&&t%12<6.5)clip="waving";
  this.active=clip;
  const r=this.rotate.bind(this),u=this.unit;
  const phaseTime=t<this.until?age:t;
  this.avatar.humanoid.resetNormalizedPose();
  r("leftUpperArm",-0.03,0,-1.38);r("rightUpperArm",-0.03,0,1.38);
  r("leftLowerArm",0,-0.12,0);r("rightLowerArm",0,0.12,0);
  this.fingers("left");this.fingers("right");
  r("spine",0.012*Math.sin(t*1.65),0,0.008*Math.sin(t*0.8));r("head",0.008*Math.sin(t*0.7),0.025*Math.sin(t*0.5),0);
  const expr={happy:0,sad:0,aa:0,oh:0,relaxed:0,blink:Math.pow(Math.max(0,Math.cos(t*1.47)),48)};
  const hip=this.nodes.hips,sit=seated.has(clip);
  if(sit){const height=clip==="kneeling"?0.22:clip==="pondering"?0.24:0.20;hip.position.y+=this.ground+height*u-this.baseHip;}
  if(clip==="walking"){
   const phase=phaseTime*6.4,gait=Math.sin(phase);hip.position.y-=0.022*u;r("hips",0,gait*0.035,gait*0.025);r("spine",0.025,-gait*0.04,0);
   for(const [side,sign] of [["left",1],["right",-1]]){
    const p=phase+(sign===1?0:Math.PI),swing=Math.sin(p),foot=this.feet[side].clone();
    foot.z+=0.13*u*Math.cos(p);foot.y+=0.07*u*Math.max(0,swing);
    this.foot(side,this.root.localToWorld(foot),this.point(sign*0.1,0.45,0.8));this.orient(side+"Foot",-0.12*Math.max(0,swing),0,0);
    r(side+"UpperArm",Math.cos(p)*0.2,sign*-0.1,sign*-1.36);r(side+"LowerArm",0,sign*-0.22,0);
   }
  }
  if(clip==="waving"){
   r("rightUpperArm",0,0.2,0.62+Math.sin(t*2)*0.025);r("rightLowerArm",0,0.75,-1.75);
   r("rightHand",Math.sin(phaseTime*4.8)*0.08,0,Math.sin(phaseTime*4.8)*0.23);this.fingers("right",0.025);expr.happy=0.3;
  }
  if(clip==="talking"){
   r("spine",0.01*Math.sin(t*1.65),0.025*Math.sin(t*1.3),0.018*Math.sin(t*1.7));r("head",0.04*Math.sin(t*2.1),0.05*Math.sin(t*0.9),0.02);
   r("rightUpperArm",-0.15,0.3,1.05);r("rightLowerArm",0,0.65,-1.0+0.12*Math.sin(t*2.3));r("rightHand",0.1*Math.sin(t*2.3),0,0.08*Math.sin(t*1.9));
   expr.aa=0.08+Math.max(0,Math.sin(t*10.5))*0.35;expr.happy=0.15;
  }
  if(clip==="sad"){
   r("spine",0.13,0,0);r("chest",0.08,0,0);r("head",0.3,0.03*Math.sin(t*0.5),-0.07);r("leftUpperArm",0.08,-0.16,-1.48);r("rightUpperArm",0.08,0.16,1.48);expr.sad=0.8;
  }
  if(clip==="happy"){
   r("spine",-0.035,0,Math.sin(t*2.4)*0.035);r("head",-0.05,0,Math.sin(t*2.4)*0.025);
   r("leftUpperArm",-0.1,-0.3,-0.95);r("rightUpperArm",-0.1,0.3,0.95);r("leftLowerArm",0,-0.55,1.2);r("rightLowerArm",0,0.55,-1.2);hip.position.y+=0.008*u*Math.sin(phaseTime*4.8);expr.happy=0.85;
  }
  if(clip==="laughing"){
   const laugh=Math.sin(t*10);r("spine",0.10+0.025*laugh,0,0.015*Math.sin(t*2));r("head",-0.06+0.035*laugh,0,0.05);
   this.hand("left",this.point(0.15,1.06,0.25),this.point(0.45,0.9,0.2));this.orient("leftHand",-Math.PI/2,0,Math.PI);this.hand("right",this.point(-0.10,1.3,0.28),this.point(-0.45,1.0,0.25));expr.happy=0.95;expr.aa=0.15+0.16*Math.max(0,laugh);
  }
  if(clip==="thinking"){
   r("head",0.10,0.09,0.08);r("spine",0.015,-0.025,0);this.root.updateWorldMatrix(true,true);
   const chin=this.nodes.head.localToWorld(v(-0.025*u,-0.08*u,0.11*u));
   this.hand("right",chin,this.point(-0.20,1.07,0.24));this.root.updateWorldMatrix(true,true);const elbow=this.nodes.rightLowerArm.getWorldPosition(v()).add(v(0.03*u,-0.015*u,0.035*u));this.hand("left",elbow,this.point(0.30,0.95,0.2));this.orient("leftHand",-Math.PI/2,0,Math.PI);this.fingers("right",0.85);expr.relaxed=0.15;
  }
  if(sit){
   if(clip==="sitting-cross-legged"){
    r("spine",0.04,0,0);expr.relaxed=0.35;
    this.foot("left",this.point(-0.16,0.08,0.29),this.point(0.8,0.05,0.6));this.foot("right",this.point(0.16,0.11,0.22),this.point(-0.8,0.05,0.6));
    this.orient("leftFoot",0,-0.7,-0.45);this.orient("rightFoot",0,0.7,0.45);this.root.updateWorldMatrix(true,true);
    for(const side of ["left","right"]){const knee=this.nodes[side+"LowerLeg"].getWorldPosition(v()).add(v(0,0.035*u,-0.08*u));this.hand(side,knee,this.point(side==="left"?0.5:-0.5,0.5,0.25));this.orient(side+"Hand",0,side==="left"?-Math.PI/2:Math.PI/2,0);}
   }else if(clip==="kneeling"){
    for(const [side,sign] of [["left",1],["right",-1]]){
     this.root.updateWorldMatrix(true,true);
     const start=this.root.worldToLocal(this.nodes[side+"UpperLeg"].getWorldPosition(v()));
     const [thigh,shin]=this.legLengths[side],kneeY=this.ground+0.075*u,ankleY=this.ground+0.07*u;
     const kneeZ=start.z+Math.sqrt(Math.max(0.001,thigh*thigh-(start.y-kneeY)**2));
     const ankleZ=kneeZ-Math.sqrt(Math.max(0.001,shin*shin-(kneeY-ankleY)**2));
     this.foot(side,this.root.localToWorld(v(start.x,ankleY,ankleZ)),this.root.localToWorld(v(start.x,kneeY,kneeZ)));this.orient(side+"Foot",Math.PI,0,0);
     this.hand(side,this.point(sign*0.12,0.22,0.20),this.point(sign*0.35,0.5,0.1));this.orient(side+"Hand",0,sign*-Math.PI/2,0);
    }r("head",0.06,0,0);expr.relaxed=0.3;
   }else{
    r("spine",0.48,0.08,0);r("chest",0.12,0,0);r("neck",0.12,0,0);r("head",0.15,0,0);
    this.foot("right",this.point(-0.09,0.08,0.55),this.point(-0.09,1.3,0.55));this.foot("left",this.point(0.18,0.08,0.2),this.point(0.75,0.05,0.4));
    this.orient("rightFoot",0,0,0);this.orient("leftFoot",0,-0.6,-0.45);this.root.updateWorldMatrix(true,true);
    const chin=this.nodes.head.localToWorld(v(0,-0.075*u,0.10*u)),knee=this.nodes.rightLowerLeg.getWorldPosition(v());
    this.hand("right",chin.clone().add(v(-0.035*u,-0.055*u,0)),this.point(-0.4,0.40,0.38));
    this.hand("left",knee.clone().add(v(0.045*u,-0.11*u,0.045*u)),this.point(0.38,0.4,0.4));this.orient("leftHand",-Math.PI/2,0,Math.PI);
    this.fingers("right",0.8);this.fingers("left",0.25);expr.sad=0.25;expr.relaxed=0.25;
   }
  }
  if(clip==="clapping"){
   const open=0.020+0.12*smooth(0.15,0.85,0.5+0.5*Math.cos(phaseTime*7));
   for(const [side,sign] of [["left",1],["right",-1]]){
    this.hand(side,this.point(sign*open,1.19,0.35),this.point(sign*0.42,0.95,0.15));this.orient(side+"Hand",0,Math.PI,sign*Math.PI/2);this.fingers(side,0.025);
   }r("head",-0.02,0,Math.sin(t*2)*0.015);expr.happy=0.65;
  }
  if(clip==="jumping"){
   const p=(age%2.7+2.7)%2.7;
   const crouch=p<0.5?smooth(0,0.5,p):p<0.7?1-smooth(0.5,0.7,p):p<1.35?0:p<1.55?smooth(1.35,1.55,p):1-smooth(1.55,2.05,p);
   const flight=p>=0.7&&p<1.35?Math.sin((p-0.7)/0.65*Math.PI):0,rootY=0.23*flight*u;hip.position.y+=rootY-crouch*0.13*u;r("spine",crouch*0.13,0,0);
   for(const [side,sign] of [["left",1],["right",-1]]){
    const target=this.feet[side].clone();target.y+=rootY;this.foot(side,this.root.localToWorld(target),this.point(sign*0.13,0.45,0.8));this.orient(side+"Foot",flight*0.25,0,0);
    r(side+"UpperArm",crouch*0.25-flight*2.1,0,sign*-1.28);r(side+"LowerArm",0,sign*-0.2,sign*flight*0.35);
   }expr.happy=0.55;
  }
  if(clip==="nodding")r("head",0.16*Math.sin(age*4),0,0);
  if(clip==="shaking-head")r("head",0,0.22*Math.sin(age*3.5),0);
  if(clip==="bowing"){const bend=0.42*(smooth(0,0.9,age)-smooth(3.0,4.1,age));r("hips",bend*0.3,0,0);r("spine",bend,0,0);r("head",bend*0.3,0,0);}
  if(clip==="stretching"){
   r("leftUpperArm",0,-0.2,0.95);r("rightUpperArm",0,0.2,-0.95);r("leftLowerArm",0,0,0.25);r("rightLowerArm",0,0,-0.25);r("spine",-0.04,0,Math.sin(t*0.8)*0.05);r("head",-0.08,0,0);expr.relaxed=0.3;
  }
  // Smooth complete target pose after solving contacts, including hip height.
  const alpha=dt===0?1:1-Math.exp(-(sit?4:clip==="clapping"?16:8)*dt);
  for(const [name,node] of Object.entries(this.nodes)){
   const target=node.quaternion.clone();if(this.previous[name])node.quaternion.copy(this.previous[name]).slerp(target,alpha);this.previous[name]=node.quaternion.clone();
  }
  this.hipPosition.lerp(hip.position,alpha);hip.position.copy(this.hipPosition);
  for(const [name,target] of Object.entries(expr)){
   this.expressions[name]=THREE.MathUtils.lerp(this.expressions[name]??0,target,dt===0?1:1-Math.exp(-12*dt));this.avatar.expressionManager?.setValue(name,this.expressions[name]);
  }
  this.root.updateWorldMatrix(true,true);
 }
}
