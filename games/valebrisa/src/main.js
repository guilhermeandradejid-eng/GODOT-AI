import './style.css';
import * as THREE from 'three';
import { PixelRenderer } from './render.js';
import { shared, toonMat, unlitMat } from './materials.js';
import { World, toWorld, toUV, PLACES } from './world.js';
import { buildScenery, mergeStatic, campfire, torch } from './props.js';
import { buildGrass } from './grass.js';
import { Lighting, TIME_PRESETS } from './lighting.js';
import { FX } from './fx.js';
import { UI } from './ui.js';
import { Input } from './input.js';
import { initAudio, sfx, playMusic, toggleMusic, isMusicOn } from './audio.js';
import { Player, NPC, Slime, Mushroom, Beetle, StumpBoss, Pickup, Chest, Projectile } from './entities.js';

// =============================================================================
// Valebrisa — RPG de ação isométrico (versão de teste para navegador)
// =============================================================================

const SAVE_KEY = 'valebrisa-save-v1';
const storage = {
  get() { try { return JSON.parse(localStorage.getItem(SAVE_KEY) || 'null'); } catch { return null; } },
  set(v) { try { localStorage.setItem(SAVE_KEY, JSON.stringify(v)); } catch { /* sem armazenamento */ } },
  clear() { try { localStorage.removeItem(SAVE_KEY); } catch { /* */ } },
};
const W = (u, v) => toWorld(u, v);
const QS = new URLSearchParams(location.search);
const FAST = QS.has('fast'); // só para testes automatizados
const FIREFLY = new THREE.Color(1.5, 2.0, 0.7), FIRE_HOT = new THREE.Color(2.2, 1.5, 0.5), FIRE_COOL = new THREE.Color(0.9, 0.25, 0.1);

class Game {
  constructor() {
    this.pr = new PixelRenderer(document.getElementById('game'));
    this.scene = new THREE.Scene();
    this.scene.background = new THREE.Color(0x253532);
    this.input = new Input();
    this.world = new World();
    this.kills = 0;
    this.playTime = 0;
    this.hitstop = 0;
    this.shakeT = 0; this.shakeAmp = 0;
    this.state = 'title';
    this.musicOn = true;
    this.enemies = [];
    this.projectiles = [];
    this.pickups = [];
    this.npcs = [];
    this.interactables = [];
    this.timers = [];
    this.spikes = [];
    this.quest = { stage: 0, slimes: 0, rune: false, gate: false, boss: false };

    this.buildWorld();
    this.fx = new FX(this.scene, this.pr, document.getElementById('ui'));
    this.ui = new UI(document.getElementById('ui'), this);
    this.fx.ui = this.ui.dmgLayer;
    this.player = new Player(this);
    const sp = W(...PLACES.spawn);
    this.player.place(sp.x, sp.z);
    this.player.facing = Math.PI * 0.25;
    this.camTarget = this.player.pos.clone();
    this.buildActors();
    this.loadOrNew(false);

    window.addEventListener('resize', () => { this.pr.resize(); this.ui.applyScale(); });
    this.clock = new THREE.Timer();
    this.ui.titleScreen(!!storage.get());
    this.titleT = 0;
    const hq = QS.get('hora');
    this.lighting.fixed = hq && TIME_PRESETS[hq] !== undefined ? TIME_PRESETS[hq] : 18.0;
    this.lighting.hour = this.lighting.fixed ?? 8.5;
    if (hq) this.timeMode = hq;
    this.loop = this.loop.bind(this);
    requestAnimationFrame(this.loop);
    const unlock = () => { initAudio(); if (this.state === 'title') playMusic('vila'); };
    window.addEventListener('pointerdown', unlock); window.addEventListener('keydown', unlock); window.addEventListener('touchstart', unlock);
  }

  // ------------------------------------------------------------ mundo
  buildWorld() {
    const sc = this.scene, world = this.world;
    sc.add(world.buildTerrainMesh());
    sc.add(world.buildWaterMesh());
    this.scenery = buildScenery(world, sc);
    // fogueira do pescador e tochas do portão
    let fireAt = W(-21.2, 4.6);
    for (let r = 0; r < 4; r += 0.4) { let ok = false; for (let a = 0; a < 6.28 && !ok; a += 0.5) { const c = W(-21.2 + Math.cos(a) * r, 4.6 + Math.sin(a) * r); if (world.freeCircle(c.x, c.z, 0.9) && world.heightAt(c.x, c.z) > -0.1) { fireAt = c; ok = true; } } if (ok) break; }
    this.fire = campfire(); this.fire.position.set(fireAt.x, world.heightAt(fireAt.x, fireAt.z), fireAt.z); sc.add(this.fire);
    world.addCircle(fireAt.x, fireAt.z, 0.5);
    this.torches = [[-3.1, -15.0], [3.1, -15.0], [-2.6, -22.4], [2.6, -22.4]].map((at) => {
      const w = W(...at), t = torch(); t.position.set(w.x, world.heightAt(w.x, w.z), w.z); sc.add(t); world.addCircle(w.x, w.z, 0.15); return t;
    });
    this.grassCount = buildGrass(world, sc, (x, z) => this.scenery.blocked(x, z, -0.45) || Math.hypot(x - fireAt.x, z - fireAt.z) < 1, this.pr, [
      { c: [-6, -3], r: 5, colors: [0, 1] }, { c: [8, 4], r: 4, colors: [2, 0] }, { c: [-14, 7], r: 4, colors: [3, 0, 6] },
      { c: [4, -9], r: 4, colors: [1, 4] }, { c: [-6, 22], r: 3, colors: [2, 5] }, { c: [7, 33], r: 3, colors: [1, 3] },
      { c: [16, -6], r: 6, colors: [3, 2, 6] }, { c: [-16, -5], r: 5, colors: [1, 0] }, { c: [0, -29], r: 7, colors: [0, 3, 6] },
      { c: [-24, 5], r: 4, colors: [3, 0] }, { c: [12, 15], r: 4, colors: [4, 1] }, { c: [-12, 30], r: 3, colors: [2, 1] },
    ]);

    sc.updateMatrixWorld(true);
    // luz: sol de fim de tarde + ambiente
    const sun = new THREE.DirectionalLight(0xffffff, 1.0);
    sun.castShadow = true;
    sun.shadow.mapSize.set(2048, 2048);
    Object.assign(sun.shadow.camera, { left: -22, right: 22, top: 22, bottom: -22, near: 1, far: 70 });
    sun.shadow.bias = -0.0006;
    sun.shadow.normalBias = 0.02;
    sc.add(sun, sun.target);
    this.sun = sun;
    // iluminação dinâmica: ciclo de dia + luzes pontuais
    this.lighting = new Lighting(sc, this.pr, sun);
    this.scenery.lamps.forEach((g) => { const p = g.userData.light.clone(); g.localToWorld(p); this.lighting.addStatic(p, 0xffa850, 6, 2.0, { flicker: 0.4 }); });
    sc.getObjectByName('Vila').children.forEach((h) => { if (h.userData.chimney) { const p = new THREE.Vector3(0, 1.0, 1.9); h.localToWorld(p); this.lighting.addStatic(p, 0xffc070, 3.2, 0.7); } });
    this.lighting.addStatic(new THREE.Vector3(fireAt.x, world.heightAt(fireAt.x, fireAt.z) + 0.5, fireAt.z), 0xff9a40, 5.5, 2.0, { flicker: 1, night: false });
    this.torches.forEach((t) => { const p = new THREE.Vector3(0, 1.75, 0); t.localToWorld(p); this.lighting.addStatic(p, 0xffa64a, 5, 1.9, { flicker: 1 }); });
    this.shafts = this.makeShafts();
    this.heroLight = this.lighting.addStatic(new THREE.Vector3(), 0xffd9a0, 3.2, 0.7, { flicker: 0.3 });
    // chaminés
    this.chimneys = [];
    sc.getObjectByName('Vila').children.forEach((h) => { if (h.userData.chimney) { const p = h.userData.chimney.clone(); h.localToWorld(p); this.chimneys.push(p); } });
    // junta geometria estática (vila, ruínas, ponte)
    sc.updateMatrixWorld(true);
    for (const o of [sc.getObjectByName('Vila'), sc.getObjectByName('Ruinas')]) mergeStatic(o);
    // trava da arena do chefe
    const ae = W(0, -21.6);
    this.arenaLock = this.world.addBox(ae.x, ae.z, 3.2, 0.3, Math.PI / 4);
    this.arenaLock.off = true;
    this.arenaVines = new THREE.Group();
    for (let i = 0; i < 11; i++) {
      const p = W(-2.8 + i * 0.56, -21.6 + Math.sin(i * 1.7) * 0.25);
      const v = new THREE.Mesh(new THREE.ConeGeometry(0.22, 1.5 + (i % 3) * 0.3, 5), toonMat({ color: i % 2 ? '#4f7d46' : '#5e8a3e', outline: 0.9 }));
      v.position.set(p.x, this.world.heightAt(p.x, p.z) + 0.6, p.z);
      v.rotation.z = (Math.random() - 0.5) * 0.4; v.castShadow = true;
      this.arenaVines.add(v);
    }
    this.arenaVines.visible = false;
    sc.add(this.arenaVines);
    const ac = W(0, -30);
    this.arenaCenter = new THREE.Vector3(ac.x, this.world.heightAt(ac.x, ac.z), ac.z);
    this.butterflies = this.makeButterflies();
  }

