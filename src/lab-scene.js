import * as THREE from '../vendor/three.module.js';

/**
 * SpinLab XR — an original, intentionally fictional reaction-wheel workcell.
 * All meshes and canvas labels are generated here. Dimensions are metres.
 * No proprietary CAD, third-party artwork, real hardware models, or shadows.
 */
export function buildLab(scene) {
  const root = new THREE.Group();
  root.name = 'SpinLab / procedural workcell';
  scene.add(root);
  scene.background = new THREE.Color('#081321');

  const materials = {
    floor: new THREE.MeshStandardMaterial({ color: '#0b1725', roughness: .92 }),
    wall: new THREE.MeshStandardMaterial({ color: '#101f31', roughness: .95 }),
    frame: new THREE.MeshStandardMaterial({ color: '#24364b', metalness: .65, roughness: .47 }),
    dark: new THREE.MeshStandardMaterial({ color: '#111d2a', metalness: .3, roughness: .65 }),
    metal: new THREE.MeshStandardMaterial({ color: '#9cacba', metalness: .72, roughness: .32 }),
    brushed: new THREE.MeshStandardMaterial({ color: '#536e84', metalness: .7, roughness: .43 }),
    rotor: new THREE.MeshStandardMaterial({ color: '#8195a5', metalness: .82, roughness: .31 }),
    black: new THREE.MeshStandardMaterial({ color: '#07111a', metalness: .12, roughness: .73 }),
    orange: new THREE.MeshStandardMaterial({ color: '#ff913d', metalness: .2, roughness: .43 }),
    brass: new THREE.MeshStandardMaterial({ color: '#d7ae5d', metalness: .7, roughness: .34 }),
    cyan: new THREE.MeshStandardMaterial({ color: '#4edee0', emissive: '#1a8d9d', emissiveIntensity: .48, roughness: .38 }),
    white: new THREE.MeshStandardMaterial({ color: '#deedf0', roughness: .5 }),
    guard: new THREE.MeshPhysicalMaterial({
      color: '#8ed4e7', transparent: true, opacity: .105, metalness: .05,
      roughness: .18, depthWrite: false, side: THREE.DoubleSide,
    }),
  };
  const textures = [];
  const interactive = [];
  const v = new THREE.Vector3();
  const temp = new THREE.Object3D();
  const clamp = THREE.MathUtils.clamp;

  function mesh(geometry, material, parent = root, position = [0, 0, 0]) {
    const object = new THREE.Mesh(geometry, material);
    object.position.set(...position);
    parent.add(object);
    return object;
  }
  function box(size, position, material, parent = root) {
    return mesh(new THREE.BoxGeometry(...size), material, parent, position);
  }
  function cylinder(radius, height, position, material, parent = root, segments = 32) {
    return mesh(new THREE.CylinderGeometry(radius, radius, height, segments), material, parent, position);
  }
  function ring(radius, tube, position, material, parent = root, segments = 48) {
    const object = mesh(new THREE.TorusGeometry(radius, tube, 5, segments), material, parent, position);
    object.rotation.x = Math.PI / 2;
    return object;
  }
  function instances(geometry, material, placements, parent = root) {
    const object = new THREE.InstancedMesh(geometry, material, placements.length);
    placements.forEach((placement, index) => {
      temp.position.set(...(placement.position || placement));
      temp.rotation.set(...(placement.rotation || [0, 0, 0]));
      temp.scale.set(...(placement.scale || [1, 1, 1]));
      temp.updateMatrix();
      object.setMatrixAt(index, temp.matrix);
    });
    object.instanceMatrix.needsUpdate = true;
    parent.add(object);
    return object;
  }
  function cable(points, material = materials.black, radius = .004, parent = root) {
    const curve = new THREE.CatmullRomCurve3(points.map(point => new THREE.Vector3(...point)));
    return mesh(new THREE.TubeGeometry(curve, 28, radius, 5, false), material, parent);
  }
  function label(text, position, width = .25, height = .06, options = {}) {
    const canvas = document.createElement('canvas');
    canvas.width = 768;
    canvas.height = Math.round(768 * height / width);
    const context = canvas.getContext('2d');
    context.fillStyle = options.background || '#112436';
    context.fillRect(0, 0, canvas.width, canvas.height);
    context.fillStyle = options.accent || '#5ddfe3';
    context.fillRect(0, 0, 8, canvas.height);
    context.font = `600 ${Math.round(canvas.height * .36)}px system-ui, sans-serif`;
    context.textAlign = 'center';
    context.textBaseline = 'middle';
    context.fillStyle = options.color || '#dff3f5';
    context.fillText(text, canvas.width / 2, canvas.height / 2 + 1, canvas.width - 42);
    const texture = new THREE.CanvasTexture(canvas);
    texture.colorSpace = THREE.SRGBColorSpace;
    texture.anisotropy = 2;
    textures.push(texture);
    let object;
    if (options.sprite) {
      object = new THREE.Sprite(new THREE.SpriteMaterial({ map: texture, depthTest: true }));
      object.scale.set(width, height, 1);
      object.position.set(...position);
      (options.parent || root).add(object);
    } else {
      object = mesh(new THREE.PlaneGeometry(width, height),
        new THREE.MeshBasicMaterial({ map: texture, side: THREE.DoubleSide }),
        options.parent || root, position);
      if (options.horizontal) object.rotation.x = -Math.PI / 2;
    }
    object.name = `Label: ${text}`;
    return object;
  }
  function target(object, action, name) {
    object.userData.action = action;
    object.userData.label = name;
    interactive.push(object);
    return object;
  }

  // Light is deliberately inexpensive and independent of real-time shadows.
  const lights = new THREE.Group();
  lights.name = 'Workcell / static illumination';
  lights.add(new THREE.HemisphereLight('#b6d6eb', '#102134', 2.25));
  const key = new THREE.DirectionalLight('#e5f5ff', 2.5);
  key.position.set(-2, 4.5, 2);
  lights.add(key);
  const rimLight = new THREE.DirectionalLight('#5ccde7', 1.2);
  rimLight.position.set(2, 3, -4);
  lights.add(rimLight);
  root.add(lights);

  // A restrained workshop gives scale cues without competing with the station.
  box([12, .035, 12], [0, -.025, -2], materials.floor);
  const gridVertices = [];
  for (let i = -12; i <= 12; i += 1) {
    const p = i * .5;
    gridVertices.push(-6, .002, p - 2, 6, .002, p - 2);
    gridVertices.push(p, .002, -8, p, .002, 4);
  }
  const gridGeometry = new THREE.BufferGeometry();
  gridGeometry.setAttribute('position', new THREE.Float32BufferAttribute(gridVertices, 3));
  root.add(new THREE.LineSegments(gridGeometry,
    new THREE.LineBasicMaterial({ color: '#224257', transparent: true, opacity: .35 })));
  box([7, 3.5, .07], [0, 1.7, -3.7], materials.wall);
  const wallFrames = [
    [-2.25, 1.7, -3.64], [2.25, 1.7, -3.64], [0, 3.15, -3.64],
  ];
  instances(new THREE.BoxGeometry(.025, 3.1, .03), materials.frame, wallFrames.slice(0, 2));
  box([5.4, .025, .03], wallFrames[2], materials.frame);
  box([2.3, .008, .016], [0, 2.7, -3.63], materials.cyan);
  label('SPINLAB  /  ROTATING SYSTEMS', [0, 2.45, -3.64], 1.45, .16);
  label('ENGINEERING TRAINING • RX-01', [0, 2.2, -3.64], 1.1, .095,
    { color: '#8ea9bd', accent: '#263f52', background: '#101f31' });

  // Welded frame, feet and a thick worktop. Repeated details are instanced.
  const benchCenterZ = -1.4;
  const framePlacements = [];
  for (const x of [-.76, .76]) {
    for (const z of [-1.84, -.96]) framePlacements.push({ position: [x, .42, z], scale: [.065, .77, .065] });
    framePlacements.push({ position: [x, .2, benchCenterZ], scale: [.045, .045, .91] });
  }
  framePlacements.push({ position: [0, .19, -1.84], scale: [1.54, .045, .045] });
  framePlacements.push({ position: [0, .75, -.96], scale: [1.54, .075, .05] });
  framePlacements.push({ position: [0, .75, -1.84], scale: [1.54, .075, .05] });
  instances(new THREE.BoxGeometry(1, 1, 1), materials.frame, framePlacements);
  instances(new THREE.CylinderGeometry(.058, .065, .045, 12), materials.black,
    [[-.76, .025, -1.84], [.76, .025, -1.84], [-.76, .025, -.96], [.76, .025, -.96]]);
  box([1.8, .075, 1.12], [0, .8125, benchCenterZ], materials.brushed);
  box([1.76, .012, 1.08], [0, .856, benchCenterZ], materials.dark);
  box([1.8, .016, .018], [0, .83, -.831], materials.cyan);
  box([1.18, .025, .6], [0, .28, -1.43], materials.dark);
  label('SPINLAB  /  RX-01', [-.43, .785, -.833], .52, .044);
  label('REACTION-WHEEL BALANCING', [.37, .785, -.833], .58, .044,
    { accent: '#ff913d', color: '#b2c8d7' });

  // Fixture plate, mounting slots and socket-head fasteners.
  box([.75, .04, .72], [.02, .882, -1.4], materials.brushed);
  box([.69, .008, .66], [.02, .906, -1.4], materials.metal);
  const slotPlacements = [];
  for (const x of [-.26, .26]) {
    for (const z of [-1.63, -1.17]) slotPlacements.push([x, .911, z]);
  }
  instances(new THREE.BoxGeometry(.082, .003, .013), materials.dark, slotPlacements);
  const bolts = [];
  for (const x of [-.303, .343]) for (const z of [-1.7, -1.1]) bolts.push([x, .916, z]);
  for (const x of [-.84, .84]) for (const z of [-1.9, -.9]) bolts.push([x, .865, z]);
  instances(new THREE.CylinderGeometry(.008, .008, .009, 6), materials.black, bolts);
  label('BALANCE FIXTURE  /  FICTIONAL DEMONSTRATOR', [.02, .918, -1.08], .55, .035,
    { horizontal: true, color: '#b9cbd4', accent: '#536e84', background: '#314859' });

  const rotorAssembly = new THREE.Group();
  rotorAssembly.name = 'Spindle / exploded assembly';
  rotorAssembly.position.set(0, .914, -1.4);
  root.add(rotorAssembly);
  box([.27, .021, .27], [0, .01, 0], materials.dark, rotorAssembly);
  cylinder(.066, .045, [0, .04, 0], materials.brushed, rotorAssembly);
  ring(.057, .003, [0, .062, 0], materials.cyan, rotorAssembly);
  const axle = cylinder(.018, .15, [0, .072, 0], materials.metal, rotorAssembly, 24);
  axle.name = 'Spindle shaft';
  instances(new THREE.CylinderGeometry(.006, .006, .006, 6), materials.metal,
    [[-.105, .024, -.105], [.105, .024, -.105], [-.105, .024, .105], [.105, .024, .105]], rotorAssembly);

  function makeRotor(parent, radius = .22, detailed = true) {
    const group = new THREE.Group();
    parent.add(group);
    cylinder(radius, .014, [0, 0, 0], materials.rotor, group, 64);
    const annulus = mesh(new THREE.RingGeometry(radius * .51, radius * .87, 64), materials.brushed, group, [0, .0075, 0]);
    annulus.rotation.x = -Math.PI / 2;
    cylinder(radius * .225, .026, [0, .006, 0], materials.metal, group, 32);
    cylinder(radius * .085, .029, [0, .008, 0], materials.black, group, 20);
    ring(radius * .91, .0016, [0, .0085, 0], materials.metal, group, 64);
    const holes = [];
    const ticks = [];
    for (let i = 0; i < 12; i += 1) {
      const angle = i / 12 * Math.PI * 2;
      holes.push([Math.cos(angle) * radius * .7, .008, Math.sin(angle) * radius * .7]);
      ticks.push({
        position: [Math.cos(angle) * radius * .965, .008, Math.sin(angle) * radius * .965],
        rotation: [0, -angle, 0],
      });
    }
    instances(new THREE.CylinderGeometry(radius * .035, radius * .035, .002, 10), materials.black, holes, group);
    instances(new THREE.BoxGeometry(radius * .045, .002, radius * .014), materials.orange, ticks, group);
    if (detailed) {
      const hubBolts = [];
      for (let i = 0; i < 6; i += 1) {
        const angle = i / 6 * Math.PI * 2;
        hubBolts.push([Math.cos(angle) * .037, .021, Math.sin(angle) * .037]);
      }
      instances(new THREE.CylinderGeometry(.004, .004, .006, 6), materials.dark, hubBolts, group);
    }
    return group;
  }
  const rotor = makeRotor(rotorAssembly);
  rotor.name = 'Rotor / slowed visual rotation';
  rotor.position.y = .086;
  const massMarker = new THREE.Group();
  massMarker.name = 'Correction mass';
  rotor.add(massMarker);
  const massFoot = box([.029, .009, .021], [0, .015, 0], materials.orange, massMarker);
  const massWeight = cylinder(.011, .015, [0, .025, 0], materials.brass, massMarker, 12);
  cylinder(.0034, .004, [0, .035, 0], materials.black, massMarker, 6);
  massMarker.position.x = .181;

  // Clear interlocked lid. Geometry rotates around a real rear hinge location.
  const guard = new THREE.Group();
  guard.name = 'Guard / rear hinge';
  guard.position.set(0, .925, -1.75);
  root.add(guard);
  const guardWidth = .68;
  const guardDepth = .7;
  const guardHeight = .46;
  box([guardWidth, .006, guardDepth], [0, guardHeight, guardDepth / 2], materials.guard, guard);
  box([.005, guardHeight, guardDepth], [-guardWidth / 2, guardHeight / 2, guardDepth / 2], materials.guard, guard);
  box([.005, guardHeight, guardDepth], [guardWidth / 2, guardHeight / 2, guardDepth / 2], materials.guard, guard);
  box([guardWidth, guardHeight, .005], [0, guardHeight / 2, guardDepth], materials.guard, guard);
  const guardBars = [];
  for (const x of [-guardWidth / 2, guardWidth / 2]) {
    for (const z of [0, guardDepth]) guardBars.push({ position: [x, guardHeight / 2, z], scale: [.014, guardHeight, .014] });
    guardBars.push({ position: [x, guardHeight, guardDepth / 2], scale: [.014, .014, guardDepth] });
    guardBars.push({ position: [x, 0, guardDepth / 2], scale: [.014, .014, guardDepth] });
  }
  for (const z of [0, guardDepth]) guardBars.push({ position: [0, guardHeight, z], scale: [guardWidth, .014, .014] });
  instances(new THREE.BoxGeometry(1, 1, 1), materials.frame, guardBars, guard);
  box([.23, .007, .013], [0, guardHeight + .006, guardDepth], materials.cyan, guard);
  const guardHandle = target(box([.17, .023, .029], [0, .35, guardDepth + .026], materials.orange, guard), 'guard', 'Open / close guard');
  box([.014, .045, .03], [-.07, .328, guardDepth + .016], materials.dark, guard);
  box([.014, .045, .03], [.07, .328, guardDepth + .016], materials.dark, guard);
  const hinges = instances(new THREE.CylinderGeometry(.015, .015, .09, 12), materials.metal,
    [{ position: [-.23, .927, -1.75], rotation: [0, 0, Math.PI / 2] },
      { position: [.23, .927, -1.75], rotation: [0, 0, Math.PI / 2] }]);
  hinges.name = 'Guard hinge barrels';
  label('GUARD  /  SELECT HANDLE', [0, .425, guardDepth + .007], .28, .035,
    { parent: guard, accent: '#ff913d', background: '#20354b' });
  const interlock = box([.028, .025, .03], [.365, .94, -1.07], materials.cyan);
  interlock.name = 'Guard interlock indicator';

  // Linear sensor carriage with exposed leadscrew, knob and a small probe.
  const probe = new THREE.Group();
  probe.name = 'Probe / sensor carriage';
  probe.position.set(.46, .94, -1.4);
  root.add(probe);
  box([.27, .027, .19], [0, -.013, 0], materials.dark, probe);
  box([.255, .012, .175], [0, .007, 0], materials.brushed, probe);
  instances(new THREE.CylinderGeometry(.008, .008, .24, 12), materials.metal,
    [{ position: [0, .029, -.057], rotation: [0, 0, Math.PI / 2] },
      { position: [0, .029, .057], rotation: [0, 0, Math.PI / 2] }], probe);
  const carriage = new THREE.Group();
  carriage.name = 'Probe / translating carriage';
  probe.add(carriage);
  box([.095, .045, .13], [0, .041, 0], materials.brushed, carriage);
  box([.055, .08, .058], [-.015, .102, 0], materials.dark, carriage);
  const sensorBarrel = cylinder(.014, .102, [-.07, .103, 0], materials.metal, carriage, 20);
  sensorBarrel.rotation.z = Math.PI / 2;
  const sensorTip = cylinder(.011, .008, [-.124, .103, 0], materials.cyan, carriage, 16);
  sensorTip.rotation.z = Math.PI / 2;
  const micrometer = cylinder(.017, .095, [.162, .03, 0], materials.metal, probe, 24);
  micrometer.rotation.z = Math.PI / 2;
  const micrometerKnob = target(cylinder(.024, .045, [.221, .03, 0], materials.orange, probe, 24), 'home', 'Home sensor probe');
  micrometerKnob.rotation.z = Math.PI / 2;
  const knobRidges = [];
  for (let i = 0; i < 16; i += 1) {
    const angle = i / 16 * Math.PI * 2;
    knobRidges.push({ position: [.221, .03 + Math.cos(angle) * .024, Math.sin(angle) * .024], rotation: [angle, 0, 0] });
  }
  instances(new THREE.BoxGeometry(.037, .003, .003), materials.brass, knobRidges, probe);
  const scaleMarks = [];
  for (let i = 0; i <= 12; i += 1) scaleMarks.push([-.108 + i * .018, .015, .08]);
  instances(new THREE.BoxGeometry(.0015, .001, .008), materials.white, scaleMarks, probe);
  label('PROBE  /  0–12 mm', [.025, .018, .072], .19, .025,
    { parent: probe, horizontal: true, accent: '#ff913d', background: '#314859' });
  cable([[.46, 1.05, -1.43], [.58, 1.08, -1.55], [.74, .94, -1.65], [.8, .87, -1.9], [.8, .5, -1.94]]);
  cable([[.015, .94, -1.5], [.1, .925, -1.7], [.39, .92, -1.79], [.6, .88, -1.9], [.7, .45, -1.94]], materials.dark, .006);

  // Kitted assembly tray: no downloaded CAD or brand-specific part shapes.
  box([.35, .022, .64], [-.63, .875, -1.42], materials.frame);
  box([.325, .009, .61], [-.63, .889, -1.42], materials.black);
  const spareRotor = makeRotor(root, .137, false);
  spareRotor.name = 'Kitted rotor / select to mount';
  spareRotor.position.set(-.63, .907, -1.51);
  const trayTarget = target(cylinder(.147, .018, [-.63, .906, -1.51],
    new THREE.MeshBasicMaterial({ visible: false })), 'mount', 'Mount / remove rotor');
  // Three.js raycasting includes an invisible material; keep the mesh visible.
  // This volume gives the tray an easy controller target without visual clutter.
  trayTarget.userData.hitOnly = true;
  const massKit = [];
  for (let i = 0; i < 3; i += 1) massKit.push([-.71 + i * .08, .909, -1.19]);
  instances(new THREE.SphereGeometry(.017, 12, 8), materials.brass, massKit);
  instances(new THREE.CylinderGeometry(.022, .022, .005, 16), materials.dark,
    massKit.map(p => [p[0], .897, p[2]]));
  label('ROTOR KIT', [-.63, .902, -1.69], .25, .038,
    { horizontal: true, accent: '#ff913d' });
  label('TRIM MASSES', [-.63, .902, -1.105], .25, .031,
    { horizontal: true, accent: '#d7ae5d', color: '#b6cbd4' });

  // Small rail-mounted cable junction and orange carrying handles complete the fixture.
  box([.17, .08, .09], [.62, .91, -1.84], materials.dark);
  instances(new THREE.CylinderGeometry(.007, .007, .014, 12), materials.cyan,
    [{ position: [.57, .95, -1.791], rotation: [Math.PI / 2, 0, 0] },
      { position: [.61, .95, -1.791], rotation: [Math.PI / 2, 0, 0] },
      { position: [.65, .95, -1.791], rotation: [Math.PI / 2, 0, 0] }]);
  const carryHandles = [];
  for (const x of [-.86, .86]) {
    carryHandles.push({ position: [x, .88, -1.42], scale: [.017, .018, .2] });
    carryHandles.push({ position: [x, .868, -1.52], scale: [.017, .04, .017] });
    carryHandles.push({ position: [x, .868, -1.32], scale: [.017, .04, .017] });
  }
  instances(new THREE.BoxGeometry(1, 1, 1), materials.orange, carryHandles);

  // Billboard callouts are intentionally few; root owns all interactive UI.
  const explodedLabel = label('EXPLODED VIEW  /  VISUAL ONLY', [0, 1.63, -1.4], .4, .045,
    { sprite: true, accent: '#ff913d' });
  explodedLabel.visible = false;
  const explodedGuideGeometry = new THREE.BufferGeometry().setFromPoints([
    new THREE.Vector3(0, 1.01, -1.4), new THREE.Vector3(0, 1.5, -1.4),
  ]);
  const explodedGuide = new THREE.Line(explodedGuideGeometry,
    new THREE.LineDashedMaterial({ color: '#66d6da', dashSize: .016, gapSize: .014, transparent: true, opacity: .6 }));
  explodedGuide.computeLineDistances();
  explodedGuide.visible = false;
  root.add(explodedGuide);

  let exploded = false;
  let visualAngle = 0;
  let lastTime;
  let openAmount = 0;
  let probePosition = 6;
  let previousMounted = true;
  function setExploded(value) {
    exploded = Boolean(value);
    explodedLabel.visible = exploded;
    explodedGuide.visible = exploded;
    rotor.position.y = .086 + (exploded ? .29 : 0);
    axle.scale.y = exploded ? 2.6 : 1;
  }

  function update(state = {}) {
    const rpm = Number.isFinite(state.rpm) ? Math.max(0, state.rpm) : 0;
    const time = Number.isFinite(state.time) ? state.time : performance.now() / 1000;
    const dt = lastTime === undefined ? 1 / 60 : clamp(time - lastTime, 0, .1);
    lastTime = time;
    // Slow the visual mesh only. Telemetry and balancing calculations use real RPM.
    visualAngle += rpm / 60 * Math.PI * 2 * .022 * dt;
    rotor.rotation.y = visualAngle % (Math.PI * 2);
    const mounted = state.mounted !== false;
    rotor.visible = mounted;
    spareRotor.visible = !mounted;
    if (previousMounted !== mounted) trayTarget.userData.label = mounted ? 'Remove rotor to kit tray' : 'Mount rotor on spindle';
    previousMounted = mounted;
    const desiredOpen = state.guardClosed === false ? 1 : 0;
    openAmount += (desiredOpen - openAmount) * Math.min(1, dt * 8);
    guard.rotation.x = -openAmount * 1.18;
    interlock.material = state.guardClosed === false ? materials.orange : materials.cyan;
    const sensor = state.sensorPosition;
    if (typeof sensor === 'number' && Number.isFinite(sensor)) probePosition = clamp(sensor, 0, 12);
    else if (sensor && Number.isFinite(sensor.x)) probePosition = clamp(sensor.x, 0, 12);
    carriage.position.x = (probePosition - 6) * .008;
    micrometerKnob.rotation.x = (probePosition - 6) * .9;
    const angle = Number.isFinite(state.massAngle) ? state.massAngle * Math.PI / 180 : 0;
    massMarker.position.set(Math.cos(angle) * .181, 0, -Math.sin(angle) * .181);
    massMarker.rotation.y = angle;
    const grams = Number.isFinite(state.massGrams) ? Math.max(0, state.massGrams) : 1;
    massMarker.visible = grams > .001;
    massWeight.scale.y = clamp(.6 + grams * .2, .6, 2.6);
    massFoot.scale.x = clamp(.7 + grams * .08, .7, 1.65);
    // Preserve exact spindle location regardless of exploded-view selection.
    rotor.position.y = .086 + (exploded ? .29 : 0);
  }

  // Static geometry budget is inspectable without a renderer or GPU extension.
  const stats = { meshes: 0, drawCalls: 0, triangles: 0, textures: textures.length, units: 'metres', procedural: true };
  root.traverse(object => {
    if (!object.isMesh && !object.isLine) return;
    stats.meshes += object.isMesh ? 1 : 0;
    stats.drawCalls += 1;
    if (object.isMesh) {
      const count = object.geometry.index?.count || object.geometry.attributes.position?.count || 0;
      stats.triangles += count / 3 * (object.isInstancedMesh ? object.count : 1);
    }
  });
  stats.triangles = Math.round(stats.triangles);
  root.userData.stats = stats;
  update({ rpm: 0, time: 0, guardClosed: true, mounted: true, sensorPosition: 6, massAngle: 0, massGrams: 1 });
  return { rotor, rotorAssembly, guard, probe, massMarker, interactive, update, setExploded, stats };
}
