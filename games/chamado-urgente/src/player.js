import * as THREE from 'three';
import { makePerson, setFace, animateFace } from './characters.js';
import { LINES, pick } from './lines.js';
import { pushOutCircle } from './physics.js';
import { PLAYER, PLAYER_COLORS, ITEMS } from './config.js';
import { Item } from './items.js';

const VERB = {
  cable: 'Trocar cabo', virus: 'Rodar antivírus', paper: 'Repor papel', jam: 'Desemperrar', fire: 'Apagar fogo', router: 'Reiniciar roteador',
};
// Os técnicos: cada um com visual e personalidade
export const TECHS = [
  { name: 'Léo', look: { hair: 0x3b2a20, hairStyle: 0, skin: 0xf2c29b, glasses: true, headset: true } },
  { name: 'Duda', look: { hair: 0x1d1410, hairStyle: 5, skin: 0x9a6440, hat: 'beanie', hatColor: 0x2fc4b0, lashes: true, earrings: 0xffd23f, hoodie: true } },
  { name: 'Kenji', look: { hair: 0x1d1410, hairStyle: 6, skin: 0xf6d2b5, hat: 'cap', hatColor: 0xffd23f, headset: true } },
  { name: 'Bruna', look: { hair: 0xb0122b, hairStyle: 4, skin: 0xc68a5e, lashes: true, glasses: true, headset: true } },
];

const _v = new THREE.Vector3();

export class Player {
  constructor(index, device, scene, spawn) {
    this.index = index;
    this.device = device;
    this.color = PLAYER_COLORS[index];
    this.tech = TECHS[index];
    this.p = makePerson({ shirt: this.color.shirt, pants: 0x2a2f3d, shoes: 0xffffff, ...this.tech.look });
    this.celebrateT = 0; this.stepT = 0; this.quipT = 0; this.idleLook = 0;
    this.root = this.p.root;
    this.root.scale.setScalar(1.18);
    scene.add(this.root);
    // anel colorido no chão (identifica o jogador)
    const ring = new THREE.Mesh(new THREE.RingGeometry(0.42, 0.52, 32), new THREE.MeshBasicMaterial({ color: this.color.shirt, transparent: true, opacity: 0.85, toneMapped: false }));
    ring.rotation.x = -Math.PI / 2; ring.position.y = 0.015;
    this.root.add(ring);
    this.ring = ring;
    // ponto onde o item carregado fica
    this.hold = new THREE.Group();
    this.hold.position.set(0, 0.72, 0.42);
    this.root.add(this.hold);

    this.pos = this.root.position;
    this.pos.copy(spawn);
    this.vel = new THREE.Vector3();
    this.angle = Math.PI;
    this.held = null;
    this.dashT = 0; this.dashCool = 0;
    this.coffeeT = 0;
    this.walkPhase = 0;
    this.fixing = null; this.spraying = false;
    this.squash = 0;
    this.hint = '';
    this.denyT = 0;
    this.stun = 0;
  }

  get forward() { return _v.set(Math.sin(this.angle), 0, Math.cos(this.angle)); }

  grab(item, game) {
    if (this.held) return;
    item.attachTo(this);
    this.held = item;
    this.squash = 0.6;
    game.sfx.pickup();
  }
  drop(game, vel = null) {
    const it = this.held; if (!it) return;
    it.release(vel);
    if (!vel) {
      const f = this.forward;
      it.pos.set(this.pos.x + f.x * 0.55, Math.max(it.pos.y, 0.85), this.pos.z + f.z * 0.55);
      game.sfx.drop();
    }
    this.held = null;
  }

