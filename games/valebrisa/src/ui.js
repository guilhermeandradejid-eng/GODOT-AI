import { portrait, icon, drawPixels } from './pixelart.js';
import { sfx } from './audio.js';

// Interface em DOM com fonte pixel e janelas no estilo JRPG 16-bit.
// Tudo é medido em "pixels do jogo" (--u), então a UI casa com a resolução da cena.

const h = (tag, cls, html) => { const e = document.createElement(tag); if (cls) e.className = cls; if (html !== undefined) e.innerHTML = html; return e; };

export const PORTRAITS = {
  hero: { top: 'spiky' },
  amora: { top: 'bun', hair: '#c9c3d6', hairL: '#efeaf6', cloth: '#7d5aa0', cloth2: '#5a3f78', accent: '#e8c36a', accent2: '#b9903f' },
  tiao: { top: 'bandana', hair: '#3a2a2a', accent: '#d4553f', accent2: '#9c3a2c', cloth: '#7a9a4a', cloth2: '#567034', beard: '#4a3426' },
  rubi: { top: 'helmet', cloth: '#8a8fa8', cloth2: '#5f6480', accent: '#d4553f', accent2: '#9c3a2c' },
  pipa: { top: 'short', hair: '#e8b04a', hairL: '#f6d27a', cloth: '#e85d75', cloth2: '#b3405a', accent: '#f6f1e0', accent2: '#c9c0a8' },
  bento: { top: 'hat', hair: '#6b5a4a', cloth: '#4f7fa0', cloth2: '#3a5f78', accent: '#c9b48c', accent2: '#9c8a64', beard: '#e9e2cf' },
};

export class UI {
  constructor(root, game) {
    this.root = root;
    this.game = game;
    root.innerHTML = '';
    // HUD
    this.hud = h('div', 'hud');
    const card = h('div', 'hero-card');
    const pf = h('div', 'portrait frame');
    pf.appendChild(portrait(PORTRAITS.hero));
    card.appendChild(pf);
    const bars = h('div', 'bars');
    bars.innerHTML = `<div class="nameline"><span class="name">Nico</span><span class="lv">Nv 1</span></div>
      <div class="bar hp"><i class="trail"></i><i class="fill"></i><b></b></div>
      <div class="bar ep"><i class="fill"></i></div>
      <div class="bar xp"><i class="fill"></i></div>`;
    card.appendChild(bars);
    this.hud.appendChild(card);
    const inv = h('div', 'inv frame');
    const c1 = h('span', 'it'); c1.appendChild(icon('coin')); this.goldEl = h('b', '', '0'); c1.appendChild(this.goldEl);
    const c2 = h('span', 'it'); c2.appendChild(icon('potion')); this.potEl = h('b', '', 'x2'); c2.appendChild(this.potEl); c2.appendChild(h('kbd', 'hint-k', 'Q'));
    this.clockEl = h('span', 'it clock', '<i class="sun"></i><b>08:00</b>');
    const c3 = h('span', 'it rune hidden'); c3.appendChild(icon('rune')); c3.appendChild(h('b', '', 'Runa'));
    this.runeEl = c3;
    inv.append(this.clockEl, c1, c2, c3);
    this.hud.appendChild(inv);
    root.appendChild(this.hud);
    this.hpFill = bars.querySelector('.hp .fill'); this.hpTrail = bars.querySelector('.hp .trail'); this.hpTxt = bars.querySelector('.hp b');
    this.epFill = bars.querySelector('.ep .fill'); this.xpFill = bars.querySelector('.xp .fill'); this.lvEl = bars.querySelector('.lv');
    this.trail = 1;

    this.quest = h('div', 'quest frame', '<h4>Missão</h4><p></p>');
    root.appendChild(this.quest);
    this.banner = h('div', 'banner', '<small></small><span></span>');
    root.appendChild(this.banner);
    this.boss = h('div', 'bossbar hidden', '<span></span><div class="bar"><i class="trail"></i><i class="fill"></i></div>');
    root.appendChild(this.boss);
    this.prompt = h('div', 'prompt hidden');
    root.appendChild(this.prompt);
    this.toastEl = h('div', 'toast hidden');
    root.appendChild(this.toastEl);
    this.big = h('div', 'bigtext hidden');
    root.appendChild(this.big);
    this.dmgLayer = h('div', 'dmg-layer');
    root.appendChild(this.dmgLayer);

    // diálogo
    this.dlg = h('div', 'dialog frame hidden');
    this.dlgPortrait = h('div', 'pt frame');
    this.dlgName = h('div', 'nm');
    this.dlgText = h('div', 'tx');
    this.dlgNext = h('div', 'nx', '▼');
    this.dlg.append(this.dlgPortrait, this.dlgName, this.dlgText, this.dlgNext);
    root.appendChild(this.dlg);
    this.dialogQueue = null;

    this.screen = h('div', 'screen hidden');
    root.appendChild(this.screen);
    this.fade = h('div', 'fade');
    root.appendChild(this.fade);
    this.buildTouch();
    this.applyScale();
  }

