// Sons sintetizados com WebAudio (sem arquivos de áudio).
let ctx = null, master = null, musicGain = null, musicOn = true, musicTimer = null;

export function initAudio() {
  if (ctx) { if (ctx.state === 'suspended') ctx.resume(); return; }
  try {
    ctx = new (window.AudioContext || window.webkitAudioContext)();
    master = ctx.createGain(); master.gain.value = 0.5; master.connect(ctx.destination);
    musicGain = ctx.createGain(); musicGain.gain.value = 0.18; musicGain.connect(master);
  } catch { ctx = null; }
}

function tone(freq, dur = 0.1, type = 'square', vol = 0.2, slide = 0, when = 0, dest = null) {
  if (!ctx) return;
  const t = ctx.currentTime + when;
  const o = ctx.createOscillator(), g = ctx.createGain();
  o.type = type; o.frequency.setValueAtTime(freq, t);
  if (slide) o.frequency.exponentialRampToValueAtTime(Math.max(30, freq + slide), t + dur);
  g.gain.setValueAtTime(0.0001, t);
  g.gain.exponentialRampToValueAtTime(vol, t + 0.01);
  g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
  o.connect(g); g.connect(dest || master);
  o.start(t); o.stop(t + dur + 0.02);
}

function noise(dur = 0.2, vol = 0.15, freq = 1200, when = 0) {
  if (!ctx) return;
  const t = ctx.currentTime + when;
  const len = Math.floor(ctx.sampleRate * dur);
  const buf = ctx.createBuffer(1, len, ctx.sampleRate);
  const d = buf.getChannelData(0);
  for (let i = 0; i < len; i++) d[i] = (Math.random() * 2 - 1) * (1 - i / len);
  const src = ctx.createBufferSource(); src.buffer = buf;
  const f = ctx.createBiquadFilter(); f.type = 'bandpass'; f.frequency.value = freq; f.Q.value = 0.8;
  const g = ctx.createGain(); g.gain.value = vol;
  src.connect(f); f.connect(g); g.connect(master);
  src.start(t);
}

export const sfx = {
  pickup: () => { tone(520, 0.07, 'square', 0.12, 300); },
  drop: () => { tone(300, 0.08, 'triangle', 0.15, -120); },
  throw: () => { noise(0.18, 0.12, 900); tone(400, 0.12, 'sine', 0.08, 500); },
  dash: () => { noise(0.12, 0.1, 600); },
  tick: () => { tone(880, 0.03, 'square', 0.05); },
  deny: () => { tone(180, 0.12, 'square', 0.1); tone(150, 0.12, 'square', 0.1, 0, 0.1); },
  coffee: () => { tone(660, 0.1, 'sine', 0.15, 0); tone(990, 0.15, 'sine', 0.15, 0, 0.08); },
  ring: () => { for (let i = 0; i < 2; i++) { tone(1320, 0.07, 'square', 0.07, 0, i * 0.16); tone(1046, 0.07, 'square', 0.07, 0, i * 0.16 + 0.08); } },
  alarm: () => { tone(740, 0.22, 'sawtooth', 0.08, 300); tone(740, 0.22, 'sawtooth', 0.08, 300, 0.25); },
  resolve: () => { [523, 659, 784, 1046].forEach((f, i) => tone(f, 0.12, 'square', 0.1, 0, i * 0.06)); },
  fail: () => { tone(300, 0.25, 'sawtooth', 0.12, -150); tone(200, 0.35, 'sawtooth', 0.12, -100, 0.2); },
  spray: () => { noise(0.1, 0.06, 2500); },
  countdown: (last) => { tone(last ? 880 : 440, last ? 0.4 : 0.15, 'square', 0.12); },
  whistle: () => { tone(1500, 0.5, 'sine', 0.15, 400); },
};

// Música de fundo: loop simples de bossa/lo-fi chiptune gerado em tempo real.
const BPM = 112;
const prog = [[57, 60, 64, 67], [62, 65, 69, 72], [55, 59, 62, 65], [60, 64, 67, 71]];
const mtof = (m) => 440 * Math.pow(2, (m - 69) / 12);
let step = 0;
export function startMusic() {
  if (!ctx || musicTimer) return;
  const beat = 60 / BPM / 2;
  musicTimer = setInterval(() => {
    if (!musicOn) return;
    const bar = Math.floor(step / 8) % prog.length, s = step % 8;
    const ch = prog[bar];
    if (s === 0 || s === 3 || s === 6) tone(mtof(ch[0] - 12), beat * 1.6, 'triangle', 0.35, 0, 0, musicGain);
    if (s % 2 === 1) tone(mtof(ch[1 + (s % 3)]), beat * 0.8, 'square', 0.06, 0, 0, musicGain);
    if (s === 4) tone(mtof(ch[3] + 12), beat * 1.2, 'sine', 0.08, 0, 0, musicGain);
    if (s % 2 === 0) noise(0.03, 0.05, 6000);
    step++;
  }, (beat * 1000));
}
export function stopMusic() { clearInterval(musicTimer); musicTimer = null; }
export function toggleMusic() { musicOn = !musicOn; return musicOn; }
