import * as THREE from '../vendor/three.module.js';
import { SpinLabSimulation, SIMULATION_CONSTANTS as C } from './simulation.js';
import { buildLab } from './lab-scene.js';

const $ = id => document.getElementById(id);
const sim = new SpinLabSimulation();
const canvas = $('world');
let renderer;
try { renderer = new THREE.WebGLRenderer({ canvas, antialias:true, powerPreference:'high-performance' }); }
catch (error) { $('fatal').hidden=false; $('fatal').textContent=`WebGL could not start. Enable hardware acceleration and reload. ${error.message}`; throw error; }
renderer.setPixelRatio(Math.min(devicePixelRatio, 1.5));
renderer.setSize(innerWidth, innerHeight);
renderer.outputColorSpace=THREE.SRGBColorSpace;
renderer.toneMapping=THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure=1.2;
renderer.xr.enabled=true;
renderer.xr.setReferenceSpaceType('local-floor');
renderer.xr.setFramebufferScaleFactor(1);
const scene = new THREE.Scene();
scene.background=new THREE.Color('#081321');
const stage = new THREE.Group();
scene.add(stage);
const lab=buildLab(stage);
const camera=new THREE.PerspectiveCamera(42,innerWidth/innerHeight,0.05,45);
const lookAt=new THREE.Vector3(0,1.02,-1.4);
let orbit={azimuth:.38,elevation:.36,distance:3.25};
function setCamera(){ const {azimuth:a,elevation:e,distance:d}=orbit; camera.position.set(lookAt.x+Math.sin(a)*Math.cos(e)*d,lookAt.y+Math.sin(e)*d,lookAt.z+Math.cos(a)*Math.cos(e)*d);camera.lookAt(lookAt); }
setCamera();
const raycaster=new THREE.Raycaster(), tempMatrix=new THREE.Matrix4(), pointer=new THREE.Vector2();
const interactive=[...lab.interactive];
const controllers=[];
let exploded=false, runs=[], recordedRun=false, lastUi=0,lastPanel=0, previousTime=0, fpsElapsed=0, fpsFrames=0, sessionMessage='Load the rotor into the fixture.', selectedDial=null;
let baseline=[];
let activeHover=null;
let savedReport=null;
try{const candidate=JSON.parse(localStorage.getItem('spinlab-last-report')||'null');if(candidate?.application==='SpinLab XR')savedReport=candidate;}catch{/* A corrupt or unavailable saved report does not block the lab. */}
function downloadJson(report){const href=URL.createObjectURL(new Blob([JSON.stringify(report,null,2)],{type:'application/json'}));const a=document.createElement('a');a.href=href;a.download='spinlab-session.json';a.click();setTimeout(()=>URL.revokeObjectURL(href),1000);}
const savedButton=document.createElement('button');savedButton.textContent='↓ Saved report';savedButton.className='quiet';savedButton.hidden=!savedReport;document.querySelector('.header-actions').prepend(savedButton);savedButton.addEventListener('click',()=>{if(savedReport)downloadJson(savedReport);});

