import * as THREE from 'three';
import * as M from './models.js';
import * as TX from './textures.js';
import { PALETTE } from './config.js';
import { addOutline } from './toon.js';
import { aabb, DeskStation, PrinterStation, RouterStation, DispenserStation, CoffeeStation } from './stations.js';

// Cenário 1: "Andar 7 — Escritório da Contabilidade".
// Coordenadas: x ∈ [-12, 12], z ∈ [-7.5, 7.5]; a câmera olha de +z.
export const BOUNDS = { minX: -12, maxX: 12, minZ: -7.5, maxZ: 7.5 };

const PEOPLE = [
  { name: 'Mariana', person: { shirt: 0xff7b9c, hair: 0x5a3320, hairStyle: 5, skin: 0xf2c29b, lashes: true, earrings: 0xffd23f } },
  { name: 'Seu Jorge', person: { shirt: 0xf4efe6, hair: 0x9aa3b5, hairStyle: 3, skin: 0xc68a5e, tie: 0xb0122b, mustache: true, glasses: true } },
  { name: 'Pri', person: { shirt: 0x7ad1c1, hair: 0x1d1410, hairStyle: 2, skin: 0x8d5a3b, lashes: true, earrings: 0xff5a8a } },
  { name: 'Rafael', person: { shirt: 0xffd23f, hair: 0x3b2a20, hairStyle: 6, skin: 0xf6d2b5, hoodie: true } },
  { name: 'Dona Cida', person: { shirt: 0xf4efe6, cardigan: 0xb07cff, hair: 0xe9eef7, hairStyle: 1, skin: 0xe8b48c, glasses: true, lashes: true } },
  { name: 'Thiago', person: { shirt: 0x5d6b8a, hair: 0x2a1c14, hairStyle: 0, skin: 0xb27650, tie: 0x3d7bff, beard: true } },
  { name: 'Bia', person: { shirt: 0xff9b54, hair: 0xb0122b, hairStyle: 4, skin: 0xf2c29b, lashes: true, glasses: true } },
  { name: 'Carlão', person: { shirt: 0x6fb1c8, hair: 0x1d1410, hairStyle: 3, skin: 0x9a6440, beard: true, bowtie: 0xffd23f } },
];
const BOSS = { name: 'Diretor Ramos', person: { shirt: 0x2a2f3d, hair: 0x6a6466, hairStyle: 0, skin: 0xf2c29b, tie: 0xffd23f, mustache: true, glasses: true } };

function place(obj, x, y, z) { obj.position.set(x, y, z); return obj; }