  // raios de luz entre as árvores (somados, em degraus de pixel), alinhados ao sol
  makeShafts() {
    const mat = new THREE.ShaderMaterial({
      transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, side: THREE.DoubleSide,
      uniforms: { uColor: { value: new THREE.Color() }, uAmt: { value: 0 }, uTime: shared.uTime, uNormalPass: shared.uNormalPass },
      vertexShader: 'varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }',
      fragmentShader: `uniform vec3 uColor; uniform float uAmt; uniform float uTime; uniform float uNormalPass; varying vec2 vUv;
        float bayer(vec2 fc){ ivec2 p = ivec2(mod(fc,4.0)); int i = p.x + p.y*4; int m[16] = int[16](0,8,2,10,12,4,14,6,3,11,1,9,15,7,13,5); return (float(m[i])+0.5)/16.0; }
        void main(){
          if (uNormalPass > 0.5) discard;
          float edge = smoothstep(0.0, 0.25, vUv.x) * smoothstep(1.0, 0.75, vUv.x);
          float len = smoothstep(0.0, 0.25, vUv.y) * smoothstep(1.0, 0.55, vUv.y);
          float stripe = 0.65 + 0.35 * step(0.5, fract(vUv.x * 2.5 + sin(uTime * 0.3 + vUv.y * 2.0) * 0.2));
          float a = edge * len * stripe * uAmt * (0.75 + 0.25 * sin(uTime * 0.8 + vUv.x * 6.0));
          a = floor(a * 4.0 + bayer(gl_FragCoord.xy) * 0.9) / 4.0;
          if (a <= 0.0) discard;
          gl_FragColor = vec4(uColor * a * 0.32, 1.0);
        }`,
    });
    const spots = [[-3, -17, 1.4], [3.5, -19, 1.1], [-5, -27, 1.6], [4, -31, 1.3], [-1, -34, 1.0], [6, -26, 0.9], [-14, -8, 1.2], [-19, 0, 1.0], [18, -9, 1.3], [21, 0, 1.0], [-12, 22, 1.0], [13, 29, 1.1], [-24, 7, 1.2], [9, -11, 1.0], [-7, -10, 0.9]];
    return spots.map(([u, v, w]) => {
      const m = new THREE.Mesh(new THREE.PlaneGeometry(1, 1).translate(0, 0.5, 0), mat);
      m.layers.set(1); m.renderOrder = 3; m.frustumCulled = false;
      const p = W(u, v);
      m.userData.base = new THREE.Vector3(p.x, this.world.heightAt(p.x, p.z), p.z);
      m.userData.w = w;
      this.scene.add(m);
      return m;
    });
  }
  updateShafts() {
    const L = this.lighting, d = L.sunDir, cam = this.pr.camDir;
    const amt = L.shaftAmt * (d.y > 0.1 ? 1 : 0);
    const m0 = this.shafts[0].material;
    m0.uniforms.uAmt.value = amt;
    m0.uniforms.uColor.value.copy(shared.uSunColor.value);
    if (amt <= 0) { this.shafts.forEach((s) => { s.visible = false; }); return; }
    const X = new THREE.Vector3().crossVectors(d, cam).normalize(), Z = new THREE.Vector3().crossVectors(X, d).normalize();
    const len = 7;
    for (const s of this.shafts) {
      s.visible = true;
      const m = new THREE.Matrix4().makeBasis(X.clone().multiplyScalar(s.userData.w), d.clone().multiplyScalar(len), Z);
      m.setPosition(s.userData.base);
      s.matrixAutoUpdate = false; s.matrix.copy(m); s.matrixWorldNeedsUpdate = true;
    }
  }

  makeButterflies() {
    const list = [];
    const cols = [0xf4d35e, 0xf6f1e0, 0x9db7f0, 0xef8fa8];
    const spots = [[-6, -3], [8, 4], [-14, 7], [-5, 22], [6, 31], [16, -6], [-24, 5], [3, -9]];
    spots.forEach((s, i) => {
      const g = new THREE.Group();
      for (const side of [-1, 1]) {
        const wgeo = new THREE.PlaneGeometry(0.16, 0.12); wgeo.translate(side * 0.08, 0, 0);
        const w = new THREE.Mesh(wgeo, unlitMat(cols[i % cols.length], { side: THREE.DoubleSide }));
        w.layers.set(1); g.add(w);
      }
      g.layers.set(1);
      const c = W(...s);
      this.scene.add(g);
      list.push({ g, c: new THREE.Vector3(c.x, this.world.heightAt(c.x, c.z) + 0.8, c.z), ph: Math.random() * 10 });
    });
    return list;
  }

