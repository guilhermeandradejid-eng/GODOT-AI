import * as THREE from 'three';
import { buildHumanoid, buildSlime, buildMushroom, buildBeetle, buildStumpBoss, Animator, poseHumanoid, snap8 } from './characters.js';
import { toonMat, unlitMat } from './materials.js';
import { sfx } from './audio.js';
import { S } from './world.js';

// =============================================================================
// Entidades: herói, inimigos (gosma, fungão, besouro-chifre), chefe (Toco Ancião),
// NPCs, coletáveis, baús e projéteis.
// =============================================================================

const V3 = THREE.Vector3;
const angDiff = (a, b) => { let d = a - b; while (d > Math.PI) d -= Math.PI * 2; while (d < -Math.PI) d += Math.PI * 2; return d; };
export const screenToWorld = (sx, sy) => ({ x: (sx + sy) * S, z: (sy - sx) * S });

// ---------------------------------------------------------------- base
class Actor {
  constructor(game, rig) {
    this.game = game;
    this.rig = rig;
    this.obj = rig.root;
    this.anim = new Animator(rig);
    this.pos = new V3();
    this.kb = new V3();
    this.facing = Math.PI / 4;
    this.drawFacing = this.facing;
    this.radius = 0.35;
    this.flash = 0;
    this.y = 0;
    this.shadow = blobShadow(this.radius * 1.4);
    game.scene.add(this.obj);
    game.scene.add(this.shadow);
  }
  place(x, z) { this.pos.set(x, 0, z); this.y = this.game.world.heightAt(x, z); this.pos.y = this.y; this.sync(); }
  sync(extraY = 0) {
    const gy = this.game.world.heightAt(this.pos.x, this.pos.z);
    this.y += (gy - this.y) * 0.5;
    this.pos.y = this.y;
    this.obj.position.set(this.pos.x, this.y + extraY, this.pos.z);
    this.drawFacing = snap8(this.facing);
    this.obj.rotation.y = this.drawFacing;
    this.shadow.position.set(this.pos.x, gy + 0.03, this.pos.z);
    this.rig.flash.value = this.flash > 0 ? 1 : 0;
  }
  remove() { this.game.scene.remove(this.obj); this.game.scene.remove(this.shadow); }
  distTo(p) { return Math.hypot(p.x - this.pos.x, p.z - this.pos.z); }
  angleTo(p) { return Math.atan2(p.x - this.pos.x, p.z - this.pos.z); }
}

const shadowMat = unlitMat(0x000000, { transparent: true, opacity: 0.0 });
function blobShadow(r) {
  // sombra "de sprite": elipse escura discreta sob o personagem (além da sombra real)
  const g = new THREE.CircleGeometry(r, 10); g.rotateX(-Math.PI / 2);
  const m = new THREE.Mesh(g, new THREE.MeshBasicMaterial({ color: 0x1b1a2a, transparent: true, opacity: 0.28, depthWrite: false }));
  m.layers.set(1);
  m.renderOrder = 1;
  return m;
}

// ---------------------------------------------------------------- herói
export const HERO_LOOK = { skin: '#f3c9a1', hair: '#8a4a30', hairStyle: 'spiky', tunic: '#3f86b8', tunic2: '#2c628c', pants: '#4b3d5e', boots: '#6b4433', scarf: '#e0533d', weapon: 'sword', pack: true, belt: '#6b4433', sleeve: '#3f86b8' };

export class Player extends Actor {
  constructor(game) {
    super(game, buildHumanoid(HERO_LOOK));
    this.radius = 0.32;
    this.state = 'free';
    this.st = 0;
    this.combo = 0;
    this.comboTimer = 0;
    this.queued = false;
    this.charge = 0;
    this.invuln = 0;
    this.rollCd = 0;
    this.hitSet = new Set();
    this.stepT = 0;
    this.stats = { level: 1, exp: 0, hp: 100, maxHp: 100, ep: 50, maxEp: 50, atk: 10, gold: 0, potions: 2 };
  }

  get alive() { return this.state !== 'dead'; }
  expNeeded() { return Math.round(25 * Math.pow(this.stats.level, 1.45)); }

  gainExp(n) {
    const s = this.stats;
    s.exp += n;
    let up = false;
    while (s.exp >= this.expNeeded()) {
      s.exp -= this.expNeeded(); s.level++;
      s.maxHp += 18; s.maxEp += 6; s.atk += 3;
      s.hp = s.maxHp; s.ep = s.maxEp;
      up = true;
    }
    if (up) this.game.onLevelUp();
  }

