import * as THREE from 'three';
import { iconImg, ICONS } from './icons.js';
import { STARS, START_HOUR, END_HOUR, ROUND_SECONDS, ITEMS } from './config.js';

const $ = (sel) => document.querySelector(sel);
const _v = new THREE.Vector3();

export class UI {
  constructor(camera, renderer) {
    this.camera = camera;
    this.renderer = renderer;
    this.ticketsEl = $('#tickets');
    this.markersEl = $('#markers');
    this.cards = new Map();
    this.markers = new Map();
    this.hints = [];
    this.scoreEl = $('#score-value');
    this.clockEl = $('#clock-time');
    this.starsFill = $('#stars-fill');
    this.starsEls = [...document.querySelectorAll('#stars-bar .star')];
    this.banner = $('#banner');
    this.netAlert = $('#net-alert');
    this.setGoals(STARS);
  }

  project(p) {
    _v.copy(p).project(this.camera);
    const r = this.renderer.domElement.getBoundingClientRect();
    return { x: (_v.x * 0.5 + 0.5) * r.width + r.left, y: (-_v.y * 0.5 + 0.5) * r.height + r.top, behind: _v.z > 1 };
  }

  setGoals(goals) {
    this.goals = goals;
    this.starsEls.forEach((el, i) => { el.innerHTML = ICONS.star; el.style.left = `${(goals[i] / goals[2]) * 100}%`; });
  }

  // ------------------------------------------------------------ cartões
  addTicket(t) {
    const el = document.createElement('div');
    el.className = 'card enter' + (t.vip ? ' vip' : '');
    el.innerHTML = `
      <div class="card-icon">${iconImg(t.def.icon, 34)}</div>
      <div class="card-body">
        <div class="card-title">${t.def.title}</div>
        <div class="card-who">${t.vip ? '★ VIP · ' : ''}${t.who}${t.def.item ? ` · <span class="need">${iconImg(ITEMS[t.def.item].icon, 14)} ${ITEMS[t.def.item].label}</span>` : ''}</div>
        <div class="sla"><div class="sla-fill"></div></div>
      </div>
      <div class="card-id">#${String(1000 + t.id)}</div>`;
    this.ticketsEl.appendChild(el);
    requestAnimationFrame(() => el.classList.remove('enter'));
    this.cards.set(t.id, { el, fill: el.querySelector('.sla-fill') });

    const m = document.createElement('div');
    m.className = 'marker' + (t.vip ? ' vip' : '');
    m.innerHTML = `
      <svg class="ring" viewBox="0 0 64 64"><circle cx="32" cy="32" r="28" class="ring-bg"/><circle cx="32" cy="32" r="28" class="ring-fg"/></svg>
      <div class="marker-icon">${iconImg(t.def.icon, 34)}</div>
      <div class="marker-progress"><div></div></div>`;
    this.markersEl.appendChild(m);
    this.markers.set(t.id, { el: m, ring: m.querySelector('.ring-fg'), prog: m.querySelector('.marker-progress'), bar: m.querySelector('.marker-progress div'), t });
  }

  removeTicket(t, success) {
    const c = this.cards.get(t.id);
    if (c) {
      c.el.classList.add(success ? 'done' : 'failed');
      setTimeout(() => c.el.remove(), 650);
      this.cards.delete(t.id);
    }
    const m = this.markers.get(t.id);
    if (m) { m.el.classList.add(success ? 'pop' : 'failed'); setTimeout(() => m.el.remove(), 500); this.markers.delete(t.id); }
  }

