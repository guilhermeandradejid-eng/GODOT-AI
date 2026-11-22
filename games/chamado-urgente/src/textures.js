import * as THREE from 'three';

function canvas(w, h) {
  const c = document.createElement('canvas');
  c.width = w; c.height = h;
  return [c, c.getContext('2d')];
}

function tex(c, repeat = null) {
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = 8;
  if (repeat) {
    t.wrapS = t.wrapT = THREE.RepeatWrapping;
    t.repeat.set(repeat[0], repeat[1]);
  }
  return t;
}

function hex(n) { return '#' + n.toString(16).padStart(6, '0'); }

// Carpete de escritório em placas, com leve ruído.
export function carpetTexture(a = 0x5d6b8a, b = 0x546180) {
  const [c, g] = canvas(256, 256);
  const s = 128;
  for (let y = 0; y < 2; y++) for (let x = 0; x < 2; x++) {
    g.fillStyle = hex((x + y) % 2 ? a : b);
    g.fillRect(x * s, y * s, s, s);
    // fibras na direção da placa
    g.globalAlpha = 0.08;
    for (let i = 0; i < 40; i++) {
      g.fillStyle = i % 2 ? '#ffffff' : '#000000';
      if ((x + y) % 2) g.fillRect(x * s, y * s + i * 3.2, s, 1);
      else g.fillRect(x * s + i * 3.2, y * s, 1, s);
    }
    g.globalAlpha = 1;
  }
  const img = g.getImageData(0, 0, 256, 256);
  for (let i = 0; i < img.data.length; i += 4) {
    const n = (Math.random() - 0.5) * 14;
    img.data[i] += n; img.data[i + 1] += n; img.data[i + 2] += n;
  }
  g.putImageData(img, 0, 0);
  g.strokeStyle = 'rgba(0,0,0,0.18)';
  g.lineWidth = 2;
  g.strokeRect(1, 1, 254, 254);
  g.beginPath(); g.moveTo(128, 0); g.lineTo(128, 256); g.moveTo(0, 128); g.lineTo(256, 128); g.stroke();
  return tex(c, [1, 1]);
}

// Piso vinílico quadriculado (sala de TI / copa).
export function vinylTexture(a = '#e9e4da', b = '#d4cdbf') {
  const [c, g] = canvas(128, 128);
  g.fillStyle = a; g.fillRect(0, 0, 128, 128);
  g.fillStyle = b; g.fillRect(0, 0, 64, 64); g.fillRect(64, 64, 64, 64);
  g.strokeStyle = 'rgba(0,0,0,0.12)'; g.lineWidth = 2;
  g.strokeRect(0, 0, 64, 64); g.strokeRect(64, 64, 64, 64); g.strokeRect(64, 0, 64, 64); g.strokeRect(0, 64, 64, 64);
  return tex(c, [1, 1]);
}

export function woodTexture() {
  const [c, g] = canvas(256, 64);
  g.fillStyle = '#c98f5a'; g.fillRect(0, 0, 256, 64);
  for (let i = 0; i < 30; i++) {
    g.strokeStyle = `rgba(90,50,20,${0.06 + Math.random() * 0.1})`;
    g.lineWidth = 1 + Math.random() * 2;
    g.beginPath();
    const y = Math.random() * 64;
    g.moveTo(0, y);
    for (let x = 0; x <= 256; x += 32) g.lineTo(x, y + Math.sin(x * 0.05 + i) * 3);
    g.stroke();
  }
  return tex(c);
}

// --- Telas dos monitores ----------------------------------------------------
const SW = 128, SH = 80;

function desktopBase(g, hue) {
  const grd = g.createLinearGradient(0, 0, SW, SH);
  grd.addColorStop(0, `hsl(${hue},80%,62%)`);
  grd.addColorStop(1, `hsl(${hue + 40},75%,45%)`);
  g.fillStyle = grd; g.fillRect(0, 0, SW, SH);
}

export function screenOk(hue = 205, variant = 0) {
  const [c, g] = canvas(SW, SH);
  desktopBase(g, hue);
  // janelas abertas
  g.fillStyle = 'rgba(255,255,255,0.92)';
  g.fillRect(14, 12, 62, 42);
  g.fillStyle = `hsl(${hue},60%,35%)`; g.fillRect(14, 12, 62, 7);
  g.fillStyle = '#c9d2e3';
  for (let i = 0; i < 5; i++) g.fillRect(19, 24 + i * 6, 30 + ((i * 17 + variant * 7) % 22), 3);
  g.fillStyle = 'rgba(255,255,255,0.85)'; g.fillRect(70, 30, 44, 34);
  g.fillStyle = '#ffd23f'; g.fillRect(74, 50, 7, 10); g.fillStyle = '#ff7b54'; g.fillRect(84, 42, 7, 18);
  g.fillStyle = '#2fc46b'; g.fillRect(94, 36, 7, 24); g.fillStyle = '#3d7bff'; g.fillRect(104, 46, 7, 14);
  g.fillStyle = 'rgba(0,0,0,0.35)'; g.fillRect(0, SH - 9, SW, 9);
  g.fillStyle = '#ffffff'; g.fillRect(4, SH - 7, 5, 5);
  return tex(c);
}

