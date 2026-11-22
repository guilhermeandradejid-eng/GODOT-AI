import * as THREE from 'three';
import { EffectComposer } from 'three/addons/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/addons/postprocessing/RenderPass.js';
import { UnrealBloomPass } from 'three/addons/postprocessing/UnrealBloomPass.js';
import { OutputPass } from 'three/addons/postprocessing/OutputPass.js';
import { ShaderPass } from 'three/addons/postprocessing/ShaderPass.js';

import { buildLevel } from './level.js';
import { FX } from './fx.js';
import { Player } from './player.js';
import { Item } from './items.js';
import { TicketManager } from './tickets.js';
import { UI } from './ui.js';
import { devices, pollGamepads, keyPressed, endFrame } from './input.js';
import { sfx, initAudio, startMusic, toggleMusic } from './audio.js';
import { ROUND_SECONDS, STARS, TICKETS, PROBLEMS, PLAYER_COLORS, TEAM_SCALE } from './config.js';
import { iconImg, ICONS } from './icons.js';

const params = new URLSearchParams(location.search);

// ------------------------------------------------------------------ render
const renderer = new THREE.WebGLRenderer({ antialias: true, powerPreference: 'high-performance' });
renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
renderer.setSize(window.innerWidth, window.innerHeight);
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFShadowMap;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.05;
document.getElementById('app').appendChild(renderer.domElement);

const scene = new THREE.Scene();
scene.background = makeBackground();

const camera = new THREE.PerspectiveCamera(36, window.innerWidth / window.innerHeight, 0.5, 200);
const camTarget = new THREE.Vector3(0, 0, 0.9);
const CAM_PITCH = THREE.MathUtils.degToRad(57);

const hemi = new THREE.HemisphereLight(0xe4eeff, 0x7a6a58, 1.35);
scene.add(hemi);
const sun = new THREE.DirectionalLight(0xfff0d8, 2.7);
sun.position.set(-9, 20, 12);
sun.target.position.set(0, 0, 0);
sun.castShadow = true;
sun.shadow.mapSize.set(2048, 2048);
Object.assign(sun.shadow.camera, { left: -17, right: 17, top: 13, bottom: -13, near: 1, far: 60 });
sun.shadow.bias = -0.0004;
sun.shadow.normalBias = 0.03;
sun.shadow.radius = 3;
scene.add(sun, sun.target);
const windowLight = new THREE.DirectionalLight(0xbfe0ff, 0.6);
windowLight.position.set(2, 6, -14);
scene.add(windowLight);

const rt = new THREE.WebGLRenderTarget(1, 1, { type: THREE.HalfFloatType, samples: 4 });
const composer = new EffectComposer(renderer, rt);
composer.addPass(new RenderPass(scene, camera));
// limpa pixels NaN/Inf (brilhos especulares extremos) antes do bloom, senão viram "manchas" brancas
composer.addPass(new ShaderPass({
  uniforms: { tDiffuse: { value: null } },
  vertexShader: 'varying vec2 vUv; void main() { vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }',
  fragmentShader: `uniform sampler2D tDiffuse; varying vec2 vUv;
    void main() { vec4 c = texture2D(tDiffuse, vUv);
      if (any(isnan(c)) || any(isinf(c))) c = vec4(0.0, 0.0, 0.0, 1.0);
      gl_FragColor = vec4(clamp(c.rgb, 0.0, 16.0), c.a); }`,
}));
const bloom = new UnrealBloomPass(new THREE.Vector2(256, 256), 0.55, 0.5, 0.92);
if (!params.has('nobloom')) composer.addPass(bloom);
composer.addPass(new OutputPass());

function makeBackground() {
  const c = document.createElement('canvas'); c.width = 512; c.height = 512;
  const g = c.getContext('2d');
  const grd = g.createRadialGradient(256, 200, 40, 256, 256, 420);
  grd.addColorStop(0, '#34407a'); grd.addColorStop(1, '#141a33');
  g.fillStyle = grd; g.fillRect(0, 0, 512, 512);
  g.fillStyle = 'rgba(255,255,255,0.05)';
  for (let y = 0; y < 512; y += 24) for (let x = (y / 24) % 2 ? 12 : 0; x < 512; x += 24) { g.beginPath(); g.arc(x, y, 2.2, 0, Math.PI * 2); g.fill(); }
  const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace;
  return t;
}