  // ------------------------------------------------------------ personagens
  buildActors() {
    const P = PLACES;
    const npc = (def, at, facing = Math.PI / 4) => {
      const n = new NPC(this, def);
      const w = W(...at);
      n.place(w.x, w.z); n.facing = facing;
      if (def.mode !== 'wander') n.collider = this.world.addCircle(w.x, w.z, 0.38);
      this.npcs.push(n);
      this.interactables.push({ obj: n, pos: n.pos, label: 'Falar', r: 1.7, action: () => this.talkTo(n) });
      return n;
    };
    this.amora = npc({ name: 'Vó Amora', id: 'amora', wave: true, look: { skin: '#eec4a0', hair: '#cfc9dc', hairStyle: 'bun', tunic: '#7d5aa0', tunic2: '#5a3f78', pants: '#5a3f78', boots: '#4a3a3a', weapon: 'staff', belt: '#e8c36a', cape: '#5a3f78' } }, P.elder, Math.PI * 0.75);
    this.tiao = npc({ name: 'Tião', id: 'tiao', look: { skin: '#d9a47a', hair: '#3a2a2a', hairStyle: 'bald', hat: 'bandana', hatColor: '#d4553f', beard: '#4a3426', tunic: '#7a9a4a', tunic2: '#567034', pants: '#5e4a3a' } }, [P.merchant[0] + 0.4, P.merchant[1] + 2.1], Math.PI * 0.25);
    this.pipa = npc({ name: 'Pipa', id: 'pipa', mode: 'wander', look: { skin: '#f3c9a1', hair: '#e8b04a', hairStyle: 'short', tunic: '#e85d75', tunic2: '#b3405a', pants: '#4f7fa0', scarf: '#f6f1e0' } }, [3, 28]);
    this.bento = npc({ name: 'Seu Bento', id: 'bento', mode: 'sit', look: { skin: '#e0b088', hair: '#6b5a4a', hairStyle: 'bald', hat: 'bandana', hatColor: '#c9b48c', beard: '#e9e2cf', tunic: '#4f7fa0', tunic2: '#3a5f78', pants: '#5e4a3a' } }, (() => { const f = toUV(this.fire.position.x, this.fire.position.z); return [f.u + 1.1, f.v - 0.5]; })(), Math.PI * 0.95);
    this.rubi = npc({ name: 'Rubi', id: 'rubi', look: { skin: '#c98d6a', hair: '#2a2235', hairStyle: 'long', tunic: '#8a8fa8', tunic2: '#5f6480', pants: '#4b3d5e', weapon: 'sword', cape: '#d4553f', sleeve: '#8a8fa8' } }, [2.6, -13.2], Math.PI * 0.5);
    this.pipa.radius = 0.3;
    this.pipa.obj.scale.setScalar(0.82);

    // placas
    this.signs = [
      { at: [2.2, 16.5], lines: [{ text: '↑ Campo dos Ventos     ↓ Vila de Valebrisa\n← Lago do Pescador' }] },
      { at: [-2.4, -12.6], lines: [{ text: 'BOSQUE ANTIGO\nPerigo: o Toco Ancião não gosta de visitas.' }] },
    ];
    for (const s of this.signs) { const w = W(...s.at); this.interactables.push({ pos: new THREE.Vector3(w.x, this.world.heightAt(w.x, w.z), w.z), label: 'Ler', r: 1.5, action: () => this.say(s.lines) }); }

    // baú da runa
    const cw = W(18.6, -7.4);
    this.chest = new Chest(this, new THREE.Vector3(cw.x, this.world.heightAt(cw.x, cw.z), cw.z), Math.PI * 0.75, 'rune');
    this.chestVines = new THREE.Group();
    for (let i = 0; i < 9; i++) {
      const v = new THREE.Mesh(new THREE.TorusGeometry(0.35 + Math.random() * 0.15, 0.05, 4, 8), toonMat({ color: '#4f7d46', outline: 0.9 }));
      v.position.set(cw.x + (Math.random() - 0.5) * 0.3, this.chest.pos.y + 0.25 + Math.random() * 0.3, cw.z + (Math.random() - 0.5) * 0.3);
      v.rotation.set(Math.random() * 3, Math.random() * 3, 0);
      this.chestVines.add(v);
    }
    this.scene.add(this.chestVines);
    this.interactables.push({ pos: this.chest.pos, label: 'Abrir', r: 1.6, enabled: () => !this.chest.opened, action: () => this.openChest() });
    // portão
    const gate = this.scenery.gate;
    this.interactables.push({ pos: new THREE.Vector3(gate.x, this.world.heightAt(gate.x, gate.z), gate.z), label: 'Portão', r: 2.6, enabled: () => !this.quest.gate, action: () => this.useGate() });

    // acampamentos de inimigos
    this.camps = [
      { kind: 'slime', at: [-7, -1], n: 3 }, { kind: 'slime', at: [6, 1.5], n: 3 }, { kind: 'slime', at: [2, -8], n: 3 },
      { kind: 'slime', at: [-11, -9], n: 2 }, { kind: 'slime', at: [12, -1.5], n: 2 }, { kind: 'slime', at: [-18, 9], n: 2 },
      { kind: 'beetle', at: [-16.5, -4.5], n: 2 }, { kind: 'beetle', at: [-8, -11], n: 1 },
      { kind: 'mushroom', at: [17, -5], n: 5, hollow: true },
    ];
    for (const c of this.camps) this.spawnCamp(c);
    // chefe
    this.boss = new StumpBoss(this);
    this.boss.place(this.arenaCenter.x, this.arenaCenter.z);
    this.boss.facing = Math.PI / 4;
    this.bossCollider = this.world.addCircle(this.arenaCenter.x, this.arenaCenter.z, 1.35);
    this.bossCollider.off = true;
    this.bossRef = this.boss;
  }

  spawnCamp(c) {
    c.list = [];
    c.respawnT = 0;
    const base = W(...c.at);
    for (let i = 0; i < c.n; i++) {
      let x, z, tries = 0;
      do { const a = Math.random() * Math.PI * 2, r = 0.8 + Math.random() * 2.2; x = base.x + Math.cos(a) * r; z = base.z + Math.sin(a) * r; tries++; } while (!this.world.freeCircle(x, z, 0.6) && tries < 30);
      let e;
      if (c.kind === 'slime') e = new Slime(this);
      else if (c.kind === 'beetle') e = new Beetle(this);
      else {
        const big = i === 0;
        e = new Mushroom(this, big ? { hp: 95, exp: 30, name: 'Fungão-rei', cap: '#9b5fc0' } : { cap: i % 2 ? '#d4553f' : '#e2853f' });
        if (big) { e.baseScale = 1.35; e.radius = 0.6; e.big = true; }
      }
      e.place(x, z);
      e.facing = Math.random() * 6.28;
      e.camp = c;
      this.enemies.push(e);
      c.list.push(e);
    }
  }

  // ------------------------------------------------------------ salvar
  save() {
    const s = this.player.stats;
    storage.set({ stats: s, quest: this.quest, kills: this.kills, time: this.playTime });
  }
  loadOrNew(load) {
    const d = load ? storage.get() : null;
    if (d) {
      Object.assign(this.player.stats, d.stats);
      Object.assign(this.quest, d.quest);
      this.kills = d.kills || 0; this.playTime = d.time || 0;
      if (this.quest.rune) { this.chest.opened = true; this.chest.lid.rotation.x = -1.9; this.chestVines.visible = false; }
      if (this.quest.gate) this.openGateInstant();
      if (this.quest.boss) { this.boss.alive = false; this.boss.gone = true; this.boss.remove(); }
    }
    this.ui.setRune(this.quest.rune && !this.quest.gate);
    this.updateQuestText();
  }

  // ------------------------------------------------------------ missão
  updateQuestText() {
    const q = this.quest;
    const T = {
      0: ['Missão', 'Fale com a <em>Vó Amora</em> na praça da vila.'],
      1: ['Gosmas no campo', `Derrote gosmas no <em>Campo dos Ventos</em> (${Math.min(q.slimes, 6)}/6).`],
      2: ['Gosmas no campo', 'Volte e fale com a <em>Vó Amora</em>.'],
      3: ['A runa perdida', 'Encontre a <em>Runa do Bosque</em> no Vale dos Cogumelos, a leste do campo.'],
      4: ['O portão', 'Leve a runa ao <em>portão do Bosque Antigo</em>, ao norte.'],
      5: ['O Toco Ancião', 'Acalme o <em>Toco Ancião</em> na Clareira Antiga.'],
      6: ['Vitória', 'Volte à vila e conte tudo à <em>Vó Amora</em>.'],
      7: ['Livre', 'Explore Valebrisa à vontade. Obrigado por jogar!'],
    };
    const [t, txt] = T[q.stage];
    this.ui.setQuest(t, txt);
  }
  setStage(n) { this.quest.stage = n; this.updateQuestText(); sfx.quest(); this.save(); }

  async say(lines) {
    if (this.ui.inDialog) return;
    const prev = this.state;
    this.state = 'dialog';
    this.player.state = 'talk';
    await this.ui.dialog(lines);
    this.player.state = 'free';
    if (this.state === 'dialog') this.state = prev === 'dialog' ? 'play' : prev;
  }