export function screenNoNet() {
  const [c, g] = canvas(SW, SH);
  g.fillStyle = '#39415a'; g.fillRect(0, 0, SW, SH);
  g.strokeStyle = '#cfd6e4'; g.lineWidth = 6; g.lineCap = 'round';
  g.beginPath(); g.arc(64, 54, 28, Math.PI * 1.2, Math.PI * 1.8); g.stroke();
  g.beginPath(); g.arc(64, 54, 15, Math.PI * 1.2, Math.PI * 1.8); g.stroke();
  g.fillStyle = '#cfd6e4'; g.beginPath(); g.arc(64, 54, 4, 0, Math.PI * 2); g.fill();
  g.strokeStyle = '#ff5a5a'; g.lineWidth = 7;
  g.beginPath(); g.moveTo(40, 16); g.lineTo(88, 64); g.stroke();
  g.fillStyle = '#ffffff'; g.font = 'bold 11px sans-serif'; g.textAlign = 'center';
  g.fillText('SEM CONEXÃO', 64, 76);
  return tex(c);
}

export function screenVirus(frame = 0) {
  const [c, g] = canvas(SW, SH);
  g.fillStyle = frame % 2 ? '#b0122b' : '#7d0a1f'; g.fillRect(0, 0, SW, SH);
  // faixas de glitch
  for (let i = 0; i < 6; i++) {
    g.fillStyle = `rgba(${i % 2 ? '0,255,120' : '255,255,255'},0.25)`;
    g.fillRect(0, ((i * 23 + frame * 31) % SH), SW, 2 + (i % 3));
  }
  // caveira
  g.fillStyle = '#ffffff';
  g.beginPath(); g.arc(64, 34, 20, 0, Math.PI * 2); g.fill();
  g.fillRect(52, 44, 24, 14);
  g.fillStyle = frame % 2 ? '#b0122b' : '#7d0a1f';
  g.beginPath(); g.arc(56, 33, 6, 0, Math.PI * 2); g.arc(72, 33, 6, 0, Math.PI * 2); g.fill();
  g.fillRect(58, 50, 3, 8); g.fillRect(63, 50, 3, 8); g.fillRect(68, 50, 3, 8);
  g.fillStyle = '#6ee36e'; g.font = 'bold 10px monospace'; g.textAlign = 'center';
  g.fillText(frame % 2 ? 'HACKED!!1' : 'R$ 9.999 BTC', 64, 74);
  return tex(c);
}

export function screenScan(p = 0) {
  const [c, g] = canvas(SW, SH);
  g.fillStyle = '#0f3d2a'; g.fillRect(0, 0, SW, SH);
  g.fillStyle = '#6ee36e'; g.font = 'bold 11px monospace'; g.textAlign = 'center';
  g.fillText('ANTIVÍRUS', 64, 26);
  g.strokeStyle = '#6ee36e'; g.lineWidth = 2; g.strokeRect(14, 38, 100, 14);
  g.fillRect(16, 40, 96 * p, 10);
  return tex(c);
}

export function screenOff() {
  const [c, g] = canvas(8, 8);
  g.fillStyle = '#151924'; g.fillRect(0, 0, 8, 8);
  return tex(c);
}

// Skyline vista pelas janelas.
export function skylineTexture() {
  const [c, g] = canvas(1024, 256);
  const grd = g.createLinearGradient(0, 0, 0, 256);
  grd.addColorStop(0, '#7fc8ff'); grd.addColorStop(0.65, '#cfe9ff'); grd.addColorStop(1, '#ffe2c2');
  g.fillStyle = grd; g.fillRect(0, 0, 1024, 256);
  // nuvens
  g.fillStyle = 'rgba(255,255,255,0.85)';
  for (let i = 0; i < 9; i++) {
    const x = (i * 137) % 1024, y = 30 + (i * 53) % 60;
    for (let k = 0; k < 4; k++) { g.beginPath(); g.arc(x + k * 18, y + (k % 2) * 6, 16 + (k % 3) * 5, 0, Math.PI * 2); g.fill(); }
  }
  const rows = [['#9fb7d6', 0.55, 140], ['#7d93b8', 0.4, 170], ['#5f7399', 0.3, 200]];
  for (const [col, , base] of rows) {
    let x = 0;
    while (x < 1024) {
      const w = 40 + Math.random() * 70, h = 40 + Math.random() * (256 - base + 60);
      g.fillStyle = col; g.fillRect(x, 256 - h, w, h);
      g.fillStyle = 'rgba(255,255,230,0.5)';
      for (let wy = 256 - h + 8; wy < 250; wy += 12) for (let wx = x + 6; wx < x + w - 6; wx += 10) if (Math.random() < 0.5) g.fillRect(wx, wy, 5, 6);
      x += w + 4;
    }
  }
  return tex(c);
}

// Etiqueta/placa com texto (nome de sala, cartaz).
export function labelTexture(text, bg = '#3b4566', fg = '#ffffff', w = 256, h = 64) {
  const [c, g] = canvas(w, h);
  g.fillStyle = bg;
  const r = 14;
  g.beginPath(); g.roundRect(2, 2, w - 4, h - 4, r); g.fill();
  g.fillStyle = fg; g.font = `bold ${Math.floor(h * 0.48)}px Fredoka, sans-serif`;
  g.textAlign = 'center'; g.textBaseline = 'middle';
  g.fillText(text, w / 2, h / 2 + 2);
  return tex(c);
}

export function posterTexture(lines, bg = '#ffd23f') {
  const [c, g] = canvas(128, 160);
  g.fillStyle = bg; g.fillRect(0, 0, 128, 160);
  g.fillStyle = '#1d2540'; g.font = 'bold 18px Fredoka, sans-serif'; g.textAlign = 'center';
  lines.forEach((l, i) => g.fillText(l, 64, 40 + i * 26));
  g.strokeStyle = '#1d2540'; g.lineWidth = 6; g.strokeRect(3, 3, 122, 154);
  return tex(c);
}
