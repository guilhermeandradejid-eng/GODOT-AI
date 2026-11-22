// Dispositivos de entrada: dois "lados" do teclado + até 4 gamepads.
// Cada dispositivo expõe: move {x,z}, grab (pegar/soltar), use (consertar/arremessar), dash, start.

const keys = new Set();
const pressedThisFrame = new Set();
window.addEventListener('keydown', (e) => {
  if (['Space', 'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight', 'Tab'].includes(e.code)) e.preventDefault();
  if (!keys.has(e.code)) pressedThisFrame.add(e.code);
  keys.add(e.code);
});
window.addEventListener('keyup', (e) => keys.delete(e.code));
window.addEventListener('blur', () => keys.clear());

export const KEY_LAYOUTS = {
  kbA: { up: ['KeyW'], down: ['KeyS'], left: ['KeyA'], right: ['KeyD'], grab: ['KeyE', 'Space'], use: ['KeyF'], dash: ['ShiftLeft'], label: 'Teclado (WASD)', hint: 'E pegar · F usar · Shift correr' },
  kbB: { up: ['ArrowUp'], down: ['ArrowDown'], left: ['ArrowLeft'], right: ['ArrowRight'], grab: ['Enter', 'KeyL', 'Numpad0'], use: ['ShiftRight', 'KeyK', 'NumpadDecimal'], dash: ['ControlRight', 'KeyJ', 'NumpadEnter'], label: 'Teclado (Setas)', hint: 'Enter pegar · Shift dir. usar · Ctrl dir. correr' },
};

class KeyboardDevice {
  constructor(id) { this.id = id; this.layout = KEY_LAYOUTS[id]; this.kind = 'keyboard'; this.label = this.layout.label; this.hint = this.layout.hint; }
  any(list) { return list.some((k) => keys.has(k)); }
  pressed(list) { return list.some((k) => pressedThisFrame.has(k)); }
  read() {
    const L = this.layout;
    let x = (this.any(L.right) ? 1 : 0) - (this.any(L.left) ? 1 : 0);
    let z = (this.any(L.down) ? 1 : 0) - (this.any(L.up) ? 1 : 0);
    const len = Math.hypot(x, z); if (len > 1) { x /= len; z /= len; }
    return {
      x, z,
      grab: this.pressed(L.grab),
      use: this.any(L.use), usePressed: this.pressed(L.use),
      dash: this.pressed(L.dash),
      join: this.pressed(L.grab),
    };
  }
}

const padPrev = new Map();
class GamepadDevice {
  constructor(index) { this.id = 'pad' + index; this.index = index; this.kind = 'gamepad'; this.label = 'Controle ' + (index + 1); this.hint = 'A pegar · X usar · B correr'; }
  read() {
    const gp = navigator.getGamepads?.()[this.index];
    if (!gp) return { x: 0, z: 0, grab: false, use: false, usePressed: false, dash: false, join: false, start: false };
    const prev = padPrev.get(this.index) || [];
    const b = (i) => !!gp.buttons[i]?.pressed;
    const p = (i) => b(i) && !prev[i];
    let x = gp.axes[0] || 0, z = gp.axes[1] || 0;
    if (b(14)) x = -1; if (b(15)) x = 1; if (b(12)) z = -1; if (b(13)) z = 1;
    const len = Math.hypot(x, z);
    if (len < 0.22) { x = 0; z = 0; } else if (len > 1) { x /= len; z /= len; }
    const out = { x, z, grab: p(0), use: b(2) || b(7), usePressed: p(2) || p(7), dash: p(1) || p(5), join: p(0), start: p(9) };
    padPrev.set(this.index, gp.buttons.map((bb) => bb.pressed));
    return out;
  }
}

// ------------------------------------------------------------------ touch
// joystick virtual (metade esquerda, nasce onde o dedo toca) + botões A (pegar), B (usar), Correr
export const touchState = { active: false, x: 0, z: 0, grab: false, use: false, dash: false, prev: {} };
export const isTouchDevice = () => 'ontouchstart' in window || navigator.maxTouchPoints > 0;

class TouchDevice {
  constructor() { this.id = 'touch'; this.kind = 'touch'; this.label = 'Toque'; this.hint = 'Joystick + botões A / B'; }
  read() {
    const t = touchState, p = t.prev;
    const out = { x: t.x, z: t.z, grab: t.grab && !p.grab, use: t.use, usePressed: t.use && !p.use, dash: t.dash && !p.dash, join: t.grab && !p.grab, start: false };
    t.prev = { grab: t.grab, use: t.use, dash: t.dash };
    return out;
  }
}

export function setupTouch(onFirstTouch) {
  const root = document.getElementById('touch');
  const zone = root.querySelector('.stick-zone');
  const base = root.querySelector('.stick-base');
  const knob = root.querySelector('.stick-knob');
  const R = 56;
  let stickId = null, ox = 0, oy = 0;
  const setStick = (dx, dy) => {
    const l = Math.hypot(dx, dy), k = l > R ? R / l : 1;
    dx *= k; dy *= k;
    knob.style.transform = `translate(${dx}px, ${dy}px)`;
    const m = Math.hypot(dx, dy) / R;
    touchState.x = m > 0.18 ? dx / R : 0; touchState.z = m > 0.18 ? dy / R : 0;
  };
  zone.addEventListener('pointerdown', (e) => {
    if (stickId !== null) return;
    stickId = e.pointerId; try { zone.setPointerCapture(e.pointerId); } catch {}
    ox = e.clientX; oy = e.clientY;
    base.style.left = ox + 'px'; base.style.top = oy + 'px';
    base.classList.add('on'); setStick(0, 0);
  });
  zone.addEventListener('pointermove', (e) => { if (e.pointerId === stickId) setStick(e.clientX - ox, e.clientY - oy); });
  const end = (e) => { if (e.pointerId !== stickId) return; stickId = null; base.classList.remove('on'); setStick(0, 0); };
  zone.addEventListener('pointerup', end); zone.addEventListener('pointercancel', end);
  for (const b of root.querySelectorAll('[data-btn]')) {
    const k = b.dataset.btn;
    b.addEventListener('pointerdown', (e) => { e.preventDefault(); try { b.setPointerCapture(e.pointerId); } catch {} touchState[k] = true; b.classList.add('down'); navigator.vibrate?.(8); });
    const up = () => { touchState[k] = false; b.classList.remove('down'); };
    b.addEventListener('pointerup', up); b.addEventListener('pointercancel', up); b.addEventListener('lostpointercapture', up);
  }
  window.addEventListener('touchstart', () => { if (!touchState.active) { touchState.active = true; document.body.classList.add('touch'); onFirstTouch?.(); } }, { passive: true });
  if (isTouchDevice()) { touchState.active = true; document.body.classList.add('touch'); }
}

export const devices = {
  touch: new TouchDevice(),
  kbA: new KeyboardDevice('kbA'),
  kbB: new KeyboardDevice('kbB'),
};

export function pollGamepads() {
  const gps = navigator.getGamepads?.() || [];
  for (let i = 0; i < gps.length; i++) {
    if (gps[i] && !devices['pad' + i]) devices['pad' + i] = new GamepadDevice(i);
  }
}

export function keyPressed(code) { return pressedThisFrame.has(code); }
export function endFrame() { pressedThisFrame.clear(); }