  async talkTo(n) {
    n.talking = true;
    this.player.facing = this.player.angleTo(n.pos);
    const q = this.quest, s = this.player.stats;
    const A = (text) => ({ who: n.def.id === 'amora' ? 'amora' : n.def.id, name: n.name, text });
    const H = (text) => ({ who: 'hero', name: 'Nico', text });
    let lines;
    switch (n.def.id) {
      case 'amora':
        if (q.stage === 0) lines = [
          A('Nico! Que bom que acordou. O vento parou de soprar em Valebrisa desde ontem à noite.'),
          A('E sem vento as gosmas saíram da beira do rio e tomaram o Campo dos Ventos.'),
          H('Deixa comigo, vó! Pra que serve um aprendiz de guardião?'),
          A('Ha! Então leve sua espada. Ataque três vezes seguidas para um combo, e role para escapar dos pulos delas.'),
          A('Derrote seis gosmas e volte aqui. A ponte fica ao norte da praça.'),
        ];
        else if (q.stage === 1) lines = [A(`Ainda faltam ${6 - q.slimes} gosmas. Se apertar, beba uma poção (Q). O Tião vende mais na barraca.`)];
        else if (q.stage === 2) lines = [
          A('Você voltou inteirinho! Mas o vento continua parado...'),
          A('Só pode ser o Toco Ancião. Ele dorme no Bosque Antigo e, quando acorda de mau humor, prende o vento nas raízes.'),
          A('O portão do bosque só abre com a Runa do Bosque. Ela foi guardada num baú no Vale dos Cogumelos, a leste.'),
          H('Cogumelos... tipo os que soltam esporos roxos?'),
          A('Esses mesmos. Segure o botão de ataque para um giro carregado: funciona bem contra grupos.'),
        ];
        else if (q.stage === 3) lines = [A('O Vale dos Cogumelos fica a leste do campo, subindo a rampa de terra.')];
        else if (q.stage === 4) lines = [A('Você achou a runa! Leve-a ao portão ao norte. A Rubi está de guarda por lá.')];
        else if (q.stage === 5) lines = [A('Quando ele bater os galhos no chão, fique longe e depois ataque sem dó: ele fica tonto.')];
        else if (q.stage === 6) {
          lines = [A('Sinta isso... o vento voltou! Você conseguiu, Nico!'), A('O Toco Ancião só queria dormir em paz. Agora vai cochilar mais uns cem anos.'), H('E eu vou tirar um cochilo de uns cem minutos.')];
          await this.say(lines); n.talking = false;
          this.setStage(7);
          this.state = 'ending'; this.ui.endingScreen(); playMusic('vila');
          return;
        } else lines = [A('Valebrisa é sua casa, guardião. Volte sempre que quiser.')];
        break;
      case 'tiao':
        if (s.potions >= 5) lines = [A('Sua mochila já tá cheia de poção, campeão!')];
        else if (s.gold >= 15) { s.gold -= 15; s.potions++; sfx.coin(); lines = [A('Poção fresquinha, 15 moedas. Feita com framboesa do vale!'), A(`Pronto: agora você tem ${s.potions}.`)]; }
        else lines = [A('Poção por 15 moedas. As gosmas deixam umas moedinhas cair, sabia?')];
        break;
      case 'pipa':
        lines = [A(['Dizem que a lâmina de vento (L) atravessa vários inimigos de uma vez!', 'Quando eu crescer vou ser guardiã igual você!', 'Os besouros param tontos quando batem de cara numa pedra. Hihi.'][Math.floor(Math.random() * 3)])];
        break;
      case 'bento':
        if (!q.bentoGift) { q.bentoGift = true; s.potions = Math.min(5, s.potions + 1); lines = [A('Shhh... os peixes estão dormindo sem vento.'), A('Toma, leva esta poção. Um guardião precisa de fôlego.')]; sfx.potion(); }
        else lines = [A('Rolar na hora certa é como pescar: tudo é questão de tempo.')];
        break;
      case 'rubi':
        if (q.gate) lines = [A('Boa sorte lá dentro. Os avisos vermelhos no chão mostram onde ele vai atacar.')];
        else if (q.rune) lines = [A('Essa é a Runa do Bosque! Encoste-a no cadeado do portão.')];
        else lines = [A('Ninguém passa sem a Runa do Bosque. Ordens da Vó Amora.')];
        break;
    }
    await this.say(lines);
    n.talking = false;
    if (n.def.id === 'amora') {
      if (q.stage === 0) this.setStage(1);
      else if (q.stage === 2) this.setStage(3);
    }
  }

  openChest() {
    if (this.chest.opened) return;
    const hollowLeft = this.camps.find((c) => c.hollow).list.filter((e) => e.alive).length;
    if (hollowLeft > 0 && !this.quest.rune) {
      this.say([{ text: `Raízes prendem o baú. Os fungões do vale parecem controlá-las... (${hollowLeft} restantes)` }]);
      return;
    }
    this.chest.open();
    sfx.chest();
    this.lighting.flash(this.chest.pos.clone().add(new THREE.Vector3(0, 0.8, 0)), 0x7fe0c8, 5, 2, 1.6);
    this.fx.burst({ x: this.chest.pos.x, y: this.chest.pos.y + 0.6, z: this.chest.pos.z }, 24, { speed: 2.5, up: 3, g: -4, color: [0x7fe0c8, 0xffffff, 0xf2c14e], life: 0.9 });
    this.quest.rune = true;
    this.ui.setRune(true);
    this.ui.bigText('Runa do Bosque!', 'blue', 2.2);
    if (this.quest.stage <= 3) this.setStage(4);
  }

  useGate() {
    if (!this.quest.rune) { this.say([{ text: 'Um cadeado de madeira com uma runa desenhada. Está trancado.' }]); return; }
    this.quest.gate = true;
    this.ui.setRune(false);
    sfx.gate();
    this.shake(4);
    this.gateAnim = 0;
    this.scenery.gate.collider.off = true;
    if (this.quest.stage <= 4) this.setStage(5);
    this.ui.bigText('O portão se abriu', 'blue', 2);
  }
  openGateInstant() {
    const g = this.scenery.gate;
    g.collider.off = true; g.doors.children.forEach((l, i) => { l.rotation.y = (i === 0 ? 1 : -1) * 1.6; }); g.vines.visible = false; g.lock.visible = false;
  }

  tryInteract() {
    const p = this.player;
    const it = this.nearInteractable();
    if (!it) return false;
    it.action();
    return true;
  }
  nearInteractable() {
    const p = this.player;
    let best = null, bd = 1e9;
    for (const it of this.interactables) {
      if (it.enabled && !it.enabled()) continue;
      const d = Math.hypot(it.pos.x - p.pos.x, it.pos.z - p.pos.z);
      if (d < it.r && d < bd) { bd = d; best = it; }
    }
    return best;
  }

  // ------------------------------------------------------------ combate
  hittables() { return this.boss && this.boss.alive && this.boss.state !== 'dormant' && this.boss.state !== 'intro' && this.boss.lift > -1 ? [...this.enemies, this.boss] : this.enemies; }
  nearestEnemy(pos, r) {
    let best = null, bd = r;
    for (const e of this.hittables()) { if (!e.alive) continue; const d = Math.hypot(e.pos.x - pos.x, e.pos.z - pos.z); if (d < bd) { bd = d; best = e; } }
    return best;
  }

  hitEnemy(e, dmg, from, kb, crit) {
    if (!e.alive) return;
    if (e.state === 'stunned') dmg = Math.round(dmg * 1.5);
    e.hp -= dmg;
    e.flash = 0.09;
    e.aggro = true;
    if (e.kind !== 'boss') {
      const a = Math.atan2(e.pos.x - from.x, e.pos.z - from.z);
      const k = e.big ? kb * 0.4 : kb;
      e.kb.set(Math.sin(a) * k, 0, Math.cos(a) * k);
      if (e.state === 'windup' || e.state === 'puff') { e.state = 'chase'; e.cd = 0.8; e.st = 0; if (e.rig.parts.cap) e.rig.parts.cap.scale.setScalar(1); }
    }
    const hp = { x: e.pos.x, y: e.pos.y + (e.kind === 'boss' ? 1.4 : 0.5), z: e.pos.z };
    this.lighting.flash(new THREE.Vector3(hp.x, hp.y, hp.z), crit ? 0xffd27a : 0xfff0d0, crit ? 3.4 : 2.6, crit ? 1.6 : 1.0, 0.14);
    this.fx.hitSpark(hp, crit ? 0xfff2a8 : 0xffffff);
    this.fx.text(new THREE.Vector3(e.pos.x, e.pos.y + (e.kind === 'boss' ? 1.6 : 0), e.pos.z), String(dmg), crit ? 'crit' : '');
    this.hitstop = Math.max(this.hitstop, crit ? 0.085 : 0.05);
    this.shake(crit ? 2 : 1);
    crit ? sfx.crit() : sfx.hit();
    if (e.hp <= 0) this.killEnemy(e);
  }

