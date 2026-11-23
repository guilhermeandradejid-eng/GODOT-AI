// Som 100% sintetizado (WebAudio): efeitos estilo 16-bit e um sequenciador com 3 temas.
let ctx = null, master = null, musicBus = null, sfxBus = null;
let musicOn = true, current = null, timer = null, step = 0, nextT = 0;

export function initAudio() {
  if (ctx) { if (ctx.state === 'suspended') ctx.resume(); return; }
  try {
    ctx = new (window.AudioContext || window.webkitAudioContext)();
    master = ctx.createGain(); master.gain.value = 0.55; master.connect(ctx.destination);
    musicBus = ctx.createGain(); musicBus.gain.value = 0.16; musicBus.connect(master);
    sfxBus = ctx.createGain(); sfxBus.gain.value = 0.7; sfxBus.connect(master);
  } catch { ctx = null; }
}

function tone(freq, dur = 0.1, type = 'square', vol = 0.2, slide = 0, when = 0, dest = null, abs = false) {
  if (!ctx) return;
  const t = abs ? when : ctx.currentTime + when;
  const o = ctx.createOscillator(), g = ctx.createGain();
  o.type = type; o.frequency.setValueAtTime(freq, t);
  if (slide) o.frequency.exponentialRampToValueAtTime(Math.max(30, freq + slide), t + dur);
  g.gain.setValueAtTime(0.0001, t);
  g.gain.exponentialRampToValueAtTime(vol, t + 0.008);
  g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
  o.connect(g); g.connect(dest || sfxBus);
  o.start(t); o.stop(t + dur + 0.03);
}
let noiseBuf = null;
function noise(dur = 0.2, vol = 0.15, freq = 1200, when = 0, dest = null, q = 0.8, abs = false) {
  if (!ctx) return;
  const t = abs ? when : ctx.currentTime + when;
  if (!noiseBuf) { noiseBuf = ctx.createBuffer(1, ctx.sampleRate, ctx.sampleRate); const d = noiseBuf.getChannelData(0); for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1; }
  const src = ctx.createBufferSource(); src.buffer = noiseBuf;
  const f = ctx.createBiquadFilter(); f.type = 'bandpass'; f.frequency.value = freq; f.Q.value = q;
  const g = ctx.createGain(); g.gain.setValueAtTime(vol, t); g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
  src.connect(f); f.connect(g); g.connect(dest || sfxBus);
  src.start(t, Math.random() * 0.5); src.stop(t + dur + 0.02);
}

export const sfx = {
  swing: (i = 0) => { noise(0.09, 0.14, 1800 + i * 500, 0, null, 1.4); tone(300 + i * 80, 0.07, 'triangle', 0.06, 300); },
  hit: () => { noise(0.07, 0.25, 700); tone(160, 0.08, 'square', 0.12, -80); tone(95, 0.16, 'sine', 0.35, -45); },
  heavy: () => { noise(0.14, 0.32, 380, 0, null, 0.6); tone(70, 0.28, 'sine', 0.45, -35); tone(220, 0.1, 'square', 0.08, -120); },
  poof: () => { noise(0.22, 0.22, 900, 0, null, 0.5); tone(520, 0.12, 'triangle', 0.08, 380); },
  whoosh: (k = 0) => { noise(0.12 + k * 0.05, 0.16 + k * 0.05, 1200 - k * 300, 0, null, 1.1); },
  crit: () => { noise(0.1, 0.3, 900); tone(880, 0.08, 'square', 0.08, 400); },
  hurt: () => { tone(300, 0.15, 'sawtooth', 0.12, -180); noise(0.1, 0.15, 500); },
  die: () => { tone(520, 0.08, 'square', 0.08, -200); tone(260, 0.2, 'square', 0.08, -150, 0.07); noise(0.25, 0.12, 400, 0.05); },
  roll: () => { noise(0.16, 0.1, 500); },
  coin: (i = 0) => { tone(1318 + i * 30, 0.05, 'square', 0.05); tone(1760 + i * 30, 0.09, 'square', 0.05, 0, 0.05); },
  heart: () => { tone(660, 0.08, 'triangle', 0.12); tone(990, 0.12, 'triangle', 0.1, 0, 0.07); },
  potion: () => { [523, 659, 784, 1046].forEach((f, i) => tone(f, 0.1, 'triangle', 0.1, 40, i * 0.05)); },
  charge: () => { tone(440, 0.25, 'square', 0.04, 600); },
  charged: () => { tone(1320, 0.12, 'square', 0.06); tone(1760, 0.14, 'square', 0.05, 0, 0.06); },
  spin: () => { noise(0.3, 0.2, 1500, 0, null, 0.6); tone(220, 0.3, 'sawtooth', 0.06, 440); },
  cast: () => { tone(880, 0.2, 'triangle', 0.08, -500); noise(0.2, 0.1, 3000); },
  blip: () => { tone(980 + Math.random() * 60, 0.025, 'square', 0.025); },
  select: () => { tone(740, 0.05, 'square', 0.06); tone(988, 0.07, 'square', 0.06, 0, 0.05); },
  deny: () => { tone(200, 0.1, 'square', 0.08); tone(160, 0.12, 'square', 0.08, 0, 0.09); },
  levelup: () => { [523, 659, 784, 1046, 1318].forEach((f, i) => tone(f, 0.16, 'square', 0.07, 0, i * 0.08)); tone(1568, 0.5, 'triangle', 0.08, 0, 0.42); },
  quest: () => { [784, 988, 1175, 1568].forEach((f, i) => tone(f, 0.18, 'triangle', 0.1, 0, i * 0.1)); },
  chest: () => { tone(392, 0.1, 'square', 0.06); [523, 659, 784, 1046, 1318, 1568].forEach((f, i) => tone(f, 0.12, 'square', 0.05, 0, 0.25 + i * 0.07)); },
  telegraph: () => { tone(220, 0.25, 'sawtooth', 0.05, 110); },
  slam: () => { noise(0.5, 0.35, 160, 0, null, 0.5); tone(80, 0.4, 'sine', 0.3, -40); },
  root: () => { noise(0.25, 0.25, 300); tone(140, 0.2, 'square', 0.08, -60); },
  shoot: () => { tone(500, 0.08, 'square', 0.05, -250); },
  roar: () => { noise(0.9, 0.3, 220, 0, null, 0.7); tone(110, 0.9, 'sawtooth', 0.12, -50); tone(116, 0.9, 'sawtooth', 0.1, -50); },
  gate: () => { noise(0.6, 0.2, 250); [262, 330, 392, 523].forEach((f, i) => tone(f, 0.2, 'triangle', 0.08, 0, 0.2 + i * 0.1)); },
  hop: () => { tone(260, 0.07, 'sine', 0.06, 200); },
  step: () => { noise(0.03, 0.03, 900); },
};