  update(dt, input) {
    const g = this.game, s = this.stats;
    this.st += dt;
    this.invuln = Math.max(0, this.invuln - dt);
    this.rollCd = Math.max(0, this.rollCd - dt);
    this.flash = Math.max(0, this.flash - dt);
    this.comboTimer = Math.max(0, this.comboTimer - dt);
    if (this.comboTimer <= 0 && this.state === 'free') this.combo = 0;
    s.ep = Math.min(s.maxEp, s.ep + dt * 2.4);

    const mv = input ? input.move() : { x: 0, y: 0 };
    const wmv = screenToWorld(mv.x, mv.y);
    const mlen = Math.hypot(mv.x, mv.y);
    const locked = !input;
    let speed = 0;

    // knockback
    if (this.kb.lengthSq() > 0.001) {
      g.world.move(this.pos, this.kb.x * dt, this.kb.z * dt, this.radius);
      this.kb.multiplyScalar(Math.exp(-10 * dt));
    }

    switch (this.state) {
      case 'free': {
        if (mlen > 0.1) {
          this.facing = Math.atan2(wmv.x, wmv.z);
          speed = 4.6 * mlen;
          g.world.move(this.pos, wmv.x * speed * dt, wmv.z * speed * dt, this.radius);
          this.anim.set('walk');
          this.stepT += dt * mlen;
          if (this.stepT > 0.3) { this.stepT = 0; g.fx.dust(this.pos, 1, g.surfaceDust(this.pos)); sfx.step(); }
        } else this.anim.set('idle');
        if (locked) break;
        if (input.consume('attack')) { if (!g.tryInteract()) this.startAttack(); }
        else if (input.consume('interact')) g.tryInteract();
        else if (input.consume('roll')) this.startRoll(wmv, mlen);
        else if (input.consume('skill')) this.startCast();
        else if (input.consume('potion')) g.usePotion();
        break;
      }
      case 'attack': {
        const dur = this.combo === 3 ? 0.42 : 0.3;
        const k = this.st / dur;
        // avanço
        if (this.st < 0.12) {
          const t = g.nearestEnemy(this.pos, 3);
          const close = t && this.distTo(t.pos) < t.radius + this.radius + 0.45;
          if (!close) g.world.move(this.pos, Math.sin(this.facing) * 3.2 * dt, Math.cos(this.facing) * 3.2 * dt, this.radius);
        }
        if (this.st > 0.06 && this.st < 0.16) this.doHit(this.combo === 3 ? 1.75 : 1.45, this.combo === 3 ? 2.2 : 2.3, [1, 1.1, 1.7][this.combo - 1], this.combo === 3 ? 7 : 4);
        if (input && input.wasPressed('attack') && this.st > 0.08) { input.consume('attack'); this.queued = true; }
        if (input && input.consume('roll')) { this.startRoll(wmv, mlen); break; }
        if (k >= 1) {
          if (this.queued && this.combo < 3) { this.startAttack(); }
          else if (input && input.isHeld('attack') && this.combo === 1 && this.heldSince > 0.25) { this.state = 'charge'; this.st = 0; this.charge = 0; this.anim.set('charge'); sfx.charge(); }
          else { this.state = 'free'; this.comboTimer = 0.45; }
        }
        if (input && input.isHeld('attack')) this.heldSince += dt; else this.heldSince = 0;
        break;
      }
      case 'charge': {
        const prev = this.charge;
        this.charge = Math.min(1, this.charge + dt / 0.65);
        if (mlen > 0.1) { this.facing = Math.atan2(wmv.x, wmv.z); g.world.move(this.pos, wmv.x * 1.6 * dt, wmv.z * 1.6 * dt, this.radius); }
        if (prev < 1 && this.charge >= 1) { sfx.charged(); g.fx.burst(this.swordTip(), 12, { speed: 2, up: 1, g: 0, life: 0.4, color: [0xfff2a8, 0xffffff], size: 0.07 }); }
        if (Math.random() < (this.charge >= 1 ? 0.8 : 0.3)) g.fx.particle(this.swordTip(), { vy: 1.2, life: 0.3, color: this.charge >= 1 ? 0xfff2a8 : 0xbfe6ff, size: 0.06 });
        this.flash = this.charge >= 1 && Math.floor(this.st * 12) % 4 === 0 ? 0.02 : 0;
        if (!input || !input.isHeld('attack')) {
          if (this.charge >= 1) this.startSpin(); else { this.state = 'free'; }
        }
        break;
      }
      case 'spin': {
        const dur = 0.5, k = this.st / dur;
        if (this.st < 0.02) { sfx.spin(); }
        if (mlen > 0.1) g.world.move(this.pos, wmv.x * 2.4 * dt, wmv.z * 2.4 * dt, this.radius);
        if (this.st > 0.05 && this.st < 0.42) this.doHit(2.0, Math.PI * 2, 1.5, 8, true);
        if (Math.floor(this.st * 30) % 3 === 0) {
          const a = -this.st * 14;
          g.fx.particle({ x: this.pos.x + Math.sin(a) * 1.6, y: this.pos.y + 0.5, z: this.pos.z + Math.cos(a) * 1.6 }, { vy: 0.6, life: 0.25, color: 0xfff2a8, size: 0.09 });
        }
        if (k >= 1) { this.state = 'free'; this.comboTimer = 0; }
        this.anim.k = k;
        break;
      }
      case 'roll': {
        const k = this.st / 0.36;
        const sp = 9.5 * (1 - k * 0.6);
        g.world.move(this.pos, this.rollDir.x * sp * dt, this.rollDir.z * sp * dt, this.radius);
        if (Math.random() < 0.5) g.fx.dust(this.pos, 1, g.surfaceDust(this.pos));
        if (k >= 1) { this.state = 'free'; this.rollCd = 0.12; }
        break;
      }
      case 'cast': {
        if (this.st > 0.12 && !this.casted) { this.casted = true; g.spawnWindBlade(this); }
        if (this.st > 0.34) this.state = 'free';
        break;
      }
      case 'hurt': {
        if (this.st > 0.28) this.state = 'free';
        break;
      }
      case 'dead': break;
      case 'talk': this.anim.set('idle'); break;
    }

    // animação
    const stepped = this.anim.update(dt);
    if (stepped || this.state === 'roll') {
      const name = this.state === 'attack' ? 'attack' + this.combo : this.state === 'free' || this.state === 'talk' ? this.anim.state : this.state;
      const dur = this.state === 'attack' ? (this.combo === 3 ? 0.42 : 0.3) : this.state === 'roll' ? 0.36 : this.state === 'spin' ? 0.5 : this.state === 'cast' ? 0.34 : 1;
      const tt = this.state === 'roll' ? this.st : this.anim.frameT;
      poseHumanoid(this.rig, name, tt, Math.min(1, (this.state === 'free' ? 0 : this.st) / dur));
    }
    // piscar quando invulnerável
    this.obj.visible = !(this.invuln > 0 && this.state !== 'roll' && Math.floor(this.invuln * 16) % 2 === 0);
    this.sync();
  }