function notify(message,ok=true){sessionMessage=message;$('status').textContent=message;$('status').style.color=ok?'#aac0ce':'#ffbb88';}
function haptic(controller, strength=.2){const pad=controller?.userData.source?.gamepad; try{pad?.hapticActuators?.[0]?.pulse(strength,40)?.catch?.(()=>{});}catch{/* Optional hardware feature. */}}
function downloadReport(){
  const report={application:'SpinLab XR',version:'0.1.0',savedAt:new Date().toISOString(),model:'Fictional single-plane damped support; no qualification claims',latest:sim.exportReport(),completedRuns:structuredClone(runs)};
  const json=JSON.stringify(report,null,2);
  savedReport=report;savedButton.hidden=false;
  try{localStorage.setItem('spinlab-last-report',json);}catch{/* Download remains available if storage is full. */}
  if(renderer.xr.isPresenting){notify('Report saved in this browser. Exit VR and select Saved report to download.');return;}
  downloadJson(report);notify('Session report exported as JSON.');
}
function action(name,controller){
  let result;
  switch(name){
    case 'mount':result=sim.mountRotor();break;
    case 'guard':result=sim.toggleGuard();break;
    case 'home':result=sim.homeProbe();break;
    case 'run':result=sim.startSweep();if(result.ok)recordedRun=false;break;
    case 'stop':result=sim.stop();break;
    case 'estop':result=sim.emergencyStop();break;
    case 'fault':result=sim.injectFault('sensor');break;
    case 'recover':
      if(sim.estop){result=sim.releaseEstop();notify(result.message);updateUI();return;}
      result=sim.resetFault();break;
    case 'reset':result=sim.reset();runs=[];baseline=[];recordedRun=false;break;
    case 'report':downloadReport();return;
    case 'exploded':exploded=!exploded;lab.setExploded(exploded);notify(exploded?'Assembly view: geometry separated for inspection.':'Assembly returned to operating view.');updateUI();return;
    default:return;
  }
  if(result){notify(result.message,result.ok);haptic(controller,result.ok ? .22 : .55);}
  updateUI();
}
document.querySelectorAll('[data-action]').forEach(button=>button.addEventListener('click',()=>action(button.dataset.action)));
$('exploded-button').addEventListener('click',()=>action('exploded'));
$('reset-view').addEventListener('click',()=>{orbit={azimuth:.38,elevation:.36,distance:3.25};setCamera();});
$('help-button').addEventListener('click',()=>$('help').showModal());
for(const id of ['close-help','begin'])$(id).addEventListener('click',()=>$('help').close());
document.addEventListener('keydown',e=>{if(e.key==='?'&&!$('help').open)$('help').showModal();});
// The guide opens explicitly so the lab remains visible on initial load.
function setDial(name,value,refresh=true){
  let result;
  if(name==='probe')result=sim.setProbePosition(Math.max(0,Math.min(12,Math.round(value*20)/20)));
  if(name==='mass')result=sim.setCorrection(Math.max(0,Math.min(1.2,Math.round(value*1000)/1000)),sim.massAngle);
  if(name==='angle')result=sim.setCorrection(sim.massGrams,((Math.round(value)%360)+360)%360);
  if(result)notify(result.message,result.ok);
  if(refresh)updateUI();
}
for(const name of ['probe','mass','angle'])$(name).addEventListener('input',e=>setDial(name,Number(e.target.value)));
function dialValue(name){return name==='probe'?sim.sensorPosition:name==='mass'?sim.massGrams:sim.massAngle;}
function nextInstruction(t){
  if(t.estop)return 'E-stop is latched. Wait for zero speed, release, then reset the fault.';
  if(t.fault)return t.fault==='guard'?'Wait for zero speed. Close guard, then reset the fault.':'Wait for zero speed. Reset fault, then home the probe.';
  if(t.rpm>0&&!t.running)return 'Coasting. Wait for zero speed before opening the guard.';
  if(t.running)return 'Observe the resonance peak. Keep the guard closed through the sweep.';
  if(!t.mounted)return 'Load the rotor from the tray into the fixture.';
  if(!t.homed)return 'Home the vibration probe to establish its reference.';
  if(Math.abs(t.sensorPosition-6)>.5)return 'Set the probe between 5.5 and 6.5 mm before running.';
  if(t.passed)return 'Verified. Save the report, or inject a fault to practice recovery.';
  if(t.complete)return 'Open guard. Add 0.600 g at 300°, close guard, and repeat the sweep.';
  if(!t.guardClosed)return t.massGrams>0?'Close the guard, then verify your correction with a new sweep.':'Close the guard to enable the baseline sweep.';
  return runs.length?'Run another sweep to verify the new configuration.':'Run the baseline speed sweep. Watch vibration rise near resonance.';
}
function updateUI(){
  const t=sim.getTelemetry();
  $('rpm').textContent=Math.round(t.rpm).toLocaleString('en-US');
  $('vibration').innerHTML=`${t.vibration.toFixed(2)} <small>mm/s</small>`;
  $('residual').innerHTML=`${t.residual.toFixed(1)} <small>g·mm</small>`;
  $('phase').textContent=`${Math.round(t.phase)}°`;
  $('run-state').textContent=t.estop?'E-STOP':t.fault?'FAULT':t.running?'ACQUIRING':t.rpm>0?'COASTING':t.passed?'VERIFIED':'STANDBY';
  $('guard-button').textContent=t.guardClosed?'03  Open guard':'03  Close guard';
  $('mount-button').textContent=t.mounted?'✓  Rotor mounted':'01  Load rotor';
  for(const[name,val,digits]of[['probe',t.sensorPosition,2],['mass',t.massGrams,3],['angle',t.massAngle,0]]){$(`${name}-value`).textContent=val.toFixed(digits);$(name).value=val;}
  $('next-step').textContent=nextInstruction(t);
  const step=t.passed?3:runs.length>0?2:t.mounted&&t.homed&&t.guardClosed?1:0;
  document.querySelectorAll('#steps li').forEach((li,i)=>{li.classList.toggle('active',i===step);li.classList.toggle('done',i<step);});
  $('interlocks').innerHTML=[[t.mounted,'ROTOR'],[t.guardClosed,'GUARD'],[t.homed&&Math.abs(t.sensorPosition-6)<=.5,'PROBE'],[!t.fault&&!t.estop,'DRIVE']].map(([ok,label])=>`<span class="${ok?'ok':(t.fault?'bad':'')}">${ok?'●':'○'} ${label}</span>`).join('');
  const result=$('result');result.className=`result ${t.complete?(t.passed?'pass':'fail'):''}`;
  result.textContent=t.fault?'FAULT LATCHED · DRIVE REMOVED':t.complete?(t.passed?'✓ VERIFIED · RESIDUAL ≤ 2 g·mm':'BASELINE CAPTURED · CORRECTION REQUIRED'):t.running?`ACQUIRING · ${Math.round(t.progress*100)}%`:t.rpm>0?'COASTING · KEEP GUARD CLOSED':runs.length?'CONFIGURATION CHANGED · RE-RUN REQUIRED':'AWAITING BASELINE SWEEP';
  document.querySelector('[data-action="recover"]').textContent=t.estop?'Release E-stop':'Reset / re-arm';
  $('exploded-button').textContent=exploded?'◇ Return to assembly':'◇ Explore assembly';
  drawSweep($('sweep-chart'),t);drawPolar($('polar-chart'),t);
}
function drawSweep(target,t){
  const ctx=target.getContext('2d'),w=target.width,h=target.height;ctx.clearRect(0,0,w,h);
  const left=52,right=w-18,top=16,bottom=h-30;
  const samples=sim.measurements;
  const all=[...samples,...baseline];
  const ymax=Math.max(15,...all.map(p=>p.vibration*1.15));
  ctx.font='18px Segoe UI';ctx.fillStyle='#8099ac';ctx.strokeStyle='#66829925';ctx.lineWidth=1;
  for(let i=0;i<=3;i++){let y=top+(bottom-top)*i/3;ctx.beginPath();ctx.moveTo(left,y);ctx.lineTo(right,y);ctx.stroke();ctx.fillText((ymax*(1-i/3)).toFixed(0),5,y+6);}
  for(const n of [0,600,1200,1800]){let x=left+(right-left)*n/1800;ctx.fillText(String(n),x-17,h-6);}
  function line(points,color){if(!points.length)return;ctx.strokeStyle=color;ctx.lineWidth=3;ctx.beginPath();points.forEach((p,i)=>{const x=left+(right-left)*p.rpm/1800,y=bottom-(bottom-top)*p.vibration/ymax;i?ctx.lineTo(x,y):ctx.moveTo(x,y);});ctx.stroke();}
  line(baseline,'#ffbb795e');line(samples,'#6ce5c9');
  if(samples.length){const p=samples.at(-1);ctx.fillStyle='#d7fff4';ctx.beginPath();ctx.arc(left+(right-left)*p.rpm/1800,bottom-(bottom-top)*p.vibration/ymax,4,0,Math.PI*2);ctx.fill();}
  else{ctx.fillStyle='#7692a5';ctx.font='18px Segoe UI';ctx.fillText('Run sweep to acquire data',left+32,top+(bottom-top)*.56);}
}
function drawPolar(target,t){
  const ctx=target.getContext('2d'),w=target.width,h=target.height;ctx.clearRect(0,0,w,h);const x=w/2,y=h/2,r=Math.min(w,h)*.38;
  ctx.strokeStyle='#6a8b9e33';ctx.lineWidth=1.5;for(const k of [.33,.66,1]){ctx.beginPath();ctx.arc(x,y,r*k,0,Math.PI*2);ctx.stroke();}
  ctx.beginPath();ctx.moveTo(x-r,y);ctx.lineTo(x+r,y);ctx.moveTo(x,y-r);ctx.lineTo(x,y+r);ctx.stroke();
  function vec(angle,length,color){const a=angle*Math.PI/180;ctx.strokeStyle=color;ctx.fillStyle=color;ctx.lineWidth=3;ctx.beginPath();ctx.moveTo(x,y);const px=x+Math.cos(a)*r*length,py=y-Math.sin(a)*r*length;ctx.lineTo(px,py);ctx.stroke();ctx.beginPath();ctx.arc(px,py,5,0,Math.PI*2);ctx.fill();}
  vec(120,.75,'#ffbb7977');if(t.massGrams>0)vec(t.massAngle,Math.min(1,t.massGrams*30/24),'#789cff');vec(t.phase,Math.min(1,t.residual/24),'#6ce5c9');
  ctx.font='15px Segoe UI';ctx.fillStyle='#8099ac';ctx.fillText('0°',x+r+4,y+5);ctx.fillText('90°',x-12,y-r-5);
}

