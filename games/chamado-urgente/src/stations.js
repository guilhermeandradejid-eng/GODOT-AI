import * as THREE from 'three';
import * as M from './models.js';
import * as TX from './textures.js';
import { PROBLEMS } from './config.js';

// Caixa AABB no plano XZ.
export function aabb(cx, cz, w, d, top = 1) {
  return { minX: cx - w / 2, maxX: cx + w / 2, minZ: cz - d / 2, maxZ: cz + d / 2, top };
}
export function closestOnBox(b, x, z, out = { x: 0, z: 0 }) {
  out.x = Math.max(b.minX, Math.min(b.maxX, x));
  out.z = Math.max(b.minZ, Math.min(b.maxZ, z));
  return out;
}

// Gira uma AABB local (w x d) conforme rotação em múltiplos de 90°.
function rotBox(cx, cz, w, d, rotY, top) {
  const q = Math.round(rotY / (Math.PI / 2)) % 2 !== 0;
  return aabb(cx, cz, q ? d : w, q ? w : d, top);
}

const SCAN_FRAMES = Array.from({ length: 11 }, (_, i) => TX.screenScan(i / 10));
const VIRUS_FRAMES = [TX.screenVirus(0), TX.screenVirus(1)];
const NONET = TX.screenNoNet();

class Station {
  constructor(kind, name) {
    this.kind = kind; this.name = name;
    this.problem = null;
    this.group = new THREE.Group();
    this.box = null;         // área de interação
    this.colliders = [];
    this.markerOffset = new THREE.Vector3(0, 2.0, 0);
    this.vip = false;
    this.shake = 0;
  }
  get pos() { return this.group.position; }
  markerPos(out) { return out.copy(this.group.position).add(this.markerOffset); }
  canHave() { return false; }
  setProblem(type, ticket) { this.problem = { type, progress: 0, ticket, def: PROBLEMS[type], t: 0 }; this.onProblem?.(type); }
  clearProblem(success) { const t = this.problem?.type; this.problem = null; this.onClear?.(t, success); }
  update() {}
}