  swordTip() {
    const b = this.rig.parts.blade;
    const p = new V3(0, 0, 0.3);
    b.localToWorld(p);
    return p;
  }

  startAttack() {
    const chaining = this.state === 'attack' || (this.comboTimer > 0 && this.combo > 0);
    this.combo = chaining && this.combo < 3 ? this.combo + 1 : 1;
    this.state = 'attack'; this.st = 0; this.queued = false; this.hitSet.clear();
    this.heldSince = 0;
    this.anim.set('attack' + this.combo, true);
    // mira automática leve: vira para o inimigo mais próximo à frente
    const t = this.game.nearestEnemy(this.pos, 3.2);
    if (t && Math.abs(angDiff(this.angleTo(t.pos), this.facing)) < 1.2) this.facing = this.angleTo(t.pos);
    sfx.swing(this.combo - 1);
    const fx = this.game.fx;
    const arcs = [[2.3, 1], [2.3, -1], [1.6, 1]];
    const [arc, dir] = arcs[this.combo - 1];
    setTimeout(() => {
      if (this.state !== 'attack') return;
      if (this.combo === 3) fx.slash(this.pos, this.facing, { radius: 1.75, arc: 1.5, y: 0.35, thick: 0.6, color: 0xffffff, color2: 0xfff2a8, life: 0.16 });
      else fx.slash(this.pos, this.facing, { radius: 1.45, arc, y: 0.55, dir, life: 0.13 });
    }, 50);
  }

  startSpin() {
    this.state = 'spin'; this.st = 0; this.hitSet.clear(); this.anim.set('spin', true);
    this.game.fx.ring(this.pos, { r0: 0.6, r1: 2.3, color: 0xfff2a8, life: 0.3, y: 0.5, width: 0.18 });
    this.game.fx.slash(this.pos, this.facing, { radius: 2.0, arc: Math.PI * 2, y: 0.5, thick: 0.55, color: 0xffffff, color2: 0xfff2a8, life: 0.3 });
  }

  startRoll(wmv, mlen) {
    if (this.rollCd > 0) return;
    const dir = mlen > 0.1 ? new V3(wmv.x, 0, wmv.z).normalize() : new V3(Math.sin(this.facing), 0, Math.cos(this.facing));
    this.rollDir = dir;
    this.facing = Math.atan2(dir.x, dir.z);
    this.state = 'roll'; this.st = 0; this.anim.set('roll', true);
    this.invuln = Math.max(this.invuln, 0.3);
    sfx.roll();
  }

  startCast() {
    const s = this.stats;
    if (s.ep < 12) { sfx.deny(); this.game.ui.toast('Energia insuficiente'); return; }
    s.ep -= 12;
    const t = this.game.nearestEnemy(this.pos, 9);
    if (t) this.facing = this.angleTo(t.pos);
    this.state = 'cast'; this.st = 0; this.casted = false; this.anim.set('cast', true);
    sfx.cast();
  }

  doHit(reach, arc, mult, kb, multiHit = false) {
    const g = this.game;
    for (const e of g.hittables()) {
      if (!e.alive) continue;
      const key = multiHit ? e.id + ':' + Math.floor(this.st / 0.16) : e.id;
      if (this.hitSet.has(key)) continue;
      const d = this.distTo(e.pos) - e.radius;
      if (d > reach) continue;
      if (arc < Math.PI * 2 && Math.abs(angDiff(this.angleTo(e.pos), this.facing)) > arc / 2 && d > 0.3) continue;
      this.hitSet.add(key);
      const crit = Math.random() < 0.12;
      const dmg = Math.round(this.stats.atk * mult * (crit ? 1.6 : 1) * (0.9 + Math.random() * 0.2));
      g.hitEnemy(e, dmg, this.pos, kb, crit);
    }
  }

  hurt(dmg, from) {
    if (this.invuln > 0 || this.state === 'dead') return false;
    const s = this.stats;
    s.hp = Math.max(0, s.hp - dmg);
    this.flash = 0.1;
    this.invuln = 1.0;
    const a = Math.atan2(this.pos.x - from.x, this.pos.z - from.z);
    this.kb.set(Math.sin(a) * 7, 0, Math.cos(a) * 7);
    this.game.fx.text(this.pos, String(dmg), 'hurt');
    sfx.hurt();
    if (s.hp <= 0) { this.state = 'dead'; this.st = 0; this.anim.set('dead', true); this.game.onPlayerDeath(); }
    else if (this.state !== 'charge' || dmg > 10) { this.state = 'hurt'; this.st = 0; this.anim.set('hurt', true); }
    return true;
  }
}

// ---------------------------------------------------------------- NPC
export class NPC extends Actor {
  constructor(game, def) {
    super(game, buildHumanoid(def.look));
    this.def = def;
    this.name = def.name;
    this.radius = 0.35;
    this.home = null;
    this.mode = def.mode || 'idle';
    this.talking = false;
    this.wanderT = 1 + Math.random() * 2;
    this.target = null;
    this.collider = null;
  }
  update(dt) {
    const g = this.game, p = g.player;
    if (!this.home) this.home = this.pos.clone();
    let st = this.mode === 'sit' ? 'sit' : 'idle';
    if (this.talking) { this.facing = this.angleTo(p.pos); st = 'talk'; }
    else if (this.mode === 'wander') {
      this.wanderT -= dt;
      if (this.wanderT <= 0) {
        this.wanderT = 2 + Math.random() * 3;
        const a = Math.random() * Math.PI * 2, r = Math.random() * 2.5;
        this.target = this.target ? null : new V3(this.home.x + Math.cos(a) * r, 0, this.home.z + Math.sin(a) * r);
      }
      if (this.target && this.distTo(this.target) > 0.2) {
        this.facing = this.angleTo(this.target);
        g.world.move(this.pos, Math.sin(this.facing) * 1.4 * dt, Math.cos(this.facing) * 1.4 * dt, this.radius);
        st = 'walk';
      }
    } else if (this.distTo(p.pos) < 4 && this.mode !== 'sit') {
      this.facing += angDiff(this.angleTo(p.pos), this.facing) * Math.min(1, dt * 4);
      if (this.def.wave && this.distTo(p.pos) < 3.2 && !this.waved) { this.waved = true; this.waveT = 1.4; }
    }
    if (this.waveT > 0) { this.waveT -= dt; st = 'wave'; }
    this.anim.set(st);
    if (this.anim.update(dt)) poseHumanoid(this.rig, st, this.anim.frameT, 0);
    this.sync();
  }
}