// In-headset controls are actual world-space meshes; no DOM interaction is required.
const vrUI=new THREE.Group();stage.add(vrUI);vrUI.visible=false;
function canvasSurface(width,height,worldW,worldH){const c=document.createElement('canvas');c.width=width;c.height=height;const texture=new THREE.CanvasTexture(c);texture.colorSpace=THREE.SRGBColorSpace;texture.minFilter=THREE.LinearFilter;const mesh=new THREE.Mesh(new THREE.PlaneGeometry(worldW,worldH),new THREE.MeshBasicMaterial({map:texture,side:THREE.DoubleSide}));return{canvas:c,ctx:c.getContext('2d'),texture,mesh};}
const vrButtons=[];
function makeButton(label,name,x,y,z,width=.56,color='#203b4b'){
  const s=canvasSurface(640,88,width,.067);s.mesh.position.set(x,y,z);s.mesh.userData.action=name;s.mesh.userData.label=label;s.color=color;vrUI.add(s.mesh);interactive.push(s.mesh);vrButtons.push(s);return s;
}
const controlsX=-.95, controlsZ=-1.25;
const panelBack=new THREE.Mesh(new THREE.BoxGeometry(.66,.82,.025),new THREE.MeshBasicMaterial({color:0x122331}));panelBack.position.set(controlsX,1.31,controlsZ-.02);vrUI.add(panelBack);
const controlTitle=canvasSurface(768,100,.58,.075);controlTitle.mesh.position.set(controlsX,1.65,controlsZ);vrUI.add(controlTitle.mesh);
const controlActions=[['LOAD ROTOR','mount'],['HOME PROBE','home'],['CLOSE GUARD','guard'],['RUN SWEEP','run'],['STOP / COAST','stop'],['E-STOP','estop'],['RESET FAULT','recover'],['SAVE REPORT','report']];
controlActions.forEach(([label,name],i)=>makeButton(label,name,controlsX,1.56-i*.081,controlsZ+.003,.56,name==='run'?'#28614f':name==='estop'?'#71323d':'#203b4b'));
const vrInstrument=canvasSurface(768,960,.65,.81);vrInstrument.mesh.position.set(.95,1.37,-1.25);vrUI.add(vrInstrument.mesh);
const vrInstruction=canvasSurface(1536,220,1.32,.19);vrInstruction.mesh.position.set(0,1.98,-1.4);vrUI.add(vrInstruction.mesh);
const dialObjects=[];
for(const[i,name]of['probe','mass','angle'].entries()){
  const group=new THREE.Group();group.position.set((i-1)*.24,.98,-.84);
  const body=new THREE.Mesh(new THREE.CylinderGeometry(.044,.044,.043,32),new THREE.MeshStandardMaterial({color:0x385b6b,roughness:.34,metalness:.7}));body.rotation.x=Math.PI/2;body.userData.action=`dial:${name}`;group.add(body);interactive.push(body);
  const tick=new THREE.Mesh(new THREE.BoxGeometry(.004,.025,.004),new THREE.MeshBasicMaterial({color:0x6ce5c9}));tick.position.set(0,.023,.024);body.add(tick);
  for(let j=0;j<12;j++){const angle=j*Math.PI/6;const ridge=new THREE.Mesh(new THREE.BoxGeometry(.003,.007,.005),body.material);ridge.position.set(Math.sin(angle)*.043,Math.cos(angle)*.043,0);group.add(ridge);}
  const label=canvasSurface(512,110,.205,.044);label.mesh.position.set(0,-.084,.018);group.add(label.mesh);vrUI.add(group);dialObjects.push({name,body,label});
}
const explorer=makeButton('EXPLODE ASSEMBLY','exploded',0,1.76,-1.55,.38);
makeButton('SENSOR FAULT','fault',.77,.89,-1.24,.32,'#493f34');
makeButton('NEW SESSION','reset',1.13,.89,-1.24,.32);
const occluders=[panelBack,vrInstrument.mesh,vrInstruction.mesh,controlTitle.mesh];
function wrap(ctx,text,x,y,maxWidth,lineHeight,maxLines=3){const words=text.split(' ');let line='',n=0;for(const word of words){const next=line?`${line} ${word}`:word;if(ctx.measureText(next).width>maxWidth&&line){ctx.fillText(line,x,y+n*lineHeight);line=word;n++;if(n>=maxLines)return;}else line=next;}ctx.fillText(line,x,y+n*lineHeight);}
function drawPanels(){
  const t=sim.getTelemetry();
  for(const s of vrButtons){const {ctx}=s;const name=s.mesh.userData.action;let label=s.mesh.userData.label;if(name==='guard')label=t.guardClosed?'OPEN GUARD':'CLOSE GUARD';if(name==='recover')label=t.estop?'RELEASE E-STOP':'RESET FAULT';if(name==='mount'&&t.mounted)label='ROTOR MOUNTED';if(name==='exploded')label=exploded?'ASSEMBLED VIEW':'EXPLODE ASSEMBLY';ctx.fillStyle=s.color;ctx.fillRect(0,0,640,88);ctx.strokeStyle='#628397';ctx.lineWidth=2;ctx.strokeRect(1,1,638,86);ctx.fillStyle='#e7f6fa';ctx.font='600 29px Segoe UI';ctx.textAlign='center';ctx.fillText(label,320,55);s.texture.needsUpdate=true;}
  const title=controlTitle.ctx;title.fillStyle='#122331';title.fillRect(0,0,768,100);title.font='600 31px Segoe UI';title.fillStyle='#6ce5c9';title.fillText('SPINLAB / STATION CONTROL',24,65);controlTitle.texture.needsUpdate=true;
  const ctx=vrInstrument.ctx;ctx.fillStyle='#132535';ctx.fillRect(0,0,768,960);ctx.fillStyle='#6ce5c9';ctx.font='600 27px Segoe UI';ctx.fillText('LIVE VIBRATION INSTRUMENT',35,58);ctx.fillStyle='#e8f3f7';ctx.font='300 95px Segoe UI';ctx.fillText(`${Math.round(t.rpm)} RPM`,35,172);ctx.font='32px Segoe UI';ctx.fillText(`${t.vibration.toFixed(2)} mm/s  |  ${t.residual.toFixed(2)} g·mm`,35,240);ctx.fillStyle='#9cb6c7';ctx.font='24px Segoe UI';ctx.fillText(`Phase ${Math.round(t.phase)}° · 30 mm correction radius`,35,290);
  ctx.drawImage($('sweep-chart'),20,320,728,250);ctx.drawImage($('polar-chart'),22,580,275,252);ctx.fillStyle='#9cb6c7';ctx.font='25px Segoe UI';wrap(ctx,`ROTOR ${t.mounted?'LOADED':'EMPTY'}  /  GUARD ${t.guardClosed?'CLOSED':'OPEN'}`,315,630,420,38);wrap(ctx,`PROBE ${t.homed?'HOMED':'NOT HOMED'}`,315,720,420,38);ctx.fillStyle=t.fault?'#ff9b95':t.passed?'#6ce5c9':'#ffcb92';ctx.font='600 27px Segoe UI';wrap(ctx,t.fault?`FAULT: ${t.fault.toUpperCase()}`:t.passed?'VERIFIED · SAVE REPORT':t.running?'ACQUIRING SWEEP':t.rpm>0?'COASTING · KEEP GUARD CLOSED':t.complete?'CORRECTION REQUIRED':'STANDBY',35,895,700,37,2);vrInstrument.texture.needsUpdate=true;
  const ins=vrInstruction.ctx;ins.fillStyle='#102330';ins.fillRect(0,0,1536,220);ins.fillStyle='#6ce5c9';ins.font='600 29px Segoe UI';ins.fillText('COMMISSIONING / NEXT MOVE',34,47);ins.fillStyle='#ebf6f9';ins.font='33px Segoe UI';wrap(ins,nextInstruction(t),34,98,1470,44,2);ins.fillStyle='#9eb8c8';ins.font='24px Segoe UI';ins.fillText(sessionMessage.slice(0,110),34,195);vrInstruction.texture.needsUpdate=true;
  for(const dial of dialObjects){const v=dialValue(dial.name);dial.body.rotation.y=v*(dial.name==='mass'?4:1)*Math.PI/180;const c=dial.label.ctx;c.fillStyle='#132535';c.fillRect(0,0,512,110);c.font='600 28px Segoe UI';c.fillStyle=selectedDial===dial.name?'#ffc17b':'#6ce5c9';c.textAlign='center';c.fillText(dial.name.toUpperCase(),256,36);c.fillStyle='#e8f3f7';c.font='31px Segoe UI';c.fillText(`${v.toFixed(dial.name==='mass'?3:dial.name==='probe'?2:0)} ${dial.name==='mass'?'g':dial.name==='probe'?'mm':'deg'}`,256,86);dial.label.texture.needsUpdate=true;}
}