  applyScale() {
    const u = Math.max(2, Math.min(5, Math.round(window.innerHeight / 240)));
    document.documentElement.style.setProperty('--u', u + 'px');
  }

  // ------------------------------------------------------------ HUD
  update(dt) {
    const s = this.game.player.stats;
    const hp = s.hp / s.maxHp;
    this.trail = this.trail > hp ? Math.max(hp, this.trail - dt * 0.6) : hp;
    this.hpFill.style.width = (hp * 100).toFixed(1) + '%';
    this.hpTrail.style.width = (this.trail * 100).toFixed(1) + '%';
    this.hpTxt.textContent = `${Math.ceil(s.hp)}/${s.maxHp}`;
    this.hpFill.parentElement.classList.toggle('low', hp < 0.3);
    this.epFill.style.width = (s.ep / s.maxEp * 100).toFixed(1) + '%';
    this.xpFill.style.width = (s.exp / this.game.player.expNeeded() * 100).toFixed(1) + '%';
    this.lvEl.textContent = 'Nv ' + s.level;
    this.goldEl.textContent = s.gold;
    this.potEl.textContent = 'x' + s.potions;
    // chefe
    const b = this.game.bossRef;
    if (b && this.bossShown) {
      const k = Math.max(0, b.hp / b.maxHp);
      this.bossTrail = this.bossTrail > k ? Math.max(k, this.bossTrail - dt * 0.35) : k;
      this.boss.querySelector('.fill').style.width = (k * 100) + '%';
      this.boss.querySelector('.trail').style.width = (this.bossTrail * 100) + '%';
    }
    // texto do diálogo (máquina de escrever)
    if (this.typing) {
      this.typeT += dt * 48;
      const n = Math.min(this.fullText.length, Math.floor(this.typeT));
      if (n !== this.shown) {
        if (Math.floor(n / 2) !== Math.floor(this.shown / 2)) sfx.blip();
        this.shown = n;
        this.dlgText.textContent = this.fullText.slice(0, n);
      }
      if (n >= this.fullText.length) this.typing = false;
    }
    this.dlgNext.classList.toggle('hidden', this.typing);
    if (this.toastT > 0) { this.toastT -= dt; if (this.toastT <= 0) this.toastEl.classList.add('hidden'); }
    if (this.bannerT > 0) { this.bannerT -= dt; if (this.bannerT <= 0) this.banner.classList.remove('show'); }
    if (this.bigT > 0) { this.bigT -= dt; if (this.bigT <= 0) this.big.classList.add('hidden'); }
  }

  setQuest(title, text) {
    this.quest.querySelector('h4').textContent = title;
    this.quest.querySelector('p').innerHTML = text;
    this.quest.classList.remove('pulse'); void this.quest.offsetWidth; this.quest.classList.add('pulse');
  }
  setClock(label, night) {
    if (this._clock !== label) { this._clock = label; this.clockEl.querySelector('b').textContent = label; }
    this.clockEl.classList.toggle('night', night);
  }
  setRune(on) { this.runeEl.classList.toggle('hidden', !on); }