// ---------------------------------------------------------------------------
export class DeskStation extends Station {
  constructor({ x, z, rotY = 0, name, person, divider, hue }) {
    super('desk', name);
    this.hueOk = TX.screenOk(hue, Math.floor(Math.random() * 5));
    const desk = M.makeDesk(this.hueOk, divider);
    this.desk = desk;
    this.group.add(desk.group);
    const chair = M.makeChair(0x3b4566);
    chair.position.set(0, 0, 0.78);
    chair.rotation.y = Math.PI;
    this.group.add(chair);
    this.chair = chair;
    // funcionário sentado
    const p = M.makePerson(person);
    p.root.position.set(0, 0.06, 0.8);
    p.root.rotation.y = Math.PI;
    // pose sentada: pernas para frente
    p.legL.rotation.x = -1.45; p.legR.rotation.x = -1.45;
    p.legL.position.y = p.legR.position.y = 0.48;
    p.body.position.y = 0.72;
    this.group.add(p.root);
    this.person = p;
    // pele com material próprio para "ficar vermelho de raiva"
    this.skinMat = p.head.children[0].material.clone();
    this.skinBase = this.skinMat.color.clone();
    p.head.children[0].material = this.skinMat;
    this.mood = 'work'; this.moodT = 0;

    this.loose = M.makeLooseCable();
    this.loose.position.set(0.95, 0, 0.35);
    this.loose.visible = false;
    this.group.add(this.loose);

    this.bugs = new THREE.Group();
    for (let i = 0; i < 4; i++) {
      const b = M.sphere(0.06, M.mat(0x2a2f3d), 0, 0, 0); b.scale.set(1, 0.6, 1.4);
      b.add(M.sphere(0.035, M.mat(0x6ee36e, { emissive: 0x6ee36e, emissiveIntensity: 1.5 }), 0, 0.03, 0.06));
      this.bugs.add(b);
    }
    this.bugs.visible = false;
    this.group.add(this.bugs);

    this.group.position.set(x, 0, z);
    this.group.rotation.y = rotY;
    this.box = rotBox(x, z + 0.3 * Math.cos(rotY), 1.8, 1.65, rotY, 0.78);
    this.colliders.push(rotBox(x, z, 1.8, 0.95, rotY, 0.78));
    this.colliders.push(aabb(x + Math.sin(rotY) * 0.8, z + Math.cos(rotY) * 0.8, 0.62, 0.62, 0.5));
    this.markerOffset.set(0, 2.25, 0);
    this.netDown = false;
    this.screenState = 'ok';
  }
  canHave(type) { return type === 'cable' || type === 'virus'; }
  onProblem(type) {
    this.mood = 'angry';
    if (type === 'cable') this.loose.visible = true;
    if (type === 'virus') this.bugs.visible = true;
  }
  onClear(type, success) {
    this.loose.visible = false; this.bugs.visible = false;
    this.mood = success ? 'happy' : 'sad'; this.moodT = 0;
  }
  setScreen(t) { if (this.desk.screenMat.map !== t) { this.desk.screenMat.map = t; this.desk.screenMat.needsUpdate = true; } }
  update(dt, time, fx) {
    const pr = this.problem;
    // tela
    if (pr?.type === 'virus') {
      if (pr.progress > 0.01) this.setScreen(SCAN_FRAMES[Math.min(10, Math.floor((pr.progress / pr.def.hold) * 10))]);
      else this.setScreen(VIRUS_FRAMES[Math.floor(time * 5) % 2]);
      this.desk.pcLed.material = M.mat(0xff3b3b, { emissive: 0xff3b3b, emissiveIntensity: 2.5 });
    } else if (pr?.type === 'cable' || this.netDown) {
      this.setScreen(NONET);
      this.desk.pcLed.material = M.mat(0xffb02b, { emissive: 0xffb02b, emissiveIntensity: 2.5 });
    } else {
      this.setScreen(this.hueOk);
      this.desk.pcLed.material = M.mat(0x2fc46b, { emissive: 0x2fc46b, emissiveIntensity: 2 });
    }
    // efeitos do problema
    if (pr?.type === 'cable' && Math.random() < dt * 3) {
      const p = this.loose.getWorldPosition(new THREE.Vector3()); p.y += 0.1;
      fx.sparks(p, 5);
    }
    if (pr?.type === 'virus') {
      const mp = this.desk.monitor.getWorldPosition(new THREE.Vector3());
      this.bugs.children.forEach((b, i) => {
        const a = time * (1.6 + i * 0.3) + i * 1.7;
        b.position.set(Math.cos(a) * (0.5 + i * 0.07), 0.8, -0.05 + Math.sin(a) * 0.3);
        b.rotation.y = -a + Math.PI;
      });
      if (pr.progress > 0.01 && Math.random() < dt * 20) { mp.y += 0.5; fx.bits(mp); }
    }
    // humor do funcionário
    this.moodT += dt;
    const P = this.person;
    const urgency = pr ? 1 - pr.ticket.remaining / pr.ticket.sla : 0;
    const want = this.skinBase.clone().lerp(new THREE.Color(0xff6a5a), pr ? Math.min(1, urgency * 1.1) : 0);
    this.skinMat.color.lerp(want, Math.min(1, dt * 4));
    if (pr) {
      const f = 9 + urgency * 8;
      P.armL.rotation.x = -2.6 + Math.sin(time * f) * 0.5;
      P.armR.rotation.x = -2.6 + Math.sin(time * f + Math.PI) * 0.5;
      P.armL.rotation.z = -0.3; P.armR.rotation.z = 0.3;
      P.head.rotation.y = Math.sin(time * 6) * 0.35;
      P.rig.position.y = Math.abs(Math.sin(time * f * 0.5)) * 0.08 * (0.5 + urgency);
      P.root.rotation.y = Math.PI + Math.sin(time * 2) * 0.4;
      P.mouth.scale.set(1.2, 3, 1);
    } else if (this.mood === 'happy' && this.moodT < 1.8) {
      P.armL.rotation.x = P.armR.rotation.x = -2.9;
      P.armL.rotation.z = -0.5; P.armR.rotation.z = 0.5;
      P.rig.position.y = Math.abs(Math.sin(this.moodT * 9)) * 0.35;
      P.root.rotation.y = Math.PI + this.moodT * 7;
      P.head.rotation.y = 0;
      P.mouth.scale.set(1.6, 2, 1);
      if (Math.random() < dt * 6) fx.hearts(P.head.getWorldPosition(new THREE.Vector3()).add(new THREE.Vector3(0, 0.3, 0)));
    } else if (this.mood === 'sad' && this.moodT < 3) {
      P.armL.rotation.x = P.armR.rotation.x = -0.2;
      P.armL.rotation.z = P.armR.rotation.z = 0;
      P.head.rotation.x = 0.4;
      P.rig.position.y = 0;
      P.root.rotation.y = Math.PI;
      P.mouth.scale.set(1, 1, 1);
    } else {
      // digitando
      this.mood = 'work';
      P.head.rotation.x = 0.1 + Math.sin(time * 0.7 + this.pos.x) * 0.05;
      P.head.rotation.y = Math.sin(time * 0.4 + this.pos.z) * 0.15;
      P.armL.rotation.x = -1.25 + Math.sin(time * 14 + this.pos.x) * 0.08;
      P.armR.rotation.x = -1.25 + Math.sin(time * 13 + 1 + this.pos.x) * 0.08;
      P.armL.rotation.z = 0.15; P.armR.rotation.z = -0.15;
      P.rig.position.y = 0;
      P.root.rotation.y += (Math.PI - P.root.rotation.y) * Math.min(1, dt * 5);
      P.mouth.scale.set(1, 1, 1);
    }
  }
}