function findHit(origin,direction){raycaster.set(origin,direction);const hits=raycaster.intersectObjects([...interactive,...occluders],true);return hits.find(hit=>hit.object.visible&&isVisible(hit.object)&&hit.distance<5);}
function isVisible(object){while(object){if(!object.visible)return false;object=object.parent;}return true;}
function hitForController(controller){tempMatrix.identity().extractRotation(controller.matrixWorld);const origin=new THREE.Vector3().setFromMatrixPosition(controller.matrixWorld),direction=new THREE.Vector3(0,0,-1).applyMatrix4(tempMatrix);return findHit(origin,direction);}
function targetAction(object){while(object&&!object.userData.action)object=object.parent;return object?.userData.action;}
function selectStart(controller){const hit=hitForController(controller);if(!hit)return;const name=targetAction(hit.object);if(name?.startsWith('dial:')){const dial=name.slice(5);selectedDial=dial;controller.userData.dial=dial;controller.userData.rawDial=dialValue(dial);controller.userData.lastRoll=new THREE.Euler().setFromQuaternion(controller.quaternion,'YXZ').z;haptic(controller);}else action(name,controller);}
for(let i=0;i<2;i++){
  const controller=renderer.xr.getController(i);scene.add(controller);controllers.push(controller);
  const line=new THREE.Line(new THREE.BufferGeometry().setFromPoints([new THREE.Vector3(),new THREE.Vector3(0,0,-1)]),new THREE.LineBasicMaterial({color:i===0?0x6ce5c9:0x9ab7ff,transparent:true,opacity:.7}));line.scale.z=3;controller.add(line);controller.userData.line=line;
  const tip=new THREE.Mesh(new THREE.SphereGeometry(.007,10,6),new THREE.MeshBasicMaterial({color:0x6ce5c9}));scene.add(tip);controller.userData.tip=tip;tip.visible=false;
  controller.addEventListener('connected',e=>{controller.userData.source=e.data;});
  controller.addEventListener('disconnected',()=>{controller.userData.source=null;controller.userData.dial=null;tip.visible=false;});
  controller.addEventListener('selectstart',()=>selectStart(controller));
  controller.addEventListener('selectend',()=>{controller.userData.dial=null;selectedDial=null;});
  controller.addEventListener('squeezestart',()=>{const hit=hitForController(controller);const name=hit&&targetAction(hit.object);if(['mount','guard','home'].includes(name))action(name,controller);});
}
function updateControllers(dt){
  for(const controller of controllers){const source=controller.userData.source;if(!source)continue;const hit=hitForController(controller),tip=controller.userData.tip;tip.visible=!!hit;if(hit){tip.position.copy(hit.point);controller.userData.line.scale.z=hit.distance;}else controller.userData.line.scale.z=3;
    const axes=source.gamepad?.axes??[],x=axes[2]??axes[0]??0,y=axes[3]??axes[1]??0;
    const dial=controller.userData.dial;
    if(dial){const roll=new THREE.Euler().setFromQuaternion(controller.quaternion,'YXZ').z;let delta=roll-controller.userData.lastRoll;if(delta>Math.PI)delta-=Math.PI*2;if(delta<-Math.PI)delta+=Math.PI*2;controller.userData.lastRoll=roll;const stick=Math.abs(x)>.18?x*dt:0;const sensitivity=dial==='mass' ? .20 : dial==='probe'?2.0:90;const change=(delta+stick)*sensitivity;controller.userData.rawDial+=change;if(dial==='angle')controller.userData.rawDial=((controller.userData.rawDial%360)+360)%360;else controller.userData.rawDial=THREE.MathUtils.clamp(controller.userData.rawDial,0,dial==='mass'?1.2:12);if(Math.abs(change)>.0001)setDial(dial,controller.userData.rawDial,false);}
    else if(source.handedness==='left'&&Math.abs(y)>.7)stage.position.y=THREE.MathUtils.clamp(stage.position.y-y*dt*.25,-.5,.25);
  }
}
let pointerDown=null;
canvas.addEventListener('pointerdown',e=>{pointerDown={x:e.clientX,y:e.clientY,azimuth:orbit.azimuth,elevation:orbit.elevation};canvas.setPointerCapture(e.pointerId);});
canvas.addEventListener('pointermove',e=>{
  if(renderer.xr.isPresenting)return;
  if(pointerDown){const dx=e.clientX-pointerDown.x,dy=e.clientY-pointerDown.y;orbit.azimuth=pointerDown.azimuth-dx*.004;orbit.elevation=THREE.MathUtils.clamp(pointerDown.elevation+dy*.003,.05,1.15);setCamera();}
  else{pointer.set(e.clientX/innerWidth*2-1,-e.clientY/innerHeight*2+1);raycaster.setFromCamera(pointer,camera);const hit=raycaster.intersectObjects(lab.interactive,true).find(h=>isVisible(h.object));canvas.style.cursor=hit?'pointer':'grab';}
});
canvas.addEventListener('pointerup',e=>{if(pointerDown&&Math.hypot(e.clientX-pointerDown.x,e.clientY-pointerDown.y)<5){pointer.set(e.clientX/innerWidth*2-1,-e.clientY/innerHeight*2+1);raycaster.setFromCamera(pointer,camera);const hit=raycaster.intersectObjects(lab.interactive,true).find(h=>isVisible(h.object));if(hit)action(targetAction(hit.object));}pointerDown=null;});
canvas.addEventListener('wheel',e=>{orbit.distance=THREE.MathUtils.clamp(orbit.distance+e.deltaY*.002,1.6,5);setCamera();e.preventDefault();},{passive:false});
addEventListener('resize',()=>{camera.aspect=innerWidth/innerHeight;camera.updateProjectionMatrix();renderer.setSize(innerWidth,innerHeight);});

