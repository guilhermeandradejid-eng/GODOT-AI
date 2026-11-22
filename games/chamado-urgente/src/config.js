// Ajustes de jogo centralizados: mude aqui para balancear.

export const ROUND_SECONDS = 180;          // um "expediente" (09:00 → 18:00)
export const START_HOUR = 9;
export const END_HOUR = 18;

export const PLAYER = {
  radius: 0.36,
  speed: 4.6,
  accel: 38,
  carrySlow: 0.92,
  dashSpeed: 11,
  dashTime: 0.16,
  dashCooldown: 0.55,
  reach: 1.05,
  throwSpeed: 9.5,
  coffeeBoost: 1.35,
  coffeeTime: 10,
};

export const PLAYER_COLORS = [
  { shirt: 0x3d7bff, name: 'Azul' },
  { shirt: 0xff8a2b, name: 'Laranja' },
  { shirt: 0x2fc46b, name: 'Verde' },
  { shirt: 0xb05cff, name: 'Roxo' },
];

// Itens que podem ser carregados.
export const ITEMS = {
  cable:        { label: 'Cabo de rede',    icon: 'cable' },
  paper:        { label: 'Resma de papel',  icon: 'paper' },
  extinguisher: { label: 'Extintor',        icon: 'extinguisher' },
  pendrive:     { label: 'Pendrive antivírus', icon: 'usb' },
};

// Tipos de chamado. `sla` em segundos, `hold` = tempo de conserto (segundos-pessoa,
// dois técnicos juntos consertam 2x mais rápido), `item` = ferramenta necessária.
export const PROBLEMS = {
  cable:  { title: 'Cabo de rede partido', icon: 'cable',  sla: 48, hold: 1.4, item: 'cable',        consume: true,  target: 'desk',    weight: 3, reward: 100 },
  virus:  { title: 'Vírus no computador',  icon: 'virus',  sla: 55, hold: 3.2, item: 'pendrive',     consume: false, target: 'desk',    weight: 3, reward: 130 },
  paper:  { title: 'Impressora sem papel', icon: 'paper',  sla: 40, hold: 0.7, item: 'paper',        consume: true,  target: 'printer', weight: 3, reward: 80 },
  jam:    { title: 'Impressora emperrada', icon: 'jam',    sla: 45, hold: 3.0, item: null,           consume: false, target: 'printer', weight: 2, reward: 110 },
  fire:   { title: 'Impressora pegando fogo!', icon: 'fire', sla: 32, hold: 2.6, item: 'extinguisher', consume: false, target: 'printer', weight: 1.2, reward: 170 },
  router: { title: 'Internet caiu!',       icon: 'router', sla: 34, hold: 2.6, item: null,           consume: false, target: 'router',  weight: 1, reward: 150 },
};

export const TICKETS = {
  firstDelay: 2.5,
  intervalStart: 11,
  intervalEnd: 5.5,
  maxOpen: 6,
  failPenalty: 60,
  // vírus espalha para o PC vizinho quando sobra esta fração do SLA
  virusSpreadAt: 0.45,
  // com a internet fora, o SLA dos outros chamados corre mais rápido
  routerDownDrain: 1.6,
};

export const STARS = [450, 1000, 1650];

// Ajuste por tamanho da equipe (1 a 4 técnicos): intervalo entre chamados e metas de estrelas.
export const TEAM_SCALE = {
  interval: [1.4, 1, 0.82, 0.7],
  stars: [0.65, 1, 1.3, 1.55],
};

export const PALETTE = {
  floor: 0xd9cbb5,
  carpet: 0x5d6b8a,
  carpet2: 0x546180,
  wall: 0xf1e6d6,
  wallTrim: 0x3b4566,
  wood: 0xc98f5a,
  woodDark: 0x8e5b34,
  desk: 0xf4efe6,
  metal: 0x9aa3b5,
  dark: 0x2a2f3d,
  plant: 0x4fb36a,
  pot: 0xe07a4f,
  bg: 0x1d2540,
};