function fitCamera() {
  const w = window.innerWidth, h = window.innerHeight;
  renderer.setSize(w, h);
  composer.setSize(w, h);
  camera.aspect = w / h;
  const vfov = THREE.MathUtils.degToRad(camera.fov);
  const hfov = 2 * Math.atan(Math.tan(vfov / 2) * camera.aspect);
  const halfW = 13.2, halfD = 9.2;
  const dW = halfW / Math.tan(hfov / 2);
  const dD = (halfD * Math.sin(CAM_PITCH) + 1.5) / Math.tan(vfov / 2);
  game.camDist = Math.max(dW, dD) * 1.06;
  // empurra a imagem para baixo, abrindo espaço para os cartões de chamado no topo
  camera.setViewOffset(w, h, 0, -Math.min(60, h * 0.06), w, h);
  camera.updateProjectionMatrix();
}

// ------------------------------------------------------------------ jogo
const level = buildLevel(scene);
const fx = new FX(scene);
const ui = new UI(camera, renderer);

const game = {
  scene, fx, sfx, ui,
  colliders: level.colliders,
  stations: level.stations,
  desks: level.desks,
  items: [],
  players: [],
  tickets: null,
  state: 'menu',
  time: 0,
  score: 0,
  streak: 0,
  stats: { resolved: 0, failed: 0, byType: {} },
  camDist: 30,
  shake: 0,
  countdown: 0,
  joined: [],
  addProgress, onTicketOpened, onTicketResolved, onTicketFailed,
  spawnItem(kind, pos) { const it = new Item(kind, scene, pos); game.items.push(it); return it; },
};
window.__game = game;
fitCamera();
window.addEventListener('resize', fitCamera);

function resetWorld() {
  for (const it of game.items) it.destroy();
  game.items = [];
  for (const p of game.players) p.root.removeFromParent();
  game.players = [];
  for (const s of game.stations) if (s.problem) s.clearProblem(true);
  for (const s of game.stations) { s.mood = 'work'; s.moodT = 99; }
  for (const sp of level.itemSpawns) game.items.push(new Item(sp.kind, scene, sp.pos.clone()));
  ui.clearAll();
}

function startRound() {
  initAudio(); startMusic();
  resetWorld();
  if (!game.joined.length) game.joined.push(devices.kbA);
  game.players = game.joined.map((d, i) => new Player(i, d, scene, level.spawn[i]));
  ui.setPlayers(game.players);
  game.goals = STARS.map((s) => Math.round(s * TEAM_SCALE.stars[game.players.length - 1] / 50) * 50);
  ui.setGoals(game.goals);
  game.tickets = new TicketManager(game);
  game.score = 0; game.streak = 0;
  game.stats = { resolved: 0, failed: 0, byType: {} };
  ui.setScore(0); ui.setClock(0);
  game.state = 'countdown'; game.countdown = 3.2;
  show('hud'); hide('menu'); hide('results'); hide('pause');
}

function addProgress(station, player, dt) {
  const pr = station.problem; if (!pr) return;
  pr.progress += dt;
  player._tick = (player._tick || 0) + dt;
  if (player._tick > 0.13) { player._tick = 0; sfx.tick(); }
  if (pr.progress >= pr.def.hold) {
    if (pr.def.consume && player.held?.kind === pr.def.item) {
      const it = player.held; player.held = null; it.destroy();
    }
    game.tickets.resolve(station, player);
  }
}

function onTicketOpened(t) {
  ui.addTicket(t);
  if (t.type === 'fire') { sfx.alarm(); ui.showBanner('FOGO NA ' + t.station.name.toUpperCase() + '!', 'danger'); }
  else if (t.type === 'router') { sfx.alarm(); ui.showBanner('INTERNET CAIU!', 'danger'); }
  else sfx.ring();
  if (t.vip) ui.showBanner('★ Chamado VIP do diretor!', 'vip');
}

