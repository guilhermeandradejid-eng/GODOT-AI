// Entrada unificada: teclado, mouse, controle e toque. Gera ações abstratas.
const KEYMAP = {
  KeyW: 'up', ArrowUp: 'up', KeyS: 'down', ArrowDown: 'down', KeyA: 'left', ArrowLeft: 'left', KeyD: 'right', ArrowRight: 'right',
  KeyJ: 'attack', KeyZ: 'attack',
  KeyK: 'roll', Space: 'roll', ShiftLeft: 'roll', ShiftRight: 'roll',
  KeyL: 'skill', KeyX: 'skill',
  KeyQ: 'potion', KeyC: 'potion',
  KeyE: 'interact', Enter: 'interact', NumpadEnter: 'interact',
  Escape: 'pause', KeyP: 'pause', KeyM: 'music',
};

export class Input {
  constructor() {
    this.held = new Set();
    this.pressed = new Set();
    this.touchHeld = new Set();
    this.stick = { x: 0, y: 0 };
    this.padPrev = [];
    this.lastDevice = 'keyboard';
    window.addEventListener('keydown', (e) => {
      const a = KEYMAP[e.code];
      if (!a) return;
      if (['Space', 'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight'].includes(e.code)) e.preventDefault();
      if (!e.repeat) this.pressed.add(a);
      if (a === 'roll' && !e.repeat) this.pressed.add('confirm');
      if ((a === 'interact' || a === 'attack') && !e.repeat) this.pressed.add('confirm');
      this.held.add(a);
      this.lastDevice = 'keyboard';
    });
    window.addEventListener('keyup', (e) => { const a = KEYMAP[e.code]; if (a) this.held.delete(a); });
    window.addEventListener('blur', () => this.held.clear());
    const cv = document.getElementById('game');
    cv.addEventListener('mousedown', (e) => {
      if (e.button === 0) { this.held.add('attack'); this.pressed.add('attack'); this.pressed.add('confirm'); }
      if (e.button === 2) this.pressed.add('skill');
      this.lastDevice = 'keyboard';
    });
    window.addEventListener('mouseup', (e) => { if (e.button === 0) this.held.delete('attack'); });
    cv.addEventListener('contextmenu', (e) => e.preventDefault());
  }

  /** botões de toque chamam isto */
  touch(action, down) {
    this.lastDevice = 'touch';
    if (down) { this.touchHeld.add(action); this.pressed.add(action); if (action === 'attack') this.pressed.add('confirm'); }
    else this.touchHeld.delete(action);
  }

  poll() {
    const pads = navigator.getGamepads ? navigator.getGamepads() : [];
    this.padMove = { x: 0, y: 0 };
    this.padHeld = new Set();
    for (const gp of pads) {
      if (!gp) continue;
      const map = { 0: 'attack', 1: 'roll', 2: 'skill', 3: 'potion', 5: 'interact', 4: 'roll', 7: 'attack', 9: 'pause', 8: 'music' };
      gp.buttons.forEach((b, i) => {
        const a = map[i];
        const was = this.padPrev[gp.index * 32 + i];
        if (b.pressed) { if (a) this.padHeld.add(a); if (!was && a) { this.pressed.add(a); if (i === 0) this.pressed.add('confirm'); this.lastDevice = 'pad'; } }
        this.padPrev[gp.index * 32 + i] = b.pressed;
      });
      let x = gp.axes[0] || 0, y = gp.axes[1] || 0;
      if (gp.buttons[14]?.pressed) x = -1; if (gp.buttons[15]?.pressed) x = 1;
      if (gp.buttons[12]?.pressed) y = -1; if (gp.buttons[13]?.pressed) y = 1;
      if (Math.hypot(x, y) > 0.22) { this.padMove = { x, y }; this.lastDevice = 'pad'; }
    }
  }

  isHeld(a) { return this.held.has(a) || this.touchHeld.has(a) || this.padHeld?.has(a); }
  wasPressed(a) { return this.pressed.has(a); }
  consume(a) { const had = this.pressed.has(a); this.pressed.delete(a); return had; }

  /** vetor de movimento em espaço de tela (x direita, y baixo), comprimento ≤ 1 */
  move() {
    let x = 0, y = 0;
    if (this.held.has('left')) x -= 1; if (this.held.has('right')) x += 1;
    if (this.held.has('up')) y -= 1; if (this.held.has('down')) y += 1;
    if (x || y) { const l = Math.hypot(x, y); return { x: x / l, y: y / l }; }
    if (this.padMove && (this.padMove.x || this.padMove.y)) { const l = Math.min(1, Math.hypot(this.padMove.x, this.padMove.y)); const n = Math.hypot(this.padMove.x, this.padMove.y); return { x: this.padMove.x / n * l, y: this.padMove.y / n * l }; }
    if (this.stick.x || this.stick.y) return { ...this.stick };
    return { x: 0, y: 0 };
  }

  endFrame() { this.pressed.clear(); }
}
