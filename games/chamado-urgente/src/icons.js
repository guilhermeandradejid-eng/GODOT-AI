// Ícones SVG próprios (estilo "sticker"), usados no HUD e nos marcadores.
const wrap = (body) =>
  `<svg viewBox="0 0 48 48" xmlns="http://www.w3.org/2000/svg" stroke-linejoin="round" stroke-linecap="round">${body}</svg>`;

export const ICONS = {
  cable: wrap(`
    <path d="M8 38 C 14 26, 22 34, 26 22" fill="none" stroke="#1d2540" stroke-width="7"/>
    <path d="M8 38 C 14 26, 22 34, 26 22" fill="none" stroke="#3fa9ff" stroke-width="4"/>
    <rect x="22" y="8" width="16" height="16" rx="3" fill="#e9eef7" stroke="#1d2540" stroke-width="3"/>
    <rect x="26" y="4" width="8" height="6" fill="#ffd23f" stroke="#1d2540" stroke-width="2.5"/>
    <path d="M40 30 l4 -3 M40 36 l5 1 M36 40 l2 5" stroke="#ffd23f" stroke-width="3"/>`),
  paper: wrap(`
    <rect x="9" y="12" width="30" height="26" rx="3" fill="#ffffff" stroke="#1d2540" stroke-width="3"/>
    <rect x="9" y="20" width="30" height="9" fill="#3fa9ff" stroke="#1d2540" stroke-width="3"/>
    <path d="M14 8 h20" stroke="#1d2540" stroke-width="3"/>`),
  jam: wrap(`
    <rect x="6" y="18" width="36" height="18" rx="4" fill="#cfd6e4" stroke="#1d2540" stroke-width="3"/>
    <path d="M14 18 l4 -10 l6 6 l5 -7 l5 11" fill="#ffffff" stroke="#1d2540" stroke-width="3"/>
    <circle cx="35" cy="27" r="3" fill="#ff5a5a"/>
    <path d="M12 42 h24" stroke="#1d2540" stroke-width="3"/>`),
  fire: wrap(`
    <path d="M24 4 C 30 14, 40 18, 38 30 C 37 40, 30 44, 24 44 C 16 44, 9 38, 10 29 C 11 21, 17 19, 18 11 C 22 15, 22 19, 24 22 C 26 16, 26 10, 24 4 Z" fill="#ff6b2b" stroke="#1d2540" stroke-width="3"/>
    <path d="M24 26 C 28 31, 31 33, 30 37 C 29 41, 19 41, 18 37 C 17 33, 21 32, 24 26 Z" fill="#ffd23f"/>`),
  virus: wrap(`
    <ellipse cx="24" cy="28" rx="11" ry="13" fill="#6ee36e" stroke="#1d2540" stroke-width="3"/>
    <circle cx="24" cy="13" r="6" fill="#6ee36e" stroke="#1d2540" stroke-width="3"/>
    <path d="M13 22 l-7 -4 M13 30 h-8 M14 37 l-7 5 M35 22 l7 -4 M35 30 h8 M34 37 l7 5 M20 8 l-3 -5 M28 8 l3 -5" stroke="#1d2540" stroke-width="3"/>
    <path d="M24 17 v24" stroke="#1d2540" stroke-width="2.5"/>
    <circle cx="21.5" cy="12" r="1.6" fill="#1d2540"/><circle cx="26.5" cy="12" r="1.6" fill="#1d2540"/>`),
  router: wrap(`
    <rect x="6" y="28" width="36" height="12" rx="4" fill="#cfd6e4" stroke="#1d2540" stroke-width="3"/>
    <circle cx="14" cy="34" r="2.2" fill="#ff5a5a"/><circle cx="21" cy="34" r="2.2" fill="#ff5a5a"/>
    <path d="M12 20 a17 17 0 0 1 24 0 M17 25 a9 9 0 0 1 14 0" fill="none" stroke="#1d2540" stroke-width="3.5"/>
    <path d="M10 8 L38 36" stroke="#ff5a5a" stroke-width="4.5"/>`),
  extinguisher: wrap(`
    <rect x="15" y="14" width="16" height="30" rx="7" fill="#ff4d4d" stroke="#1d2540" stroke-width="3"/>
    <rect x="18" y="24" width="10" height="9" rx="2" fill="#ffffff"/>
    <path d="M23 14 v-6 h10 l6 4" fill="none" stroke="#1d2540" stroke-width="3.5"/>
    <path d="M18 8 h8" stroke="#1d2540" stroke-width="3.5"/>`),
  usb: wrap(`
    <rect x="13" y="18" width="22" height="26" rx="5" fill="#2fc46b" stroke="#1d2540" stroke-width="3"/>
    <rect x="17" y="6" width="14" height="13" fill="#e9eef7" stroke="#1d2540" stroke-width="3"/>
    <rect x="20" y="10" width="3" height="3" fill="#1d2540"/><rect x="25" y="10" width="3" height="3" fill="#1d2540"/>
    <path d="M19 31 l4 4 l7 -8" fill="none" stroke="#ffffff" stroke-width="3.5"/>`),
  coffee: wrap(`
    <path d="M10 18 h24 v12 a10 10 0 0 1 -10 10 h-4 a10 10 0 0 1 -10 -10 Z" fill="#ffffff" stroke="#1d2540" stroke-width="3"/>
    <path d="M34 21 h3 a5 5 0 0 1 0 10 h-4" fill="none" stroke="#1d2540" stroke-width="3"/>
    <path d="M16 12 c0 -3 3 -3 3 -6 M23 12 c0 -3 3 -3 3 -6" fill="none" stroke="#9aa3b5" stroke-width="2.5"/>
    <rect x="12" y="20" width="20" height="4" fill="#8e5b34"/>`),
  star: wrap(`<path d="M24 4 l6 13 l14 1.5 l-10.5 9.5 l3 14 l-12.5 -7 l-12.5 7 l3 -14 l-10.5 -9.5 l14 -1.5 Z" fill="#ffd23f" stroke="#1d2540" stroke-width="3"/>`),
  hand: wrap(`<path d="M16 42 v-18 a3 3 0 0 1 6 0 v-12 a3 3 0 0 1 6 0 v12 h1 a3 3 0 0 1 6 0 v6 a3 3 0 0 1 4 2 v4 c0 6 -4 10 -10 10 h-6 c-4 0 -7 -2 -7 -4 Z" fill="#ffd7b0" stroke="#1d2540" stroke-width="3"/>`),
};

export function iconImg(name, size = 28) {
  const svg = ICONS[name] || ICONS.star;
  return `<span class="ico" style="width:${size}px;height:${size}px">${svg}</span>`;
}