function onTicketResolved(t, player) {
  const f = Math.max(0, t.remaining / t.sla);
  const bonus = Math.round(60 * f);
  game.streak++;
  const streakBonus = Math.min(5, game.streak - 1) * 10;
  const pts = t.reward + bonus + streakBonus;
  game.score += pts;
  game.stats.resolved++;
  game.stats.byType[t.type] = (game.stats.byType[t.type] || 0) + 1;
  ui.removeTicket(t, true);
  ui.setScore(game.score);
  const mp = t.station.markerPos(new THREE.Vector3());
  ui.floatText(mp, `+${pts}`, '#ffd23f', true);
  if (game.streak >= 3) ui.floatText(mp.clone().add(new THREE.Vector3(0, -0.6, 0)), `Combo x${game.streak}!`, '#7fe3ff');
  fx.confetti(mp.clone().add(new THREE.Vector3(0, -0.6, 0)));
  sfx.resolve();
}

function onTicketFailed(t) {
  game.score = Math.max(0, game.score - TICKETS.failPenalty);
  game.streak = 0;
  game.stats.failed++;
  ui.removeTicket(t, false);
  ui.setScore(game.score);
  ui.floatText(t.station.markerPos(new THREE.Vector3()), `SLA estourado! -${TICKETS.failPenalty}`, '#ff5a5a', true);
  sfx.fail();
  game.shake = 0.35;
}

function endRound() {
  game.state = 'ending';
  sfx.whistle();
  ui.showBanner('Fim do expediente!', '', 2000);
  setTimeout(showResults, 1800);
}

function showResults() {
  game.state = 'results';
  const stars = game.goals.filter((s) => game.score >= s).length;
  ui.clearAll(); ui.setNetDown(false);
  for (const h of ui.hints) h.classList.add('empty');
  const el = document.getElementById('results');
  el.querySelector('.res-stars').innerHTML = [0, 1, 2].map((i) => `<span class="rstar ${i < stars ? 'on' : ''}" style="animation-delay:${0.3 + i * 0.35}s">${ICONS.star}</span>`).join('');
  el.querySelector('.res-score').textContent = game.score;
  const total = game.stats.resolved + game.stats.failed;
  const sla = total ? Math.round((game.stats.resolved / total) * 100) : 100;
  const msg = stars === 3 ? 'Promoção! A TI é a melhor equipe da empresa.' : stars === 2 ? 'Bom trabalho! Só alguns usuários reclamaram no RH.' : stars === 1 ? 'Sobreviveu... mas o diretor quer uma reunião.' : 'Demitidos! (brincadeira, tentem de novo)';
  el.querySelector('.res-msg').textContent = msg;
  el.querySelector('.res-stats').innerHTML = `
    <div><b>${game.stats.resolved}</b><span>chamados resolvidos</span></div>
    <div><b>${game.stats.failed}</b><span>SLA estourados</span></div>
    <div><b>${sla}%</b><span>dentro do SLA</span></div>`;
  el.querySelector('.res-goals').innerHTML = game.goals.map((s, i) => `<span class="${game.score >= s ? 'ok' : ''}">${'★'.repeat(i + 1)} ${s}</span>`).join('');
  show('results'); hide('hud');
}

// ------------------------------------------------------------------ menus
function show(id) { document.getElementById(id).classList.remove('hidden'); }
function hide(id) { document.getElementById(id).classList.add('hidden'); }

function buildMenu() {
  const how = document.getElementById('how');
  how.innerHTML = Object.entries(PROBLEMS).map(([k, d]) => `
    <div class="how-row">${iconImg(d.icon, 30)}<div><b>${d.title}</b><span>${{
      cable: 'Pegue um cabo na Sala de TI e troque na mesa',
      virus: 'Leve o pendrive antivírus da bancada e segure para escanear',
      paper: 'Pegue papel no Almoxarifado',
      jam: 'Segure para desemperrar (2 técnicos = 2x mais rápido)',
      fire: 'Pegue um extintor e borrife!',
      router: 'Corra ao rack e reinicie — sem internet o SLA corre mais rápido',
    }[k]}</span></div></div>`).join('');
  renderSlots();
}