// ---------------------------------------------------------------- inimigos
let nextId = 1;
export class Enemy extends Actor {
  constructor(game, kind, rig, o) {
    super(game, rig);
    this.id = nextId++;
    this.kind = kind;
    this.maxHp = this.hp = o.hp;
    this.dmg = o.dmg; this.exp = o.exp; this.gold = o.gold;
    this.radius = o.radius ?? 0.4;
    this.name = o.name;
    this.alive = true;
    this.state = 'idle';
    this.st = Math.random();
    this.cd = 1 + Math.random();
    this.home = null;
    this.aggro = false;
    this.stun = 0;
    this.squash = 1;
    this.camp = o.camp;
    this.leash = o.leash ?? 11;
    this.baseScale = 1;
  }
  hurtReact() {}
  update(dt) {
    const g = this.game, p = g.player;
    if (!this.home) this.home = this.pos.clone();
    this.st += dt;
    this.cd -= dt;
    this.flash = Math.max(0, this.flash - dt);
    if (this.kb.lengthSq() > 0.001) {
      g.world.move(this.pos, this.kb.x * dt, this.kb.z * dt, this.radius);
      this.kb.multiplyScalar(Math.exp(-9 * dt));
    }
    if (!this.alive) {
      this.deathT += dt;
      const k = Math.min(1, this.deathT / 0.35), bs = this.baseScale;
      this.obj.scale.set(bs * (1 + k * 0.5), bs * Math.max(0.01, 1 - k), bs * (1 + k * 0.5));
      this.flash = Math.floor(this.deathT * 20) % 2 ? 0.05 : 0;
      this.sync();
      if (k >= 1 && !this.gone) { this.gone = true; this.remove(); }
      return;
    }
    const d = this.distTo(p.pos);
    if (!this.aggro && d < 7 && p.alive) this.aggro = true;
    if (this.aggro && (this.distTo(this.home) > this.leash + 4 || !p.alive)) { this.aggro = false; this.state = 'return'; }
    this.think(dt, d, p);
    // dano de contato
    if (this.contact && d < this.radius + p.radius + 0.05 && p.alive) g.damagePlayer(this.contactDmg ?? Math.round(this.dmg * 0.6), this.pos);
    this.sync(this.lift || 0);
    const bs = this.baseScale;
    this.obj.scale.set(bs / Math.sqrt(this.squash), bs * this.squash, bs / Math.sqrt(this.squash));
  }
  wander(dt, speed) {
    if (!this.wTarget || this.distTo(this.wTarget) < 0.3 || this.st > 3) {
      this.st = 0;
      const a = Math.random() * Math.PI * 2, r = Math.random() * 3;
      this.wTarget = new V3(this.home.x + Math.cos(a) * r, 0, this.home.z + Math.sin(a) * r);
    }
    this.facing = this.angleTo(this.wTarget);
    this.game.world.move(this.pos, Math.sin(this.facing) * speed * dt, Math.cos(this.facing) * speed * dt, this.radius);
  }
  goHome(dt, speed) {
    this.facing = this.angleTo(this.home);
    this.game.world.move(this.pos, Math.sin(this.facing) * speed * dt, Math.cos(this.facing) * speed * dt, this.radius);
    if (this.distTo(this.home) < 0.6) { this.state = 'idle'; this.hp = Math.min(this.maxHp, this.hp + this.maxHp * 0.5); }
  }
}