  showBanner(name, sub = 'Região') {
    this.banner.querySelector('small').textContent = sub;
    this.banner.querySelector('span').textContent = name;
    this.banner.classList.remove('show'); void this.banner.offsetWidth; this.banner.classList.add('show');
    this.bannerT = 2.8;
  }
  toast(msg, t = 1.6) { this.toastEl.textContent = msg; this.toastEl.classList.remove('hidden'); this.toastT = t; }
  bigText(msg, cls = '', t = 2) { this.big.className = 'bigtext ' + cls; this.big.textContent = msg; this.bigT = t; }
  showBoss(name) { this.boss.querySelector('span').textContent = name; this.boss.classList.remove('hidden'); this.bossShown = true; this.bossTrail = 1; }
  hideBoss() { this.boss.classList.add('hidden'); this.bossShown = false; }

  setPrompt(text, screenPos) {
    if (!text) { this.prompt.classList.add('hidden'); return; }
    this.prompt.classList.remove('hidden');
    const key = this.game.input.lastDevice === 'touch' ? 'A' : this.game.input.lastDevice === 'pad' ? 'Ⓐ' : 'E';
    const html = `<kbd>${key}</kbd>${text}`;
    if (this.prompt.innerHTML !== html) this.prompt.innerHTML = html;
    this.prompt.style.transform = `translate(${Math.round(screenPos.x)}px, ${Math.round(screenPos.y)}px) translate(-50%, -100%)`;
  }

  // ------------------------------------------------------------ diálogo
  /** lines: [{who:'amora', name:'Vó Amora', text:'...'}]. Resolve quando termina. */
  dialog(lines) {
    return new Promise((resolve) => {
      this.dialogQueue = { lines, i: 0, resolve };
      this.dlg.classList.remove('hidden');
      this.showLine();
    });
  }
  showLine() {
    const q = this.dialogQueue, l = q.lines[q.i];
    this.dlgPortrait.innerHTML = '';
    if (l.who && PORTRAITS[l.who]) { this.dlgPortrait.appendChild(portrait(PORTRAITS[l.who])); this.dlgPortrait.classList.remove('hidden'); }
    else this.dlgPortrait.classList.add('hidden');
    this.dlg.classList.toggle('noportrait', !(l.who && PORTRAITS[l.who]));
    this.dlgName.textContent = l.name || '';
    this.dlgName.classList.toggle('hidden', !l.name);
    this.fullText = l.text; this.typeT = 0; this.shown = 0; this.typing = true;
    this.dlgText.textContent = '';
  }
  get inDialog() { return !!this.dialogQueue; }
  advance() {
    const q = this.dialogQueue;
    if (!q) return;
    if (this.typing) { this.typing = false; this.shown = this.fullText.length; this.dlgText.textContent = this.fullText; return; }
    sfx.select();
    q.i++;
    if (q.i >= q.lines.length) { this.dlg.classList.add('hidden'); this.dialogQueue = null; q.resolve(); }
    else this.showLine();
  }

  // ------------------------------------------------------------ telas
  showScreen(html, cls) {
    this.screen.className = 'screen ' + cls;
    this.screen.innerHTML = html;
    this.screen.querySelectorAll('[data-act]').forEach((b) => {
      b.addEventListener('click', (e) => { e.stopPropagation(); sfx.select(); this.game.onMenu(b.dataset.act, b); });
    });
    this.menuItems = [...this.screen.querySelectorAll('[data-act]')];
    this.menuIndex = 0;
    this.focusMenu();
    this.hud.classList.toggle('dim', true);
  }
  hideScreen() { this.screen.className = 'screen hidden'; this.menuItems = null; this.hud.classList.remove('dim'); }
  focusMenu() { this.menuItems?.forEach((b, i) => b.classList.toggle('sel', i === this.menuIndex)); }
  menuInput(input) {
    if (!this.menuItems?.length) return;
    const mv = input.move();
    this.menuCd = (this.menuCd || 0) - 1 / 60;
    if (Math.abs(mv.y) > 0.5 && this.menuCd <= 0) {
      this.menuIndex = (this.menuIndex + (mv.y > 0 ? 1 : -1) + this.menuItems.length) % this.menuItems.length;
      this.focusMenu(); sfx.blip(); this.menuCd = 0.2;
    }
    if (Math.abs(mv.y) < 0.2) this.menuCd = 0;
    if (input.consume('confirm') || input.consume('interact')) { input.consume('attack'); input.consume('roll'); const b = this.menuItems[this.menuIndex]; sfx.select(); this.game.onMenu(b.dataset.act, b); }
  }