const vrButton=$('enter-vr');
async function detectVR(){
  if(!isSecureContext){vrButton.textContent='VR requires HTTPS / localhost';vrButton.disabled=true;return;}
  try{const supported=!!navigator.xr&&await navigator.xr.isSessionSupported('immersive-vr');vrButton.textContent=supported?'Enter VR ↗':'Quest 2 · VR setup';vrButton.dataset.supported=String(supported);}catch{vrButton.textContent='Quest 2 · VR setup';}
}
vrButton.addEventListener('click',async()=>{
  if(renderer.xr.isPresenting){await renderer.xr.getSession().end();return;}
  if(vrButton.dataset.supported!=='true'){notify('Open this app in Quest Browser via USB localhost or trusted HTTPS. See docs/INSTALL_QUEST2.md.');$('help').showModal();return;}
  try{const session=await navigator.xr.requestSession('immersive-vr',{optionalFeatures:['local-floor','bounded-floor'],requiredFeatures:[]});await renderer.xr.setSession(session);if(session.supportedFrameRates?.includes(72))await session.updateTargetFrameRate(72).catch(()=>{});}
  catch(e){notify(`VR session did not start: ${e.message}`,false);}
});
renderer.xr.addEventListener('sessionstart',()=>{document.body.classList.add('immersive');vrUI.visible=true;vrButton.textContent='Exit VR';camera.position.set(0,0,0);camera.quaternion.identity();stage.position.y=0;});
renderer.xr.addEventListener('sessionend',()=>{document.body.classList.remove('immersive');vrUI.visible=false;controllers.forEach(c=>{c.userData.tip.visible=false;c.userData.dial=null;});selectedDial=null;stage.position.y=0;setCamera();detectVR();notify('Desktop view restored. You can export the report here.');});
detectVR();updateUI();drawPanels();
// Optional flat preview for inspecting world-space panel layout without an XR runtime.
if(new URLSearchParams(location.search).get('layout')==='vr'){
  vrUI.visible=true;document.body.classList.add('immersive');camera.fov=80;camera.updateProjectionMatrix();camera.position.set(0,1.6,.15);camera.lookAt(0,1.25,-1.4);
}