export class Slime extends Enemy {
  constructor(game, o = {}) {
    const col = o.color || ['#5ec8e0', '#5ec8e0', '#a3df52', '#f08fb0'][Math.floor(Math.random() * 4)];
    super(game, 'slime', buildSlime(col), { hp: 28, dmg: 9, exp: 7, gold: [1, 4], radius: 0.42, name: 'Gosma', ...o });
    this.contactDmg = 7;
    this.hopT = 0;
    this.color = col;
  }
  think(dt, d, p) {
    const g = this.game;
    this.lift = 0;
    this.squash += (1 - this.squash) * Math.min(1, dt * 10);
    switch (this.state) {
      case 'idle':
        if (this.aggro) { this.state = 'chase'; this.st = 0; break; }
        if (this.st > 1.2 + Math.random()) { this.state = 'hop'; this.st = 0; this.hopDir = Math.random() * Math.PI * 2; this.hopSpeed = 1.4; }
        this.squash = 1 + Math.sin(this.st * 5) * 0.06;
        break;
      case 'return': this.goHome(dt, 2); this.lift = Math.abs(Math.sin(this.st * 8)) * 0.25; break;
      case 'chase':
        this.facing = this.angleTo(p.pos);
        if (d < 2.6 && this.cd <= 0) { this.state = 'windup'; this.st = 0; sfx.telegraph(); break; }
        if (this.st > 0.55) { this.state = 'hop'; this.st = 0; this.hopDir = this.angleTo(p.pos) + (Math.random() - 0.5) * 0.6; this.hopSpeed = 2.4; }
        this.squash = 1 + Math.sin(this.st * 9) * 0.08;
        break;
      case 'hop': {
        const k = this.st / 0.38;
        this.facing = this.hopDir;
        g.world.move(this.pos, Math.sin(this.hopDir) * this.hopSpeed * dt * 1.6, Math.cos(this.hopDir) * this.hopSpeed * dt * 1.6, this.radius);
        this.lift = Math.sin(Math.min(1, k) * Math.PI) * 0.45;
        this.squash = k < 0.1 ? 0.7 : 1.18;
        if (k >= 1) { this.state = this.aggro ? 'chase' : 'idle'; this.st = 0; this.squash = 0.72; g.fx.dust(this.pos, 2, 0x8fc77a); }
        break;
      }
      case 'windup':
        this.facing = this.angleTo(p.pos);
        this.squash = 0.62 + Math.sin(this.st * 40) * 0.04;
        this.flash = Math.floor(this.st * 14) % 2 ? 0.02 : 0;
        if (this.st > 0.5) { this.state = 'leap'; this.st = 0; this.leapDir = this.facing; sfx.hop(); }
        break;
      case 'leap': {
        const k = this.st / 0.42;
        g.world.move(this.pos, Math.sin(this.leapDir) * 7 * dt, Math.cos(this.leapDir) * 7 * dt, this.radius);
        this.lift = Math.sin(Math.min(1, k) * Math.PI) * 0.8;
        this.squash = 1.25;
        if (d < this.radius + p.radius + 0.25) g.damagePlayer(this.dmg, this.pos);
        if (k >= 1) { this.state = 'chase'; this.st = 0; this.cd = 1.6 + Math.random(); this.squash = 0.6; g.fx.dust(this.pos, 4, 0x8fc77a); }
        break;
      }
    }
    if (this.anim.update(dt)) { /* gosma é toda squash & stretch */ }
  }
}

export class Mushroom extends Enemy {
  constructor(game, o = {}) {
    super(game, 'mushroom', buildMushroom(null, o.cap || '#d4553f'), { hp: 42, dmg: 11, exp: 11, gold: [2, 6], radius: 0.45, name: 'Fungão', ...o });
    this.contactDmg = 6;
  }
  think(dt, d, p) {
    const g = this.game, parts = this.rig.parts;
    let walking = false;
    switch (this.state) {
      case 'idle':
        if (this.aggro) { this.state = 'chase'; break; }
        if (Math.random() < dt * 0.3) this.state = 'stroll';
        break;
      case 'stroll': this.wander(dt, 0.8); walking = true; if (this.st > 2.5) { this.state = 'idle'; this.st = 0; } if (this.aggro) this.state = 'chase'; break;
      case 'return': this.goHome(dt, 1.8); walking = true; break;
      case 'chase': {
        this.facing = this.angleTo(p.pos);
        if (d < 7 && this.cd <= 0) { this.state = 'puff'; this.st = 0; sfx.telegraph(); break; }
        const sp = d > 4 ? 1.4 : d < 2.6 ? -1.6 : 0;
        if (sp) { g.world.move(this.pos, Math.sin(this.facing) * sp * dt, Math.cos(this.facing) * sp * dt, this.radius); walking = true; }
        break;
      }
      case 'puff': {
        this.facing = this.angleTo(p.pos);
        const k = Math.min(1, this.st / 0.7);
        parts.cap.scale.setScalar(1 + k * 0.3 + Math.sin(this.st * 30) * 0.03);
        if (this.st > 0.7) {
          parts.cap.scale.setScalar(0.85);
          for (const off of [-0.32, 0, 0.32]) g.spawnSpore(this, this.facing + off);
          g.fx.burst({ x: this.pos.x, y: this.pos.y + 0.9, z: this.pos.z }, 8, { speed: 1.5, up: 1, g: 0.5, color: [0xb98ad6, 0xd9b8ef], life: 0.5, size: 0.1 });
          sfx.shoot();
          this.state = 'chase'; this.cd = 2.2 + Math.random() * 0.8;
        }
        break;
      }
    }
    if (this.state !== 'puff') parts.cap.scale.lerp(new V3(1, 1, 1), Math.min(1, dt * 8));
    if (this.anim.update(dt)) {
      const t = this.anim.frameT * 9;
      parts.legL.rotation.x = walking ? Math.sin(t) * 0.6 : 0;
      parts.legR.rotation.x = walking ? -Math.sin(t) * 0.6 : 0;
      parts.body.position.y = walking ? Math.abs(Math.cos(t)) * 0.05 : 0;
      parts.cap.rotation.z = walking ? Math.sin(t) * 0.08 : Math.sin(this.anim.frameT * 2) * 0.04;
    }
  }
}