// ------------------------------------------------------------------ música
const mtof = (m) => 440 * Math.pow(2, (m - 69) / 12);
// cada tema: bpm, passos por compasso (colcheias), acordes [baixo, ...], melodia em graus (null = pausa)
const THEMES = {
  vila: {
    bpm: 96, swing: 0.08,
    chords: [[53, 65, 69, 72], [50, 62, 65, 69], [46, 58, 62, 65], [48, 60, 64, 67]],
    mel: [72, null, 74, 76, null, 74, 72, null, 69, null, 72, 74, null, null, 72, 69, 70, null, 69, 67, null, 65, 67, null, 72, null, 69, 67, 64, null, null, null],
    lead: 'triangle', bass: 'triangle', drums: false,
  },
  campo: {
    bpm: 124, swing: 0,
    chords: [[50, 62, 66, 69], [55, 67, 71, 74], [52, 64, 67, 71], [57, 69, 73, 76]],
    mel: [74, 76, 78, null, 81, null, 78, 76, 74, null, 71, 74, 76, null, null, null, 79, 78, 76, null, 74, 76, 78, null, 76, null, 73, 74, 69, null, null, null],
    lead: 'square', bass: 'triangle', drums: true,
  },
  chefe: {
    bpm: 148, swing: 0,
    chords: [[45, 57, 60, 64], [41, 53, 57, 60], [43, 55, 59, 62], [40, 52, 56, 59]],
    mel: [69, 72, 76, 72, 77, 76, 72, 69, 68, 71, 74, 71, 76, 74, 71, 68, 69, 72, 76, 79, 81, 79, 76, 72, 74, 72, 71, 68, 64, null, 68, 71],
    lead: 'square', bass: 'sawtooth', drums: true,
  },
};

export function playMusic(name) {
  if (!ctx || current === name) return;
  current = name; step = 0; nextT = ctx.currentTime + 0.1;
  if (!timer) timer = setInterval(schedule, 40);
}
export function stopMusic() { current = null; }

function schedule() {
  if (!ctx || !current) return;
  const th = THEMES[current];
  const dt = 60 / th.bpm / 2;
  while (nextT < ctx.currentTime + 0.15) {
    if (musicOn) playStep(th, step, nextT + (step % 2 ? th.swing * dt : 0), dt);
    step++; nextT += dt;
  }
}

function playStep(th, s, t, dt) {
  const bar = Math.floor(s / 8) % th.chords.length, b = s % 8;
  const ch = th.chords[bar];
  const bus = musicBus;
  if (b === 0 || b === 4 || (th.drums && b === 6)) tone(mtof(ch[0] - 12), dt * 1.7, th.bass, 0.35, 0, t, bus, true);
  if (b % 2 === 1) tone(mtof(ch[1 + ((b >> 1) % 3)]), dt * 0.7, 'square', 0.045, 0, t, bus, true);
  const m = th.mel[s % th.mel.length];
  if (m) tone(mtof(m), dt * 1.5, th.lead, th.lead === 'square' ? 0.06 : 0.12, 0, t, bus, true);
  if (th.drums) {
    if (b === 0 || b === 4) noise(0.12, 0.2, 120, t, bus, 0.6, true);
    if (b === 2 || b === 6) noise(0.08, 0.14, 2200, t, bus, 0.9, true);
    noise(0.025, 0.05, 7000, t, bus, 1.2, true);
  }
}

export function toggleMusic() { musicOn = !musicOn; return musicOn; }
export function isMusicOn() { return musicOn; }