  // escolhe o que está à frente do jogador
  findTargets(game) {
    const f = this.forward.clone();
    let item = null, itemScore = 1e9;
    if (!this.held) {
      for (const it of game.items) {
        if (it.heldBy || !it.alive) continue;
        const dx = it.pos.x - this.pos.x, dz = it.pos.z - this.pos.z;
        const d = Math.hypot(dx, dz);
        if (d > PLAYER.reach + 0.15 || it.pos.y > 1.3) continue;
        const dot = d > 0.01 ? (dx * f.x + dz * f.z) / d : 1;
        if (dot < -0.1 && d > 0.45) continue;
        const sc = d - dot * 0.5;
        if (sc < itemScore) { itemScore = sc; item = it; }
      }
    }
    let station = null, stScore = 1e9;
    const sprayReach = this.held?.kind === 'extinguisher' ? 2.3 : PLAYER.reach;
    for (const s of game.stations) {
      if (!s.box) continue;
      const cx = Math.max(s.box.minX, Math.min(s.box.maxX, this.pos.x));
      const cz = Math.max(s.box.minZ, Math.min(s.box.maxZ, this.pos.z));
      const dx = cx - this.pos.x, dz = cz - this.pos.z;
      const d = Math.hypot(dx, dz);
      const reach = s.problem?.type === 'fire' ? sprayReach : PLAYER.reach;
      if (d > reach) continue;
      // direção para o centro da estação
      const ccx = s.pos.x - this.pos.x, ccz = s.pos.z - this.pos.z, cl = Math.hypot(ccx, ccz) || 1;
      const dot = (ccx * f.x + ccz * f.z) / cl;
      if (dot < (s.problem?.type === 'fire' && d > PLAYER.reach ? 0.55 : -0.05)) continue;
      let sc = d - dot * 0.6;
      if (s.problem) sc -= 0.5; // problemas têm prioridade
      if (sc < stScore) { stScore = sc; station = s; }
    }
    return { item, station };
  }

  update(dt, inp, game) {
    const playing = game.state === 'playing';
    if (!playing) inp = { x: 0, z: 0, grab: false, use: false, usePressed: false, dash: false };
    this.dashCool = Math.max(0, this.dashCool - dt);
    this.coffeeT = Math.max(0, this.coffeeT - dt);
    this.denyT = Math.max(0, this.denyT - dt);
    this.stun = Math.max(0, this.stun - dt);
    this.quipT = Math.max(0, this.quipT - dt);
    this.celebrateT = Math.max(0, this.celebrateT - dt);

    // --- movimento
    let speed = PLAYER.speed * (this.held ? PLAYER.carrySlow : 1) * (this.coffeeT > 0 ? PLAYER.coffeeBoost : 1);
    if (this.fixing || this.spraying) speed *= 0.15;
    const want = new THREE.Vector3(inp.x, 0, inp.z).multiplyScalar(speed);
    if (this.stun > 0) want.multiplyScalar(0.2);
    if (inp.dash && this.dashCool <= 0 && this.stun <= 0) {
      this.dashT = PLAYER.dashTime; this.dashCool = PLAYER.dashCooldown;
      game.sfx.dash(); game.fx.puff(this.pos.clone().setY(0.1), 7);
      this.squash = -0.5;
    }
    if (this.dashT > 0) {
      this.dashT -= dt;
      const f = this.forward;
      this.vel.set(f.x * PLAYER.dashSpeed, 0, f.z * PLAYER.dashSpeed);
      if (Math.random() < 0.6) game.fx.puff(this.pos.clone().setY(0.1), 1);
    } else {
      const k = Math.min(1, PLAYER.accel * dt / Math.max(1, speed));
      this.vel.x += (want.x - this.vel.x) * Math.min(1, k * 2.2);
      this.vel.z += (want.z - this.vel.z) * Math.min(1, k * 2.2);
    }
    this.pos.x += this.vel.x * dt; this.pos.z += this.vel.z * dt;
    pushOutCircle(this.pos, PLAYER.radius, game.colliders);

    if (inp.x || inp.z) {
      const target = Math.atan2(inp.x, inp.z);
      let da = target - this.angle;
      while (da > Math.PI) da -= Math.PI * 2; while (da < -Math.PI) da += Math.PI * 2;
      this.angle += da * Math.min(1, dt * 16);
    }
    this.root.rotation.y = this.angle;

    // --- interação
    const { item, station } = this.findTargets(game);
    if (item) item.highlight = 1;
    this.target = station;
    this.hint = '';
    this.fixing = null; this.spraying = false;
    const pr = station?.problem;

    if (inp.grab) {
      if (!this.held) {
        if (item) this.grab(item, game);
        else if (station?.kind === 'dispenser') {
          const it = new Item(station.item, game.scene, this.pos.clone());
          game.items.push(it);
          this.grab(it, game);
          game.fx.puff(station.pos.clone().setY(1.0), 5, 0xffffff);
        } else if (station?.kind === 'coffee') {
          this.drinkCoffee(game);
        }
      } else {
        if (station?.kind === 'dispenser' && station.item === this.held.kind) {
          const it = this.held; this.held = null; it.destroy(); game.sfx.drop();
        } else this.drop(game);
      }
    }

    if (inp.use && this.held?.kind === 'extinguisher' && this.dashT <= 0) {
      this.spraying = true;
      const f = this.forward;
      const nozzle = this.pos.clone().add(new THREE.Vector3(f.x * 0.65, 0.85, f.z * 0.65));
      game.fx.foam(nozzle, f);
      if (Math.random() < dt * 12) game.sfx.spray();
      if (pr?.type === 'fire') { game.addProgress(station, this, dt); this.fixing = station; this.quip(game, LINES.techFire); }
    } else if (inp.use && pr && this.dashT <= 0) {
      const need = pr.def.item;
      if (!need || this.held?.kind === need) {
        this.fixing = station;
        this.quip(game, LINES.tech);
        game.addProgress(station, this, dt);
      } else if (inp.usePressed) {
        this.denyT = 1.2; game.sfx.deny();
      }
    } else if (inp.usePressed && station?.kind === 'coffee' && !this.held) {
      this.drinkCoffee(game);
    } else if (inp.usePressed && this.held && this.held.kind !== 'extinguisher') {
      // arremessar
      const f = this.forward;
      const v = new THREE.Vector3(f.x * PLAYER.throwSpeed, 4.2, f.z * PLAYER.throwSpeed);
      v.x += this.vel.x * 0.4; v.z += this.vel.z * 0.4;
      this.drop(game, v);
      game.sfx.throw();
      this.squash = -0.4;
    }

    // dica contextual
    const d = this.device;
    const kGrab = d.kind === 'gamepad' || d.kind === 'touch' ? 'A' : d.id === 'kbA' ? 'E' : 'Enter';
    const kUse = d.kind === 'gamepad' ? 'X' : d.kind === 'touch' ? 'B' : d.id === 'kbA' ? 'F' : 'Shift';
    if (this.denyT > 0 && pr?.def.item) this.hint = `Precisa: ${ITEMS[pr.def.item].label}`;
    else if (pr) {
      const need = pr.def.item;
      if (!need || this.held?.kind === need) this.hint = `${kUse} ${VERB[pr.type]}`;
      else this.hint = `Precisa: ${ITEMS[need].label}`;
    } else if (!this.held && item) this.hint = `${kGrab} Pegar ${item.def.label.toLowerCase()}`;
    else if (!this.held && station?.kind === 'dispenser') this.hint = `${kGrab} Pegar ${ITEMS[station.item].label.toLowerCase()}`;
    else if (!this.held && station?.kind === 'coffee') this.hint = this.coffeeT > 0 ? 'Cafeinado!' : `${kGrab} Tomar café`;
    else if (this.held && station?.kind === 'dispenser' && station.item === this.held.kind) this.hint = `${kGrab} Devolver`;
    else if (this.held?.kind === 'extinguisher') this.hint = this.spraying ? '' : `${kUse} Borrifar`;
    if (!playing) this.hint = '';

    this.animate(dt, game);
  }