export class Beetle extends Enemy {
  constructor(game, o = {}) {
    super(game, 'beetle', buildBeetle(), { hp: 55, dmg: 15, exp: 15, gold: [3, 8], radius: 0.5, name: 'Besouro-chifre', ...o });
    this.contactDmg = 8;
  }
  think(dt, d, p) {
    const g = this.game;
    let walking = false;
    switch (this.state) {
      case 'idle': if (this.aggro) { this.state = 'chase'; break; } this.wander(dt, 0.9); walking = true; break;
      case 'return': this.goHome(dt, 2.2); walking = true; break;
      case 'chase':
        this.facing = this.angleTo(p.pos);
        if (d < 7.5 && this.cd <= 0) {
          this.state = 'aim'; this.st = 0; sfx.telegraph();
          this.tele = g.fx.telegraph(this.pos, 0.5, 0.75, 0xff4a4a);
          this.lineTele = g.chargeLine(this);
          break;
        }
        g.world.move(this.pos, Math.sin(this.facing) * 1.5 * dt, Math.cos(this.facing) * 1.5 * dt, this.radius); walking = true;
        break;
      case 'aim':
        if (this.st < 0.45) this.facing = this.angleTo(p.pos);
        g.updateChargeLine(this.lineTele, this);
        if (Math.random() < 0.4) g.fx.dust(this.pos, 1, 0xc9b48c);
        this.obj.position.x += (Math.random() - 0.5) * 0.04;
        if (this.st > 0.75) { this.state = 'charge'; this.st = 0; g.removeChargeLine(this.lineTele); this.hitPlayer = false; }
        break;
      case 'charge': {
        const before = this.pos.clone();
        const sp = 10;
        g.world.move(this.pos, Math.sin(this.facing) * sp * dt, Math.cos(this.facing) * sp * dt, this.radius);
        walking = true;
        if (Math.random() < 0.6) g.fx.dust(this.pos, 1, 0xc9b48c);
        if (d < this.radius + p.radius + 0.3 && !this.hitPlayer) { if (g.damagePlayer(this.dmg, this.pos)) this.hitPlayer = true; }
        const moved = before.distanceTo(this.pos);
        if (moved < sp * dt * 0.4 && this.st > 0.05) { this.state = 'stunned'; this.st = 0; this.stun = 1.4; g.shake(3); sfx.slam(); g.fx.burst({ x: this.pos.x, y: this.pos.y + 0.6, z: this.pos.z }, 6, { color: 0xfff2a8, speed: 1.5, up: 1.5, life: 0.6 }); }
        else if (this.st > 0.85) { this.state = 'chase'; this.cd = 1.8 + Math.random(); }
        break;
      }
      case 'stunned':
        if (Math.floor(this.st * 6) % 2 === 0 && Math.random() < 0.3) g.fx.particle({ x: this.pos.x + Math.sin(this.st * 8) * 0.4, y: this.pos.y + 1.0, z: this.pos.z + Math.cos(this.st * 8) * 0.4 }, { life: 0.2, color: 0xfff2a8, size: 0.08 });
        if (this.st > this.stun) { this.state = 'chase'; this.cd = 1.2; }
        break;
    }
    if (this.anim.update(dt)) {
      const t = this.anim.frameT * 16;
      let i = 0;
      for (const [k, leg] of Object.entries(this.rig.parts)) if (k.startsWith('leg')) { leg.rotation.y = walking ? Math.sin(t + i * 1.7) * 0.5 : 0; i++; }
      this.rig.parts.body.rotation.z = this.state === 'stunned' ? Math.sin(this.anim.frameT * 20) * 0.1 : 0;
    }
  }
}