  titleScreen(hasSave) {
    this.showScreen(`
      <div class="logo"><span class="l1">VALEBRISA</span><span class="l2">contos do vale dos ventos</span></div>
      <div class="menu frame">
        <button data-act="new">Novo jogo</button>
        ${hasSave ? '<button data-act="continue">Continuar</button>' : ''}
        <button data-act="controls">Controles</button>
      </div>
      <div class="foot">versão de teste · ${new Date().getFullYear()}</div>`, 'title');
  }

  controlsScreen() {
    this.showScreen(`
      <div class="panel frame">
        <h3>Controles</h3>
        <table>
          <tr><th></th><th>Teclado</th><th>Controle</th></tr>
          <tr><td>Mover</td><td>WASD / setas</td><td>analógico</td></tr>
          <tr><td>Atacar (combo x3)</td><td>J · Z · clique</td><td>A</td></tr>
          <tr><td>Giro carregado</td><td>segurar ataque</td><td>segurar A</td></tr>
          <tr><td>Rolar (invulnerável)</td><td>Espaço · K · Shift</td><td>B</td></tr>
          <tr><td>Lâmina de vento</td><td>L · X · botão dir.</td><td>X</td></tr>
          <tr><td>Poção</td><td>Q · C</td><td>Y</td></tr>
          <tr><td>Falar / abrir</td><td>E · Enter</td><td>A</td></tr>
          <tr><td>Pausa · música</td><td>Esc · M</td><td>Start</td></tr>
        </table>
        <p class="tip">No celular: joystick à esquerda, botões à direita (deite o aparelho).</p>
        <button data-act="back">Voltar</button>
      </div>`, 'controls');
  }

  pauseScreen() {
    const s = this.game.player.stats, pr = this.game.pr;
    this.showScreen(`
      <div class="panel frame">
        <h3>Pausa</h3>
        <div class="stats">
          <div><span>Nível</span><b>${s.level}</b></div><div><span>Ataque</span><b>${s.atk}</b></div>
          <div><span>Vida</span><b>${Math.ceil(s.hp)}/${s.maxHp}</b></div><div><span>Energia</span><b>${Math.floor(s.ep)}/${s.maxEp}</b></div>
          <div><span>Moedas</span><b>${s.gold}</b></div><div><span>Inimigos</span><b>${this.game.kills}</b></div>
        </div>
        <button data-act="resume">Continuar</button>
        <button data-act="music">Música: ${this.game.musicOn ? 'ligada' : 'desligada'}</button>
        <button data-act="pixels">Pixels: ${pr.pixelScaleOverride ? pr.pixelScaleOverride + 'x' : 'auto'}</button>
        <button data-act="outlines">Contornos: ${pr.outlines ? 'sim' : 'não'}</button>
        <button data-act="time">Hora do dia: ${this.game.timeMode || 'ciclo'}</button>
        <button data-act="style">Estilo: ${this.game.styleName}</button>
        <button data-act="controls">Controles</button>
        <button data-act="restart">Recomeçar do zero</button>
      </div>`, 'pause');
  }

  deathScreen() {
    this.showScreen(`
      <div class="panel frame center">
        <h3>Você desmaiou...</h3>
        <p>A Vó Amora te encontrou e te levou de volta para a vila.<br>Algumas moedas ficaram pelo caminho.</p>
        <button data-act="revive">Levantar</button>
      </div>`, 'death');
  }