// ---------------------------------------------------------------------------
export class PrinterStation extends Station {
  constructor({ x, z, rotY = 0, name }) {
    super('printer', name);
    this.p = M.makePrinter();
    this.group.add(this.p.group);
    this.group.position.set(x, 0, z);
    this.group.rotation.y = rotY;
    this.box = rotBox(x, z, 1.05, 0.85, rotY, 0.82);
    this.colliders.push(this.box);
    this.light = new THREE.PointLight(0xff7a2b, 0, 6, 1.6);
    this.light.position.set(0, 1.3, 0.2);
    this.group.add(this.light);
    this.markerOffset.set(0, 2.9, 0);
    this.sootLevel = 0;
  }
  canHave(type) { return type === 'paper' || type === 'jam' || type === 'fire'; }
  onProblem(type) {
    this.p.crumple.visible = type === 'jam';
    this.p.outPaper.visible = type !== 'paper';
  }
  onClear(type) {
    this.p.crumple.visible = false; this.p.outPaper.visible = true;
    this.light.intensity = 0;
    if (type === 'fire') this.sootLevel = 1;
  }
  update(dt, time, fx) {
    const pr = this.problem;
    const led = this.p.ledMat;
    const blink = Math.floor(time * 4) % 2 === 0;
    if (!pr) { led.color.set(0x2fc46b); led.emissive.set(0x2fc46b); }
    else if (pr.type === 'fire') { led.color.set(0xff3b3b); led.emissive.set(blink ? 0xff3b3b : 0x000000); }
    else { led.color.set(0xffb02b); led.emissive.set(blink ? 0xffb02b : 0x000000); }

    this.sootLevel = Math.max(0, this.sootLevel - dt * 0.03);
    this.p.soot.material.opacity = pr?.type === 'fire' ? Math.min(0.75, 0.2 + pr.t * 0.04) : this.sootLevel * 0.7;
    this.p.soot.visible = this.p.soot.material.opacity > 0.01;

    // tremida (emperrada) / pulsar
    let sh = 0;
    if (pr?.type === 'jam') sh = 0.025;
    if (pr && pr.progress > 0 && pr.type === 'jam') sh = 0.05;
    this.p.body.position.x = Math.sin(time * 60) * sh;
    this.p.body.rotation.z = Math.sin(time * 37) * sh * 0.6;

    const top = this.group.localToWorld(new THREE.Vector3(0, 0.9, 0.1));
    if (pr?.type === 'jam' && Math.random() < dt * 3) fx.smoke(top, false);
    if (pr?.type === 'fire') {
      const k = Math.min(2.0, 1.15 + pr.t * 0.03) * (1 - (pr.progress / pr.def.hold) * 0.7);
      fx.fire(top, k);
      if (Math.random() < dt * 10) fx.sparks(top, 2);
      this.light.intensity = (5 + Math.sin(time * 30) * 1.5 + Math.random() * 1.5) * k;
    } else if (this.sootLevel > 0.3 && Math.random() < dt * 2) {
      fx.smoke(top, true);
    }
    if (pr?.type === 'paper') {
      // gaveta piscando aberta
      this.p.tray.position.z = 0.41 + (blink ? 0.06 : 0);
    } else this.p.tray.position.z = 0.41;
  }
}