export function buildLevel(scene) {
  const colliders = [];
  const stations = [];
  const root = new THREE.Group();
  scene.add(root);

  const addStation = (s) => { stations.push(s); root.add(s.group); colliders.push(...s.colliders); return s; };
  const solid = (obj, box) => { root.add(obj); if (box) colliders.push(box); return obj; };

  // ---------------- piso / laje ----------------
  const slab = M.box(25.8, 1.2, 17.0, 0xe9e4da, 0, -0.6, 0, 0.1);
  slab.receiveShadow = true; root.add(slab);
  const slabTrim = M.box(26.0, 0.16, 17.2, 0x3b4566, 0, -0.08, 0, 0.04);
  root.add(slabTrim);

  const carpet = TX.carpetTexture(PALETTE.carpet, PALETTE.carpet2);
  carpet.repeat.set(18.5 / 2, 15 / 2);
  const officeFloor = new THREE.Mesh(new THREE.PlaneGeometry(18.5, 15), new THREE.MeshStandardMaterial({ map: carpet, roughness: 0.95 }));
  officeFloor.rotation.x = -Math.PI / 2; officeFloor.position.set(2.75, 0.002, 0); officeFloor.receiveShadow = true;
  root.add(officeFloor);

  const vinyl = TX.vinylTexture('#e9e4da', '#d6cfc0');
  vinyl.repeat.set(5.5, 7);
  const tiFloor = new THREE.Mesh(new THREE.PlaneGeometry(5.5, 7.5), new THREE.MeshStandardMaterial({ map: vinyl, roughness: 0.6 }));
  tiFloor.rotation.x = -Math.PI / 2; tiFloor.position.set(-9.25, 0.003, -3.75); tiFloor.receiveShadow = true;
  root.add(tiFloor);
  const vinyl2 = TX.vinylTexture('#cfe0d6', '#b9cec2');
  vinyl2.repeat.set(5.5, 7);
  const stFloor = new THREE.Mesh(new THREE.PlaneGeometry(5.5, 7.5), new THREE.MeshStandardMaterial({ map: vinyl2, roughness: 0.6 }));
  stFloor.rotation.x = -Math.PI / 2; stFloor.position.set(-9.25, 0.003, 3.75); stFloor.receiveShadow = true;
  root.add(stFloor);


  // ---------------- paredes ----------------
  const H = 3.0, T = 0.3;
  const wallMat = M.mat(PALETTE.wall);
  const trimMat = M.mat(PALETTE.wallTrim);
  const wall = (cx, cz, w, d, h = H, mat = wallMat) => {
    const m = M.box(w, h, d, mat, cx, h / 2, cz, 0.03);
    solid(m, aabb(cx, cz, w, d, h));
    const base = M.box(w + 0.02, 0.14, d + 0.02, trimMat, cx, 0.07, cz, 0.02); root.add(base);
    return m;
  };
  // parede do fundo com janelas
  const BZ = BOUNDS.minZ - T / 2;
  wall(0, BZ, 24.6, T, 0.95);
  const upper = M.box(24.6, 0.6, T, wallMat, 0, H - 0.3, BZ, 0.03); root.add(upper);
  for (let x = -12; x <= 12; x += 3) root.add(M.box(0.5, H, T + 0.06, wallMat, x, H / 2, BZ, 0.03));
  const glass = new THREE.Mesh(new THREE.PlaneGeometry(24.4, 1.45), new THREE.MeshStandardMaterial({ color: 0xaee3ff, transparent: true, opacity: 0.18, roughness: 0.3, metalness: 0.0 }));
  glass.position.set(0, 1.67, BZ); root.add(glass);
  for (let x = -10.5; x <= 10.5; x += 3) root.add(M.box(2.5, 0.06, 0.4, 0xf4efe6, x, 0.97, BZ + 0.08, 0.02));
  // laterais
  wall(BOUNDS.minX - T / 2, 0, T, 15.6);
  wall(BOUNDS.maxX + T / 2, 0, T, 15.6);
  // mureta frontal (baixa para não tapar a visão)
  wall(0, BOUNDS.maxZ + T / 2, 24.6, T, 0.45);

  // divisórias de vidro: sala de TI (em cima) e almoxarifado (embaixo)
  const glassMat = new THREE.MeshStandardMaterial({ color: 0xbfe8ff, transparent: true, opacity: 0.28, roughness: 0.3 });
  const partition = (cx, cz, w, d) => {
    const h = 1.6;
    root.add(M.box(w, 0.4, d, trimMat, cx, 0.2, cz, 0.03));
    const g = new THREE.Mesh(new THREE.BoxGeometry(w, h - 0.45, d * 0.4), glassMat); g.position.set(cx, 0.4 + (h - 0.45) / 2, cz); root.add(g);
    root.add(M.box(w + 0.02, 0.06, d + 0.02, trimMat, cx, h, cz, 0.02));
    colliders.push(aabb(cx, cz, w, d, h));
  };
  const PX = -6.5;
  partition(PX, -6.0, 0.16, 3.0);    // TI: z -7.5..-4.5
  partition(PX, -1.0, 0.16, 2.0);    // TI: z -2.0..0.0  (porta em -4.5..-2.0)
  partition(PX, 1.0, 0.16, 2.0);     // almox: z 0..2  (porta em 2..4.5)
  partition(PX, 6.0, 0.16, 3.0);     // almox: z 4.5..7.5
  partition(-9.25, 0, 5.5, 0.16);    // parede entre TI e almox

  // placas
  const sign = (text, x, y, z, bg, rotY = 0) => {
    const m = new THREE.Mesh(new THREE.PlaneGeometry(2.0, 0.5), new THREE.MeshBasicMaterial({ map: TX.labelTexture(text, bg), transparent: true }));
    m.position.set(x, y, z); m.rotation.y = rotY; root.add(m); return m;
  };
  sign('SALA DE TI', -9.25, 2.55, BZ + 0.2, '#3d7bff');
  sign('ALMOXARIFADO', -6.42, 1.95, 5.2, '#2fc46b', Math.PI / 2).scale.setScalar(0.8);
  sign('CONTABILIDADE', 3, 2.55, BZ + 0.2, '#ff7b54');

  // ---------------- sala de TI ----------------
  addStation(new DispenserStation({ x: -10.9, z: -6.95, name: 'Cabos de rede', item: 'cable', mesh: M.makeShelf('cable') }));
  addStation(new DispenserStation({ x: -8.1, z: -7.0, name: 'Bancada (antivírus)', item: 'pendrive', mesh: (() => {
    const g = M.makeWorkbench();
    // caixa de pendrives
    const tray = M.box(0.6, 0.1, 0.35, 0x3b4566, 0.5, 0.93, 0.15, 0.02); g.add(tray);
    for (let i = 0; i < 3; i++) { const p = M.makeItemMesh('pendrive'); p.scale.setScalar(0.7); p.position.set(0.32 + i * 0.18, 0.98, 0.15); g.add(p); }
    return g;
  })(), w: 2.2, d: 0.85, top: 0.88 }));
  // mesa do suporte com monitores
  const helpdesk = new THREE.Group();
  helpdesk.add(M.box(1.0, 0.08, 2.0, PALETTE.desk, 0, 0.74, 0, 0.03));
  for (const sz of [-0.9, 0.9]) helpdesk.add(M.box(0.9, 0.7, 0.07, PALETTE.metal, 0, 0.35, sz, 0.02));
  for (const sz of [-0.45, 0.45]) {
    const scr = new THREE.Mesh(new THREE.PlaneGeometry(0.7, 0.42), new THREE.MeshBasicMaterial({ map: TX.screenOk(150 + sz * 60, 2), toneMapped: false }));
    const fr = M.box(0.06, 0.48, 0.78, 0x1d2129, -0.3, 1.1, sz, 0.02);
    scr.position.set(-0.26, 1.1, sz); scr.rotation.y = Math.PI / 2;
    helpdesk.add(fr, scr);
  }
  helpdesk.add(M.cyl(0.05, 0.045, 0.11, 0xffd23f, 0.2, 0.84, 0.6));
  M.shadowify(helpdesk);
  helpdesk.position.set(-11.4, 0, -3.0);
  solid(helpdesk, aabb(-11.4, -3.0, 1.0, 2.0, 0.78));
  const chairTI = M.makeChair(0x3d7bff); chairTI.position.set(-10.5, 0, -3.0); chairTI.rotation.y = -Math.PI / 2; root.add(chairTI);
  root.add(place(M.makePlant(1.1), -11.4, 0, -1.0));
  colliders.push(aabb(-11.4, -1.0, 0.5, 0.5, 0.8));

  // ---------------- almoxarifado ----------------
  addStation(new DispenserStation({ x: -11.4, z: 3.3, rotY: Math.PI / 2, name: 'Papel A4', item: 'paper', mesh: M.makeShelf('paper') }));
  // pilhas de caixas
  const boxes = [[-8.0, 6.6, 0.9, 0.7, 0.6], [-8.9, 6.7, 0.7, 0.6, 0.5], [-8.4, 6.6, 0.6, 0.5, 0.45, 0.6]];
  for (const [x, z, w, d, h, y0 = 0] of boxes) {
    root.add(M.box(w, h, d, 0xc98f5a, x, y0 + h / 2, z, 0.03));
    root.add(M.box(w + 0.01, 0.06, 0.12, 0xe0c08a, x, y0 + h, z, 0.01));
  }
  colliders.push(aabb(-8.45, 6.65, 1.9, 0.75, 1.1));
  root.add(place(M.makeTrash(), -7.0, 0, 0.5));
  colliders.push(aabb(-7.0, 0.5, 0.4, 0.4, 0.45));
  // monitores velhos empilhados (decoração)
  for (let i = 0; i < 3; i++) root.add(M.box(0.6, 0.45, 0.5, 0xcfd6e4, -11.5, 0.225 + i * 0.46, 6.7, 0.06));
  colliders.push(aabb(-11.5, 6.7, 0.7, 0.6, 1.4));

  // ---------------- escritório aberto ----------------
  const dividerCols = [0x6fb1c8, 0xffb36b, 0x8fd18f, 0xc9a3ff];
  const deskSpots = [
    [-4.1, -4.6], [-2.3, -4.6], [1.5, -4.6], [3.3, -4.6],
    [-4.1, 0.6], [-2.3, 0.6], [1.5, 0.6], [3.3, 0.6],
  ];
  const desks = [];
  deskSpots.forEach(([x, z], i) => {
    const pp = PEOPLE[i];
    const d = addStation(new DeskStation({ x, z, name: pp.name, person: pp.person, divider: dividerCols[Math.floor(i / 2) % 4], hue: 190 + i * 23 }));
    desks.push(d);
  });
  // mesa do diretor (VIP)
  const boss = addStation(new DeskStation({ x: -0.4, z: 4.7, name: BOSS.name, person: BOSS.person, divider: 0xffd23f, hue: 40 }));
  boss.vip = true;
  boss.group.add(M.box(0.25, 0.3, 0.25, 0xffd23f, -0.7, 0.93, -0.1, 0.03)); // troféu
  root.add(place(M.makePlant(1.25), 1.0, 0, 4.4));
  colliders.push(aabb(1.0, 4.4, 0.55, 0.55, 0.8));
  desks.push(boss);
  // vizinhança para o vírus espalhar
  for (const d of desks) {
    d.neighbors = desks.filter((o) => o !== d && o.pos.distanceTo(d.pos) < 4.5).sort((a, b) => a.pos.distanceTo(d.pos) - b.pos.distanceTo(d.pos));
  }

  // impressoras
  addStation(new PrinterStation({ x: 6.6, z: -6.85, name: 'Impressora 1' }));
  addStation(new PrinterStation({ x: 11.35, z: 3.6, rotY: -Math.PI / 2, name: 'Impressora 2' }));
  // rack/roteador
  addStation(new RouterStation({ x: 11.4, z: -4.6, rotY: -Math.PI / 2, name: 'Rack de rede' }));
  // café
  addStation(new CoffeeStation({ x: -1.0, z: -6.95 }));

  // lounge (sofá + mesinha) — obstáculo e charme
  const sofa = new THREE.Group();
  sofa.add(M.box(2.2, 0.42, 0.9, 0xff7b54, 0, 0.21, 0, 0.12));
  sofa.add(M.box(2.2, 0.55, 0.25, 0xff7b54, 0, 0.6, -0.33, 0.1));
  for (const sx of [-1.0, 1.0]) sofa.add(M.box(0.25, 0.6, 0.9, 0xe0653f, sx, 0.3, 0, 0.1));
  sofa.add(M.box(0.5, 0.3, 0.15, 0xffd23f, -0.5, 0.55, -0.15, 0.06));
  M.shadowify(sofa);
  sofa.position.set(7.4, 0, 6.6);
  solid(sofa, aabb(7.4, 6.6, 2.3, 0.95, 0.7));
  const table = new THREE.Group();
  table.add(M.cyl(0.55, 0.55, 0.06, PALETTE.wood, 0, 0.45, 0, 24));
  table.add(M.cyl(0.06, 0.06, 0.42, PALETTE.metal, 0, 0.22, 0));
  table.add(M.cyl(0.3, 0.3, 0.03, PALETTE.metal, 0, 0.015, 0));
  table.add(M.box(0.3, 0.02, 0.22, 0xffffff, 0.1, 0.49, 0, 0.005));
  M.shadowify(table);
  table.position.set(7.4, 0, 4.9);
  solid(table, aabb(7.4, 4.9, 1.0, 1.0, 0.5));

  // tapete do lounge
  const rug = M.box(3.6, 0.03, 2.9, 0xe8b04a, 7.4, 0.015, 5.75, 0.05); rug.castShadow = false; root.add(rug);
  root.add(M.box(3.2, 0.032, 2.5, 0xf2c66a, 7.4, 0.017, 5.75, 0.05));

  // sala de reunião (mesa comprida com cadeiras) — obstáculo no caminho
  const meet = new THREE.Group();
  meet.add(M.box(2.6, 0.08, 1.2, PALETTE.wood, 0, 0.74, 0, 0.05));
  for (const sx of [-1.1, 1.1]) meet.add(M.box(0.1, 0.7, 0.9, PALETTE.dark, sx, 0.35, 0, 0.02));
  meet.add(M.box(0.5, 0.02, 0.35, 0xffffff, -0.5, 0.79, 0.1, 0.005));
  meet.add(M.cyl(0.05, 0.045, 0.1, 0x3d7bff, 0.6, 0.83, -0.2));
  meet.add(M.box(0.36, 0.02, 0.26, 0x2a2f3d, 0.1, 0.79, -0.25, 0.01));
  M.shadowify(meet);
  meet.position.set(-3.4, 0, 5.4);
  solid(meet, aabb(-3.4, 5.4, 2.6, 1.2, 0.78));
  for (const [cx, cz, ry] of [[-4.2, 4.5, 0], [-2.6, 4.5, 0], [-4.2, 6.3, Math.PI], [-2.6, 6.3, Math.PI]]) {
    const c = M.makeChair(0xff7b54); c.position.set(cx, 0, cz); c.rotation.y = ry + (Math.random() - 0.5) * 0.4; c.scale.setScalar(0.9); root.add(c);
  }
  colliders.push(aabb(-3.4, 4.5, 2.2, 0.5, 0.5), aabb(-3.4, 6.3, 2.2, 0.5, 0.5));

  // arquivos de aço
  for (let i = 0; i < 3; i++) {
    const f = new THREE.Group();
    f.add(M.box(0.6, 1.3, 0.6, 0x9aa3b5, 0, 0.65, 0, 0.03));
    for (let k = 0; k < 3; k++) { f.add(M.box(0.52, 0.36, 0.02, 0xb7bfcf, 0, 0.25 + k * 0.42, 0.31, 0.02)); f.add(M.box(0.18, 0.04, 0.03, 0x2a2f3d, 0, 0.36 + k * 0.42, 0.33, 0.01)); }
    M.shadowify(f); f.position.set(2.6 + i * 0.64, 0, 7.05); f.rotation.y = Math.PI; root.add(f);
  }
  colliders.push(aabb(3.24, 7.05, 1.95, 0.62, 1.3));

  // pilar estrutural com cartaz
  const pillar = M.box(0.7, 3.0, 0.7, PALETTE.wall, 8.2, 1.5, -1.4, 0.04);
  solid(pillar, aabb(8.2, -1.4, 0.7, 0.7, 3.0));
  root.add(M.box(0.72, 0.14, 0.72, PALETTE.wallTrim, 8.2, 0.07, -1.4, 0.02));
  const pp = new THREE.Mesh(new THREE.PlaneGeometry(0.55, 0.7), new THREE.MeshBasicMaterial({ map: TX.posterTexture(['ABRA', 'UM', 'CHAMADO!'], '#7fe3ff') }));
  pp.position.set(8.2, 1.6, -1.04); root.add(pp);

  // decoração extra
  const plants = [[-6.0, -7.0, 1.2], [5.0, -7.0, 1.0], [11.4, -1.6, 1.15], [11.4, 6.8, 1.3], [-6.0, 7.0, 1.0], [5.2, 6.9, 0.9]];
  for (const [x, z, s] of plants) {
    root.add(place(M.makePlant(s), x, 0, z));
    colliders.push(aabb(x, z, 0.5 * s, 0.5 * s, 0.8));
  }
  const cooler = M.makeWaterCooler(); cooler.position.set(11.45, 0, 0.2); cooler.rotation.y = -Math.PI / 2;
  solid(cooler, aabb(11.45, 0.2, 0.45, 0.45, 1.3));
  const wb = M.makeWhiteboard(); wb.position.set(2.9, 0, BZ + 0.2); root.add(wb);
  const clock = new THREE.Group();
  clock.add(M.cyl(0.32, 0.32, 0.06, 0xffffff, 0, 0, 0, 24));
  clock.add(M.cyl(0.34, 0.34, 0.04, 0x3b4566, 0, -0.02, 0, 24));
  clock.rotation.x = Math.PI / 2; clock.position.set(9.0, 2.45, BZ + 0.2);
  const hand1 = M.box(0.03, 0.22, 0.02, 0x1d2540, 0, 0.1, 0.04, 0.005);
  const hand2 = M.box(0.03, 0.15, 0.02, 0xff5a5a, 0, 0.07, 0.04, 0.005);
  const handsG = new THREE.Group(); const hp1 = new THREE.Group(); hp1.add(hand1); const hp2 = new THREE.Group(); hp2.add(hand2); handsG.add(hp1, hp2); handsG.position.set(9.0, 2.45, BZ + 0.26);
  root.add(clock, handsG);
  const posters = [[['FAVOR', 'REINICIAR', 'ANTES'], '#ffd23f', -4.5], [['SENHA:', '123456', '(NÃO!)'], '#ff9bb3', 9.0]];
  for (const [lines, col, x] of posters) {
    const p = new THREE.Mesh(new THREE.PlaneGeometry(0.7, 0.88), new THREE.MeshBasicMaterial({ map: TX.posterTexture(lines, col) }));
    p.position.set(x, 1.95, BZ + 0.18); p.rotation.z = (Math.random() - 0.5) * 0.1; root.add(p);
  }
  // lixeira da copa
  root.add(place(M.makeTrash(), 0.4, 0, -7.0));
  colliders.push(aabb(0.4, -7.0, 0.4, 0.4, 0.45));

  // suportes de extintor (placas vermelhas na parede)
  const extSpots = [[-7.1, -7.2], [9.5, -7.2], [-7.0, 7.1]];
  for (const [x, z] of extSpots) {
    if (z > 0) continue;
    const s = new THREE.Mesh(new THREE.PlaneGeometry(0.9, 0.24), new THREE.MeshBasicMaterial({ map: TX.labelTexture('EXTINTOR', '#ff3b3b', '#fff', 256, 64), transparent: true }));
    s.position.set(x, 1.45, BZ + 0.18);
    root.add(s);
  }

  // contorno nos móveis com que se interage (lê melhor e combina com os personagens)
  for (const st of stations) addOutline(st.group, 0.02);
  for (const o of [sofa, table, meet]) addOutline(o, 0.02);

  return {
    root, colliders, stations, desks,
    clockHands: [hand1, hand2, handsG],
    spawn: [new THREE.Vector3(-9.6, 0, -4.4), new THREE.Vector3(-8.4, 0, -4.0), new THREE.Vector3(-9.6, 0, -2.6), new THREE.Vector3(-8.4, 0, -2.4)],
    itemSpawns: [
      { kind: 'extinguisher', pos: new THREE.Vector3(-7.1, 0, -6.9) },
      { kind: 'extinguisher', pos: new THREE.Vector3(9.5, 0, -6.9) },
    ],
  };
}