  endingScreen() {
    const s = this.game.player.stats;
    const t = Math.floor(this.game.playTime);
    this.showScreen(`
      <div class="panel frame center ending">
        <div class="stars">${'<i></i>'.repeat(3)}</div>
        <h3>O vento voltou a Valebrisa!</h3>
        <p>O Toco Ancião adormeceu de novo e o rio voltou a correr.<br>Obrigado por jogar a versão de teste.</p>
        <div class="stats">
          <div><span>Nível</span><b>${s.level}</b></div><div><span>Tempo</span><b>${Math.floor(t / 60)}m ${t % 60}s</b></div>
          <div><span>Inimigos</span><b>${this.game.kills}</b></div><div><span>Moedas</span><b>${s.gold}</b></div>
        </div>
        <button data-act="explore">Continuar explorando</button>
        <button data-act="restart">Jogar de novo</button>
      </div>`, 'ending');
  }

  fadeTo(on, ms = 400) {
    this.fade.style.transition = `opacity ${ms}ms steps(6)`;
    this.fade.classList.toggle('on', on);
    return new Promise((r) => setTimeout(r, ms));
  }

  // ------------------------------------------------------------ toque
  buildTouch() {
    const t = h('div', 'touch hidden');
    t.innerHTML = `<div class="stick"><div class="knob"></div></div>
      <div class="btns">
        <button data-a="attack" class="b-attack">ATK</button>
        <button data-a="roll" class="b-roll">ROLA</button>
        <button data-a="skill" class="b-skill">VENTO</button>
        <button data-a="potion" class="b-potion">POÇÃO</button>
      </div>
      <button class="b-pause" data-a="pause">II</button>`;
    this.root.appendChild(t);
    this.touchEl = t;
    const input = this.game.input;
    t.querySelectorAll('button[data-a]').forEach((b) => {
      const a = b.dataset.a;
      b.addEventListener('touchstart', (e) => { e.preventDefault(); input.touch(a, true); b.classList.add('down'); }, { passive: false });
      b.addEventListener('touchend', (e) => { e.preventDefault(); input.touch(a, false); b.classList.remove('down'); }, { passive: false });
      b.addEventListener('touchcancel', () => { input.touch(a, false); b.classList.remove('down'); });
    });
    const stick = t.querySelector('.stick'), knob = t.querySelector('.knob');
    let id = null, cx = 0, cy = 0;
    const R = 50;
    const zone = this.root;
    window.addEventListener('touchstart', (e) => {
      this.showTouch();
      for (const tc of e.changedTouches) {
        if (id === null && tc.clientX < window.innerWidth * 0.45 && !(e.target.closest && e.target.closest('button'))) {
          id = tc.identifier; cx = tc.clientX; cy = tc.clientY;
          stick.style.left = cx + 'px'; stick.style.top = cy + 'px'; stick.classList.add('on');
        }
      }
    }, { passive: true });
    window.addEventListener('touchmove', (e) => {
      for (const tc of e.changedTouches) if (tc.identifier === id) {
        let dx = tc.clientX - cx, dy = tc.clientY - cy;
        const l = Math.hypot(dx, dy);
        if (l > R) { dx = dx / l * R; dy = dy / l * R; }
        knob.style.transform = `translate(${dx}px, ${dy}px)`;
        const m = Math.min(1, l / R);
        input.stick = l > 6 ? { x: dx / Math.max(l, 1) * m, y: dy / Math.max(l, 1) * m } : { x: 0, y: 0 };
      }
    }, { passive: true });
    const end = (e) => { for (const tc of e.changedTouches) if (tc.identifier === id) { id = null; input.stick = { x: 0, y: 0 }; knob.style.transform = ''; stick.classList.remove('on'); } };
    window.addEventListener('touchend', end); window.addEventListener('touchcancel', end);
    void zone;
  }
  showTouch() { this.touchEl.classList.remove('hidden'); document.body.classList.add('is-touch'); }
}

export { drawPixels };