  killEnemy(e) {
    e.alive = false; e.deathT = 0;
    this.kills++;
    sfx.die();
    const c = { coin: 0, n: 0 };
    void c;
    const col = e.kind === 'slime' ? [new THREE.Color(e.color).getHex(), 0xffffff, 0xd8f5e8] : e.kind === 'mushroom' ? [0xd4553f, 0xf6f1e0, 0xb98ad6] : e.kind === 'beetle' ? [0x6a4fa0, 0x3a2f4f, 0xffcf4a] : [0x7b5a48, 0x6e9d4c, 0xffb347];
    this.fx.burst({ x: e.pos.x, y: e.pos.y + 0.4, z: e.pos.z }, e.kind === 'boss' ? 60 : 16, { speed: e.kind === 'boss' ? 6 : 3.5, up: 4, g: -14, color: col, life: 0.8, size: 0.12, floor: e.pos.y + 0.05 });
    this.fx.ring(e.pos, { r0: 0.2, r1: 1.4, color: 0xffffff, life: 0.25, y: 0.3 });
    const [g0, g1] = e.gold;
    const gold = Math.round(g0 + Math.random() * (g1 - g0));
    const n = Math.min(10, Math.ceil(gold / 2));
    for (let i = 0; i < n; i++) this.pickups.push(new Pickup(this, 'coin', new THREE.Vector3(e.pos.x, e.pos.y + 0.5, e.pos.z), Math.ceil(gold / n)));
    if (Math.random() < 0.22) this.pickups.push(new Pickup(this, 'heart', new THREE.Vector3(e.pos.x, e.pos.y + 0.5, e.pos.z), 15));
    if (Math.random() < 0.2) this.pickups.push(new Pickup(this, 'orb', new THREE.Vector3(e.pos.x, e.pos.y + 0.5, e.pos.z), 12));
    this.fx.text(e.pos, `+${e.exp} EXP`, 'exp');
    this.player.gainExp(e.exp);
    if (e.kind === 'slime' && this.quest.stage === 1) {
      this.quest.slimes++;
      this.updateQuestText();
      if (this.quest.slimes >= 6) { this.setStage(2); this.ui.toast('Gosmas suficientes! Volte à Vó Amora.', 2.5); }
    }
    if (e.camp?.hollow && e.camp.list.every((x) => !x.alive)) {
      this.ui.toast('As raízes do baú se soltaram!', 2.5);
      sfx.quest();
      this.chestVines.visible = false;
    }
    if (e.kind === 'boss') this.onBossDeath(e);
  }

  damagePlayer(dmg, from) {
    const p = this.player;
    if (this.state !== 'play') return false;
    if (p.hurt(dmg, from)) { this.shake(3); this.hitstop = Math.max(this.hitstop, 0.06); this.pr.compMat.uniforms.uHitFlash.value = 0.25; return true; }
    return false;
  }

  usePotion() {
    const s = this.player.stats;
    if (s.potions <= 0) { sfx.deny(); this.ui.toast('Sem poções'); return; }
    if (s.hp >= s.maxHp) { this.ui.toast('Vida cheia'); return; }
    s.potions--;
    const heal = Math.round(s.maxHp * 0.5);
    s.hp = Math.min(s.maxHp, s.hp + heal);
    sfx.potion();
    this.lighting.flash(this.player.pos.clone().add(new THREE.Vector3(0, 0.6, 0)), 0x8ef0a0, 3.5, 1.4, 0.8, this.player.pos);
    this.fx.text(this.player.pos, '+' + heal, 'heal');
    this.fx.burst({ x: this.player.pos.x, y: this.player.pos.y + 0.3, z: this.player.pos.z }, 14, { speed: 1.2, up: 2.5, g: 1, color: [0x8ef0a0, 0xffffff, 0xef8fa8], life: 0.8, size: 0.08 });
  }

  collect(p) {
    const s = this.player.stats;
    if (p.kind === 'coin') { s.gold += p.value; sfx.coin(Math.random() * 4); }
    else if (p.kind === 'heart') { s.hp = Math.min(s.maxHp, s.hp + p.value); sfx.heart(); this.fx.text(this.player.pos, '+' + p.value, 'heal'); }
    else if (p.kind === 'orb') { s.ep = Math.min(s.maxEp, s.ep + p.value); sfx.heart(); }
  }

  onLevelUp() {
    sfx.levelup();
    this.lighting.flash(this.player.pos.clone().add(new THREE.Vector3(0, 0.8, 0)), 0xffd060, 5.5, 1.8, 1.0, null);
    this.ui.bigText(`Nível ${this.player.stats.level}!`, '', 2.2);
    const p = this.player.pos;
    this.fx.ring(p, { r0: 0.3, r1: 2.5, color: 0xf2c14e, life: 0.5, y: 0.1 });
    for (let i = 0; i < 30; i++) this.fx.particle({ x: p.x + (Math.random() - 0.5) * 1.2, y: p.y + Math.random() * 0.4, z: p.z + (Math.random() - 0.5) * 1.2 }, { vy: 2 + Math.random() * 2, life: 0.9, color: Math.random() < 0.5 ? 0xf2c14e : 0xffffff, size: 0.08, drag: 1 });
    this.save();
  }

  async onPlayerDeath() {
    this.state = 'dying';
    playMusic(null);
    await new Promise((r) => setTimeout(r, 1400));
    this.state = 'dead';
    this.ui.deathScreen();
  }

  async revive() {
    this.ui.hideScreen();
    await this.ui.fadeTo(true, 400);
    const p = this.player, s = p.stats;
    s.hp = s.maxHp; s.ep = s.maxEp; s.gold = Math.floor(s.gold * 0.8);
    p.state = 'free'; p.invuln = 1.5; p.kb.set(0, 0, 0);
    const w = W(...PLACES.spawn); p.place(w.x, w.z);
    this.resetBoss();
    for (const pr of this.projectiles) pr.kill();
    this.projectiles = [];
    for (const e of this.enemies) if (e.alive) { e.aggro = false; e.state = e.kind === 'mushroom' ? 'idle' : 'return'; e.hp = e.maxHp; }
    this.camTarget.copy(p.pos);
    this.state = 'play';
    this.area = null;
    await this.ui.fadeTo(false, 400);
  }

  resetBoss() {
    const b = this.boss;
    if (!b.alive) return;
    b.hp = b.maxHp; b.state = 'dormant'; b.phase = 1; b.pattern = 0; b.contact = false; b.obj.visible = false; b.lift = b.sinkY;
    b.place(this.arenaCenter.x, this.arenaCenter.z);
    this.arenaLock.off = true; this.arenaVines.visible = false; this.bossCollider.off = true;
    this.ui.hideBoss();
    for (const e of this.enemies) if (e.summoned && e.alive) { e.alive = false; e.gone = true; e.remove(); }
    for (const s of this.spikes) this.scene.remove(s.obj);
    this.spikes = [];
    this.fx.clear();
    this.bossFight = false;
  }

