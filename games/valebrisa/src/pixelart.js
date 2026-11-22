// Pixel art feito à mão (strings) para retratos e ícones da interface.

const PAL = {
  k: '#1c1a2e', w: '#ffffff', e: '#2a2235', p: '#e89a8a',
  s: '#f3c9a1', S: '#d99b7a',
  y: '#f2c14e', Y: '#fff2a8', o: '#c98a2e',
  r: '#e0533d', R: '#a83a2e',
  b: '#3f86b8', B: '#2c628c',
  g: '#6aa84b', G: '#3f7046',
  c: '#7fe0c8', C: '#3fa08e',
  m: '#e8485f', M: '#a52a42', n: '#ffb3bd',
  v: '#b98ad6', V: '#7d5aa0',
  l: '#8a6043', L: '#5e3f31',
  a: '#a7b6c8', A: '#e3ebf2',
};

export function drawPixels(rows, pal = {}, scale = 1) {
  const P = { ...PAL, ...pal };
  const h = rows.length, w = Math.max(...rows.map((r) => r.length));
  const cv = document.createElement('canvas');
  cv.width = w * scale; cv.height = h * scale;
  const c = cv.getContext('2d');
  rows.forEach((row, y) => [...row].forEach((ch, x) => {
    if (ch === '.' || !P[ch]) return;
    c.fillStyle = P[ch]; c.fillRect(x * scale, y * scale, scale, scale);
  }));
  cv.className = 'px';
  return cv;
}

// ------------------------------------------------------------------ retratos 16x16
const FACE = [
  '.khshhhhhhhhshk.',
  '.khsssssssssshk.',
  '.ksssesssssesssk',
  '.ksssesssssesssk',
  '.kspsssssssspsk.',
  '..kssssSSssssk..',
  '...kksssssskk...',
];
const TOPS = {
  spiky: ['................', '.....kkkkkk.....', '...kkHHhhHHkk...', '..khHHhhhhHhhk..', '.khhHhhhhhhhhhk.', '.khhhhhhhhhhhhk.'],
  bun: ['......kkkk......', '.....khHhhk.....', '...kkkhhhhkkk...', '..khHHhhhhhhhk..', '.khHhhhhhhhhhhk.', '.khhhhhhhhhhhhk.'],
  bandana: ['................', '....kkkkkkkk....', '..kkrrrrrrrrkk..', '.krRrrrrrrrrRrk.', '.krrrrwrrwrrrrk.', '.kRRRRRRRRRRRRk.'],
  hat: ['................', '.....kkkkkk.....', '....kyyyyyyk....', '...kyYyyyyyyk...', 'kkkyyyyyyyyyykkk', 'kyyyyyyyyyyyyyyk'],
  helmet: ['......kkkk......', '....kkaAAakk....', '...kaAAaaaaak...', '..kaAaaaaaaaak..', '.kaaaaaaaaaaaak.', '.kkkkkkkkkkkkkk.'],
  short: ['................', '.....kkkkkk.....', '...kkhhhhhhkk...', '..khHhhhhhhhhk..', '.khHhhhhhhhhhhk.', '.khhhhhhhhhhhhk.'],
};
const BEARD = ['.kspsssssssspsk.', '..ksWWWWWWWWsk..', '...kWWWWWWWWk...'];

export function portrait({ top = 'spiky', hair = '#8a4a30', hairL = '#b5653f', skin, cloth = '#3f86b8', cloth2 = '#2c628c', accent = '#e0533d', accent2 = '#a83a2e', beard = null }) {
  const rows = [...TOPS[top], ...FACE];
  if (beard) { rows[10] = BEARD[0]; rows[11] = BEARD[1]; rows[12] = BEARD[2]; }
  rows.push('..krrrkkkkrrrk..', '.krrRrrrrrrRrrk.', '.kbbbbRRbbbbbbk.');
  const pal = { h: hair, H: hairL, r: accent, R: accent2, b: cloth, B: cloth2, W: beard || '#ddd' };
  if (skin) { pal.s = skin; }
  return drawPixels(rows, pal, 1);
}

// ------------------------------------------------------------------ ícones
export const ICONS = {
  coin: ['..kkkk..', '.kyyyyk.', 'kyYyyyok', 'kyYyyyok', 'kyYyyyok', 'kyyyyook', '.kyooook', '..kkkk..'],
  potion: ['...kk...', '..klLk..', '...kk...', '..kmmk..', '.kmnmmk.', 'kmnmmmmk', 'kmmmmmMk', 'kmmmmMMk', '.kMMMMk.', '..kkkk..'],
  heart: ['.kk..kk.', 'kmnkkmmk', 'kmnmmmmk', 'kmmmmmMk', '.kmmmMk.', '..kmMk..', '...kk...'],
  rune: ['...kk...', '..kcck..', '.kcwCck.', 'kccwCCck', 'kcCwwCck', '.kcCCck.', '..kcck..', '...kk...'],
  ep: ['...kk...', '..kbbk..', '.kbwbbk.', 'kbwbbbBk', 'kbbbbBBk', '.kbBBBk.', '..kBBk..', '...kk...'],
  sword: ['......kk', '.....kAk', '....kAak', '...kAak.', 'k.kAak..', 'kykak...', '.kyk....', 'kLkyk...'],
  skull: ['.kkkkk.', 'kwwwwwk', 'kwkwkwk', 'kwwwwwk', '.kwwwk.', '.kwkwk.'],
  star: ['...k...', '..kyk..', 'kkyYykk', '.kyyyk.', '.kykyk.', 'kk...kk'],
};

export function icon(name, scale = 1, pal) { return drawPixels(ICONS[name], pal, scale); }
