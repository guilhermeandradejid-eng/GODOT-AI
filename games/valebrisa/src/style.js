// Estilo de arte global: 'toon' (desenho animado liso, padrão) ou 'pixel' (pixel art 3D).
// Trocado no menu de pausa (recarrega a página) ou por ?estilo=pixel|toon.
let s = 'toon';
try {
  const q = new URLSearchParams(location.search).get('estilo');
  s = q || localStorage.getItem('valebrisa-style') || 'toon';
} catch { /* sem armazenamento */ }
export const STYLE = s === 'pixel' ? 'pixel' : 'toon';
export const TOON = STYLE === 'toon';
export function setStyle(v) { try { localStorage.setItem('valebrisa-style', v); } catch { /* */ } }