renderer.setAnimationLoop((timestamp)=>{
  const elapsed=previousTime?(timestamp-previousTime)/1000:0;const dt=Math.min(elapsed,.05);previousTime=timestamp;
  sim.tick(dt);
  const t=sim.getTelemetry();
  if(t.complete&&!recordedRun){const report=sim.exportReport();runs.push(report);if(!baseline.length)baseline=sim.measurements.map(p=>({...p}));recordedRun=true;notify(t.passed?'Verification passed. Residual is within the training limit.':'Baseline captured. Open guard and apply a correction.');}
  lab.update({rpm:t.rpm,time:sim.time,guardClosed:t.guardClosed,mounted:t.mounted,sensorPosition:t.sensorPosition,massAngle:t.massAngle,massGrams:t.massGrams});
  if(renderer.xr.isPresenting)updateControllers(dt);
  if(timestamp-lastUi>100){updateUI();lastUi=timestamp;}
  if(renderer.xr.isPresenting&&timestamp-lastPanel>160){drawPanels();lastPanel=timestamp;}
  renderer.render(scene,camera);
  fpsElapsed+=elapsed;fpsFrames++;if(fpsElapsed>=1){$('fps').textContent=`${renderer.xr.isPresenting?'XR':'DESKTOP'} · ${Math.round(fpsFrames/fpsElapsed)} FPS · ${renderer.info.render.calls} DRAWS`;fpsElapsed=0;fpsFrames=0;}
});
// Compact, read-only diagnostics for QA; mutating the station uses visible controls.
window.spinlab={getTelemetry:()=>sim.getTelemetry(),getReport:()=>sim.exportReport(),getRuns:()=>structuredClone(runs),getRenderStats:()=>({calls:renderer.info.render.calls,triangles:renderer.info.render.triangles,geometries:renderer.info.memory.geometries,textures:renderer.info.memory.textures}),version:'0.1.0'};