  // ------------------------------------------------------------ chefe
  onBossIntro(b) {
    this.bossFight = true;
    this.arenaLock.off = false; this.arenaVines.visible = true;
    sfx.roar();
    this.shake(6, 2.2);
    playMusic('chefe');
    this.ui.showBanner('Toco Ancião', 'Guardião do Bosque');
  }
  onBossReady(b) { this.ui.showBoss('TOCO ANCIÃO'); this.bossCollider.off = false; }
  onBossPhase2(b) {
    sfx.roar(); this.shake(5, 1);
    this.ui.toast('O Toco Ancião ficou furioso!', 2);
    for (let i = 0; i < 3; i++) {
      const a = (i / 3) * Math.PI * 2;
      const s = new Slime(this, { color: '#9b7fd0', hp: 22, exp: 4, gold: [0, 2] });
      s.place(this.arenaCenter.x + Math.cos(a) * 4, this.arenaCenter.z + Math.sin(a) * 4);
      s.summoned = true; s.aggro = true; s.leash = 30;
      this.enemies.push(s);
      this.fx.dust(s.pos, 6, 0x8a6a50);
    }
  }
  async onBossDeath(b) {
    this.bossCollider.off = true;
    this.quest.boss = true;
    this.hitstop = 0.4;
    this.shake(8, 1.5);
    sfx.roar();
    this.ui.hideBoss();
    for (const pr of this.projectiles) pr.kill();
    this.ui.bigText('Vitória!', '', 3);
    for (const e of this.enemies) if (e.summoned && e.alive) this.killEnemy(e);
    this.arenaLock.off = true; this.arenaVines.visible = false;
    this.bossFight = false;
    for (let i = 0; i < 6; i++) this.pickups.push(new Pickup(this, 'heart', new THREE.Vector3(b.pos.x, b.pos.y + 1, b.pos.z), 20));
    this.setStage(6);
    playMusic('campo');
    this.windBack = 1;
  }

  rootSpike(at, delay, dmg) {
    const y = this.world.heightAt(at.x, at.z);
    const pos = new THREE.Vector3(at.x, y, at.z);
    this.fx.telegraph(pos, 1.05, delay);
    this.later(delay, () => {
      if (!this.bossFight) return;
      const g = new THREE.Group();
      for (let i = 0; i < 4; i++) {
        const c = new THREE.Mesh(new THREE.ConeGeometry(0.2 + Math.random() * 0.1, 1.1 + Math.random() * 0.5, 5), toonMat({ color: i % 2 ? '#7b5a48' : '#6a4b3c', outline: 0.9 }));
        c.position.set((Math.random() - 0.5) * 0.8, 0.5, (Math.random() - 0.5) * 0.8); c.rotation.set((Math.random() - 0.5) * 0.5, 0, (Math.random() - 0.5) * 0.5); c.castShadow = true;
        g.add(c);
      }
      g.position.copy(pos); g.scale.y = 0.01;
      this.scene.add(g);
      this.spikes.push({ obj: g, t: 0 });
      sfx.root();
      this.fx.dust(pos, 5, 0x8a6a50);
      if (Math.hypot(this.player.pos.x - at.x, this.player.pos.z - at.z) < 1.1) this.damagePlayer(dmg, pos);
    });
  }
  bossSlam(b) {
    sfx.slam(); this.shake(7, 0.5);
    this.lighting.flash(b.pos.clone().add(new THREE.Vector3(0, 0.5, 0)), 0xffc070, 6, 1.4, 0.35);
    this.fx.ring(b.pos, { r0: 1, r1: 4.6, color: 0xfff2a8, life: 0.4, y: 0.15, width: 0.15 });
    this.fx.ring(b.pos, { r0: 0.5, r1: 3.6, color: 0xffffff, life: 0.3, y: 0.2, width: 0.25 });
    for (let i = 0; i < 24; i++) { const a = (i / 24) * Math.PI * 2; this.fx.dust({ x: b.pos.x + Math.cos(a) * 2.5, y: b.pos.y, z: b.pos.z + Math.sin(a) * 2.5 }, 1, 0x8a6a50); }
    if (this.player.distTo(b.pos) < 4.4) this.damagePlayer(22, b.pos);
  }
  bossEmerge(b) {
    sfx.slam(); this.shake(5, 0.4);
    this.fx.burst({ x: b.pos.x, y: b.pos.y + 0.3, z: b.pos.z }, 30, { speed: 4, up: 5, g: -14, color: [0x8a6a50, 0x6e9d4c, 0x7b5a48], life: 0.8, size: 0.12 });
    this.bossCollider.x = b.pos.x; this.bossCollider.z = b.pos.z;
    if (this.player.distTo(b.pos) < 2.0) this.damagePlayer(20, b.pos);
  }

  // ------------------------------------------------------------ projéteis
  spawnWindBlade(p) {
    const geo = new THREE.RingGeometry(0.45, 0.75, 10, 1, -1.1, 2.2); geo.rotateX(-Math.PI / 2);
    const g = new THREE.Group();
    const m = new THREE.Mesh(geo, unlitMat(0x7fe0c8, { side: THREE.DoubleSide }));
    const geo2 = new THREE.RingGeometry(0.6, 0.78, 10, 1, -0.9, 1.8); geo2.rotateX(-Math.PI / 2);
    const m2 = new THREE.Mesh(geo2, unlitMat(0xffffff, { side: THREE.DoubleSide })); m2.position.y = 0.01;
    g.add(m, m2); g.rotation.y = p.facing - Math.PI / 2;
    g.traverse((o) => o.layers.set(1));
    const dir = new THREE.Vector3(Math.sin(p.facing), 0, Math.cos(p.facing));
    const blade = new Projectile(this, { owner: 'player', mesh: g, pos: p.pos.clone().add(new THREE.Vector3(0, 0.6, 0)).addScaledVector(dir, 0.5), vel: dir.multiplyScalar(12), life: 0.75, radius: 0.6, pierce: true, dmg: Math.round(p.stats.atk * 1.4), trail: 0xbff5e8 });
    this.projectiles.push(blade);
    this.lighting.flash(blade.pos, 0x7fe0c8, 4, 1.6, 0.75, blade.pos);
  }
  spawnSpore(e, ang) {
    const m = new THREE.Mesh(new THREE.IcosahedronGeometry(0.16, 0), toonMat({ color: '#b98ad6', outline: 0.9, emissive: 0.5 }));
    const dir = new THREE.Vector3(Math.sin(ang), 0, Math.cos(ang));
    this.projectiles.push(new Projectile(this, { owner: 'enemy', mesh: m, pos: e.pos.clone().add(new THREE.Vector3(0, 0.75, 0)).addScaledVector(dir, 0.5), vel: dir.multiplyScalar(4.2), life: 2.4, radius: 0.22, dmg: e.dmg, spin: 3, trail: 0xd9b8ef }));
  }
  spawnSeed(b, ang) {
    const g = new THREE.Group();
    const nut = new THREE.Mesh(new THREE.IcosahedronGeometry(0.17, 0), toonMat({ color: '#b07a4a', outline: 0.95 }));
    const cap = new THREE.Mesh(new THREE.SphereGeometry(0.17, 6, 3, 0, Math.PI * 2, 0, Math.PI / 2), toonMat({ color: '#6b4a34', outline: 0.95 }));
    cap.position.y = 0.06; g.add(nut, cap);
    const dir = new THREE.Vector3(Math.sin(ang), 0, Math.cos(ang));
    this.projectiles.push(new Projectile(this, { owner: 'enemy', mesh: g, pos: b.pos.clone().add(new THREE.Vector3(0, 0.8, 0)).addScaledVector(dir, 1.6), vel: dir.multiplyScalar(5.2), life: 2.6, radius: 0.24, dmg: 12, spin: 6 }));
  }
  chargeLine(e) {
    const geo = new THREE.PlaneGeometry(0.9, 7); geo.rotateX(-Math.PI / 2); geo.translate(0, 0, 3.5);
    const m = new THREE.Mesh(geo, unlitMat(0xff4a4a, { transparent: true, opacity: 0.35, depthWrite: false }));
    m.layers.set(1); m.renderOrder = 2;
    this.scene.add(m);
    this.updateChargeLine(m, e);
    return m;
  }
  updateChargeLine(m, e) { if (!m) return; m.position.set(e.pos.x, e.pos.y + 0.07, e.pos.z); m.rotation.y = e.facing; m.material.opacity = 0.2 + (Math.floor(e.st * 10) % 2) * 0.2; }
  removeChargeLine(m) { if (m) { this.scene.remove(m); m.geometry.dispose(); } }