// ---------------------------------------------------------------- chefe
export class StumpBoss extends Enemy {
  constructor(game) {
    super(game, 'boss', buildStumpBoss(), { hp: 950, dmg: 18, exp: 260, gold: [60, 80], radius: 1.45, name: 'Toco Ancião', leash: 99 });
    this.state = 'dormant';
    this.phase = 1;
    this.pattern = 0;
    this.sinkY = -2.6;
    this.lift = this.sinkY;
    this.shadow.scale.setScalar(2.6);
    this.contact = false;
    this.spikes = [];
  }
  think(dt, d, p) {
    const g = this.game, parts = this.rig.parts;
    const enraged = this.hp < this.maxHp * 0.5;
    if (enraged && this.phase === 1) { this.phase = 2; g.onBossPhase2(this); }
    const speedK = enraged ? 1.25 : 1;
    switch (this.state) {
      case 'dormant':
        this.lift = this.sinkY;
        this.obj.visible = false; this.shadow.visible = false;
        if (d < 7.5) { this.state = 'intro'; this.st = 0; this.obj.visible = true; this.shadow.visible = true; g.onBossIntro(this); }
        break;
      case 'intro': {
        const k = Math.min(1, this.st / 2.2);
        this.lift = this.sinkY * (1 - k) + Math.sin(this.st * 40) * 0.03 * (1 - k);
        if (Math.random() < 0.7) g.fx.dust(this.pos, 2, 0x8a6a50);
        if (this.st > 2.6) { this.state = 'pause'; this.st = 0; g.onBossReady(this); }
        break;
      }
      case 'pause':
        this.lift = 0;
        this.facing += angDiff(this.angleTo(p.pos), this.facing) * Math.min(1, dt * 3);
        if (this.st > 1.1 / speedK) this.nextPattern();
        break;
      case 'roots': {
        this.facing += angDiff(this.angleTo(p.pos), this.facing) * Math.min(1, dt * 3);
        const waves = enraged ? 4 : 3, gap = 0.75 / speedK;
        const w = Math.floor(this.st / gap);
        if (w < waves && w !== this.lastWave) {
          this.lastWave = w;
          const n = enraged ? 5 : 4;
          for (let i = 0; i < n; i++) {
            const a = Math.random() * Math.PI * 2, r = i === 0 ? 0 : 1.6 + Math.random() * 2.4;
            const at = { x: p.pos.x + Math.cos(a) * r + (i === 0 ? Math.sin(p.facing) * 0.8 : 0), z: p.pos.z + Math.sin(a) * r + (i === 0 ? Math.cos(p.facing) * 0.8 : 0) };
            g.rootSpike(at, 0.85 / speedK, this.dmg);
          }
          parts.armL.rotation.z = -0.6; parts.armR.rotation.z = 0.6;
          sfx.telegraph();
        }
        if (this.st > waves * gap + 1.0) { this.state = 'pause'; this.st = 0; }
        break;
      }
      case 'seeds': {
        const waves = enraged ? 4 : 3, gap = 0.55 / speedK;
        this.obj.rotation.y += dt * 4;
        const w = Math.floor(this.st / gap);
        if (w < waves && w !== this.lastWave && this.st > 0.4) {
          this.lastWave = w;
          const n = enraged ? 16 : 12;
          for (let i = 0; i < n; i++) g.spawnSeed(this, (i / n) * Math.PI * 2 + w * 0.2);
          sfx.shoot();
        }
        if (this.st > 0.4 + waves * gap + 0.6) { this.state = 'pause'; this.st = 0; }
        break;
      }
      case 'slam': {
        const wind = 1.15 / speedK;
        if (this.st < wind) {
          const k = this.st / wind;
          parts.armL.rotation.z = -1.3 * k; parts.armR.rotation.z = 1.3 * k;
          this.lift = k * 0.5;
        } else if (!this.slammed) {
          this.slammed = true;
          this.lift = 0;
          parts.armL.rotation.z = 0.5; parts.armR.rotation.z = -0.5;
          g.bossSlam(this);
        } else if (this.st > wind + 0.2) {
          this.state = 'stunned'; this.st = 0; this.stun = enraged ? 1.8 : 2.4;
          g.fx.text(this.pos, 'ATORDOADO!', 'info');
        }
        break;
      }
      case 'stunned': {
        parts.face.position.y = 1.15 + Math.sin(this.st * 3) * 0.04;
        parts.face.rotation.x = 0.25;
        parts.armL.rotation.z = 0.7; parts.armR.rotation.z = -0.7;
        if (Math.random() < 0.15) g.fx.particle({ x: this.pos.x + Math.sin(this.st * 6) * 0.9, y: this.pos.y + 2.9, z: this.pos.z + Math.cos(this.st * 6) * 0.9 }, { life: 0.3, color: 0xfff2a8, size: 0.12 });
        if (this.st > this.stun) { parts.face.position.y = 1.35; parts.face.rotation.x = 0; this.state = 'pause'; this.st = 0; }
        break;
      }
      case 'burrow': {
        // afunda, viaja até perto do herói e emerge
        if (this.st < 0.7) { this.lift = -this.st / 0.7 * 2.6; if (Math.random() < 0.8) g.fx.dust(this.pos, 2, 0x8a6a50); this.contact = false; }
        else if (!this.dest) {
          const a = Math.random() * Math.PI * 2;
          const c = g.arenaCenter;
          let x = p.pos.x + Math.cos(a) * 2.2, z = p.pos.z + Math.sin(a) * 2.2;
          const dc = Math.hypot(x - c.x, z - c.z);
          if (dc > 5.5) { x = c.x + (x - c.x) / dc * 5.5; z = c.z + (z - c.z) / dc * 5.5; }
          this.dest = new V3(x, 0, z);
          g.fx.telegraph(new V3(x, g.world.heightAt(x, z), z), 2.0, 0.9 / speedK, 0xff4a4a);
          sfx.telegraph();
          this.lift = -2.6;
        } else if (this.st > 0.7 + 0.9 / speedK && !this.emerged) {
          this.emerged = true;
          this.pos.x = this.dest.x; this.pos.z = this.dest.z; this.y = g.world.heightAt(this.pos.x, this.pos.z);
          g.bossEmerge(this);
        } else if (this.emerged) {
          const k = Math.min(1, (this.st - 0.7 - 0.9 / speedK) / 0.3);
          this.lift = -2.6 * (1 - k);
          if (k >= 1 && this.st > 2.2) { this.state = 'pause'; this.st = 0; this.dest = null; this.emerged = false; }
        }
        break;
      }
    }
    if (this.state !== 'slam' && this.state !== 'stunned' && this.state !== 'roots') {
      parts.armL.rotation.z *= 0.9; parts.armR.rotation.z *= 0.9;
    }
    if (this.anim.update(dt)) {
      const t = this.anim.frameT;
      parts.body.rotation.z = this.state === 'pause' ? Math.sin(t * 2) * 0.03 : 0;
      parts.mouth.position.y = -0.42 - (this.state === 'seeds' || this.state === 'slam' ? 0.12 : Math.abs(Math.sin(t * 3)) * 0.04);
      parts.sapling.rotation.z = Math.sin(t * 4) * 0.2;
      const eye = enraged ? 1 : 0;
      parts.eyeL.material.color.setHex(eye ? 0xff4a3a : 0xffb347); parts.eyeR.material.color.setHex(eye ? 0xff4a3a : 0xffb347);
    }
  }
  nextPattern() {
    const seq = this.phase === 1 ? ['roots', 'seeds', 'slam', 'roots', 'burrow', 'seeds', 'slam'] : ['roots', 'burrow', 'seeds', 'slam', 'roots', 'seeds', 'burrow', 'slam'];
    this.state = seq[this.pattern % seq.length];
    this.pattern++;
    this.st = 0; this.lastWave = -1; this.slammed = false;
    if (this.state === 'seeds') this.game.fx.text(this.pos, '!', 'warn');
  }
  sync(extraY = 0) {
    super.sync(extraY);
    if (this.state === 'seeds') this.obj.rotation.y = this.spin = (this.spin || 0) + 0.25;
  }
}