function renderSlots() {
  const el = document.getElementById('slots');
  el.innerHTML = [0, 1, 2, 3].map((i) => {
    const d = game.joined[i];
    const c = '#' + PLAYER_COLORS[i].shirt.toString(16).padStart(6, '0');
    return d
      ? `<div class="slot on" style="--pc:${c}"><div class="slot-face">${iconImg('hand', 40)}</div><b>Técnico ${i + 1}</b><span>${d.label}</span><small>${d.hint}</small></div>`
      : `<div class="slot" style="--pc:${c}"><div class="slot-face">?</div><b>Vaga ${i + 1}</b><span>Pressione <kbd>E</kbd>, <kbd>Enter</kbd> ou <kbd>A</kbd> no controle</span></div>`;
  }).join('');
  document.getElementById('start-btn').textContent = game.joined.length ? `Começar expediente (${game.joined.length} técnico${game.joined.length > 1 ? 's' : ''})` : 'Começar sozinho';
}

document.getElementById('start-btn').addEventListener('click', () => { initAudio(); startRound(); });
document.getElementById('again-btn').addEventListener('click', () => startRound());
document.getElementById('menu-btn').addEventListener('click', () => { game.state = 'menu'; resetWorld(); hide('results'); hide('hud'); show('menu'); renderSlots(); });
document.getElementById('resume-btn').addEventListener('click', () => togglePause());
document.getElementById('music-btn').addEventListener('click', (e) => { e.target.textContent = toggleMusic() ? 'Música: ligada' : 'Música: desligada'; });
document.addEventListener('pointerdown', () => initAudio(), { once: true });

function togglePause() {
  if (game.state === 'playing') { game.state = 'paused'; show('pause'); }
  else if (game.state === 'paused') { game.state = 'playing'; hide('pause'); }
}

buildMenu();

// ------------------------------------------------------------------ loop
const timer = new THREE.Timer();
const inputs = new Map();
const NO_INPUT = { x: 0, z: 0, grab: false, use: false, usePressed: false, dash: false, join: false, start: false };
game.inputOverride = {}; // testes: __game.inputOverride.kbA = { x: 1, ... }

function readInputs() {
  pollGamepads();
  inputs.clear();
  for (const d of Object.values(devices)) inputs.set(d, game.inputOverride[d.id] ? { ...NO_INPUT, ...game.inputOverride[d.id] } : d.read());
}

function update(dt) {
  game.time += dt;
  if (game.state === 'menu') {
    for (const [d, inp] of inputs) {
      if (inp.join && !game.joined.includes(d) && game.joined.length < 4) { game.joined.push(d); initAudio(); sfx.pickup(); renderSlots(); }
    }
    if (keyPressed('Space') || [...inputs.values()].some((i) => i.start)) startRound();
  } else if (game.state === 'results') {
    if (keyPressed('Space') || [...inputs.values()].some((i) => i.start)) startRound();
  }
  if (keyPressed('Escape') || [...inputs.values()].some((i) => i.start && (game.state === 'playing' || game.state === 'paused'))) togglePause();
  if (keyPressed('KeyM')) toggleMusic();

  if (game.state === 'countdown') {
    const before = Math.ceil(game.countdown);
    game.countdown -= dt;
    const after = Math.ceil(game.countdown);
    if (after !== before && after > 0) { ui.showBanner(String(after), 'count', 800); sfx.countdown(false); }
    if (game.countdown <= 0) { game.state = 'playing'; ui.showBanner('Expediente começou!', 'go', 1200); sfx.countdown(true); }
  }
  if (game.state === 'paused') return;

  if (game.state === 'playing') {
    game.tickets.update(dt);
    ui.setClock(game.tickets.elapsed);
    ui.setNetDown(game.tickets.routerDown);
    if (game.tickets.elapsed >= ROUND_SECONDS) endRound();
  }
  for (const p of game.players) p.update(dt, inputs.get(p.device) || NO_INPUT, game);
  // empurra jogadores entre si (e o dash derruba!)
  for (let i = 0; i < game.players.length; i++) for (let j = i + 1; j < game.players.length; j++) {
    const a = game.players[i], b = game.players[j];
    const dx = b.pos.x - a.pos.x, dz = b.pos.z - a.pos.z, d = Math.hypot(dx, dz), m = 0.8;
    if (d < m && d > 1e-4) {
      const push = (m - d) / 2, nx = dx / d, nz = dz / d;
      a.pos.x -= nx * push; a.pos.z -= nz * push; b.pos.x += nx * push; b.pos.z += nz * push;
      for (const [x, y, s] of [[a, b, 1], [b, a, -1]]) if (x.dashT > 0 && y.stun <= 0) {
        y.vel.set(nx * 7 * s, 0, nz * 7 * s); y.stun = 0.35; y.squash = 0.8; sfx.drop();
        fx.puff(y.pos.clone().setY(0.6), 8, 0xffffff);
      }
    }
  }
  for (const it of game.items) it.update(dt, game);
  game.items = game.items.filter((i) => i.alive);
  for (const s of game.stations) s.update(dt, game.time, fx);
  fx.update(dt);

  // relógio de parede
  const el = game.tickets && game.state !== 'menu' ? game.tickets.elapsed : 0;
  const hours = 9 + 9 * Math.min(1, el / ROUND_SECONDS);
  level.clockHands[2].children[0].rotation.z = -(hours % 12) / 12 * Math.PI * 2;
  level.clockHands[2].children[1].rotation.z = -(hours % 1) * Math.PI * 2;

  // câmera: leve acompanhamento do grupo + tremida
  let cx = 0, cz = 0;
  if (game.players.length) { for (const p of game.players) { cx += p.pos.x; cz += p.pos.z; } cx /= game.players.length; cz /= game.players.length; }
  const tx = cx * 0.08, tz = 0.9 + cz * 0.05;
  camTarget.x += (tx - camTarget.x) * Math.min(1, dt * 2);
  camTarget.z += (tz - camTarget.z) * Math.min(1, dt * 2);
  game.shake = Math.max(0, game.shake - dt);
}