  quip(game, list) {
    if (this.quipT > 0 || Math.random() > 0.35) { this.quipT = Math.max(this.quipT, 2); return; }
    this.quipT = 9 + Math.random() * 6;
    game.ui.say((o) => o.copy(this.pos).setY(2.6), pick(list), 'tech');
  }
  celebrate(game) {
    this.celebrateT = 0.9; this.squash = 0.7;
    if (Math.random() < 0.4) game.ui.say((o) => o.copy(this.pos).setY(2.6), pick(LINES.techDone), 'tech');
  }

  drinkCoffee(game) {
    if (this.coffeeT > PLAYER.coffeeTime - 1) return;
    this.coffeeT = PLAYER.coffeeTime;
    game.sfx.coffee();
    game.ui.floatText(this.pos.clone().setY(2.2), 'Café! +velocidade', '#ffb02b');
    game.fx.hearts(this.pos.clone().setY(1.6));
  }

  animate(dt, game) {
    const P = this.p;
    const sp = Math.hypot(this.vel.x, this.vel.z);
    this.walkPhase += dt * (4 + sp * 2.6);
    const w = Math.min(1, sp / 3);
    const t = game.time;
    P.legL.rotation.x = Math.sin(this.walkPhase) * 0.9 * w;
    P.legR.rotation.x = -Math.sin(this.walkPhase) * 0.9 * w;
    P.rig.position.y = Math.abs(Math.sin(this.walkPhase)) * 0.11 * w;
    P.rig.rotation.set(0, 0, Math.sin(this.walkPhase) * 0.07 * w);
    P.body.rotation.set(0.14 * w + (this.dashT > 0 ? 0.45 : 0), 0, 0);
    P.head.rotation.set(0, 0, 0);
    // passos levantam poeirinha
    if (w > 0.5) { this.stepT -= dt * (4 + sp * 2.6); if (this.stepT <= 0) { this.stepT = Math.PI; game.fx.puff(this.pos.clone().setY(0.05), 2, 0xe9e4da); } }

    const urgent = game.tickets?.open.some((tk) => tk.remaining / tk.sla < 0.25);
    let face = urgent ? 'panic' : 'neutral';
    if (this.fixing || this.spraying) {
      const fast = this.spraying ? Math.sin(t * 40) * 0.05 : Math.sin(t * 22);
      P.armL.rotation.set(-1.5 + fast * 0.45, 0, 0);
      P.armR.rotation.set(-1.5 - fast * 0.45, 0, 0);
      P.body.rotation.x = this.spraying ? -0.12 : 0.22;
      P.rig.position.y = Math.abs(Math.sin(t * 22)) * 0.04;
      face = 'focused';
    } else if (this.held) {
      P.armL.rotation.set(-1.4, 0, 0.25); P.armR.rotation.set(-1.4, 0, -0.25);
    } else {
      P.armL.rotation.set(-Math.sin(this.walkPhase) * 1.0 * w, 0, -0.1 - Math.sin(t * 2) * 0.03);
      P.armR.rotation.set(Math.sin(this.walkPhase) * 1.0 * w, 0, 0.1 + Math.sin(t * 2) * 0.03);
      // parado: olha em volta
      if (w < 0.1) { this.idleLook += dt; P.head.rotation.y = Math.sin(this.idleLook * 0.9) * 0.35 * Math.min(1, this.idleLook); }
      else this.idleLook = 0;
    }
    if (this.celebrateT > 0) {
      const k = 1 - this.celebrateT / 0.9;
      P.rig.position.y = Math.sin(k * Math.PI) * 0.6;
      P.rig.rotation.y = k * Math.PI * 2;
      P.armR.rotation.set(-3.0, 0, 0.3);
      if (!this.held) P.armL.rotation.set(-3.0, 0, -0.3);
      face = 'happy';
    }
    if (this.stun > 0) { face = 'dizzy'; P.rig.rotation.z = Math.sin(t * 20) * 0.2; }
    if (this.denyT > 0.8) face = 'sad';
    if (this.coffeeT > 0 && face === 'neutral') face = 'proud';
    setFace(P, face);
    animateFace(P, dt, t, { dizzy: this.stun > 0 || this.dizzyT > 0, sweat: urgent && !this.celebrateT, lookX: this.vel.x * 0.004, lookY: -this.vel.z * 0.003 });
    this.dizzyT = Math.max(0, (this.dizzyT || 0) - dt);

    // squash & stretch
    this.squash += (0 - this.squash) * Math.min(1, dt * 10);
    const breath = 1 + Math.sin(t * 3 + this.index) * 0.015;
    const s = 1 + this.squash * 0.25;
    P.rig.scale.set(1 / Math.sqrt(Math.abs(s)), s * breath, 1 / Math.sqrt(Math.abs(s)));
    if (this.held) this.held.group.position.y = Math.abs(Math.sin(this.walkPhase)) * 0.05 * w;
    this.ring.material.opacity = 0.6 + Math.sin(t * 4) * 0.2;
    if (this.coffeeT > 0 && Math.random() < dt * 8) game.fx.emit({ pos: this.pos.clone().setY(0.2), vel: [0, 0.4, 0], spread: 0.3, life: 0.5, size: 0.05, color: 0xffb02b, glow: true, intensity: 1.2 });
    // rastro do dash
    if (this.dashT > 0) game.fx.emit({ pos: this.pos.clone().setY(0.7), vel: [0, 0.2, 0], spread: 0.2, life: 0.3, size: 0.18, size1: 0, color: this.color.shirt, glow: true, intensity: 0.9 });
  }
}