  updateTickets(open) {
    for (const t of open) {
      const c = this.cards.get(t.id); if (!c) continue;
      const f = Math.max(0, t.remaining / t.sla);
      c.fill.style.width = `${f * 100}%`;
      c.fill.style.background = slaColor(f);
      c.el.classList.toggle('urgent', f < 0.25);
      const m = this.markers.get(t.id);
      const sp = this.project(t.station.markerPos(_v.set(0, 0, 0)));
      m.el.style.transform = `translate(${sp.x}px, ${sp.y}px) translate(-50%, -50%)`;
      const C = 2 * Math.PI * 28;
      m.ring.style.strokeDasharray = `${C}`;
      m.ring.style.strokeDashoffset = `${C * (1 - f)}`;
      m.ring.style.stroke = slaColor(f);
      m.el.classList.toggle('urgent', f < 0.25);
      const pr = t.station.problem;
      const pf = pr ? pr.progress / pr.def.hold : 0;
      m.prog.style.opacity = pf > 0 ? 1 : 0;
      m.bar.style.width = `${Math.min(1, pf) * 100}%`;
    }
  }

  // ------------------------------------------------------------ dicas por jogador
  setPlayers(players) {
    this.hints.forEach((h) => h.remove());
    this.hints = players.map((p) => {
      const el = document.createElement('div');
      el.className = 'hint';
      el.style.setProperty('--pc', '#' + p.color.shirt.toString(16).padStart(6, '0'));
      el.innerHTML = `<span class="tag">P${p.index + 1}</span><span class="txt"></span>`;
      this.markersEl.appendChild(el);
      return el;
    });
  }
  updateHints(players) {
    players.forEach((p, i) => {
      const el = this.hints[i]; if (!el) return;
      const sp = this.project(_v.copy(p.pos).setY(1.95));
      el.style.transform = `translate(${sp.x}px, ${sp.y}px) translate(-50%, -100%)`;
      const txt = el.querySelector('.txt');
      if (txt.textContent !== p.hint) txt.textContent = p.hint;
      el.classList.toggle('empty', !p.hint);
      el.classList.toggle('deny', p.hint.startsWith('Precisa'));
    });
  }

  // ------------------------------------------------------------ textos flutuantes
  floatText(worldPos, text, color = '#fff', big = false) {
    const sp = this.project(worldPos);
    const el = document.createElement('div');
    el.className = 'float' + (big ? ' big' : '');
    el.textContent = text;
    el.style.color = color;
    el.style.left = sp.x + 'px'; el.style.top = sp.y + 'px';
    document.body.appendChild(el);
    setTimeout(() => el.remove(), 1400);
  }

  // ------------------------------------------------------------ placar/relógio
  setScore(score) {
    this.scoreEl.textContent = score;
    this.scoreEl.classList.remove('bump'); void this.scoreEl.offsetWidth; this.scoreEl.classList.add('bump');
    const G = this.goals;
    const f = Math.max(0, Math.min(1, score / G[2]));
    this.starsFill.style.width = `${f * 100}%`;
    this.starsEls.forEach((el, i) => el.classList.toggle('on', score >= G[i]));
  }
  setClock(elapsed) {
    const h = START_HOUR + (END_HOUR - START_HOUR) * Math.min(1, elapsed / ROUND_SECONDS);
    const hh = Math.floor(h), mm = Math.floor((h - hh) * 60 / 10) * 10;
    this.clockEl.textContent = `${String(hh).padStart(2, '0')}:${String(mm).padStart(2, '0')}`;
    $('#clock').classList.toggle('late', ROUND_SECONDS - elapsed < 30);
    $('#clock-fill').style.width = `${Math.min(1, elapsed / ROUND_SECONDS) * 100}%`;
  }
  setNetDown(v) { this.netAlert.classList.toggle('show', v); }

  showBanner(text, cls = '', ms = 1400) {
    this.banner.textContent = text;
    this.banner.className = 'show ' + cls;
    clearTimeout(this._bt);
    this._bt = setTimeout(() => { this.banner.className = ''; }, ms);
  }

  clearAll() {
    this.cards.forEach((c) => c.el.remove()); this.cards.clear();
    this.markers.forEach((m) => m.el.remove()); this.markers.clear();
  }
}

export function slaColor(f) {
  if (f > 0.6) return '#2fc46b';
  if (f > 0.3) return '#ffb02b';
  return '#ff4d4d';
}