function render() {
  const menuSway = game.state === 'menu' ? Math.sin(game.time * 0.25) * 0.8 : 0;
  const sh = game.shake * 0.6;
  camera.position.set(camTarget.x + menuSway + (Math.random() - 0.5) * sh, Math.sin(CAM_PITCH) * game.camDist, camTarget.z + Math.cos(CAM_PITCH) * game.camDist + (Math.random() - 0.5) * sh);
  camera.lookAt(camTarget.x + menuSway * 0.5, 0, camTarget.z);
  const active = game.state === 'playing' || game.state === 'countdown' || game.state === 'ending';
  if (game.tickets && active) ui.updateTickets(game.tickets.open);
  ui.updateHints(game.players);
  composer.render();
}

function frame(ts) {
  requestAnimationFrame(frame);
  timer.update(ts);
  if (game.freeze) return; // testes: congela a imagem para capturas
  const dt = Math.min(0.05, timer.getDelta());
  readInputs();
  update(dt);
  render();
  endFrame();
}

// avança a simulação sem depender do FPS (usado nos testes headless)
window.__step = (n = 60, draw = false, dt = 1 / 60) => { for (let i = 0; i < n; i++) { readInputs(); update(dt); endFrame(); } if (draw) render(); return game.state; };

// modo automático (testes/screenshots): ?auto=2 inicia com 2 jogadores; ?demo=1 abre vários chamados
if (params.get('auto')) {
  const n = Number(params.get('auto')) || 1;
  game.joined = [devices.kbA, devices.kbB].slice(0, Math.min(2, n));
  startRound();
  game.countdown = 0.01;
  if (params.get('demo')) {
    setTimeout(() => {
      const T = game.tickets;
      T.elapsed = 60; T.script = [];
      const desks = game.desks;
      T.spawn('virus', desks[1]); T.spawn('cable', desks[6]); T.spawn('fire', game.stations.find((s) => s.name === 'Impressora 1'));
      T.spawn('jam', game.stations.find((s) => s.name === 'Impressora 2')); T.spawn('router');
      T.open.forEach((t, i) => { t.remaining = t.sla * (0.9 - i * 0.17); });
      const p = game.players[0];
      p.pos.set(5.6, 0, -5.4); p.angle = 2.5;
      p.grab(game.items[1], game);
      if (game.players[1]) { game.players[1].pos.set(-1.6, 0, -3.4); game.players[1].angle = Math.PI; }
    }, 200);
  }
}

requestAnimationFrame(frame);