  surfaceDust(p) {
    const { u, v } = toUV(p.x, p.z);
    const m = this.world.maskAt(u, v);
    return m.path > 0.4 ? 0xd9b98a : m.sand > 0.4 ? 0xf0e0b0 : m.plaza > 0.4 ? 0xc8bcae : 0xa8d07a;
  }

  later(t, fn) { this.timers.push({ t, fn }); }
  shake(amp, dur = 0.25) { this.shakeAmp = Math.max(this.shakeAmp, amp); this.shakeT = Math.max(this.shakeT, dur); }

  // ------------------------------------------------------------ áreas
  areaAt(p) {
    const { u, v } = toUV(p.x, p.z);
    const d = (a) => Math.hypot(u - a[0], v - a[1]);
    if (v < -21.5) return ['clareira', 'Clareira Antiga', 'campo'];
    if (v < -13.5) return ['bosque', 'Trilha do Bosque Antigo', 'campo'];
    if (d(PLACES.hollow) < 7.5) return ['vale', 'Vale dos Cogumelos', 'campo'];
    if (d(PLACES.plateauW) < 7) return ['mirante', 'Mirante do Oeste', 'campo'];
    if (d(PLACES.pond) < 6) return ['lago', 'Lago do Pescador', 'campo'];
    if (v > 16) return ['vila', 'Vila de Valebrisa', 'vila'];
    return ['campo', 'Campo dos Ventos', 'campo'];
  }

  // ------------------------------------------------------------ menus
  onMenu(act) {
    switch (act) {
      case 'new': storage.clear(); this.startGame(false); break;
      case 'continue': this.startGame(true); break;
      case 'controls': this.prevScreen = this.state; this.ui.controlsScreen(); break;
      case 'back': if (this.state === 'title') this.ui.titleScreen(!!storage.get()); else this.ui.pauseScreen(); break;
      case 'resume': this.ui.hideScreen(); this.state = 'play'; break;
      case 'music': this.musicOn = toggleMusic(); this.ui.pauseScreen(); break;
      case 'pixels': { const o = [0, 2, 3, 4]; const pr = this.pr; pr.pixelScaleOverride = o[(o.indexOf(pr.pixelScaleOverride) + 1) % o.length]; pr.resize(); this.ui.applyScale(); this.ui.pauseScreen(); break; }
      case 'outlines': this.pr.outlines = !this.pr.outlines; this.ui.pauseScreen(); break;
      case 'time': {
        const keys = Object.keys(TIME_PRESETS);
        const i = (keys.indexOf(this.timeMode || 'ciclo') + 1) % keys.length;
        this.timeMode = keys[i];
        this.lighting.fixed = TIME_PRESETS[this.timeMode];
        this.ui.pauseScreen();
        break;
      }
      case 'restart': storage.clear(); location.reload(); break;
      case 'revive': this.revive(); break;
      case 'explore': this.ui.hideScreen(); this.state = 'play'; break;
    }
  }

  async startGame(load) {
    initAudio();
    this.ui.hideScreen();
    await this.ui.fadeTo(true, 350);
    if (load) this.loadOrNew(true);
    if (!this.timeMode) { this.lighting.fixed = null; this.lighting.hour = 8.0; }
    this.state = 'play';
    this.camTarget.copy(this.player.pos);
    this.area = null;
    await this.ui.fadeTo(false, 350);
    if (!load || this.quest.stage === 0) this.ui.toast('Fale com a Vó Amora (E)', 3);
  }

  // ------------------------------------------------------------ laço
  loop() {
    requestAnimationFrame(this.loop);
    this.clock.update();
    let dt = Math.min(FAST ? 0.3 : 0.05, this.clock.getDelta());
    const input = this.input;
    input.poll();
    const t = (shared.uTime.value += dt);

    if (input.consume('music')) this.musicOn = toggleMusic();
    if (input.consume('pause')) {
      if (this.state === 'play') { this.state = 'pause'; this.ui.pauseScreen(); }
      else if (this.state === 'pause') { this.state = 'play'; this.ui.hideScreen(); }
    }
    if (['title', 'pause', 'dead', 'ending'].includes(this.state)) this.ui.menuInput(input);
    if (this.state === 'dialog') { if (input.consume('confirm') || input.consume('interact')) this.ui.advance(); input.consume('attack'); input.consume('roll'); }

    const playing = this.state === 'play' || this.state === 'dialog' || this.state === 'dying';
    if (this.state === 'play') this.playTime += dt;
    // hitstop congela a simulação (não a câmera nem o tempo dos shaders)
    let simDt = dt;
    if (this.hitstop > 0) { this.hitstop -= dt; simDt = 0; }

    if (playing && simDt > 0) {
      // passos de no máximo 50 ms (estável mesmo com quadros lentos)
      let rest = simDt;
      while (rest > 1e-4) { const st = Math.min(0.05, rest); this.simulate(st, this.state === 'play' ? input : null); rest -= st; }
    }
    else if (this.state === 'title' || this.state === 'ending') this.ambient(dt);

    // câmera
    const p = this.player;
    let target;
    if (this.state === 'title') {
      this.titleT += dt;
      const a = W(Math.sin(this.titleT * 0.05) * 6, 24 + Math.sin(this.titleT * 0.08) * 4);
      target = new THREE.Vector3(a.x, 0.5, a.z);
    } else {
      target = p.pos.clone();
      target.y += 0.6;
      if (this.bossFight) target.lerp(this.arenaCenter, 0.3);
    }
    this.camTarget.lerp(target, 1 - Math.exp(-dt * (this.state === 'title' ? 1 : 6)));
    if (this.shakeT > 0) {
      this.shakeT -= dt;
      const a = Math.round(this.shakeAmp * Math.min(1, this.shakeT * 4));
      this.pr.shake.set(Math.round((Math.random() - 0.5) * 2 * a), Math.round((Math.random() - 0.5) * 2 * a));
    } else { this.pr.shake.set(0, 0); this.shakeAmp = 0; }
    this.pr.updateCamera(this.camTarget);
    // sombra acompanha a câmera presa a texels
    const sc = this.sun.shadow.camera;
    const texel = (sc.right - sc.left) / this.sun.shadow.mapSize.x;
    const c = this.camTarget;
    this.sun.target.position.set(Math.round(c.x / texel) * texel, 0, Math.round(c.z / texel) * texel);
    this.sun.position.copy(this.sun.target.position).addScaledVector(this.lighting.sunDir, 30);
    this.lighting.update(dt, this.camTarget);
    shared.uPlayer.value.copy(p.pos);
    this.heroLight.pos.set(p.pos.x, p.pos.y + 1.1, p.pos.z);
    this.updateShafts();
    this.ui.setClock(this.lighting.label(), this.lighting.isNight);
    // brilho de dano no pós
    const hf = this.pr.compMat.uniforms.uHitFlash;
    hf.value = Math.max(0, hf.value - dt * 2);
    const fade = this.pr.compMat.uniforms.uFade;
    fade.value = this.state === 'dying' ? Math.min(0.6, fade.value + dt * 0.6) : Math.max(0, fade.value - dt * 2);

    this.fx.update(dt);
    this.ui.update(dt);
    // prompt de interação
    if (this.state === 'play' && p.state === 'free') {
      const it = this.nearInteractable();
      if (it) { const pos = it.pos.clone(); pos.y += it.obj ? 1.9 : 1.6; this.ui.setPrompt(it.label, this.pr.project(pos)); } else this.ui.setPrompt(null);
    } else this.ui.setPrompt(null);

    this.pr.render(this.scene);
    input.endFrame();
  }

  ambient(dt) {
    const t = shared.uTime.value;
    for (const n of this.npcs) n.update(dt);
    for (const e of this.enemies) if (e.alive && e.state !== 'chase') e.update(dt);
    this.ambientFx(dt, t);
    this.player.update(dt, null);
  }