// ---------------------------------------------------------------------------
export class RouterStation extends Station {
  constructor({ x, z, rotY = 0, name }) {
    super('router', name);
    this.r = M.makeRack();
    this.group.add(this.r.group);
    this.group.position.set(x, 0, z);
    this.group.rotation.y = rotY;
    this.box = rotBox(x, z, 0.95, 0.85, rotY, 2.0);
    this.colliders.push(this.box);
    this.markerOffset.set(0, 3.0, 0);
    this.ledPhase = this.r.leds.map(() => Math.random() * 10);
  }
  canHave(type) { return type === 'router'; }
  update(dt, time, fx) {
    const pr = this.problem;
    const blink = Math.floor(time * 3) % 2 === 0;
    this.r.leds.forEach((l, i) => {
      if (pr) {
        const on = pr.progress > 0 ? Math.random() < 0.5 : blink;
        l.material.color.set(0xff3b3b); l.material.emissive.set(on ? 0xff3b3b : 0x220000);
      } else {
        const on = Math.sin(time * (3 + (i % 5)) + this.ledPhase[i]) > -0.3;
        l.material.color.set(0x2fc46b); l.material.emissive.set(on ? 0x2fc46b : 0x0a2a14);
      }
    });
    this.r.routerLed.emissive.set(pr ? (blink ? 0xff3b3b : 0x000000) : 0x3fa9ff);
    if (pr && Math.random() < dt * 2) fx.sparks(this.group.localToWorld(new THREE.Vector3(0, 2.15, 0)), 3);
  }
}

// ---------------------------------------------------------------------------
export class DispenserStation extends Station {
  constructor({ x, z, rotY = 0, name, item, mesh, w = 1.5, d = 0.6, top = 1.6 }) {
    super('dispenser', name);
    this.item = item;
    this.group.add(mesh);
    this.group.position.set(x, 0, z);
    this.group.rotation.y = rotY;
    this.box = rotBox(x, z, w, d, rotY, top);
    this.colliders.push(this.box);
    this.markerOffset.set(0, top + 0.6, 0);
  }
}

export class CoffeeStation extends Station {
  constructor({ x, z, rotY = 0 }) {
    super('coffee', 'Café');
    this.group.add(M.makeCoffeeMachine());
    this.group.position.set(x, 0, z);
    this.group.rotation.y = rotY;
    this.box = rotBox(x, z, 1.45, 0.75, rotY, 0.95);
    this.colliders.push(this.box);
    this.cool = 0;
  }
  update(dt, time, fx) {
    this.cool = Math.max(0, this.cool - dt);
    if (Math.random() < dt * 1.2) fx.smoke(this.group.localToWorld(new THREE.Vector3(-0.2, 1.65, 0)), false);
  }
}