// ---------------------------------------------------------------- coletáveis
const pickupGeo = {
  coin: new THREE.CylinderGeometry(0.14, 0.14, 0.05, 8).rotateX(Math.PI / 2),
  heart: new THREE.OctahedronGeometry(0.16, 0),
  orb: new THREE.IcosahedronGeometry(0.13, 0),
  rune: new THREE.OctahedronGeometry(0.25, 0),
};
const pickupMats = {};
export class Pickup {
  constructor(game, kind, pos, value = 1) {
    this.game = game; this.kind = kind; this.value = value;
    const col = { coin: 0xf2c14e, heart: 0xe8485f, orb: 0x5fb6f0, rune: 0x7fe0c8 }[kind];
    if (!pickupMats[kind]) pickupMats[kind] = toonMat({ color: col, outline: 0.9, emissive: kind === 'rune' ? 0.6 : 0 });
    this.mesh = new THREE.Mesh(pickupGeo[kind], pickupMats[kind]);
    this.mesh.castShadow = true;
    game.scene.add(this.mesh);
    this.pos = pos.clone();
    const a = Math.random() * Math.PI * 2, sp = 1.5 + Math.random() * 1.8;
    this.vel = new V3(Math.cos(a) * sp, 4 + Math.random() * 2, Math.sin(a) * sp);
    this.t = 0;
    this.alive = true;
  }
  update(dt) {
    const g = this.game, p = g.player;
    this.t += dt;
    const ground = g.world.heightAt(this.pos.x, this.pos.z) + 0.25;
    const d = Math.hypot(p.pos.x - this.pos.x, p.pos.z - this.pos.z);
    if (this.t > 0.45 && d < 2.4 && p.alive) {
      const k = Math.min(1, dt * 10);
      this.pos.x += (p.pos.x - this.pos.x) * k; this.pos.z += (p.pos.z - this.pos.z) * k; this.pos.y += (p.pos.y + 0.5 - this.pos.y) * k;
      if (d < 0.5) { this.alive = false; g.collect(this); }
    } else {
      this.vel.y -= 18 * dt;
      const nx = this.pos.x + this.vel.x * dt, nz = this.pos.z + this.vel.z * dt;
      if (g.world.walkable(nx, nz)) { this.pos.x = nx; this.pos.z = nz; } else { this.vel.x *= -0.4; this.vel.z *= -0.4; }
      this.pos.y += this.vel.y * dt;
      if (this.pos.y < ground) { this.pos.y = ground; this.vel.y = Math.abs(this.vel.y) * 0.35; this.vel.x *= 0.6; this.vel.z *= 0.6; }
    }
    this.mesh.position.copy(this.pos);
    this.mesh.position.y += Math.sin(this.t * 4) * 0.05;
    this.mesh.rotation.y = Math.floor(this.t * 8) * 0.6;
    if (this.t > 25) { this.alive = false; }
    if (!this.alive) this.game.scene.remove(this.mesh);
  }
}

// ---------------------------------------------------------------- baú
export class Chest {
  constructor(game, pos, rot, contents) {
    this.game = game; this.contents = contents; this.opened = false; this.locked = true;
    const g = new THREE.Group();
    const m = (c) => toonMat({ color: c, outline: 0.95 });
    const base = new THREE.Mesh(new THREE.BoxGeometry(0.9, 0.5, 0.6), m('#9a6a3e')); base.position.y = 0.25; base.castShadow = true; g.add(base);
    for (const s of [-1, 1]) { const b = new THREE.Mesh(new THREE.BoxGeometry(0.08, 0.52, 0.62), m('#e8c36a')); b.position.set(s * 0.3, 0.26, 0); g.add(b); }
    const lid = new THREE.Group(); lid.position.set(0, 0.5, -0.3); g.add(lid);
    const lm = new THREE.Mesh(new THREE.CylinderGeometry(0.3, 0.3, 0.9, 8, 1, false, 0, Math.PI), m('#a9764a'));
    lm.rotation.z = Math.PI / 2; lm.position.z = 0.3; lm.scale.set(1, 1, 1); lid.add(lm);
    const lock = new THREE.Mesh(new THREE.BoxGeometry(0.16, 0.2, 0.06), m('#e8c36a')); lock.position.set(0, 0.42, 0.32); g.add(lock);
    g.position.copy(pos); g.rotation.y = rot;
    game.scene.add(g);
    this.obj = g; this.lid = lid; this.pos = pos;
    game.world.addBox(pos.x, pos.z, 0.5, 0.35, rot);
  }
  open() {
    if (this.opened) return;
    this.opened = true;
    this.openT = 0;
  }
  update(dt) {
    if (!this.opened || this.openT > 1) return;
    this.openT += dt;
    this.lid.rotation.x = -Math.min(1, this.openT / 0.35) * 1.9;
  }
}

// ---------------------------------------------------------------- projéteis
export class Projectile {
  constructor(game, o) {
    Object.assign(this, { life: 2, radius: 0.25, pierce: false, spin: 0 }, o);
    this.game = game; this.alive = true; this.t = 0; this.hit = new Set();
    game.scene.add(this.mesh);
    this.mesh.position.copy(this.pos);
  }
  update(dt) {
    const g = this.game;
    this.t += dt;
    this.pos.addScaledVector(this.vel, dt);
    const ground = g.world.heightAt(this.pos.x, this.pos.z);
    this.mesh.position.copy(this.pos);
    if (this.spin) this.mesh.rotation.y += this.spin * dt;
    if (this.trail && Math.random() < 0.6) g.fx.particle(this.pos, { life: 0.25, color: this.trail, size: 0.07, vy: 0.3 });
    if (this.t > this.life || ground > this.pos.y + 0.1) { this.kill(); return; }
    if (this.owner === 'enemy') {
      const p = g.player;
      if (Math.hypot(p.pos.x - this.pos.x, p.pos.z - this.pos.z) < this.radius + p.radius && p.alive) { if (g.damagePlayer(this.dmg, this.pos)) this.kill(); }
    } else {
      for (const e of g.hittables()) {
        if (!e.alive || this.hit.has(e.id)) continue;
        if (Math.hypot(e.pos.x - this.pos.x, e.pos.z - this.pos.z) < this.radius + e.radius) {
          this.hit.add(e.id);
          g.hitEnemy(e, this.dmg, this.pos.clone().addScaledVector(this.vel, -0.1), 3, false);
          if (!this.pierce) { this.kill(); return; }
        }
      }
    }
  }
  kill() {
    this.alive = false;
    this.game.scene.remove(this.mesh);
    if (this.onDie) this.onDie(this);
  }
}