  ambientFx(dt, t) {
    // fumaça das chaminés
    for (const c of this.chimneys) if (Math.random() < dt * 5) this.fx.particle({ x: c.x + (Math.random() - 0.5) * 0.15, y: c.y, z: c.z }, { vy: 0.7, vx: 0.25, vz: -0.1, life: 2.2, size: 0.2, color: 0xe9e4f0, color2: 0x9a94b0, drag: 0.3, shrink: false });
    // pólen e folhas perto da câmera
    if (Math.random() < dt * 9) {
      const f = this.camTarget;
      const p = { x: f.x + (Math.random() - 0.5) * 22, y: f.y + 2 + Math.random() * 3, z: f.z + (Math.random() - 0.5) * 22 };
      const leaf = Math.random() < 0.35;
      this.fx.particle(p, { vx: 0.6 + Math.random() * 0.4, vy: leaf ? -0.4 : -0.1, vz: -0.3, life: 4, size: leaf ? 0.08 : 0.05, color: leaf ? [0x8bc45a, 0xe2b448, 0xd6913c][Math.floor(Math.random() * 3)] : 0xfff6d0, shrink: false });
    }
    // vagalumes (no bosque sempre, em todo lugar à noite) — brilham com bloom
    const { v } = toUV(this.camTarget.x, this.camTarget.z);
    const ffRate = (v < -12 ? 6 : 0) + this.lighting.lampsOn * 10;
    if (Math.random() < dt * ffRate) {
      const f = this.camTarget;
      this.fx.particle({ x: f.x + (Math.random() - 0.5) * 18, y: f.y + Math.random() * 1.5 - 0.3, z: f.z + (Math.random() - 0.5) * 18 }, { vx: (Math.random() - 0.5) * 0.4, vy: 0.15, vz: (Math.random() - 0.5) * 0.4, life: 3, size: 0.06, color: FIREFLY, shrink: false });
    }
    // fogo da fogueira e das tochas
    const fp = this.fire.position;
    if (Math.random() < dt * 30) this.fx.particle({ x: fp.x + (Math.random() - 0.5) * 0.3, y: fp.y + 0.15, z: fp.z + (Math.random() - 0.5) * 0.3 }, { vy: 1.4 + Math.random(), vx: (Math.random() - 0.5) * 0.3, life: 0.5, size: 0.14, color: FIRE_HOT, color2: FIRE_COOL, drag: 1 });
    if (Math.random() < dt * 4) this.fx.particle({ x: fp.x, y: fp.y + 0.6, z: fp.z }, { vy: 1.2, vx: 0.3, life: 1.6, size: 0.05, color: FIRE_HOT, drag: 0.5, shrink: false });
    if (Math.random() < dt * 3) this.fx.particle({ x: fp.x, y: fp.y + 0.8, z: fp.z }, { vy: 0.6, vx: 0.2, life: 2.5, size: 0.2, color: 0x8a8498, color2: 0x4a4658, drag: 0.3, shrink: false });
    for (const tc of this.torches) {
      if (Math.random() < dt * 14) { const q = tc.position; this.fx.particle({ x: q.x + (Math.random() - 0.5) * 0.1, y: q.y + 1.78, z: q.z + (Math.random() - 0.5) * 0.1 }, { vy: 1.0, life: 0.35, size: 0.09, color: FIRE_HOT, color2: FIRE_COOL }); }
      tc.userData.flame.scale.set(1 + Math.sin(t * 20 + tc.position.x) * 0.15, 1.4 + Math.sin(t * 13) * 0.25, 1);
    }
    // roupas no varal e luzes dos lampiões
    this.scenery.cloth.forEach((c, i) => { c.rotation.x = Math.sin(t * 2.2 + i) * 0.25 + 0.15; });
    // borboletas
    for (const b of this.butterflies) {
      const k = t * 0.6 + b.ph;
      b.g.position.set(b.c.x + Math.sin(k) * 1.6 + Math.sin(k * 2.3) * 0.4, b.c.y + Math.sin(k * 3.1) * 0.3, b.c.z + Math.cos(k * 0.8) * 1.6);
      b.g.rotation.y = Math.atan2(Math.cos(k) * 1.6, -Math.sin(k * 0.8) * 1.3);
      const flap = Math.floor(t * 14 + b.ph) % 2 ? 0.9 : -0.2;
      b.g.children[0].rotation.y = flap; b.g.children[1].rotation.y = -flap;
    }
    // portão abrindo
    if (this.gateAnim !== undefined && this.gateAnim < 1) {
      this.gateAnim = Math.min(1, this.gateAnim + dt * 0.8);
      const g = this.scenery.gate;
      g.doors.children.forEach((l, i) => { l.rotation.y = (i === 0 ? 1 : -1) * 1.6 * this.gateAnim; });
      g.vines.position.y = -this.gateAnim * 2.5; g.lock.visible = this.gateAnim < 0.2;
      if (Math.random() < 0.5) this.fx.dust({ x: g.x, y: this.world.heightAt(g.x, g.z), z: g.z }, 2, 0x6e9d4c);
    }
    // runas das ruínas pulsam
    const ruins = this.scene.getObjectByName('Ruinas');
    if (ruins) ruins.children.forEach((r, i) => { if (r.userData.rune) r.userData.rune.visible = Math.floor(t * 2 + i) % 5 !== 0; });
  }

  simulate(dt, input) {
    const t = shared.uTime.value;
    this.player.update(dt, input);
    for (const n of this.npcs) n.update(dt);
    for (const e of this.enemies) e.update(dt);
    this.enemies = this.enemies.filter((e) => !e.gone);
    // inimigos não se empilham
    const es = this.enemies;
    for (let i = 0; i < es.length; i++) for (let j = i + 1; j < es.length; j++) {
      const a = es[i], b = es[j];
      if (!a.alive || !b.alive) continue;
      const dx = b.pos.x - a.pos.x, dz = b.pos.z - a.pos.z, rr = a.radius + b.radius, d2 = dx * dx + dz * dz;
      if (d2 < rr * rr && d2 > 1e-6) {
        const d = Math.sqrt(d2), push = (rr - d) * 0.5;
        this.world.move(a.pos, -dx / d * push, -dz / d * push, a.radius);
        this.world.move(b.pos, dx / d * push, dz / d * push, b.radius);
      }
    }
    if (this.boss && !this.boss.gone) { this.boss.update(dt); this.bossCollider.x = this.boss.pos.x; this.bossCollider.z = this.boss.pos.z; }
    for (const p of this.projectiles) p.update(dt);
    this.projectiles = this.projectiles.filter((p) => p.alive);
    for (const p of this.pickups) p.update(dt);
    this.pickups = this.pickups.filter((p) => p.alive);
    this.chest.update(dt);
    for (const s of this.spikes) {
      s.t += dt;
      const k = s.t < 0.1 ? s.t / 0.1 : s.t < 0.7 ? 1 : Math.max(0, 1 - (s.t - 0.7) / 0.25);
      s.obj.scale.y = Math.max(0.01, k);
      if (s.t > 1) this.scene.remove(s.obj);
    }
    this.spikes = this.spikes.filter((s) => s.t <= 1);
    for (const tm of this.timers) { tm.t -= dt; if (tm.t <= 0) tm.fn(); }
    this.timers = this.timers.filter((tm) => tm.t > 0);
    // reaparecimento dos acampamentos
    for (const c of this.camps) {
      if (c.hollow || c.list.some((e) => e.alive)) continue;
      const base = W(...c.at);
      c.respawnT += dt;
      if (c.respawnT > 25 && Math.hypot(this.player.pos.x - base.x, this.player.pos.z - base.z) > 16) this.spawnCamp(c);
    }
    // áreas
    if (this.state === 'play') {
      const [id, name, music] = this.areaAt(this.player.pos);
      if (id !== this.area) {
        this.area = id;
        this.ui.showBanner(name);
        if (!this.bossFight) playMusic(music);
      }
    }
    this.ambientFx(dt, t);
  }
}

const game = new Game();
window.__game = game;
// passo determinístico para testes automatizados
window.__step = (n = 1, dt = 1 / 60) => {
  for (let i = 0; i < n; i++) { game.simulate(dt, game.state === 'play' ? game.input : null); game.input.endFrame(); }
};
